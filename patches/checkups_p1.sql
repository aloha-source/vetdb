  -- SOAP カラム追加

CREATE TABLE IF NOT EXISTS checkups (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid             CHAR(36) NOT NULL UNIQUE,
  visit_uuid       CHAR(36) NOT NULL,              -- ↔ visits.uuid
  individual_uuid  CHAR(36) NOT NULL,              -- ↔ individuals.uuid

  -- SOAP fields
  s_subjective     TEXT NULL COMMENT 'S: Subjective (owner-reported signs, history)',
  o_objective      TEXT NULL COMMENT 'O: Objective (exam findings, labs, imaging)',
  a_assessment     TEXT NULL COMMENT 'A: Assessment / differential & working dx',
  p_plan           TEXT NULL COMMENT 'P: Plan / therapy / next steps',

  -- TPR (vital signs)
  temp_c           DECIMAL(4,1) NULL COMMENT 'TPR: Temperature (°C)',
  pulse_bpm        SMALLINT UNSIGNED NULL COMMENT 'TPR: Pulse (beats/min)',
  resp_bpm         SMALLINT UNSIGNED NULL COMMENT 'TPR: Respiratory rate (breaths/min)',

  -- 現症・経過
  clinical_course  TEXT NULL COMMENT 'Clinical course / current condition',

  status           ENUM('draft','ready') NOT NULL DEFAULT 'draft',
  created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  UNIQUE KEY uq_checkups_visit_individual (visit_uuid, individual_uuid),
  INDEX idx_checkups_visit (visit_uuid),
  INDEX idx_checkups_individual (individual_uuid),

  CONSTRAINT fk_checkups_visit_uuid
    FOREIGN KEY (visit_uuid) REFERENCES visits(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_checkups_individual_uuid
    FOREIGN KEY (individual_uuid) REFERENCES individuals(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;
