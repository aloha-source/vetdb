/* 1960_farmmirror_create_farm_users.sql */
-- @phase: create
-- @provides: table:farm_users
-- @requires: table:farms, function:uuid_v7_bin

DROP TABLE IF EXISTS farm_users;
CREATE TABLE farm_users (
  id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid         BINARY(16) NOT NULL,

  farm_uuid    BINARY(16) NOT NULL,                 -- ↔ farms.uuid
  clinic_uuid  BINARY(16) NOT NULL,                 -- 院スコープ検索用に保持（親から継承）

  display_name VARCHAR(100) NOT NULL,
  email        VARCHAR(255) NULL,
  phone        VARCHAR(50) NULL,
  role_label   VARCHAR(100) NULL,                   -- 例: 場長/経理/担当

  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at   DATETIME NULL,
  row_version  BIGINT UNSIGNED NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
