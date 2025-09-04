/* 1930_farmmirror_create_vet_users.sql */
-- @phase: create
-- @provides: table:vet_users
-- @requires: table:clinics, function:uuid_v7_bin

DROP TABLE IF EXISTS vet_users;
CREATE TABLE vet_users (
  id                 INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid               BINARY(16) NOT NULL,
  clinic_uuid        BINARY(16) NOT NULL,            -- ↔ clinics.uuid
  display_name       VARCHAR(100) NOT NULL,
  email              VARCHAR(255) NULL,
  phone              VARCHAR(50) NULL,
  role_label         VARCHAR(100) NULL,              -- 例: 院長/獣医師/スタッフ
  clinic_branch_name VARCHAR(120) NULL,              -- 分院メモ（UI補助）

  created_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at         DATETIME NULL,
  row_version        BIGINT UNSIGNED NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
