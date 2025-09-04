/* 1990_farmmirror_create_farmdb_farms_mirror.sql */
-- @phase: create
-- @provides: table:farmdb_farms_mirror

DROP TABLE IF EXISTS farmdb_farms_mirror;
CREATE TABLE farmdb_farms_mirror (
  id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid              BINARY(16) NOT NULL UNIQUE,     -- farmDB側 farm.uuid
  clinic_uuid       BINARY(16) NULL,                -- farmDBの値そのまま（NULL可）
  name              VARCHAR(120) NOT NULL,
  billing_name      VARCHAR(120) NULL,
  billing_address   VARCHAR(255) NULL,
  deleted_at        DATETIME NULL,                  -- 外部削除の鏡像（tombstone）
  updated_at_source DATETIME NULL,                  -- farmDB側の更新時刻（差分カーソル用）

  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
