/* 100_checkup_create_individuals.sql */
-- @phase: create
-- @provides: table:individuals
-- @requires: table:clinics, table:farms, table:users, function:uuid_v7_bin

DROP VIEW IF EXISTS individuals_hex_v;

DROP TRIGGER IF EXISTS tr_individuals_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_individuals_bu_rowver;
DROP TRIGGER IF EXISTS tr_individuals_bi_clinic;

DROP TABLE IF EXISTS individuals;
CREATE TABLE individuals (
  id                    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                  BINARY(16) NOT NULL UNIQUE,
  clinic_uuid           BINARY(16) NOT NULL,   -- ★ CSIFH: 所属院（履歴固定）
  farm_uuid             BINARY(16) NOT NULL,   -- ↔ farms.uuid
  user_uuid             BINARY(16) NULL,       -- ↔ users.uuid（担当メモ）
  name                  VARCHAR(100) NULL,
  ear_tag               CHAR(10) NULL,         -- 全国一意10桁（NULL可）
  status                ENUM('active','sold','dead','culled') NOT NULL DEFAULT 'active',
  gender                ENUM('female','male','cast','unknown') NOT NULL DEFAULT 'unknown',
  birth_date            DATE NULL,
  death_date            DATE NULL,
  sire_name             VARCHAR(100) NULL,     -- 父は名称メモのみ
  genetic_dam_uuid      BINARY(16) NULL,       -- 自己参照（遺伝母）
  nursing_dam_uuid      BINARY(16) NULL,       -- 自己参照（哺育母）
  genetic_dam_ear_tag   CHAR(10) NULL,
  genetic_dam_name      VARCHAR(100) NULL,
  nursing_dam_ear_tag   CHAR(10) NULL,
  nursing_dam_name      VARCHAR(100) NULL,
  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at            DATETIME NULL,
  row_version           BIGINT UNSIGNED NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
