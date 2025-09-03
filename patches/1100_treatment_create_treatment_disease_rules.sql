/* 1100_treatment_create_treatment_disease_rules.sql */
-- @phase: create
-- @provides: table:treatment_disease_rules
-- @requires: table:treatment_master, table:disease_master, function:uuid_v7_bin
-- 方針: 索引とFKは別ファイル。列定義は原文のまま。

DROP TABLE IF EXISTS treatment_disease_rules;

CREATE TABLE IF NOT EXISTS treatment_disease_rules (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid             BINARY(16) NOT NULL UNIQUE,           -- UUIDv7(bin16)
  clinic_uuid      BINARY(16) NOT NULL,                  -- 当時値（FKなし）
  treatment_uuid   BINARY(16) NOT NULL,                  -- ↔ treatment_master.uuid
  disease_uuid     BINARY(16) NOT NULL,                  -- ↔ disease_master.uuid
  disease_specific TEXT NULL,                            -- on-label時の任意表示文（病名特異）
  is_active        TINYINT(1) NOT NULL DEFAULT 1,
  created_at       DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at       DATETIME  NULL,
  row_version      BIGINT UNSIGNED NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
