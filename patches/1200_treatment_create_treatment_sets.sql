/* 1200_treatment_create_treatment_sets.sql */
-- @phase: create
-- @provides: table:treatment_sets
-- @requires: table:users, function:uuid_v7_bin

DROP TABLE IF EXISTS treatment_sets;

CREATE TABLE IF NOT EXISTS treatment_sets (
  id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid         BINARY(16) NOT NULL UNIQUE,               -- UUIDv7(bin16)
  clinic_uuid  BINARY(16) NOT NULL,                      -- 当時値（FKなし）
  user_uuid    BINARY(16) NOT NULL,                      -- ↔ users.uuid
  name         VARCHAR(100) NOT NULL,
  note         VARCHAR(255) NULL,
  sequence_no  INT UNSIGNED NOT NULL DEFAULT 1,
  visibility   ENUM('private','shared') NOT NULL DEFAULT 'shared',
  is_active    TINYINT(1) NOT NULL DEFAULT 1,

  created_at   DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at   DATETIME  NULL,
  row_version  BIGINT UNSIGNED NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
