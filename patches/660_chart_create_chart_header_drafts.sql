/* 660_chart_create_chart_header_drafts.sql */
-- @phase: create
-- @provides: table:chart_header_drafts
-- @requires: table:individuals, table:farms, table:insurance_enrollments, table:disease_master

DROP TABLE IF EXISTS chart_header_drafts;

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
  updated_at                DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
