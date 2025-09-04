/* 2020_receipt_create_receipt_checkups.sql */
-- @phase: create
-- @feature: receipt
-- @provides: table:receipt_checkups
-- @requires: function:uuid_v7_bin, table:receipt_headers

DROP TABLE IF EXISTS receipt_checkups;
CREATE TABLE IF NOT EXISTS receipt_checkups (
  id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                BINARY(16) NOT NULL UNIQUE,                  -- v7（items から参照）
  receipt_header_uuid BINARY(16) NOT NULL,                         -- ↔ receipt_headers.uuid（弱リンク）
  clinic_uuid         BINARY(16) NULL,                             -- 親ヘッダから固定継承
  source_checkup_uuid BINARY(16) NOT NULL,                         -- 由来：checkups.uuid
  checkup_at          DATETIME NULL,                               -- 任意：診療日時など
  individual_uuid     BINARY(16) NULL,                             -- 任意：印字補助
  individual_label    VARCHAR(120) NULL,                           -- 任意：個体表示名 等
  created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
