/* 1994_farmmirror_create_farmdb_farm_users_mirror.sql */
-- @phase: create
-- @provides: table:farmdb_farm_users_mirror

DROP TABLE IF EXISTS farmdb_farm_users_mirror;
CREATE TABLE farmdb_farm_users_mirror (
  id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid         BINARY(16) NOT NULL UNIQUE,
  clinic_uuid  BINARY(16) NULL,            -- farmDB由来（NULL可）
  farm_uuid    BINARY(16) NOT NULL,
  display_name VARCHAR(100) NOT NULL,
  email        VARCHAR(255) NULL,
  phone        VARCHAR(50) NULL,
  role_label   VARCHAR(100) NULL,

  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at   DATETIME NULL,
  row_version  BIGINT UNSIGNED NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
