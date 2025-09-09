SET NAMES utf8mb4;

-- ================================================
-- vetDB p015.4 — chart + disease + docsnap(snap_chart_*) + header_links
-- 方針要点：
--  - ドラフト＝ chart_headers（*_draft は廃止）
--  - 確定スナップ＝ snap_chart_headers / snap_chart_checkups / snap_chart_items
--  - ヘッダ配下の checkups 所属の「唯一の正」＝ header_links
--  - すべて DATETIME(6) に統一
--  - clinics への FK は付与しない（CSIFH）
--  - UUID トリガは NULL または all-zero(0x00...) を採番条件として扱う
-- ================================================

/* 再デプロイ安全化：旧版/関連トリガのDROP（存在しなくてもOK） */
DROP TRIGGER IF EXISTS tr_disease_master_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_chart_headers_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_chart_headers_bi_clinic_and_scope;
DROP TRIGGER IF EXISTS tr_chart_headers_bu_rowver_and_resync;
DROP TRIGGER IF EXISTS tr_snap_chart_headers_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_snap_chart_checkups_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_snap_chart_checkups_bi_clinic;
DROP TRIGGER IF EXISTS tr_snap_chart_items_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_snap_chart_items_bi_clinic;

/* 旧構成のトリガ/表（p15.3系）の掃除 */
DROP TRIGGER IF EXISTS tr_chart_items_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_chart_items_bi_clinic;
DROP TRIGGER IF EXISTS tr_chart_checkups_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_chart_checkups_bi_clinic;
DROP TRIGGER IF EXISTS tr_chart_headers_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_chart_headers_bi_clinic;
DROP TRIGGER IF EXISTS tr_chart_header_drafts_bu_rowver;
DROP TRIGGER IF EXISTS tr_chart_header_drafts_bu_clinic_sync;
DROP TRIGGER IF EXISTS tr_chart_header_drafts_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_chart_header_drafts_bi_clinic;

/* 再デプロイ安全化：表のDROP（子→親の順） */
DROP TABLE IF EXISTS snap_chart_items;
DROP TABLE IF EXISTS snap_chart_checkups;
DROP TABLE IF EXISTS snap_chart_headers;
DROP TABLE IF EXISTS header_links;                -- ← これから再作成
DROP TABLE IF EXISTS chart_header_drafts;         -- 廃止
DROP TABLE IF EXISTS chart_items;                 -- 旧スナップ配下（廃止）
DROP TABLE IF EXISTS chart_checkups;              -- 旧スナップ配下（廃止）
DROP TABLE IF EXISTS chart_headers;               -- 旧：確定／新：ドラフト（再作成のため一旦DROP）
DROP TABLE IF EXISTS disease_chief_complaint_rules;
DROP TABLE IF EXISTS disease_master;

/* =========================================================
   1) disease_master — 疾病マスタ（全院共通）
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS disease_master (
  id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid              BINARY(16) NOT NULL UNIQUE,                           -- v7 UUID
  code6             CHAR(6) NOT NULL UNIQUE,                              -- 6桁コード（0埋め）
  major_name        VARCHAR(32) NOT NULL,
  middle_name       VARCHAR(32) NOT NULL,
  minor_name        VARCHAR(32) NOT NULL,

  major_code        CHAR(2) AS (SUBSTRING(code6, 1, 2)) VIRTUAL,
  middle_code       CHAR(2) AS (SUBSTRING(code6, 3, 2)) VIRTUAL,
  minor_code        CHAR(2) AS (SUBSTRING(code6, 5, 2)) VIRTUAL,

  display_code      VARCHAR(8)
    AS (CONCAT_WS('-', major_code, middle_code, minor_code)) PERSISTENT,
  display_name      VARCHAR(255)
    AS (CONCAT_WS(' / ', major_name, middle_name, minor_name)) PERSISTENT,

  is_active         TINYINT(1) NOT NULL DEFAULT 1,
  row_version       BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at        DATETIME(6) NULL,
  created_at        DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at        DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),

  CHECK (code6 REGEXP '^[0-9]{6}$'),

  INDEX idx_dm_name (major_name, middle_name, minor_name),
  INDEX idx_dm_list (deleted_at, updated_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_disease_master_bi_uuid_v7
BEFORE INSERT ON disease_master
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL
     OR NEW.uuid = 0x00000000000000000000000000000000 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

/* =========================================================
   2) disease_chief_complaint_rules — 主訴サジェスト
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS disease_chief_complaint_rules (
  id                     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  disease_id             INT UNSIGNED NOT NULL,                 -- ↔ disease_master.id
  chief_complaint_text   VARCHAR(128) NOT NULL,
  display_order          SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  is_active              TINYINT(1) NOT NULL DEFAULT 1,

  created_at             DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at             DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),

  CONSTRAINT fk_dccr_disease
    FOREIGN KEY (disease_id) REFERENCES disease_master(id)
    ON UPDATE CASCADE ON DELETE CASCADE,

  INDEX idx_dccr_fetch (disease_id, is_active, display_order, id),
  INDEX idx_dccr_text  (chief_complaint_text)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* =========================================================
   3) chart_headers — ドラフト（編集中ヘッダ）
   ---------------------------------------------------------
   - scope_table/scope_uuid を導入（個体スコープ固定）
   - clinics への FK は付与しない（CSIFH）
   - 印刷/発行系の列は「補助フラグ」として残置（最終の正は snap_*）
   ========================================================= */
CREATE TABLE IF NOT EXISTS chart_headers (
  id                        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                      BINARY(16) NOT NULL UNIQUE,                   -- v7 UUID

  clinic_uuid               BINARY(16) NOT NULL,                           -- 当時の院（clinics.uuid）値
  scope_table               VARCHAR(32) NOT NULL,                          -- 例: 'individuals'（固定）
  scope_uuid                BINARY(16) NOT NULL,                           -- = individual_uuid

  /* 強整合FK */
  individual_uuid           BINARY(16) NOT NULL,                           -- ↔ individuals.uuid
  farm_uuid                 BINARY(16) NOT NULL,                           -- ↔ farms.uuid
  insurance_enrollment_id   INT UNSIGNED NULL,                             -- ↔ insurance_enrollments.id

  /* 任意の表示/備考（命名統一） */
  doc_title                 VARCHAR(120) NULL,
  doc_note                  VARCHAR(255) NULL,

  /* 保険期間識別（編集中はNULL可） */
  fiscal_year               YEAR NULL,
  claim_month               TINYINT UNSIGNED NULL,                         -- 1..12
  CHECK (claim_month IS NULL OR claim_month BETWEEN 1 AND 12),

  /* 転帰・期間（編集中はNULL可） */
  outcome_code              TINYINT UNSIGNED NULL,                         -- 1治癒/2死亡/3法令殺/4廃用/5中止
  onset_date                DATE NULL,
  first_visit_date          DATE NULL,
  last_visit_date           DATE NULL,
  outcome_date              DATE NULL,
  visit_count               INT UNSIGNED NOT NULL DEFAULT 0,

  /* 主訴・診断（スナップ候補） */
  chief_complaint           VARCHAR(255) NULL,
  diagnosis_text            VARCHAR(255) NULL,

  /* 疾病（6桁コード＋表示名×最大3本） */
  disease1_code             CHAR(6) NULL,
  disease1_name             VARCHAR(255) NULL,
  disease2_code             CHAR(6) NULL,
  disease2_name             VARCHAR(255) NULL,
  disease3_code             CHAR(6) NULL,
  disease3_name             VARCHAR(255) NULL,
  CHECK (disease1_code IS NULL OR disease1_code REGEXP '^[0-9]{6}$'),
  CHECK (disease2_code IS NULL OR disease2_code REGEXP '^[0-9]{6}$'),
  CHECK (disease3_code IS NULL OR disease3_code REGEXP '^[0-9]{6}$'),

  /* 合計（点/金額） */
  total_b_points            INT UNSIGNED NOT NULL DEFAULT 0,
  total_a_points            INT UNSIGNED NOT NULL DEFAULT 0,
  total_price_yen           INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_yen              INT UNSIGNED NOT NULL DEFAULT 0,
  patient_copay_yen         INT UNSIGNED NOT NULL DEFAULT 0,
  insurer_pay_yen           INT UNSIGNED NOT NULL DEFAULT 0,
  tax_yen                   INT UNSIGNED NOT NULL DEFAULT 0,

  /* ドラフト状態（共通） */
  status                    ENUM('open','closed','issued') NOT NULL DEFAULT 'open',
  status_note               VARCHAR(255) NULL,

  /* 補助フラグ：発行/印刷痕跡（最終の正は snap_* 側） */
  printed_at                DATETIME(6) NULL,
  printed_count             INT UNSIGNED NOT NULL DEFAULT 0,
  issued_at                 DATETIME(6) NULL,

  /* 任意のスナップ（プレビュー用） */
  farm_name                 VARCHAR(255) NULL,
  farm_address              VARCHAR(255) NULL,
  farm_insurance_number     VARCHAR(64)  NULL,
  animal_name               VARCHAR(255) NULL,
  ear_tag                   VARCHAR(32)  NULL,
  dam_name                  VARCHAR(255) NULL,
  dam_ear_tag               VARCHAR(32)  NULL,
  breed_code                VARCHAR(32)  NULL,
  kyosai_purpose_code       VARCHAR(32)  NULL,
  clinic_snapshot_json      JSON NULL,
  ins_farm_user_id          INT UNSIGNED NULL,
  ins_subscriber_code       CHAR(8) NULL,
  ins_status                ENUM('加入','非加入','不明','下書き') NULL,
  ins_start_date            DATE NULL,
  ins_end_date              DATE NULL,
  ins_fiscal_year           YEAR NULL,
  ins_source_note           VARCHAR(255) NULL,

  created_by                INT UNSIGNED NULL,
  updated_by                INT UNSIGNED NULL,
  row_version               BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at                DATETIME(6) NULL,
  created_at                DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at                DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),

  /* 強整合FK */
  CONSTRAINT fk_ch_individual
    FOREIGN KEY (individual_uuid) REFERENCES individuals(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_ch_farm
    FOREIGN KEY (farm_uuid)      REFERENCES farms(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_ch_insenroll
    FOREIGN KEY (insurance_enrollment_id) REFERENCES insurance_enrollments(id)
    ON UPDATE CASCADE ON DELETE SET NULL,

  CONSTRAINT fk_ch_dis1 FOREIGN KEY (disease1_code) REFERENCES disease_master(code6)
    ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_ch_dis2 FOREIGN KEY (disease2_code) REFERENCES disease_master(code6)
    ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_ch_dis3 FOREIGN KEY (disease3_code) REFERENCES disease_master(code6)
    ON UPDATE CASCADE ON DELETE SET NULL,

  /* 一覧/検索最適化 */
  INDEX idx_ch_clinic_list      (clinic_uuid, deleted_at, updated_at, id),
  INDEX idx_ch_scope            (scope_table, scope_uuid, deleted_at, updated_at, id),
  INDEX idx_ch_period           (fiscal_year, claim_month),
  INDEX idx_ch_dis1             (disease1_code),
  INDEX idx_ch_dis2             (disease2_code),
  INDEX idx_ch_dis3             (disease3_code),
  INDEX idx_ch_farm             (farm_uuid),
  INDEX idx_ch_list             (deleted_at, updated_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_chart_headers_bi_uuid_v7
BEFORE INSERT ON chart_headers
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL
     OR NEW.uuid = 0x00000000000000000000000000000000 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

DELIMITER $$
/* INSERT時：farm→clinic 継承、scope 固定化、scope_uuid 同期 */
CREATE TRIGGER tr_chart_headers_bi_clinic_and_scope
BEFORE INSERT ON chart_headers
FOR EACH ROW
BEGIN
  -- clinic 継承（CSIFH）
  IF NEW.clinic_uuid IS NULL THEN
    SELECT f.clinic_uuid INTO NEW.clinic_uuid
      FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
  END IF;

  -- scope 固定（個体スコープ）
  IF NEW.scope_table IS NULL OR NEW.scope_table = '' THEN
    SET NEW.scope_table = 'individuals';
  END IF;

  -- scope_uuid は individual_uuid と同期
  IF NEW.scope_uuid IS NULL THEN
    SET NEW.scope_uuid = NEW.individual_uuid;
  END IF;
END $$
DELIMITER ;

DELIMITER $$
/* UPDATE時：farm変更で clinic 再継承、individual変更で scope_uuid 同期、row_version++ */
CREATE TRIGGER tr_chart_headers_bu_rowver_and_resync
BEFORE UPDATE ON chart_headers
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;

  IF NEW.farm_uuid <> OLD.farm_uuid OR (NEW.clinic_uuid IS NULL) THEN
    SELECT f.clinic_uuid INTO NEW.clinic_uuid
      FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
  END IF;

  IF NEW.individual_uuid <> OLD.individual_uuid OR (NEW.scope_uuid IS NULL) THEN
    SET NEW.scope_uuid = NEW.individual_uuid;
  END IF;

  -- scope_table は固定方針（必要なら手動更新）
END $$
DELIMITER ;

/* =========================================================
   4) header_links — ヘッダと checkups の所属リンク（唯一の正）
   ---------------------------------------------------------
   - ポリモーフィック参照のためヘッダ側FKは張らない（header_table/header_uuid）
   - checkup は強FK
   - 同一ヘッダ内の重複リンクは is_active（=deleted_at IS NULL）を含めて一意禁止
   ========================================================= */
CREATE TABLE IF NOT EXISTS header_links (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  header_table  VARCHAR(32) NOT NULL,                 -- 例: 'chart_headers', 'receipt_headers' 等
  header_uuid   BINARY(16) NOT NULL,                  -- ヘッダUUID
  checkup_uuid  BINARY(16) NOT NULL,                  -- ↔ checkups.uuid
  deleted_at    DATETIME(6) NULL,
  created_at    DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),

  is_active     TINYINT(1) AS (deleted_at IS NULL) STORED,

  CONSTRAINT fk_hl_checkup
    FOREIGN KEY (checkup_uuid) REFERENCES checkups(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,

  UNIQUE KEY uq_hl_active (header_table, header_uuid, checkup_uuid, is_active),
  KEY idx_hl_header (header_table, header_uuid, is_active, checkup_uuid),
  KEY idx_hl_checkup (checkup_uuid, is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* =========================================================
   5) docsnap（確定スナップ）— snap_chart_headers
   ---------------------------------------------------------
   - 最終状態の正は snap_* 側
   - 由来追跡：source_header_uuid を保持
   ========================================================= */
CREATE TABLE IF NOT EXISTS snap_chart_headers (
  id                        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                      BINARY(16) NOT NULL UNIQUE,                 -- v7 UUID（スナップ識別）
  source_header_uuid        BINARY(16) NOT NULL,                        -- 由来：chart_headers.uuid

  clinic_uuid               BINARY(16) NOT NULL,                        -- 当時の院
  individual_uuid           BINARY(16) NOT NULL,
  farm_uuid                 BINARY(16) NOT NULL,
  insurance_enrollment_id   INT UNSIGNED NULL,

  doc_title                 VARCHAR(120) NULL,
  doc_note                  VARCHAR(255) NULL,

  fiscal_year               YEAR NOT NULL,
  claim_month               TINYINT UNSIGNED NOT NULL,                  -- 1..12
  CHECK (claim_month BETWEEN 1 AND 12),

  outcome_code              TINYINT UNSIGNED NOT NULL,
  onset_date                DATE NULL,
  first_visit_date          DATE NULL,
  last_visit_date           DATE NULL,
  outcome_date              DATE NULL,
  visit_count               INT UNSIGNED NOT NULL DEFAULT 0,

  chief_complaint           VARCHAR(255) NULL,
  diagnosis_text            VARCHAR(255) NULL,

  disease1_code             CHAR(6) NULL,
  disease1_name             VARCHAR(255) NULL,
  disease2_code             CHAR(6) NULL,
  disease2_name             VARCHAR(255) NULL,
  disease3_code             CHAR(6) NULL,
  disease3_name             VARCHAR(255) NULL,
  CHECK (disease1_code IS NULL OR disease1_code REGEXP '^[0-9]{6}$'),
  CHECK (disease2_code IS NULL OR disease2_code REGEXP '^[0-9]{6}$'),
  CHECK (disease3_code IS NULL OR disease3_code REGEXP '^[0-9]{6}$'),

  total_b_points            INT UNSIGNED NOT NULL DEFAULT 0,
  total_a_points            INT UNSIGNED NOT NULL DEFAULT 0,
  total_price_yen           INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_yen              INT UNSIGNED NOT NULL DEFAULT 0,
  patient_copay_yen         INT UNSIGNED NOT NULL DEFAULT 0,
  insurer_pay_yen           INT UNSIGNED NOT NULL DEFAULT 0,
  tax_yen                   INT UNSIGNED NOT NULL DEFAULT 0,

  /* スナップ最終状態 */
  status                    ENUM('printed','voided') NULL DEFAULT NULL,
  printed_at                DATETIME(6) NULL,
  printed_count             INT UNSIGNED NOT NULL DEFAULT 0,
  voided_at                 DATETIME(6) NULL,
  void_reason               VARCHAR(255) NULL,

  /* 任意：印字/レイアウト */
  farm_name                 VARCHAR(255) NULL,
  farm_address              VARCHAR(255) NULL,
  farm_insurance_number     VARCHAR(64)  NULL,
  animal_name               VARCHAR(255) NULL,
  ear_tag                   VARCHAR(32)  NULL,
  dam_name                  VARCHAR(255) NULL,
  dam_ear_tag               VARCHAR(32)  NULL,
  breed_code                VARCHAR(32)  NULL,
  kyosai_purpose_code       VARCHAR(32)  NULL,
  clinic_snapshot_json      JSON NULL,
  ins_farm_user_id          INT UNSIGNED NULL,
  ins_subscriber_code       CHAR(8) NULL,
  ins_status                ENUM('加入','非加入','不明','下書き') NULL,
  ins_start_date            DATE NULL,
  ins_end_date              DATE NULL,
  ins_fiscal_year           YEAR NULL,
  ins_source_note           VARCHAR(255) NULL,

  created_by                INT UNSIGNED NULL,
  created_at                DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at                DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),

  INDEX idx_sch_clinic_list (clinic_uuid, updated_at, id),
  INDEX idx_sch_period      (fiscal_year, claim_month),
  INDEX idx_sch_status      (status),
  INDEX idx_sch_individual  (individual_uuid),
  INDEX idx_sch_farm        (farm_uuid),
  INDEX idx_sch_outcome     (outcome_code),
  INDEX idx_sch_dis1        (disease1_code),
  INDEX idx_sch_dis2        (disease2_code),
  INDEX idx_sch_dis3        (disease3_code),
  INDEX idx_sch_list        (updated_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_snap_chart_headers_bi_uuid_v7
BEFORE INSERT ON snap_chart_headers
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL
     OR NEW.uuid = 0x00000000000000000000000000000000 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

/* =========================================================
   6) snap_chart_checkups — スナップ配下（SOAP/TPR）
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS snap_chart_checkups (
  id                     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                   BINARY(16) NOT NULL UNIQUE,              -- 行UUID
  snap_header_uuid       BINARY(16) NOT NULL,                     -- ↔ snap_chart_headers.uuid
  clinic_uuid            BINARY(16) NOT NULL,                     -- 当時の院
  seq_no                 INT UNSIGNED NOT NULL,                   -- ヘッダ内の並び

  source_checkup_uuid    BINARY(16) NOT NULL,                     -- 由来 checkups.uuid
  source_visit_uuid      BINARY(16) NULL,                         -- 由来 visits.uuid（任意）

  checkup_at             DATETIME(6) NULL,

  subjective_text        TEXT NULL,
  objective_text         TEXT NULL,
  assessment_text        TEXT NULL,
  plan_text              TEXT NULL,
  clinical_course_text   TEXT NULL,

  tpr_temp_c             DECIMAL(4,1) NULL,
  tpr_pulse_bpm          SMALLINT UNSIGNED NULL,
  tpr_resp_bpm           SMALLINT UNSIGNED NULL,

  created_at             DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),

  UNIQUE KEY uq_scc_hdr_seq (snap_header_uuid, seq_no),
  INDEX idx_scc_hdr         (snap_header_uuid),
  INDEX idx_scc_clinic      (clinic_uuid, snap_header_uuid),

  CONSTRAINT fk_scc_header
    FOREIGN KEY (snap_header_uuid) REFERENCES snap_chart_headers(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_snap_chart_checkups_bi_uuid_v7
BEFORE INSERT ON snap_chart_checkups
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL
     OR NEW.uuid = 0x00000000000000000000000000000000 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER tr_snap_chart_checkups_bi_clinic
BEFORE INSERT ON snap_chart_checkups
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid IS NULL THEN
    SELECT h.clinic_uuid INTO NEW.clinic_uuid
      FROM snap_chart_headers h
     WHERE h.uuid = NEW.snap_header_uuid
     LIMIT 1;
  END IF;
END $$
DELIMITER ;

/* =========================================================
   7) snap_chart_items — スナップ明細（点数×価格）
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS snap_chart_items (
  id                       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                     BINARY(16) NOT NULL UNIQUE,            -- 明細UUID
  snap_checkup_uuid        BINARY(16) NOT NULL,                   -- ↔ snap_chart_checkups.uuid
  clinic_uuid              BINARY(16) NOT NULL,                   -- 当時の院
  within_checkup_line_no   INT UNSIGNED NOT NULL,                 -- 受診回内の行順

  source_checkup_uuid      BINARY(16) NOT NULL,                   -- 由来 checkups.uuid
  treatment_uuid           BINARY(16) NULL,                       -- 由来 treatment_master.uuid 等（任意）

  description              VARCHAR(255) NOT NULL,
  qty_unit                 VARCHAR(32) NULL,
  quantity                 DECIMAL(10,2) NOT NULL DEFAULT 1,

  pay_type                 ENUM('insurance','private') NOT NULL,
  unit_b_points            INT UNSIGNED NOT NULL DEFAULT 0,
  unit_a_points            INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_points          INT UNSIGNED NOT NULL DEFAULT 0,
  yen_per_point            DECIMAL(8,2) NOT NULL DEFAULT 0.00,

  unit_price_yen           INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_price_yen       INT UNSIGNED NOT NULL DEFAULT 0,

  tax_rate                 DECIMAL(4,2) NOT NULL DEFAULT 0.00,
  subtotal_yen             INT UNSIGNED NOT NULL DEFAULT 0,

  created_at               DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),

  INDEX idx_sci_parent (snap_checkup_uuid, within_checkup_line_no),
  INDEX idx_sci_clinic (clinic_uuid, snap_checkup_uuid),

  CONSTRAINT fk_sci_ckp
    FOREIGN KEY (snap_checkup_uuid) REFERENCES snap_chart_checkups(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_snap_chart_items_bi_uuid_v7
BEFORE INSERT ON snap_chart_items
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL
     OR NEW.uuid = 0x00000000000000000000000000000000 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER tr_snap_chart_items_bi_clinic
BEFORE INSERT ON snap_chart_items
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid IS NULL THEN
    SELECT c.clinic_uuid INTO NEW.clinic_uuid
      FROM snap_chart_checkups c
     WHERE c.uuid = NEW.snap_checkup_uuid
     LIMIT 1;
  END IF;
END $$
DELIMITER ;
