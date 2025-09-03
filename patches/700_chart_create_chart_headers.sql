/* 700_chart_create_chart_headers.sql */
-- @phase: create
-- @provides: table:chart_headers
-- @requires: function:uuid_v7_bin

DROP TABLE IF EXISTS chart_headers;

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
  updated_at                DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
