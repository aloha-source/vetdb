/* 1800_appointment_create_appointment_fulfillments.sql */
-- @phase: create
-- @provides: table:appointment_fulfillments
-- @requires: table:clinics, table:appointments, table:visits

DROP TABLE IF EXISTS appointment_fulfillments;

CREATE TABLE appointment_fulfillments (
  id                 INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  clinic_uuid        BINARY(16) NOT NULL,           -- ↔ clinics.uuid（CASCADE）
  appointment_uuid   BINARY(16) NOT NULL,           -- ↔ appointments.uuid（CASCADE）
  visit_uuid         BINARY(16) NOT NULL,           -- ↔ visits.uuid（CASCADE）
  fulfilled_at       DATETIME NOT NULL,
  note               VARCHAR(255) NULL,

  row_version        BIGINT UNSIGNED NOT NULL DEFAULT 1,
  created_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
