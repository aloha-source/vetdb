/* 1760_appointment_create_calendar_sync_state.sql */
-- @phase: create
-- @provides: table:calendar_sync_state
-- @requires: table:clinics

DROP TABLE IF EXISTS calendar_sync_state;

CREATE TABLE calendar_sync_state (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  clinic_uuid   BINARY(16) NOT NULL,                -- ↔ clinics.uuid（CASCADE）
  calendar_id   VARCHAR(255) NOT NULL,
  sync_token    TEXT NOT NULL,

  row_version   BIGINT UNSIGNED NOT NULL DEFAULT 1,
  updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                  ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
