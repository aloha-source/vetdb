SET NAMES utf8mb4;

-- =========================================================
-- vetDB p017.4 — receipts（ドラフト=receipt_headers, 確定=snap_receipt_*）
-- 方針要点：
--  - ドラフト＝ receipt_headers（*_draft は廃止）
--  - 確定スナップ＝ snap_receipt_headers / snap_receipt_checkups / snap_receipt_items
--  - ヘッダ配下の checkups 所属の「唯一の正」は p15.4 の header_links を使用（本DDLでは作らない）
--  - すべて DATETIME(6) に統一
--  - clinics への FK は付与しない（CSIFH）
--  - UUID トリガは NULL または all-zero(0x00...) を採番条件として扱う
--  - receipt は visit スコープ：scope_table='visits' 固定、scope_uuid=visit_uuid 同期
-- =========================================================

/* 再デプロイ安全化：旧版/関連トリガのDROP（存在しなくてもOK） */
DROP TRIGGER IF EXISTS tr_receipt_headers_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_receipt_headers_bi_clinic_and_scope;
DROP TRIGGER IF EXISTS tr_receipt_headers_bu_rowver_and_resync;
DROP TRIGGER IF EXISTS tr_snap_receipt_headers_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_snap_receipt_headers_bi_clinic;
DROP TRIGGER IF EXISTS tr_snap_receipt_checkups_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_snap_receipt_checkups_bi_clinic;
DROP TRIGGER IF EXISTS tr_snap_receipt_items_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_snap_receipt_items_bi_clinic;

/* 旧構成のトリガ/表（p17.3系）の掃除 */
DROP TRIGGER IF EXISTS tr_receipt_header_drafts_bu_rowver;
DROP TRIGGER IF EXISTS tr_receipt_header_drafts_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_receipt_header_drafts_bi_clinic_inherit;
DROP TRIGGER IF EXISTS tr_receipt_headers_bi_clinic_inherit;
DROP TRIGGER IF EXISTS tr_receipt_checkups_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_receipt_checkups_bi_clinic_inherit;
DROP TRIGGER IF EXISTS tr_receipt_items_bi_clinic_inherit;

DROP TABLE IF EXISTS snap_receipt_items;
DROP TABLE IF EXISTS snap_receipt_checkups;
DROP TABLE IF EXISTS snap_receipt_headers;
DROP TABLE IF EXISTS receipt_header_drafts;   -- 廃止
DROP TABLE IF EXISTS receipt_items;           -- 旧スナップ配下（廃止）
DROP TABLE IF EXISTS receipt_checkups;        -- 旧スナップ配下（廃止）
DROP TABLE IF EXISTS receipt_headers;         -- 旧：確定／新：ドラフト（再作成のため一旦DROP）

/* =========================================================
   1) receipt_headers — ドラフト（編集中ヘッダ）
   ---------------------------------------------------------
   - scope_table/scope_uuid を導入（visit スコープ固定）
   - clinics への FK は付与しない（CSIFH）
   - 印刷/発行系の列は「補助フラグ」として残置（最終の正は snap_*）
   ========================================================= */
CREATE TABLE IF NOT EXISTS receipt_headers (
  id                        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                      BINARY(16) NOT NULL UNIQUE,                   -- v7 UUID

  clinic_uuid               BINARY(16) NOT NULL,                           -- 当時の院（clinics.uuid）値
  scope_table               VARCHAR(32) NOT NULL,                          -- 例: 'visits'（固定）
  scope_uuid                BINARY(16) NOT NULL,                           -- = visit_uuid
  visit_uuid                BINARY(16) NOT NULL,                           -- ↔ visits.uuid（強整合FK）

  /* 任意の表示/備考（命名統一） */
  doc_title                 VARCHAR(120) NULL,
  doc_note                  VARCHAR(255) NULL,

  /* ドラフト状態（共通） */
  status                    ENUM('open','closed','issued') NOT NULL DEFAULT 'open',
  status_note               VARCHAR(255) NULL,

  /* 補助フラグ：発行/印刷痕跡（最終の正は snap_* 側） */
  printed_at                DATETIME(6) NULL,
  printed_count             INT UNSIGNED NOT NULL DEFAULT 0,
  issued_at                 DATETIME(6) NULL,
  issued_by_user_id         INT UNSIGNED NULL,

  /* クリニック設定（ドラフト時点） */
  yen_per_point             DECIMAL(8,2) NOT NULL DEFAULT 10.00,
  copay_rate                DECIMAL(5,4) NOT NULL DEFAULT 0.1000,
  tax_rounding              ENUM('floor','round','ceil') NOT NULL DEFAULT 'round',

  /* 集計（税抜→税→税込） */
  total_b_points            INT UNSIGNED NOT NULL DEFAULT 0,
  total_a_points            INT UNSIGNED NOT NULL DEFAULT 0,
  total_price_yen           INT UNSIGNED NOT NULL DEFAULT 0,              -- 自由価格（税抜）
  subtotal_yen              INT UNSIGNED NOT NULL DEFAULT 0,              -- 点換算円 + 自由価格（税抜）
  tax_yen                   INT UNSIGNED NOT NULL DEFAULT 0,
  total_insurance_yen       INT UNSIGNED NOT NULL DEFAULT 0,              -- 税込（保険）
  total_private_yen         INT UNSIGNED NOT NULL DEFAULT 0,              -- 税込（自由）
  patient_copay_yen         INT UNSIGNED NOT NULL DEFAULT 0,              -- 患者負担
  insurer_pay_yen           INT UNSIGNED NOT NULL DEFAULT 0,              -- 保険者負担

  /* 任意：印字/レイアウト用のクリニック情報 */
  clinic_snapshot_json      JSON NULL,

  /* 監査 */
  created_by                INT UNSIGNED NULL,
  updated_by                INT UNSIGNED NULL,
  row_version               BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at                DATETIME(6) NULL,
  created_at                DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at                DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),

  /* 強整合FK（visit 起点） */
  CONSTRAINT fk_rh_visit
    FOREIGN KEY (visit_uuid) REFERENCES visits(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,

  /* 索引 */
  INDEX idx_rh_clinic_list  (clinic_uuid, deleted_at, updated_at, id),
  INDEX idx_rh_scope        (scope_table, scope_uuid, deleted_at, updated_at, id),
  INDEX idx_rh_status       (status, updated_at, id),
  INDEX idx_rh_visit        (visit_uuid, updated_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_receipt_headers_bi_uuid_v7
BEFORE INSERT ON receipt_headers
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL
     OR NEW.uuid = 0x00000000000000000000000000000000 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

DELIMITER $$
/* INSERT時：visit→farm→clinic 継承、scope 固定化、scope_uuid 同期 */
CREATE TRIGGER tr_receipt_headers_bi_clinic_and_scope
BEFORE INSERT ON receipt_headers
FOR EACH ROW
BEGIN
  -- clinic 継承：visits → farms → clinics（CSIFH）
  IF NEW.clinic_uuid IS NULL THEN
    SELECT f.clinic_uuid INTO NEW.clinic_uuid
      FROM visits v
      JOIN farms f ON f.uuid = v.farm_uuid
     WHERE v.uuid = NEW.visit_uuid
     LIMIT 1;
  END IF;

  -- scope 固定（visit スコープ）
  IF NEW.scope_table IS NULL OR NEW.scope_table = '' THEN
    SET NEW.scope_table = 'visits';
  END IF;

  -- scope_uuid は visit_uuid と同期
  IF NEW.scope_uuid IS NULL THEN
    SET NEW.scope_uuid = NEW.visit_uuid;
  END IF;
END $$
DELIMITER ;

DELIMITER $$
/* UPDATE時：visit変更で clinic 再継承、scope_uuid 同期、row_version++ */
CREATE TRIGGER tr_receipt_headers_bu_rowver_and_resync
BEFORE UPDATE ON receipt_headers
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;

  IF NEW.visit_uuid <> OLD.visit_uuid OR (NEW.clinic_uuid IS NULL) THEN
    SELECT f.clinic_uuid INTO NEW.clinic_uuid
      FROM visits v
      JOIN farms f ON f.uuid = v.farm_uuid
     WHERE v.uuid = NEW.visit_uuid
     LIMIT 1;
  END IF;

  IF NEW.visit_uuid <> OLD.visit_uuid OR (NEW.scope_uuid IS NULL) THEN
    SET NEW.scope_uuid = NEW.visit_uuid;
  END IF;

  -- scope_table は固定方針（必要なら手動更新）
END $$
DELIMITER ;

/* =========================================================
   2) docsnap（確定スナップ）— snap_receipt_headers
   ---------------------------------------------------------
   - 最終状態の正は snap_* 側
   - 由来追跡：source_header_uuid を保持
   - 受け側で receipt_no を保持（任意の対外発番）
   ========================================================= */
CREATE TABLE IF NOT EXISTS snap_receipt_headers (
  id                          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                        BINARY(16) NOT NULL UNIQUE,                 -- v7 UUID（スナップ識別）
  source_header_uuid          BINARY(16) NOT NULL,                        -- 由来：receipt_headers.uuid

  clinic_uuid                 BINARY(16) NOT NULL,
  visit_uuid                  BINARY(16) NOT NULL,                        -- 由来ヘッダの visit_uuid を固定保持
  receipt_no                  VARCHAR(40) NULL UNIQUE,                    -- 任意の対外発番（UI採番）

  doc_title                   VARCHAR(120) NULL,
  doc_note                    VARCHAR(255) NULL,

  issued_at                   DATETIME(6) NOT NULL,                       -- 発行（スナップ）時刻
  issued_by_user_id           INT UNSIGNED NULL,

  /* スナップ最終状態（印刷） */
  status                      ENUM('printed','voided') NULL DEFAULT NULL, -- 未印刷(NULL)/印刷済/取消
  printed_at                  DATETIME(6) NULL,
  printed_count               INT UNSIGNED NOT NULL DEFAULT 0,
  voided_at                   DATETIME(6) NULL,
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

  /* 任意：印字/レイアウト */
  clinic_snapshot_json        JSON NULL,

  created_at                  DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at                  DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),

  INDEX idx_srh_clinic_list   (clinic_uuid, issued_at, id),
  INDEX idx_srh_issued        (issued_at, id),
  INDEX idx_srh_status        (status, issued_at, id),
  INDEX idx_srh_visit         (visit_uuid, issued_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_snap_receipt_headers_bi_uuid_v7
BEFORE INSERT ON snap_receipt_headers
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL
     OR NEW.uuid = 0x00000000000000000000000000000000 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

DELIMITER $$
/* INSERT時：clinic/visit をヘッダから継承（保険で入れ忘れた場合の保険） */
CREATE TRIGGER tr_snap_receipt_headers_bi_clinic
BEFORE INSERT ON snap_receipt_headers
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid IS NULL OR NEW.visit_uuid IS NULL THEN
    SELECT h.clinic_uuid, h.visit_uuid
      INTO NEW.clinic_uuid, NEW.visit_uuid
      FROM receipt_headers h
     WHERE h.uuid = NEW.source_header_uuid
     LIMIT 1;
  END IF;
END $$
DELIMITER ;

/* =========================================================
   3) snap_receipt_checkups — スナップ配下（ヘッダ内の checkup 掲載）
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS snap_receipt_checkups (
  id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                BINARY(16) NOT NULL UNIQUE,                      -- v7（items から参照）
  snap_header_uuid    BINARY(16) NOT NULL,                             -- ↔ snap_receipt_headers.uuid
  clinic_uuid         BINARY(16) NOT NULL,                             -- 親ヘッダから固定継承
  source_checkup_uuid BINARY(16) NOT NULL,                             -- 由来：checkups.uuid
  checkup_at          DATETIME(6) NULL,                                -- 任意：診療日時など
  individual_uuid     BINARY(16) NULL,                                 -- 任意：印字補助
  individual_label    VARCHAR(120) NULL,                               -- 任意：個体表示名 等
  created_at          DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),

  /* 重複取り込み防止（同一ヘッダ内で同一sourceは一度だけ） */
  UNIQUE KEY uq_src_hdr_ckp (snap_header_uuid, source_checkup_uuid),

  KEY idx_src_hdr      (snap_header_uuid, id),
  KEY idx_src_src      (source_checkup_uuid),
  KEY idx_src_clinic   (clinic_uuid, snap_header_uuid, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_snap_receipt_checkups_bi_uuid_v7
BEFORE INSERT ON snap_receipt_checkups
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL
     OR NEW.uuid = 0x00000000000000000000000000000000 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

DELIMITER $$
/* 親スナップヘッダから clinic_uuid を固定継承 */
CREATE TRIGGER tr_snap_receipt_checkups_bi_clinic
BEFORE INSERT ON snap_receipt_checkups
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid IS NULL THEN
    SELECT h.clinic_uuid INTO NEW.clinic_uuid
      FROM snap_receipt_headers h
     WHERE h.uuid = NEW.snap_header_uuid
     LIMIT 1;
  END IF;
END $$
DELIMITER ;

/* =========================================================
   4) snap_receipt_items — スナップ明細（点数/自由価格 両立）
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS snap_receipt_items (
  id                     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                   BINARY(16) NOT NULL UNIQUE,                   -- 明細UUID
  snap_checkup_uuid      BINARY(16) NOT NULL,                          -- ↔ snap_receipt_checkups.uuid
  clinic_uuid            BINARY(16) NOT NULL,                          -- 親CKPから固定継承
  source_checkup_item_id INT UNSIGNED NOT NULL,                        -- 由来：checkup_items.id

  /* マスタ/入力の当時値スナップ（印字・再現に必要な範囲を保持） */
  description            VARCHAR(255) NOT NULL,                        -- 例: 処置/薬品名
  qty_unit               VARCHAR(32)  NULL,                            -- 例: mL, 回, 錠...
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
  subtotal_yen           INT UNSIGNED NOT NULL DEFAULT 0,              -- 税抜
  tax_yen                INT UNSIGNED NOT NULL DEFAULT 0,
  total_yen              INT UNSIGNED NOT NULL DEFAULT 0,              -- 税込

  note                   VARCHAR(255) NULL,
  created_at             DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),

  /* 重複取り込み防止（同一チェックアップスナップ内の同一sourceは一度だけ） */
  UNIQUE KEY uq_sri_ckp_src (snap_checkup_uuid, source_checkup_item_id),

  KEY idx_sri_ckp     (snap_checkup_uuid, id),
  KEY idx_sri_source  (source_checkup_item_id),
  KEY idx_sri_clinic  (clinic_uuid, snap_checkup_uuid, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_snap_receipt_items_bi_uuid_v7
BEFORE INSERT ON snap_receipt_items
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL
     OR NEW.uuid = 0x00000000000000000000000000000000 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

DELIMITER $$
/* 親CKPスナップから clinic_uuid を固定継承 */
CREATE TRIGGER tr_snap_receipt_items_bi_clinic
BEFORE INSERT ON snap_receipt_items
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid IS NULL THEN
    SELECT c.clinic_uuid INTO NEW.clinic_uuid
      FROM snap_receipt_checkups c
     WHERE c.uuid = NEW.snap_checkup_uuid
     LIMIT 1;
  END IF;
END $$
DELIMITER ;
