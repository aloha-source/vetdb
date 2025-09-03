/* 1300_treatment_create_treatment_set_items.sql */
-- @phase: create
-- @provides: table:treatment_set_items
-- @requires: table:treatment_sets, table:treatment_master, function:uuid_v7_bin

DROP TABLE IF EXISTS treatment_set_items;

CREATE TABLE IF NOT EXISTS treatment_set_items (
  id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid            BINARY(16) NOT NULL UNIQUE,            -- UUIDv7(bin16)
  clinic_uuid     BINARY(16) NOT NULL,                   -- 当時値（FKなし）
  set_uuid        BINARY(16) NOT NULL,                   -- ↔ treatment_sets.uuid
  treatment_uuid  BINARY(16) NOT NULL,                   -- ↔ treatment_master.uuid
  sequence_no     INT UNSIGNED NOT NULL DEFAULT 1,
  preset_quantity DECIMAL(10,2) NULL,                    -- p016.2方針（10,2）

  created_at      DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at      DATETIME  NULL,
  row_version     BIGINT UNSIGNED NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
