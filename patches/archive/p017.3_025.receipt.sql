SET NAMES utf8mb4;

/* =========================================================
   Receipts（下書き→確定スナップ）— 統合DDL（p017.3）
   ---------------------------------------------------------
   - CSIFH-PureMirror v1: clinic_uuid を各表に保持
       drafts : farms.clinic_uuid を継承（可変／farm変更時は再継承）
       headers: 当時値固定
       checkups/items: 親から固定継承
   - FK新設は draft.farm_uuid → farms(uuid) のみ
   - ヘッダに draft 参照を保持: receipt_header_drafts_uuid（弱リンク）
   - 既存テーブル(checkups等)への ALTER は本DDLに含めない
   ========================================================= */

/* --- 再デプロイ安全化：関連トリガのDROP（存在しなくてもOK） --- */
DROP TRIGGER IF EXISTS tr_receipt_header_drafts_bu_rowver;
DROP TRIGGER IF EXISTS tr_receipt_header_drafts_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_receipt_header_drafts_bi_clinic_inherit;
DROP TRIGGER IF EXISTS tr_receipt_headers_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_receipt_headers_bi_clinic_inherit;
DROP TRIGGER IF EXISTS tr_receipt_checkups_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_receipt_checkups_bi_clinic_inherit;
DROP TRIGGER IF EXISTS tr_receipt_items_bi_clinic_inherit;

/* --- 再デプロイ安全化：子→親の順でDROP（依存関係の都合） --- */
DROP TABLE IF EXISTS receipt_items;
DROP TABLE IF EXISTS receipt_checkups;
DROP TABLE IF EXISTS receipt_headers;
DROP TABLE IF EXISTS receipt_header_drafts;

/* =========================================================
   1) 下書きヘッダ：集計の本体（可変 / Mirror v1）
   - farm_uuid は弱リンクだが、draft に限り FK を付与
   - clinic_uuid は farm から継承（INSERT/UPDATE）
   ========================================================= */
CREATE TABLE IF NOT EXISTS receipt_header_drafts (
  id                    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                  BINARY(16) NOT NULL UNIQUE,                  -- v7 UUID（下書きの識別）

  /* 任意のスコープ（印字や絞り込み用） */
  farm_uuid             BINARY(16) NULL,
  clinic_uuid           BINARY(16) NULL,                             -- 当時の所属院（可変：farm変更時に再継承）
  title                 VARCHAR(120) NULL,
  note                  VARCHAR(255) NULL,

  /* 状態遷移（発行で issued に） */
  status                ENUM('open','closed','issued') NOT NULL DEFAULT 'open',
  issued_at             DATETIME NULL,                               -- issued 遷移時刻
  issued_by_user_id     INT UNSIGNED NULL,
  issued_receipt_uuid   BINARY(16) NULL,                             -- 対応する receipt_headers.uuid（作成後にセット）

  /* クリニック設定スナップ（draft時点の値） */
  yen_per_point         DECIMAL(8,2) NOT NULL DEFAULT 10.00,         -- 例: 1点=10円
  copay_rate            DECIMAL(5,4) NOT NULL DEFAULT 0.1000,        -- 例: 10% は 0.1000
  tax_rounding          ENUM('floor','round','ceil') NOT NULL DEFAULT 'round',

  /* 集計（税抜→税→税込） */
  total_b_points        INT UNSIGNED NOT NULL DEFAULT 0,
  total_a_points        INT UNSIGNED NOT NULL DEFAULT 0,
  total_price_yen       INT UNSIGNED NOT NULL DEFAULT 0,             -- 自由価格（税抜）
  subtotal_yen          INT UNSIGNED NOT NULL DEFAULT 0,             -- 点換算円 + 自由価格（税抜）
  tax_yen               INT UNSIGNED NOT NULL DEFAULT 0,
  total_insurance_yen   INT UNSIGNED NOT NULL DEFAULT 0,             -- 税込（保険）
  total_private_yen     INT UNSIGNED NOT NULL DEFAULT 0,             -- 税込（自由）
  patient_copay_yen     INT UNSIGNED NOT NULL DEFAULT 0,             -- 患者負担
  insurer_pay_yen       INT UNSIGNED NOT NULL DEFAULT 0,             -- 保険者負担

  /* 監査（可変テーブルなので row_version / deleted_at を保持） */
  created_by            INT UNSIGNED NULL,
  updated_by            INT UNSIGNED NULL,
  row_version           BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at            DATETIME NULL,
  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  /* 一覧最適化 */
  KEY idx_receipt_drafts_list   (deleted_at, updated_at, id),
  KEY idx_receipt_drafts_farm   (farm_uuid, deleted_at, updated_at, id),
  KEY idx_receipt_drafts_clinic (clinic_uuid, deleted_at, updated_at, id),

  /* draft にのみ farm FK（他表には貼らない） */
  CONSTRAINT fk_rcpt_drafts_farm
    FOREIGN KEY (farm_uuid) REFERENCES farms(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER tr_receipt_header_drafts_bi_uuid_v7
BEFORE INSERT ON receipt_header_drafts
FOR EACH ROW
BEGIN
  DECLARE v_clinic BINARY(16);

  /* uuid未指定なら v7 を自動採番 */
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid)=0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;

  /* 挿入時に farm → clinic を継承（弱参照 / FKはfarmにのみ） */
  IF NEW.clinic_uuid IS NULL AND NEW.farm_uuid IS NOT NULL THEN
    SELECT f.clinic_uuid INTO v_clinic
      FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
    SET NEW.clinic_uuid = v_clinic;
  END IF;
END $$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER tr_receipt_header_drafts_bu_rowver
BEFORE UPDATE ON receipt_header_drafts
FOR EACH ROW
BEGIN
  DECLARE v_clinic2 BINARY(16);

  /* 楽観ロック：row_version 自動インクリメント */
  SET NEW.row_version = OLD.row_version + 1;

  /* farm_uuid 変更時は clinic_uuid を再継承 */
  IF (NEW.farm_uuid <> OLD.farm_uuid) OR (NEW.clinic_uuid IS NULL AND NEW.farm_uuid IS NOT NULL) THEN
    SELECT f.clinic_uuid INTO v_clinic2
      FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
    SET NEW.clinic_uuid = v_clinic2;
  END IF;
END $$
DELIMITER ;

/* =========================================================
   2) （ここでは ALTER を除外）既存表への付加は別ファイルで管理
   - ① checkups ALTER と ② checkup_items ALTER は本DDLから除外
   ========================================================= */

/* =========================================================
   3) 確定ヘッダ：不変スナップ（Mirror v1）
   - clinic_uuid は発行時点の当時値を固定保存
   - ヘッダ→ドラフト参照: receipt_header_drafts_uuid（弱リンク／FKなし）
   ========================================================= */
CREATE TABLE IF NOT EXISTS receipt_headers (
  id                          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                        BINARY(16) NOT NULL UNIQUE,            -- v7 UUID（スナップの識別）
  receipt_header_drafts_uuid  BINARY(16) NULL,                       -- 参照元ドラフト（弱リンク）
  farm_uuid                   BINARY(16) NULL,                       -- 弱リンク（将来の参照用）
  clinic_uuid                 BINARY(16) NULL,                       -- 当時の所属院（不変）
  receipt_no                  VARCHAR(40) NULL UNIQUE,               -- 任意の対外発番（UI採番）
  title                       VARCHAR(120) NULL,
  note                        VARCHAR(255) NULL,

  issued_at                   DATETIME NOT NULL,                     -- 発行日時（スナップ時刻）
  issued_by_user_id           INT UNSIGNED NULL,

  status                      ENUM('printed','voided') NULL DEFAULT NULL,  -- 未印刷(NULL)/印刷済/取消
  printed_at                  DATETIME NULL,
  printed_count               INT UNSIGNED NOT NULL DEFAULT 0,
  voided_at                   DATETIME NULL,
  void_reason                 VARCHAR(255) NULL,
  voided_by_user_id           INT UNSIGNED NULL,

  /* クリニック設定スナップ（固定） */
  yen_per_point               DECIMAL(8,2) NOT NULL,
  copay_rate                  DECIMAL(5,4) NOT NULL,
  tax_rounding                ENUM('floor','round','ceil') NOT NULL,

  /* 集計スナップ（固定） */
  total_b_points              INT UNSIGNED NOT NULL,
  total_a_points              INT UNSIGNED NOT NULL,
  total_price_yen             INT UNSIGNED NOT NULL,
  subtotal_yen                INT UNSIGNED NOT NULL,
  tax_yen                     INT UNSIGNED NOT NULL,
  total_insurance_yen         INT UNSIGNED NOT NULL,
  total_private_yen           INT UNSIGNED NOT NULL,
  patient_copay_yen           INT UNSIGNED NOT NULL,
  insurer_pay_yen             INT UNSIGNED NOT NULL,

  /* 任意：印字/レイアウト用のクリニック情報 */
  clinic_snapshot_json        JSON NULL,

  created_at                  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  /* 検索用インデックス */
  KEY idx_rcpt_hdr_draft  (receipt_header_drafts_uuid, issued_at),   -- 追跡用
  KEY idx_rcpt_hdr_issued (issued_at, id),
  KEY idx_rcpt_hdr_status (status, issued_at, id),
  KEY idx_rcpt_hdr_farm   (farm_uuid, issued_at, id),
  KEY idx_rcpt_hdr_clinic (clinic_uuid, issued_at, id)
  -- 必要なら UNIQUE(receipt_header_drafts_uuid) で「1ドラフト=1発行」を強制可
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER tr_receipt_headers_bi_uuid_v7
BEFORE INSERT ON receipt_headers
FOR EACH ROW
BEGIN
  DECLARE v_hdr_clinic BINARY(16);

  /* uuid未指定なら v7 を自動採番 */
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid)=0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;

  /* 発行時に farm → clinic を固定継承（アプリが直接セットしても可） */
  IF NEW.clinic_uuid IS NULL AND NEW.farm_uuid IS NOT NULL THEN
    SELECT f.clinic_uuid INTO v_hdr_clinic
      FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
    SET NEW.clinic_uuid = v_hdr_clinic;
  END IF;
END $$
DELIMITER ;

/* =========================================================
   4) 確定：チェックアップスナップ（不変 / clinic_uuid はヘッダから継承）
   ========================================================= */
CREATE TABLE IF NOT EXISTS receipt_checkups (
  id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                BINARY(16) NOT NULL UNIQUE,                  -- v7（items から参照）
  receipt_header_uuid BINARY(16) NOT NULL,                         -- ↔ receipt_headers.uuid（弱リンク）
  clinic_uuid         BINARY(16) NULL,                             -- 親ヘッダから固定継承
  source_checkup_uuid BINARY(16) NOT NULL,                         -- 由来：checkups.uuid
  checkup_at          DATETIME NULL,                               -- 任意：診療日時など
  individual_uuid     BINARY(16) NULL,                             -- 任意：印字補助
  individual_label    VARCHAR(120) NULL,                           -- 任意：個体表示名 等
  created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

  /* 重複取り込み防止（同一ヘッダ内で同一sourceは一度だけ） */
  UNIQUE KEY uq_rcpt_hdr_src (receipt_header_uuid, source_checkup_uuid),

  KEY idx_rcpt_ckp_hdr    (receipt_header_uuid, id),
  KEY idx_rcpt_ckp_src    (source_checkup_uuid),
  KEY idx_rcpt_ckp_clinic (clinic_uuid, receipt_header_uuid, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER tr_receipt_checkups_bi_uuid_v7
BEFORE INSERT ON receipt_checkups
FOR EACH ROW
BEGIN
  DECLARE v_ckp_clinic BINARY(16);

  /* uuid未指定なら v7 を自動採番（items が参照するため必須） */
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid)=0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;

  /* ヘッダから clinic_uuid を固定継承 */
  IF NEW.clinic_uuid IS NULL THEN
    SELECT h.clinic_uuid INTO v_ckp_clinic
      FROM receipt_headers h WHERE h.uuid = NEW.receipt_header_uuid LIMIT 1;
    SET NEW.clinic_uuid = v_ckp_clinic;
  END IF;
END $$
DELIMITER ;

/* =========================================================
   5) 確定：行為明細スナップ（不変 / clinic_uuid はCKPから継承）
   ========================================================= */
CREATE TABLE IF NOT EXISTS receipt_items (
  id                     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  receipt_checkup_uuid   BINARY(16) NOT NULL,                       -- ↔ receipt_checkups.uuid（弱リンク）
  clinic_uuid            BINARY(16) NULL,                           -- 親CKPから固定継承
  source_checkup_item_id INT UNSIGNED NOT NULL,                     -- 由来：checkup_items.id

  /* マスタ/入力の当時値スナップ（印字・再現に必要な範囲を保持） */
  description            VARCHAR(255) NOT NULL,                     -- 例: 処置/薬品名
  qty_unit               VARCHAR(32)  NULL,                         -- 例: mL, 回, 錠...
  quantity               DECIMAL(10,2) NOT NULL DEFAULT 1,

  /* 点数/自由価格の両立 */
  pay_type               ENUM('insurance','private') NOT NULL DEFAULT 'insurance',
  unit_b_points          INT UNSIGNED NOT NULL DEFAULT 0,
  unit_a_points          INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_points        INT UNSIGNED NOT NULL DEFAULT 0,
  yen_per_point          DECIMAL(8,2) NOT NULL DEFAULT 0.00,

  unit_price_yen         INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_price_yen     INT UNSIGNED NOT NULL DEFAULT 0,

  /* 税と金額（行で算出→ヘッダで合算） */
  tax_rate               DECIMAL(4,2) NOT NULL DEFAULT 0.00,
  subtotal_yen           INT UNSIGNED NOT NULL DEFAULT 0,           -- 税抜
  tax_yen                INT UNSIGNED NOT NULL DEFAULT 0,
  total_yen              INT UNSIGNED NOT NULL DEFAULT 0,           -- 税込

  note                   VARCHAR(255) NULL,
  created_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

  /* 重複取り込み防止（同一チェックアップスナップ内の同一sourceは一度だけ） */
  UNIQUE KEY uq_rcptitem_ckp_src (receipt_checkup_uuid, source_checkup_item_id),

  KEY idx_rcpt_items_ckpuuid (receipt_checkup_uuid, id),
  KEY idx_rcpt_items_source  (source_checkup_item_id),
  KEY idx_rcpt_items_clinic  (clinic_uuid, receipt_checkup_uuid, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER tr_receipt_items_bi_clinic_inherit
BEFORE INSERT ON receipt_items
FOR EACH ROW
BEGIN
  DECLARE v_item_clinic BINARY(16);

  /* 親CKPから clinic_uuid を固定継承 */
  IF NEW.clinic_uuid IS NULL THEN
    SELECT c.clinic_uuid INTO v_item_clinic
      FROM receipt_checkups c WHERE c.uuid = NEW.receipt_checkup_uuid LIMIT 1;
    SET NEW.clinic_uuid = v_item_clinic;
  END IF;
END $$
DELIMITER ;

/* =========================================================
   6) 発行（コピー）SQL — 一時テーブルなし簡易版
   ---------------------------------------------------------
   前提:
   - :draft_hex         = 対象ドラフトのUUID(HEX文字列)
   - :actor_user_id     = 発行操作ユーザーID（任意）
   - checkups.receipt_header_drafts_uuid が既に存在
   ========================================================= */

-- 参考: 発行（issue）トランザクション（INSERTのみで一括コピー）
-- START TRANSACTION;

-- 入力
-- SET @draft_uuid = uuid_hex_to_bin(:draft_hex);
-- SET @hdr_uuid   = uuid_v7_bin();

-- 1) ヘッダ作成（ドラフトの当時値をコピー。draft参照を保持）
-- INSERT INTO receipt_headers (
--   uuid, receipt_header_drafts_uuid,
--   farm_uuid, clinic_uuid,
--   receipt_no, title, note,
--   issued_at, issued_by_user_id,
--   yen_per_point, copay_rate, tax_rounding,
--   total_b_points, total_a_points, total_price_yen,
--   subtotal_yen, tax_yen, total_insurance_yen, total_private_yen,
--   patient_copay_yen, insurer_pay_yen,
--   clinic_snapshot_json
-- )
-- SELECT
--   @hdr_uuid, d.uuid,
--   d.farm_uuid,
--   d.clinic_uuid,                         -- NULLならヘッダINSERTトリガが farm→clinic を継承
--   NULL,
--   d.title, d.note,
--   COALESCE(d.issued_at, NOW()), d.issued_by_user_id,
--   d.yen_per_point, d.copay_rate, d.tax_rounding,
--   d.total_b_points, d.total_a_points, d.total_price_yen,
--   d.subtotal_yen, d.tax_yen, d.total_insurance_yen, d.total_private_yen,
--   d.patient_copay_yen, d.insurer_pay_yen,
--   NULL
-- FROM receipt_header_drafts d
-- WHERE d.uuid = @draft_uuid;

-- 2) チェックアップ・スナップ（source_checkup_uuid を保持）
-- INSERT INTO receipt_checkups (
--   uuid, receipt_header_uuid, clinic_uuid,
--   source_checkup_uuid, checkup_at,
--   individual_uuid, individual_label
-- )
-- SELECT
--   uuid_v7_bin(),
--   @hdr_uuid,
--   NULL,                                      -- トリガでヘッダの clinic_uuid を継承
--   c.uuid,
--   COALESCE(c.checkup_at, v.start_at, c.created_at),
--   c.individual_uuid,
--   NULL
-- FROM checkups c
-- LEFT JOIN visits v ON v.uuid = c.visit_uuid
-- WHERE c.receipt_header_drafts_uuid = @draft_uuid;

-- 3) 行為明細スナップ（rc.source_checkup_uuid 経由で ckps に紐付け）
-- INSERT INTO receipt_items (
--   receipt_checkup_uuid, clinic_uuid, source_checkup_item_id,
--   description, qty_unit, quantity,
--   pay_type,
--   unit_b_points, unit_a_points, subtotal_points, yen_per_point,
--   unit_price_yen, subtotal_price_yen,
--   tax_rate, subtotal_yen, tax_yen, total_yen,
--   note
-- )
-- SELECT
--   rc.uuid,                                   -- 新規 ckps に紐付け
--   NULL,                                      -- トリガで ckps の clinic_uuid を継承
--   ci.id,
--   ci.description,
--   ci.qty_unit,
--   ci.quantity,
--   ci.pay_type,
--   ci.unit_b_points,
--   ci.unit_a_points,
--   ci.subtotal_points,
--   ci.yen_per_point,
--   ci.unit_price_yen,
--   ci.subtotal_price_yen,
--   ci.tax_rate,
--   ci.subtotal_yen,
--   ci.tax_yen,
--   ci.total_yen,
--   ci.note
-- FROM checkup_items ci
-- JOIN checkups c
--   ON c.id = ci.checkup_id
-- JOIN receipt_checkups rc
--   ON rc.receipt_header_uuid = @hdr_uuid
--  AND rc.source_checkup_uuid = c.uuid
-- WHERE c.receipt_header_drafts_uuid = @draft_uuid;

-- 4) ドラフトを発行済みに更新（双方向追跡を残す）
-- UPDATE receipt_header_drafts d
-- SET d.status = 'issued',
--     d.issued_at = COALESCE(d.issued_at, NOW()),
--     d.issued_by_user_id = COALESCE(d.issued_by_user_id, :actor_user_id),
--     d.issued_receipt_uuid = @hdr_uuid
-- WHERE d.uuid = @draft_uuid;

-- COMMIT;
