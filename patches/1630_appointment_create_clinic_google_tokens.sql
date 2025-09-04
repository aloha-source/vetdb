/* 1630_appointment_create_clinic_google_tokens.sql */
-- @phase: create
-- @provides: table:clinic_google_tokens
-- @requires: table:clinics

DROP TABLE IF EXISTS clinic_google_tokens;

CREATE TABLE clinic_google_tokens (
  id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  clinic_uuid          BINARY(16) NOT NULL,                 -- ↔ clinics.uuid
  google_email         VARCHAR(255) NOT NULL,
  access_token_enc     TEXT NOT NULL,                       -- 暗号化済み
  refresh_token_enc    TEXT NOT NULL,                       -- 暗号化済み
  token_type           VARCHAR(32) NULL,
  scopes               TEXT NULL,
  expires_at           DATETIME NULL,
  revoked_at           DATETIME NULL,

  row_version          BIGINT UNSIGNED NOT NULL DEFAULT 1,
  created_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
