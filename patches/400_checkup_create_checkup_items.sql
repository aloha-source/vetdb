/* 400_checkup_create_checkup_items.sql */
-- @phase: create
-- @provides: table:checkup_items
-- @requires: table:clinics, table:checkups, function:uuid_v7_bin

DROP TABLE IF EXISTS checkup_items;

CREATE TABLE checkup_items (
  id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                BINARY(16) NOT NULL UNIQUE,
  clinic_uuid         BINARY(16) NOT NULL,   -- ★ CSIFH
  checkup_uuid        BINARY(16) NOT NULL,   -- ↔ checkups.uuid
  treatment_uuid      BINARY(16) NULL,       -- 任意参照（マスタ未確定でも可）
  description         VARCHAR(255) NOT NULL,
  qty_unit            VARCHAR(32) NULL,
  quantity            DECIMAL(10,2) NOT NULL DEFAULT 1,
  pay_type            ENUM('insurance','private') NOT NULL DEFAULT 'private',

  /* 点数/価格の両立 */
  unit_b_points       INT UNSIGNED NOT NULL DEFAULT 0,
  unit_a_points       INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_points     INT UNSIGNED NOT NULL DEFAULT 0,
  yen_per_point       DECIMAL(8,2) NOT NULL DEFAULT 0.00,
  unit_price_yen      INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_price_yen  INT UNSIGNED NOT NULL DEFAULT 0,
  tax_rate            DECIMAL(4,2) NOT NULL DEFAULT 0.00,
  subtotal_yen        INT UNSIGNED NOT NULL DEFAULT 0,

  row_version         BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at          DATETIME NULL,
  created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci ROW_FORMAT = DYNAMIC;
