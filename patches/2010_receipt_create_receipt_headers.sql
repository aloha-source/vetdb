/* 2010_receipt_create_receipt_headers.sql */
-- @phase: create
-- @feature: receipt
-- @provides: table:receipt_headers
-- @requires: function:uuid_v7_bin, table:farms

DROP TABLE IF EXISTS receipt_headers;
CREATE TABLE IF NOT EXISTS receipt_headers (
  id                          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                        BINARY(16) NOT NULL UNIQUE,            -- v7 UUID（スナップの識別）
  receipt_header_drafts_uuid  BINARY(16) NULL,                       -- 参照元ドラフト（弱リンク）
  farm_uuid                   BINARY(16) NULL,                       -- 弱リンク（将来の参照用）
  clinic_uuid                 BINARY(16) NULL,                       -- 当時の所属院（不変）
  receipt_no                  VARCHAR(40) NULL,                      -- 任意の対外発番（UI採番）
  title                       VARCHAR(120) NULL,
  note                        VARCHAR(255) NULL,

  issued_at                   DATETIME NOT NULL,                     -- 発行日時（スナップ時刻）
  issued_by_user_id           INT UNSIGNED NULL,

  status                      ENUM('printed','voided') NULL DEFAULT NULL,  -- 未印刷(NULL)/印刷済/取消
  printed_at                  DATETIME NULL,
  printed_count               INT UNSIGNED NOT NULL DEFAULT 0,
  voided_at                   DATETIME NULL,
  void_reason                 VARCHAR(255) NULL,
  voided_by_user_id           INT UNSIGNED NULL,

  /* クリニック設定スナップ（固定） */
  yen_per_point               DECIMAL(8,2) NOT NULL,
  copay_rate                  DECIMAL(5,4) NOT NULL,
  tax_rounding                ENUM('floor','round','ceil') NOT NULL,

  /* 集計スナップ（固定） */
  total_b_points              INT UNSIGNED NOT NULL,
  total_a_points              INT UNSIGNED NOT NULL,
  total_price_yen             INT UNSIGNED NOT NULL,
  subtotal_yen                INT UNSIGNED NOT NULL,
  tax_yen                     INT UNSIGNED NOT NULL,
  total_insurance_yen         INT UNSIGNED NOT NULL,
  total_private_yen           INT UNSIGNED NOT NULL,
  patient_copay_yen           INT UNSIGNED NOT NULL,
  insurer_pay_yen             INT UNSIGNED NOT NULL,

  /* 任意：印字/レイアウト用のクリニック情報 */
  clinic_snapshot_json        JSON NULL,

  created_at                  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
