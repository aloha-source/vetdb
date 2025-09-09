SET NAMES utf8mb4;

/* =========================================================
   vetDB p015.1 (+ CSIFH-PureMirror v1) — chart+disease 統合 DDL
   ---------------------------------------------------------
   目的（CSIFH-PureMirror v1）
   - 多病院対応：実データに clinic_uuid を「当時値」で固定保存
   - 継承規則：
       chart_header_drafts  : farms.clinic_uuid を継承（可変：farm変更時は再継承）
       chart_headers        : farms.clinic_uuid を継承（確定時点の当時値）
       chart_checkups       : 親 chart_headers.clinic_uuid を継承
       chart_items          : 親 chart_checkups.clinic_uuid を継承
   - 疎結合方針：clinics への FK は**付与しない**（スナップ/移行容易性を優先）
   - 高速絞込：clinic_uuid 先頭の複合INDEXを付与
   ========================================================= */

/* 再デプロイ安全化：トリガ→子→親の順にDROP（原文＋CSIFH追加分） */
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
DROP TRIGGER IF EXISTS tr_disease_master_bi_uuid_v7;

DROP TABLE IF EXISTS chart_items;
DROP TABLE IF EXISTS chart_checkups;
DROP TABLE IF EXISTS chart_headers;
DROP TABLE IF EXISTS chart_header_drafts;
DROP TABLE IF EXISTS disease_chief_complaint_rules;
DROP TABLE IF EXISTS disease_master;

/* =========================================================
   1) disease_master — 疾病マスタ（全院共通：clinic_uuid なし）
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS disease_master (
  id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,            -- 数値主キー
  uuid              BINARY(16) NOT NULL UNIQUE,                         -- v7 UUID

  code6             CHAR(6) NOT NULL UNIQUE,                            -- 6桁コード（0埋め必須）
  major_name        VARCHAR(32) NOT NULL,                               -- 大分類名
  middle_name       VARCHAR(32) NOT NULL,                               -- 中分類名
  minor_name        VARCHAR(32) NOT NULL,                               -- 小分類名

  major_code        CHAR(2) AS (SUBSTRING(code6, 1, 2)) VIRTUAL,        -- 先頭2桁
  middle_code       CHAR(2) AS (SUBSTRING(code6, 3, 2)) VIRTUAL,        -- 中間2桁
  minor_code        CHAR(2) AS (SUBSTRING(code6, 5, 2)) VIRTUAL,        -- 末尾2桁

  display_code      VARCHAR(8)
    AS (CONCAT_WS('-', major_code, middle_code, minor_code)) PERSISTENT, -- 表示コード XX-YY-ZZ
  display_name      VARCHAR(255)
    AS (CONCAT_WS(' / ', major_name, middle_name, minor_name)) PERSISTENT, -- 表示名称 major / middle / minor

  is_active         TINYINT(1) NOT NULL DEFAULT 1,                     -- 有効フラグ
  row_version       BIGINT UNSIGNED NOT NULL DEFAULT 1,                -- 将来の差分同期/並行制御
  deleted_at        DATETIME NULL,                                     -- 論理削除（マスタのみ許容）
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  CHECK (code6 REGEXP '^[0-9]{6}$'),

  INDEX idx_dm_name (major_name, middle_name, minor_name),
  INDEX idx_dm_list (deleted_at, updated_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_disease_master_bi_uuid_v7
BEFORE INSERT ON disease_master
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid) = 0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

/* =========================================================
   2) disease_chief_complaint_rules — 主訴（凛告）サジェスト
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS disease_chief_complaint_rules (
  id                     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  disease_id             INT UNSIGNED NOT NULL,                   -- ↔ disease_master.id
  chief_complaint_text   VARCHAR(128) NOT NULL,                   -- サジェスト表示文言
  display_order          SMALLINT UNSIGNED NOT NULL DEFAULT 0,    -- 昇順で上位表示
  is_active              TINYINT(1) NOT NULL DEFAULT 1,

  created_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  CONSTRAINT fk_dccr_disease
    FOREIGN KEY (disease_id) REFERENCES disease_master(id)
    ON UPDATE CASCADE ON DELETE CASCADE,

  INDEX idx_dccr_fetch (disease_id, is_active, display_order, id),
  INDEX idx_dccr_text  (chief_complaint_text)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* =========================================================
   3) chart_header_drafts — 編集中ヘッダ（強整合＋可変）
   ---------------------------------------------------------
   CSIFH適用差分：
   - clinic_uuid 追加（NOT NULL）。INSERT時に farms から継承。
   - farm_uuid 変更時は clinic_uuid を再継承（可変のため）。
   - 院別絞込用 INDEX を追加。
   ========================================================= */
CREATE TABLE IF NOT EXISTS chart_header_drafts (
  id                        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                      BINARY(16) NOT NULL UNIQUE,                 -- v7 UUID（TRIGGER付与）

  /* CSIFH: 当時の院（clinics.uuid）値を固定保持。clinics へのFKは付与しない */
  clinic_uuid               BINARY(16) NOT NULL,

  /* 強整合FK（削除はRESTRICT、保険は任意でSET NULL） */
  individual_uuid           BINARY(16) NOT NULL,                        -- ↔ individuals.uuid
  farm_uuid                 BINARY(16) NOT NULL,                        -- ↔ farms.uuid
  insurance_enrollment_id   INT UNSIGNED NULL,                          -- ↔ insurance_enrollments.id

  fiscal_year               YEAR NULL,                                  -- 編集中はNULL許容
  claim_month               TINYINT UNSIGNED NULL,                      -- 1..12
  CHECK (claim_month IS NULL OR claim_month BETWEEN 1 AND 12),

  outcome_code              TINYINT UNSIGNED NULL,                      -- 1治癒/2死亡/3法令殺/4廃用/5中止
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

  draft_status              ENUM('open','closed','issued') NOT NULL DEFAULT 'open',  -- open治療中/closed転帰済/issuedスナップ発行済
  status_note               VARCHAR(255) NULL,

  printed_at                DATETIME NULL,
  printed_count             INT UNSIGNED NOT NULL DEFAULT 0,
  issued_at                 DATETIME NULL,

  /* 任意のスナップ（プレビュー用途） */
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
  row_version               BIGINT UNSIGNED NOT NULL DEFAULT 1,          -- 楽観ロック
  deleted_at                DATETIME NULL,                                -- ソフトデリート
  created_at                DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  /* 強整合FK */
  CONSTRAINT fk_chd_individual
    FOREIGN KEY (individual_uuid) REFERENCES individuals(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_chd_farm
    FOREIGN KEY (farm_uuid)      REFERENCES farms(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_chd_insenroll
    FOREIGN KEY (insurance_enrollment_id) REFERENCES insurance_enrollments(id)
    ON UPDATE CASCADE ON DELETE SET NULL,

  CONSTRAINT fk_chd_dis1 FOREIGN KEY (disease1_code) REFERENCES disease_master(code6)
    ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_chd_dis2 FOREIGN KEY (disease2_code) REFERENCES disease_master(code6)
    ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_chd_dis3 FOREIGN KEY (disease3_code) REFERENCES disease_master(code6)
    ON UPDATE CASCADE ON DELETE SET NULL,

  /* 一覧/検索最適化（院→更新） */
  INDEX idx_chd_clinic_list (clinic_uuid, deleted_at, updated_at, id),
  INDEX idx_hdr_drafts_open   (individual_uuid, draft_status, created_at),
  INDEX idx_hdr_drafts_period (fiscal_year, claim_month),
  INDEX idx_hdr_drafts_dis1   (disease1_code),
  INDEX idx_hdr_drafts_dis2   (disease2_code),
  INDEX idx_hdr_drafts_dis3   (disease3_code),
  INDEX idx_hdr_drafts_farm   (farm_uuid),
  INDEX idx_hdr_drafts_list   (deleted_at, updated_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_chart_header_drafts_bi_uuid_v7
BEFORE INSERT ON chart_header_drafts
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid) = 0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

DELIMITER $$
/* CSIFH: INSERT時に farms.clinic_uuid を継承（アプリから clinic_uuid を渡す必要なし） */
CREATE TRIGGER tr_chart_header_drafts_bi_clinic
BEFORE INSERT ON chart_header_drafts
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid IS NULL OR LENGTH(NEW.clinic_uuid) = 0 THEN
    SELECT f.clinic_uuid INTO NEW.clinic_uuid
      FROM farms f
     WHERE f.uuid = NEW.farm_uuid
     LIMIT 1;
  END IF;
END $$
DELIMITER ;

DELIMITER $$
/* 任意：draft 内で farm_uuid を変更した場合に clinic_uuid も再継承して整合させる */
CREATE TRIGGER tr_chart_header_drafts_bu_clinic_sync
BEFORE UPDATE ON chart_header_drafts
FOR EACH ROW
BEGIN
  IF NEW.farm_uuid <> OLD.farm_uuid THEN
    SELECT f.clinic_uuid INTO NEW.clinic_uuid
      FROM farms f
     WHERE f.uuid = NEW.farm_uuid
     LIMIT 1;
  END IF;
  /* row_version の更新は既存トリガで実施 */
END $$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER tr_chart_header_drafts_bu_rowver
BEFORE UPDATE ON chart_header_drafts
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END $$
DELIMITER ;

/* =========================================================
   4) chart_headers — 確定スナップ（不変）
   ---------------------------------------------------------
   CSIFH適用差分：
   - clinic_uuid 追加（NOT NULL）。INSERT時に farms から継承。
   - 院別絞込 INDEX を追加。
   - 個体/牧場/保険は弱リンク（原文踏襲；FKなし）。
   ========================================================= */
CREATE TABLE IF NOT EXISTS chart_headers (
  id                        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                      BINARY(16) NOT NULL UNIQUE,                -- v7 UUID

  clinic_uuid               BINARY(16) NOT NULL,                        -- 当時の院（clinics.uuid）値

  /* 追跡弱リンク（確定後は変更しないためFKなしでも可） */
  individual_uuid           BINARY(16) NOT NULL,
  farm_uuid                 BINARY(16) NOT NULL,
  insurance_enrollment_id   INT UNSIGNED NULL,

  /* 保険期間識別 */
  fiscal_year               YEAR NOT NULL,
  claim_month               TINYINT UNSIGNED NOT NULL,                 -- 1..12
  CHECK (claim_month BETWEEN 1 AND 12),

  /* 転帰・期間（確定値） */
  outcome_code              TINYINT UNSIGNED NOT NULL,                 -- 1治癒/2死亡/3法令殺/4廃用/5中止
  onset_date                DATE NULL,
  first_visit_date          DATE NULL,
  last_visit_date           DATE NULL,
  outcome_date              DATE NULL,
  visit_count               INT UNSIGNED NOT NULL DEFAULT 0,

  /* 主訴・診断（スナップ） */
  chief_complaint           VARCHAR(255) NULL,
  diagnosis_text            VARCHAR(255) NULL,

  /* 疾病スナップ（6桁コード＋表示名） */
  disease1_code             CHAR(6) NULL,
  disease1_name             VARCHAR(255) NULL,
  disease2_code             CHAR(6) NULL,
  disease2_name             VARCHAR(255) NULL,
  disease3_code             CHAR(6) NULL,
  disease3_name             VARCHAR(255) NULL,

  CHECK (disease1_code IS NULL OR disease1_code REGEXP '^[0-9]{6}$'),
  CHECK (disease2_code IS NULL OR disease2_code REGEXP '^[0-9]{6}$'),
  CHECK (disease3_code IS NULL OR disease3_code REGEXP '^[0-9]{6}$'),

  /* 金額・点数合計（スナップ） */
  total_b_points            INT UNSIGNED NOT NULL DEFAULT 0,
  total_a_points            INT UNSIGNED NOT NULL DEFAULT 0,
  total_price_yen           INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_yen              INT UNSIGNED NOT NULL DEFAULT 0,
  patient_copay_yen         INT UNSIGNED NOT NULL DEFAULT 0,
  insurer_pay_yen           INT UNSIGNED NOT NULL DEFAULT 0,
  tax_yen                   INT UNSIGNED NOT NULL DEFAULT 0,

  /* ステータス：printed / voided（未印刷はNULL） */
  status                    ENUM('printed','voided') NULL DEFAULT NULL,
  printed_at                DATETIME NULL,
  printed_count             INT UNSIGNED NOT NULL DEFAULT 0,
  voided_at                 DATETIME NULL,
  void_reason               VARCHAR(255) NULL,

  /* スナップ時の表示/保険情報（任意） */
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
  created_at                DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  /* 索引（院→期間→更新） */
  INDEX idx_ch_clinic_list            (clinic_uuid, updated_at, id),
  INDEX idx_chart_headers_period      (fiscal_year, claim_month),
  INDEX idx_chart_headers_status      (status),
  INDEX idx_chart_headers_individual  (individual_uuid),
  INDEX idx_chart_headers_farm        (farm_uuid),
  INDEX idx_chart_headers_outcome     (outcome_code),
  INDEX idx_chart_headers_dis1        (disease1_code),
  INDEX idx_chart_headers_dis2        (disease2_code),
  INDEX idx_chart_headers_dis3        (disease3_code),
  INDEX idx_ch_list                   (updated_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_chart_headers_bi_uuid_v7
BEFORE INSERT ON chart_headers
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid) = 0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

DELIMITER $$
/* CSIFH: INSERT時に farms.clinic_uuid を継承して固定（確定スナップの当時値） */
CREATE TRIGGER tr_chart_headers_bi_clinic
BEFORE INSERT ON chart_headers
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid IS NULL OR LENGTH(NEW.clinic_uuid) = 0 THEN
    SELECT f.clinic_uuid INTO NEW.clinic_uuid
      FROM farms f
     WHERE f.uuid = NEW.farm_uuid
     LIMIT 1;
  END IF;
END $$
DELIMITER ;

/* =========================================================
   5) chart_checkups — 確定スナップ配下（SOAP/TPR）
   ---------------------------------------------------------
   CSIFH適用差分：
   - clinic_uuid 追加（NOT NULL）。INSERT時に親 chart_headers から継承。
   - 院別絞込 INDEX を追加。
   ========================================================= */
CREATE TABLE IF NOT EXISTS chart_checkups (
  id                     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                   BINARY(16) NOT NULL UNIQUE,             -- 行UUID
  chart_uuid             BINARY(16) NOT NULL,                    -- ↔ chart_headers.uuid
  clinic_uuid            BINARY(16) NOT NULL,                    -- 当時の院（clinics.uuid）値
  seq_no                 INT UNSIGNED NOT NULL,                  -- ヘッダ内の並び

  source_checkup_uuid    BINARY(16) NOT NULL,                    -- 由来 checkups.uuid（監査）
  source_visit_uuid      BINARY(16) NULL,                        -- 由来 visits.uuid（任意）

  checkup_at             DATETIME NULL,                          -- 受診日時

  subjective_text        TEXT NULL,
  objective_text         TEXT NULL,
  assessment_text        TEXT NULL,
  plan_text              TEXT NULL,
  clinical_course_text   TEXT NULL,

  tpr_temp_c             DECIMAL(4,1) NULL,
  tpr_pulse_bpm          SMALLINT UNSIGNED NULL,
  tpr_resp_bpm           SMALLINT UNSIGNED NULL,

  created_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

  UNIQUE KEY uq_chart_checkups_hdr_seq (chart_uuid, seq_no),
  INDEX idx_chart_checkups_hdr (chart_uuid),
  INDEX idx_cc_clinic (clinic_uuid, chart_uuid),

  CONSTRAINT fk_chart_checkups_header
    FOREIGN KEY (chart_uuid) REFERENCES chart_headers(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_chart_checkups_bi_uuid_v7
BEFORE INSERT ON chart_checkups
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid) = 0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

DELIMITER $$
/* CSIFH: INSERT時に親 chart_headers の clinic_uuid を継承して固定 */
CREATE TRIGGER tr_chart_checkups_bi_clinic
BEFORE INSERT ON chart_checkups
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid IS NULL OR LENGTH(NEW.clinic_uuid) = 0 THEN
    SELECT ch.clinic_uuid INTO NEW.clinic_uuid
      FROM chart_headers ch
     WHERE ch.uuid = NEW.chart_uuid
     LIMIT 1;
  END IF;
END $$
DELIMITER ;

/* =========================================================
   6) chart_items — 確定スナップ明細（点数×価格 両立）
   ---------------------------------------------------------
   CSIFH適用差分：
   - clinic_uuid 追加（NOT NULL）。INSERT時に親 chart_checkups から継承。
   - 院別絞込 INDEX を追加。
   ========================================================= */
CREATE TABLE IF NOT EXISTS chart_items (
  id                       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                     BINARY(16) NOT NULL UNIQUE,           -- 明細UUID
  chart_checkup_uuid       BINARY(16) NOT NULL,                  -- ↔ chart_checkups.uuid
  clinic_uuid              BINARY(16) NOT NULL,                  -- 当時の院（clinics.uuid）値
  within_checkup_line_no   INT UNSIGNED NOT NULL,                -- 受診回内の行順

  source_checkup_uuid      BINARY(16) NOT NULL,                  -- 由来 checkups.uuid（監査）
  treatment_uuid           BINARY(16) NULL,                      -- 由来 treatment_master.uuid 等（任意）

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

  created_at               DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

  INDEX idx_chart_items_parent (chart_checkup_uuid, within_checkup_line_no),
  INDEX idx_ci_clinic         (clinic_uuid, chart_checkup_uuid),

  CONSTRAINT fk_chart_items_cc
    FOREIGN KEY (chart_checkup_uuid) REFERENCES chart_checkups(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_chart_items_bi_uuid_v7
BEFORE INSERT ON chart_items
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid) = 0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

DELIMITER $$
/* CSIFH: INSERT時に親 chart_checkups の clinic_uuid を継承して固定 */
CREATE TRIGGER tr_chart_items_bi_clinic
BEFORE INSERT ON chart_items
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid IS NULL OR LENGTH(NEW.clinic_uuid) = 0 THEN
    SELECT cc.clinic_uuid INTO NEW.clinic_uuid
      FROM chart_checkups cc
     WHERE cc.uuid = NEW.chart_checkup_uuid
     LIMIT 1;
  END IF;
END $$
DELIMITER ;
