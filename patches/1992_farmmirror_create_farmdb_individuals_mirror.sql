/* 1992_farmmirror_create_farmdb_individuals_mirror.sql */
-- @phase: create
-- @provides: table:farmdb_individuals_mirror

DROP TABLE IF EXISTS farmdb_individuals_mirror;
CREATE TABLE farmdb_individuals_mirror (
  id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                 BINARY(16) NOT NULL UNIQUE,
  clinic_uuid          BINARY(16) NULL,             -- farmDB由来（NULL可）
  farm_uuid            BINARY(16) NOT NULL,         -- 参照先もfarmDBのUUID（FKなし）
  user_uuid            BINARY(16) NULL,

  name                 VARCHAR(100) NULL,
  ear_tag              CHAR(10) NULL,
  status               ENUM('active','sold','dead','culled') NOT NULL DEFAULT 'active',
  gender               ENUM('female','male','cast','unknown') NOT NULL DEFAULT 'unknown',
  birth_date           DATE NULL,
  death_date           DATE NULL,
  sire_name            VARCHAR(100) NULL,

  genetic_dam_uuid     BINARY(16) NULL,
  nursing_dam_uuid     BINARY(16) NULL,
  genetic_dam_ear_tag  CHAR(10) NULL,
  genetic_dam_name     VARCHAR(100) NULL,
  nursing_dam_ear_tag  CHAR(10) NULL,
  nursing_dam_name     VARCHAR(100) NULL,

  created_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at           DATETIME NULL,
  row_version          BIGINT UNSIGNED NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
