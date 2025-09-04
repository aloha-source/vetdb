/* 1670_appointment_create_clinic_calendar_settings.sql */
-- @phase: create
-- @provides: table:clinic_calendar_settings
-- @requires: table:clinics, table:vet_users

DROP TABLE IF EXISTS clinic_calendar_settings;

CREATE TABLE clinic_calendar_settings (
  id                          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  clinic_uuid                 BINARY(16) NOT NULL,           -- ↔ clinics.uuid
  calendar_id                 VARCHAR(255) NOT NULL,         -- '...@group.calendar.google.com'
  calendar_summary            VARCHAR(255) NULL,
  sync_owner_vet_user_uuid    BINARY(16) NULL,               -- ↔ vet_users.uuid（SET NULL）

  row_version                 BIGINT UNSIGNED NOT NULL DEFAULT 1,
  created_at                  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
