/* 200_checkup_create_visits.sql */
-- @phase: create
-- @provides: table:visits
-- @requires: table:clinics, table:farms, function:uuid_v7_bin

DROP TABLE IF EXISTS visits;

CREATE TABLE visits (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid             BINARY(16) NOT NULL,
  clinic_uuid      BINARY(16) NOT NULL,   -- ★ CSIFH
  farm_uuid        BINARY(16) NOT NULL,   -- ↔ farms.uuid
  visit_started_at DATETIME NOT NULL,
  visit_ended_at   DATETIME NULL,
  location_text    VARCHAR(180) NULL,
  note             VARCHAR(255) NULL,
  row_version      BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at       DATETIME NULL,
  created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
