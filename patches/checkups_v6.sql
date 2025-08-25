SET NAMES utf8mb4;

-- 任意：病名マスタ（既存があれば作成不要）
CREATE TABLE IF NOT EXISTS disease_master (
  id    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  code  VARCHAR(32) NOT NULL UNIQUE,
  name  VARCHAR(255) NOT NULL,
  INDEX idx_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 1) カルテヘッダ（請求単位＋各種スナップショット）
CREATE TABLE IF NOT EXISTS chart_headers (
  id                       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                     CHAR(36) NOT NULL UNIQUE,

  -- 紐付け
  individual_uuid          CHAR(36) NOT NULL,      -- ↔ individuals.uuid
  farm_uuid                CHAR(36) NOT NULL,      -- ↔ farms.uuid
  insurance_enrollment_id  INT UNSIGNED NULL,      -- ↔ insurance_enrollments.id（任意）

  -- 期間識別（保険年度）
  fiscal_year              YEAR NOT NULL,
  claim_month              TINYINT UNSIGNED NOT NULL,  -- 1-12

  -- 転帰・日付・回数
  outcome_code             TINYINT UNSIGNED NOT NULL,  -- 1治癒/2死亡/3法令殺/4廃用/5中止
  onset_date               DATE NULL,                  -- 発病
  first_visit_date         DATE NULL,                  -- 初診
  last_visit_date          DATE NULL,                  -- 終診
  outcome_date             DATE NULL,                  -- 転帰
  visit_count              INT UNSIGNED NOT NULL DEFAULT 0,   -- カルテ内 checkups 件数（閉帳時に確定）

  -- 主訴・自由診断名
  chief_complaint          VARCHAR(255) NULL,
  diagnosis_text           VARCHAR(255) NULL,

  -- 病名（第1〜第3を直書きスナップショット）
  disease1_code            VARCHAR(32)  NULL,
  disease1_name            VARCHAR(255) NULL,
  disease2_code            VARCHAR(32)  NULL,
  disease2_name            VARCHAR(255) NULL,
  disease3_code            VARCHAR(32)  NULL,
  disease3_name            VARCHAR(255) NULL,

  -- 集計（閉帳時に確定）
  total_b_points           INT UNSIGNED NOT NULL DEFAULT 0,
  total_a_points           INT UNSIGNED NOT NULL DEFAULT 0,
  total_price_yen          INT UNSIGNED NOT NULL DEFAULT 0,   -- 自費合計
  subtotal_yen             INT UNSIGNED NOT NULL DEFAULT 0,   -- 点換算＋自費
  patient_copay_yen        INT UNSIGNED NOT NULL DEFAULT 0,
  insurer_pay_yen          INT UNSIGNED NOT NULL DEFAULT 0,
  tax_yen                  INT UNSIGNED NOT NULL DEFAULT 0,

  -- ステータス
  status ENUM('draft','closed','issued','voided') NOT NULL DEFAULT 'draft',
  closed_at                DATETIME NULL,
  issued_at                DATETIME NULL,
  printed_at               DATETIME NULL,
  printed_count            INT UNSIGNED NOT NULL DEFAULT 0,

  -- ▼ 農家スナップショット（farms 準拠）
  farm_name                VARCHAR(255) NULL,
  farm_address             VARCHAR(255) NULL,
  farm_insurance_number    VARCHAR(64)  NULL,

  -- ▼ 個体スナップショット（individuals 準拠）
  animal_name              VARCHAR(255) NULL,
  ear_tag                  VARCHAR(32)  NULL,
  dam_name                 VARCHAR(255) NULL,
  dam_ear_tag              VARCHAR(32)  NULL,
  breed_code               VARCHAR(32)  NULL,
  kyosai_purpose_code      VARCHAR(32)  NULL,  -- ※個体属性としてこちらに保持

  -- ▼ 病院情報（自由形式）
  clinic_snapshot_json     JSON NULL,

  -- ▼ 保険加入スナップショット（insurance_enrollments 主要列）
  ins_farm_user_id         INT UNSIGNED NULL,
  ins_subscriber_code      CHAR(8) NULL,
  ins_status               ENUM('加入','非加入','不明','下書き') NULL,
  ins_start_date           DATE NULL,
  ins_end_date             DATE NULL,
  ins_fiscal_year          YEAR NULL,
  ins_source_note          VARCHAR(255) NULL,

  created_by               INT UNSIGNED NULL,
  deleted_at               DATETIME NULL,
  created_at               DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at               DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  -- インデックス
  INDEX idx_period     (fiscal_year, claim_month),
  INDEX idx_status     (status),
  INDEX idx_individual (individual_uuid),
  INDEX idx_farm       (farm_uuid),
  INDEX idx_outcome    (outcome_code),
  INDEX idx_disease1   (disease1_code),
  INDEX idx_disease2   (disease2_code),
  INDEX idx_disease3   (disease3_code),

  -- 外部キー
  CONSTRAINT fk_ch_hdr_individual
    FOREIGN KEY (individual_uuid) REFERENCES individuals(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_ch_hdr_farm
    FOREIGN KEY (farm_uuid) REFERENCES farms(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_ch_hdr_ins
    FOREIGN KEY (insurance_enrollment_id) REFERENCES insurance_enrollments(id)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2) カルテ内「各回の診療」スナップ（checkups のコピー／親）
CREATE TABLE IF NOT EXISTS chart_checkups (
  id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                 CHAR(36) NOT NULL UNIQUE,      -- スナップ側のcheckup-uuid
  chart_uuid           CHAR(36) NOT NULL,             -- ↔ chart_headers.uuid
  seq_no               INT UNSIGNED NOT NULL,         -- ヘッダ内の並び（日時昇順など）
  source_checkup_uuid  CHAR(36) NOT NULL,             -- 元のcheckups.uuid
  source_visit_uuid    CHAR(36) NULL,                 -- 任意：元のvisits.uuid

  checkup_at           DATETIME NULL,                 -- 受診日時スナップ
  -- SOAP/TPR/現症・経過（スナップ）
  subjective_text      TEXT NULL,
  objective_text       TEXT NULL,
  assessment_text      TEXT NULL,
  plan_text            TEXT NULL,
  clinical_course_text TEXT NULL,
  tpr_temp_c           DECIMAL(4,1) NULL,
  tpr_pulse_bpm        SMALLINT UNSIGNED NULL,
  tpr_resp_bpm         SMALLINT UNSIGNED NULL,

  created_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

  UNIQUE KEY uq_hdr_seq (chart_uuid, seq_no),
  INDEX idx_hdr (chart_uuid),

  CONSTRAINT fk_chart_checkups_header
    FOREIGN KEY (chart_uuid) REFERENCES chart_headers(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3) カルテ明細スナップ（checkup_items のコピー／子）※冗長なし＝ヘッダ列を持たない
CREATE TABLE IF NOT EXISTS chart_items (
  id                     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  chart_checkup_uuid     CHAR(36) NOT NULL,             -- ↔ chart_checkups.uuid（親子）
  within_checkup_line_no INT UNSIGNED NOT NULL,         -- 受診回内の行順

  source_checkup_uuid    CHAR(36) NOT NULL,             -- 由来（監査用）
  treatment_uuid         CHAR(36) NULL,                 -- 任意参照
  description            VARCHAR(255) NOT NULL,

  qty_unit               VARCHAR(32) NULL,
  quantity               DECIMAL(10,2) NOT NULL DEFAULT 1,

  pay_type               ENUM('insurance','private') NOT NULL,

  unit_b_points          INT UNSIGNED NOT NULL DEFAULT 0,
  unit_a_points          INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_points        INT UNSIGNED NOT NULL DEFAULT 0,
  yen_per_point          DECIMAL(8,2) NOT NULL DEFAULT 0.00,

  unit_price_yen         INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_price_yen     INT UNSIGNED NOT NULL DEFAULT 0,

  tax_rate               DECIMAL(4,2) NOT NULL DEFAULT 0.00,
  subtotal_yen           INT UNSIGNED NOT NULL DEFAULT 0,

  created_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

  INDEX idx_parent (chart_checkup_uuid, within_checkup_line_no),

  CONSTRAINT fk_ci_cc
    FOREIGN KEY (chart_checkup_uuid) REFERENCES chart_checkups(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4) 原本：checkups（カルテ接続・対象外・SOAP/TPR）
CREATE TABLE IF NOT EXISTS checkups (
  id                     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                   CHAR(36) NOT NULL UNIQUE,

  visit_uuid             CHAR(36) NOT NULL,        -- ↔ visits.uuid
  individual_uuid        CHAR(36) NOT NULL,        -- ↔ individuals.uuid

  chart_header_uuid      CHAR(36) NULL,            -- 未接続=NULL
  claim_exclusion        ENUM('none','no_insurance','manual') NOT NULL DEFAULT 'none',
  has_insurance_cached   TINYINT(1) NOT NULL DEFAULT 0,

  -- SOAP
  subjective_text        TEXT NULL,
  objective_text         TEXT NULL,
  assessment_text        TEXT NULL,
  plan_text              TEXT NULL,

  -- TPR
  tpr_temp_c             DECIMAL(4,1) NULL,
  tpr_pulse_bpm          SMALLINT UNSIGNED NULL,
  tpr_resp_bpm           SMALLINT UNSIGNED NULL,

  clinical_course_text   TEXT NULL,                -- 現症・経過
  status                 ENUM('draft','ready') NOT NULL DEFAULT 'draft',

  created_by             INT UNSIGNED NULL,
  deleted_at             DATETIME NULL,
  created_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  UNIQUE KEY uq_visit_individual (visit_uuid, individual_uuid),
  INDEX idx_individual (individual_uuid),
  INDEX idx_claim (chart_header_uuid, claim_exclusion, has_insurance_cached, individual_uuid),

  CONSTRAINT fk_cu_visit
    FOREIGN KEY (visit_uuid) REFERENCES visits(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_cu_individual
    FOREIGN KEY (individual_uuid) REFERENCES individuals(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_cu_chart_header
    FOREIGN KEY (chart_header_uuid) REFERENCES chart_headers(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 5) 原本：checkup_items（v1p2互換・pay_typeを'insurance'/'private'で統一）
CREATE TABLE IF NOT EXISTS checkup_items (
  id                     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                   CHAR(36) NOT NULL UNIQUE,
  checkup_uuid           CHAR(36) NOT NULL,        -- ↔ checkups.uuid
  treatment_uuid         CHAR(36) NULL,
  description            VARCHAR(255) NOT NULL,

  qty_unit               VARCHAR(32) NULL,
  quantity               DECIMAL(10,2) NOT NULL DEFAULT 1,

  pay_type               ENUM('insurance','private') NOT NULL,

  unit_b_points          INT UNSIGNED NOT NULL DEFAULT 0,
  unit_a_points          INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_points        INT UNSIGNED NOT NULL DEFAULT 0,
  yen_per_point          DECIMAL(8,2) NOT NULL DEFAULT 0.00,

  unit_price_yen         INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_price_yen     INT UNSIGNED NOT NULL DEFAULT 0,

  tax_rate               DECIMAL(4,2) NOT NULL DEFAULT 0.00,
  subtotal_yen           INT UNSIGNED NOT NULL DEFAULT 0,

  deleted_at             DATETIME NULL,
  created_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  INDEX idx_items (checkup_uuid, pay_type),
  CONSTRAINT fk_ci_checkup
    FOREIGN KEY (checkup_uuid) REFERENCES checkups(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
