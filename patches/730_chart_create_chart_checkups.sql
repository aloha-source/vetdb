/* 730_chart_create_chart_checkups.sql */
-- @phase: create
-- @provides: table:chart_checkups
-- @requires: table:chart_headers, function:uuid_v7_bin

DROP TABLE IF EXISTS chart_checkups;

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

  created_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
