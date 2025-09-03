/* 760_chart_create_chart_items.sql */
-- @phase: create
-- @provides: table:chart_items
-- @requires: table:chart_checkups, function:uuid_v7_bin

DROP TABLE IF EXISTS chart_items;

CREATE TABLE IF NOT EXISTS chart_items (
  id                       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                     BINARY(16) NOT NULL UNIQUE,           -- 明細UUID
  chart_checkup_uuid       BINARY(16) NOT NULL,                  -- ↔ chart_checkups.uuid
  clinic_uuid              BINARY(16) NOT NULL,                  -- 当時の院（clinics.uuid）値
  within_checkup_line_no   INT UNSIGNED NOT NULL,                -- 受診回内の行順

  source_checkup_uuid      BINARY(16) NOT NULL,                  -- 由来 checkups.uuid（監査）
  treatment_uuid           BINARY(16) NULL,                      -- 由来 treatment_master.uuid 等（任意）

  description              VARCHAR(255) NOT NULL,
  qty_unit                 VARCHAR(32) NULL,
  quantity                 DECIMAL(10,2) NOT NULL DEFAULT 1,

  pay_type                 ENUM('insurance','private') NOT NULL,
  unit_b_points            INT UNSIGNED NOT NULL DEFAULT 0,
  unit_a_points            INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_points          INT UNSIGNED NOT NULL DEFAULT 0,
  yen_per_point            DECIMAL(8,2) NOT NULL DEFAULT 0.00,

  unit_price_yen           INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_price_yen       INT UNSIGNED NOT NULL DEFAULT 0,

  tax_rate                 DECIMAL(4,2) NOT NULL DEFAULT 0.00,
  subtotal_yen             INT UNSIGNED NOT NULL DEFAULT 0,

  created_at               DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
