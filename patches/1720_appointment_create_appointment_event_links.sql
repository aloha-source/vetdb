/* 1720_appointment_create_appointment_event_links.sql */
-- @phase: create
-- @provides: table:appointment_event_links
-- @requires: table:clinics, table:appointments, table:vet_users

DROP TABLE IF EXISTS appointment_event_links;

CREATE TABLE appointment_event_links (
  id                     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  clinic_uuid            BINARY(16) NOT NULL,           -- ↔ clinics.uuid（CASCADE）
  appointment_uuid       BINARY(16) NOT NULL,           -- ↔ appointments.uuid（CASCADE）
  google_calendar_id     VARCHAR(255) NOT NULL,
  google_event_id        VARCHAR(255) NOT NULL,
  ical_uid               VARCHAR(255) NULL,
  etag                   VARCHAR(255) NULL,
  writer_vet_user_uuid   BINARY(16) NULL,               -- ↔ vet_users.uuid（SET NULL, 監査用）
  status                 ENUM('pending','synced','failed','deleted','skipped')
                           NOT NULL DEFAULT 'pending',
  synced_at              DATETIME NULL,

  row_version            BIGINT UNSIGNED NOT NULL DEFAULT 1,
  created_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
