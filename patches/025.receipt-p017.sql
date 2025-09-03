SET NAMES utf8mb4;

/* =========================================================
   Receipts（下書き→確定スナップ）— 統合DDL（意図付き）
   ---------------------------------------------------------
   ■全体設計方針
     - 「下書き(receipt_header_drafts)」で集計・編集を行い、
       発行(issued)時に不変スナップ（receipt_headers / receipt_checkups / receipt_items）を作成。
     - 下書きは“可変”：row_version / deleted_at を持つ（強い整合が必要）。
     - スナップは“不変”：論理削除なし。取消は status='voided' + voided_at で扱う。
     - UI側ルール：checkups/ checkup_items の「手動付け替えUI」を出さない前提。
         → 付け替えによる矛盾ガードTRIGGERは置かない（簡潔＆運用で防止）。
     - 冪等性：発行処理の再実行・並行実行に備え、スナップ側に UNIQUE を付与。
       （INSERT IGNORE と組み合わせると再実行に強い）

   ■スナップの対象集合
     - 「issued の瞬間」に、draft_uuid に紐づく checkups 配下の checkup_items をそのまま取り込む。
       （= checkups.receipt_header_drafts_uuid がキー。item直付けは現行運用では使用しない）

   ■UUID／ストレージ
     - UUIDは BINARY(16) の v7 を使用（uuid_v7_bin()）。見出しキーはAUTO_INCREMENT + uuid の二段。
     - 文字コードは utf8mb4、COLLATEは utf8mb4_unicode_ci、ROW_FORMAT=DYNAMIC 推奨。

   ■月末請求
     - 集計基準は receipt_headers（非void）を推奨。
       drafts は WIP/進捗管理用。

   ■このDDLに含む内容
     1) receipt_header_drafts（下書きヘッダ）
     2) 既存 checkups / checkup_items に draft 直付けカラムの追加（ON DELETE SET NULL）
        ※ 現行の抽出は checkups のみ参照。item側は将来拡張・整合性観察用。
     3) receipt_headers / receipt_checkups / receipt_items（不変スナップ）
        - 重複防止 UNIQUE を定義
   ========================================================= */

/* --- 再デプロイ安全化：トリガを先に、次いで子→親の順でDROP --- */
DROP TRIGGER IF EXISTS tr_receipt_header_drafts_bu_rowver;
DROP TRIGGER IF EXISTS tr_receipt_header_drafts_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_receipt_headers_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_receipt_checkups_bi_uuid_v7;

DROP TABLE IF EXISTS receipt_items;
DROP TABLE IF EXISTS receipt_checkups;
DROP TABLE IF EXISTS receipt_headers;
DROP TABLE IF EXISTS receipt_header_drafts;

/* =========================================================
   1) 下書きヘッダ：集計の本体（可変）
   ---------------------------------------------------------
   - 集計列（点/円/税/負担）を保持し、発行時にスナップへコピー。
   - status: open / closed / issued
     ・issued_at / issued_receipt_uuid でスナップの対応関係を残す（相互追跡用）。
   - row_version: 楽観ロック。UIは If-Match 的更新を推奨。
   ========================================================= */
CREATE TABLE IF NOT EXISTS receipt_header_drafts (
  id                    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                  BINARY(16) NOT NULL UNIQUE,                  -- v7 UUID（下書きの識別）

  /* 任意のスコープ（印字や絞り込み用。FKは貼らず弱リンク） */
  farm_uuid             BINARY(16) NULL,
  title                 VARCHAR(120) NULL,
  note                  VARCHAR(255) NULL,

  /* 状態遷移（発行で issued に） */
  status                ENUM('open','closed','issued') NOT NULL DEFAULT 'open',
  issued_at             DATETIME NULL,                               -- issued 遷移時刻
  issued_by_user_id     INT UNSIGNED NULL,
  issued_receipt_uuid   BINARY(16) NULL,                             -- 対応する receipt_headers.uuid（作成後にセット）

  /* クリニック設定スナップ：行計算・集計の基準 */
  yen_per_point         DECIMAL(8,2) NOT NULL DEFAULT 10.00,         -- 1点=10円 等
  copay_rate            DECIMAL(5,4) NOT NULL DEFAULT 0.1000,        -- 10% は 0.1000
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
  KEY idx_receipt_drafts_list (deleted_at, updated_at, id),
  KEY idx_receipt_drafts_farm (farm_uuid, deleted_at, updated_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER tr_receipt_header_drafts_bi_uuid_v7
BEFORE INSERT ON receipt_header_drafts
FOR EACH ROW
BEGIN
  /* uuid未指定なら v7 を自動採番 */
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid)=0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER tr_receipt_header_drafts_bu_rowver
BEFORE UPDATE ON receipt_header_drafts
FOR EACH ROW
BEGIN
  /* 楽観ロック用 row_version を自動インクリメント */
  SET NEW.row_version = OLD.row_version + 1;
END $$
DELIMITER ;

/* =========================================================
   2) 既存2表に直付け（UIで付替え操作なし／ドラフト削除で自動デタッチ）
   ---------------------------------------------------------
   - checkups.receipt_header_drafts_uuid:
       スナップ抽出の起点（必須）。発行時は「このdraftにぶら下がるcheckups配下のitems」を採用。
   - checkup_items.receipt_header_drafts_uuid:
       現行抽出では未使用（将来の部分請求/観察用/クエリ補助に備える）。
       ※ 追加が不要ならこのALTERは省いても動作します。
   - ON DELETE SET NULL: draft 削除時に自動デタッチ（UIでは“削除してから再紐付け”という運用に効く）。
   ========================================================= */
ALTER TABLE checkups
  ADD COLUMN receipt_header_drafts_uuid BINARY(16) NULL AFTER individual_uuid,
  ADD KEY idx_checkups_rhd (receipt_header_drafts_uuid, id),
  ADD CONSTRAINT fk_checkups_rhd
    FOREIGN KEY (receipt_header_drafts_uuid) REFERENCES receipt_header_drafts(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL;

ALTER TABLE checkup_items
  ADD COLUMN receipt_header_drafts_uuid BINARY(16) NULL AFTER checkup_uuid,
  ADD KEY idx_ckpitems_rhd (receipt_header_drafts_uuid, id),
  ADD CONSTRAINT fk_ckpitems_rhd
    FOREIGN KEY (receipt_header_drafts_uuid) REFERENCES receipt_header_drafts(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL;

/* =========================================================
   3) 確定ヘッダ：不変スナップ（弱リンク）
   ---------------------------------------------------------
   - printed/voided を status で持つ（未印刷はNULL）。voidedは取消記録。
   - クリニック設定・集計はdraftからコピー（不変化）。
   - 月末請求の集計基準として使用（voided除外）。
   ========================================================= */
CREATE TABLE IF NOT EXISTS receipt_headers (
  id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                BINARY(16) NOT NULL UNIQUE,                  -- v7 UUID（スナップの識別）
  farm_uuid           BINARY(16) NULL,                             -- 弱リンク（将来の参照用）
  receipt_no          VARCHAR(40) NULL UNIQUE,                     -- 任意の対外発番（UI採番）
  title               VARCHAR(120) NULL,
  note                VARCHAR(255) NULL,

  issued_at           DATETIME NOT NULL,                           -- 発行日時（スナップ時刻）
  issued_by_user_id   INT UNSIGNED NULL,

  status              ENUM('printed','voided') NULL DEFAULT NULL,  -- 未印刷(NULL)/印刷済/取消
  printed_at          DATETIME NULL,
  printed_count       INT UNSIGNED NOT NULL DEFAULT 0,
  voided_at           DATETIME NULL,
  void_reason         VARCHAR(255) NULL,
  voided_by_user_id   INT UNSIGNED NULL,

  /* クリニック設定スナップ（固定） */
  yen_per_point       DECIMAL(8,2) NOT NULL,
  copay_rate          DECIMAL(5,4) NOT NULL,
  tax_rounding        ENUM('floor','round','ceil') NOT NULL,

  /* 集計スナップ（固定） */
  total_b_points      INT UNSIGNED NOT NULL,
  total_a_points      INT UNSIGNED NOT NULL,
  total_price_yen     INT UNSIGNED NOT NULL,
  subtotal_yen        INT UNSIGNED NOT NULL,
  tax_yen             INT UNSIGNED NOT NULL,
  total_insurance_yen INT UNSIGNED NOT NULL,
  total_private_yen   INT UNSIGNED NOT NULL,
  patient_copay_yen   INT UNSIGNED NOT NULL,
  insurer_pay_yen     INT UNSIGNED NOT NULL,

  /* 任意：印字/レイアウト用のクリニック情報 */
  clinic_snapshot_json JSON NULL,

  created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  /* 代表的な検索用インデックス */
  KEY idx_rcpt_hdr_issued (issued_at, id),
  KEY idx_rcpt_hdr_status (status, issued_at, id),
  KEY idx_rcpt_hdr_farm   (farm_uuid, issued_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER tr_receipt_headers_bi_uuid_v7
BEFORE INSERT ON receipt_headers
FOR EACH ROW
BEGIN
  /* uuid未指定なら v7 を自動採番 */
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid)=0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

/* =========================================================
   4) 確定：チェックアップスナップ（不変）
   ---------------------------------------------------------
   - receipt_checkups.uuid は items から参照するため “列UUID” を持つ。
   - source_checkup_uuid には元の checkups.uuid を保存（監査・追跡）。
   - UNIQUE(receipt_header_uuid, source_checkup_uuid) で
     同一レシート内の二重取り込みを防止（発行再実行への保険）。
   ========================================================= */
CREATE TABLE IF NOT EXISTS receipt_checkups (
  id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                BINARY(16) NOT NULL UNIQUE,                  -- v7（items から参照）
  receipt_header_uuid BINARY(16) NOT NULL,                         -- ↔ receipt_headers.uuid（弱リンク）
  source_checkup_uuid BINARY(16) NOT NULL,                         -- 由来：checkups.uuid
  checkup_at          DATETIME NULL,                               -- 任意：診療日時など
  individual_uuid     BINARY(16) NULL,                             -- 任意：印字補助
  individual_label    VARCHAR(120) NULL,                           -- 任意：個体表示名 等
  created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

  /* 重複取り込み防止（同一ヘッダ内で同一sourceは一度だけ） */
  UNIQUE KEY uq_rcpt_hdr_src (receipt_header_uuid, source_checkup_uuid),

  KEY idx_rcpt_ckp_hdr   (receipt_header_uuid, id),
  KEY idx_rcpt_ckp_src   (source_checkup_uuid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER tr_receipt_checkups_bi_uuid_v7
BEFORE INSERT ON receipt_checkups
FOR EACH ROW
BEGIN
  /* uuid未指定なら v7 を自動採番（items が参照するため必須） */
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid)=0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

/* =========================================================
   5) 確定：行為明細スナップ（不変）
   ---------------------------------------------------------
   - receipt_items は receipt_checkups.uuid を参照（ヘッダは辿れる）。
   - source_checkup_item_id に元の checkup_items.id を保存（監査）。
   - UNIQUE(receipt_checkup_uuid, source_checkup_item_id) で
     同一チェックアップスナップ内の二重取り込みを防止。
   - 計算列（subtotal_yen/tax_yen/total_yen）は発行時に再計算し値保存。
   ========================================================= */
CREATE TABLE IF NOT EXISTS receipt_items (
  id                     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  receipt_checkup_uuid   BINARY(16) NOT NULL,                       -- ↔ receipt_checkups.uuid（弱リンク）
  source_checkup_item_id INT UNSIGNED NOT NULL,                     -- 由来：checkup_items.id

  /* マスタ/入力の当時値スナップ（印字・再現に必要な範囲を保持） */
  description            VARCHAR(255) NOT NULL,                      -- 例: 処置/薬品名
  qty_unit               VARCHAR(32)  NULL,                          -- 例: mL, 回, 錠...
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
  subtotal_yen           INT UNSIGNED NOT NULL DEFAULT 0,            -- 税抜
  tax_yen                INT UNSIGNED NOT NULL DEFAULT 0,
  total_yen              INT UNSIGNED NOT NULL DEFAULT 0,            -- 税込

  note                   VARCHAR(255) NULL,
  created_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

  /* 重複取り込み防止（同一チェックアップスナップ内の同一sourceは一度だけ） */
  UNIQUE KEY uq_rcptitem_ckp_src (receipt_checkup_uuid, source_checkup_item_id),

  KEY idx_rcpt_items_ckpuuid (receipt_checkup_uuid, id),
  KEY idx_rcpt_items_source  (source_checkup_item_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
