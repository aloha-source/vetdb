/* 1430_clinic_create_clinic_settings.sql */
-- @phase: create
-- @provides: table:clinic_settings
-- @requires: table:clinics
-- 方針: 原文のCREATE本体＋CHECK制約を保持。索引/一意/FKは別ファイル。

/* 再デプロイ安全化（テーブル本体） */
DROP TABLE IF EXISTS clinic_settings;

CREATE TABLE clinic_settings (
  id                           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  clinic_uuid                  BINARY(16) NOT NULL,     -- ↔ clinics.uuid（1院1行）
  /* 会計系既定値 */
  yen_per_point                DECIMAL(8,2) NOT NULL DEFAULT 0.00,
  copay_rate                   DECIMAL(5,2) NOT NULL DEFAULT 0.00,   -- 例: 30.00 (=30%)
  default_tax_rate             DECIMAL(4,2) NOT NULL DEFAULT 0.00,   -- 例: 10.00 (=10%)
  price_rounding               ENUM('none','round','ceil','floor') NOT NULL DEFAULT 'round',
  price_rounding_unit          INT UNSIGNED NOT NULL DEFAULT 1,      -- 1/10/100 など

  /* 帳票/表示 */
  billing_contact_name         VARCHAR(128) NULL,       -- 請求窓口担当者名（運用表示）
  invoice_logo_path            VARCHAR(255) NULL,       -- 帳票ロゴ（S3等のパス）
  receipt_footer_text          VARCHAR(255) NULL,       -- レシート定型フッター
  invoice_registration_number  VARCHAR(14)  NULL,       -- 例: 'T' + 13桁

  /* 監査・運用列 */
  created_at                   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at                   DATETIME NULL,
  row_version                  BIGINT UNSIGNED NOT NULL DEFAULT 1,

  /* 任意: インボイス登録番号の形式検証（対応エンジンのみ有効） */
  CONSTRAINT chk_clinic_settings_invoice_reg
    CHECK (invoice_registration_number IS NULL
           OR invoice_registration_number REGEXP '^T[0-9]{13}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
