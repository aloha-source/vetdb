/* 1000_treatment_create_treatment_master.sql */
-- @phase: create
-- @provides: table:treatment_master
-- @requires: table:clinics, function:uuid_v7_bin
-- 方針: 原文のCREATEから索引(FK/KEY)を分離。列定義は原文のまま。

SET NAMES utf8mb4;

DROP TABLE IF EXISTS treatment_master;

CREATE TABLE IF NOT EXISTS treatment_master (
  id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                 BINARY(16) NOT NULL UNIQUE,                   -- UUIDv7(bin16)
  clinic_uuid          BINARY(16) NOT NULL,                          -- ↔ clinics.uuid（当時値・不変）
  code                 VARCHAR(50)  NOT NULL,                        -- 院内/製剤コード
  name                 VARCHAR(255) NOT NULL,                        -- 表示名
  type                 ENUM('procedure','medication') NOT NULL,      -- 区分
  qty_unit             VARCHAR(32)  NOT NULL,                        -- 単位
  default_pay_type     ENUM('insurance','private') NOT NULL DEFAULT 'insurance',

  /* 点数/価格（整数運用） */
  current_b_points     INT UNSIGNED NULL,
  current_a_points     INT UNSIGNED NULL,
  current_price_yen    INT UNSIGNED NULL,

  /* 税率（例 0.10） */
  tax_rate             DECIMAL(4,2) NOT NULL,

  /* 任意メタ（一本化: 全体向け注意・用法等） */
  dosage_per_kg        DECIMAL(10,4) NULL,                           -- 体重1kgあたり
  usage_text           TEXT NULL,

  /* 運用 */
  is_active            TINYINT(1) NOT NULL DEFAULT 1,
  created_at           DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at           DATETIME  NULL,                                -- SoftDelete
  row_version          BIGINT UNSIGNED NOT NULL DEFAULT 1             -- 楽観ロック
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
