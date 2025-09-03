/* 630_chart_create_disease_chief_complaint_rules.sql */
-- @phase: create
-- @provides: table:disease_chief_complaint_rules
-- @requires: table:disease_master

DROP TABLE IF EXISTS disease_chief_complaint_rules;

CREATE TABLE IF NOT EXISTS disease_chief_complaint_rules (
  id                     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  disease_id             INT UNSIGNED NOT NULL,                   
  chief_complaint_text   VARCHAR(128) NOT NULL,                   
  display_order          SMALLINT UNSIGNED NOT NULL DEFAULT 0,    
  is_active              TINYINT(1) NOT NULL DEFAULT 1,

  created_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
