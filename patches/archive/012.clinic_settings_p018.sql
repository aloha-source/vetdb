SET NAMES utf8mb4;

/* =========================================================
   clinic_settings — クリニック共通設定（p014.3 / p016.1 / p017.1 整合）
   - 税率は小数表現（10% = 0.10）
   - yen_per_point は DECIMAL(8,2)
   - copay_rate は DECIMAL(5,4)（receipt_* と一致）
   - 端数処理は method を ENUM('floor','round','ceil') に統一
     ※ 発行時: clinic_settings.tax_rounding_method → receipt_* .tax_rounding にそのままコピー
   ========================================================= */

DROP TABLE IF EXISTS clinic_settings;
CREATE TABLE clinic_settings (
  id                        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

  /* ---------- 請求・点数関連 ---------- */
  yen_per_point             DECIMAL(8,2) NOT NULL DEFAULT 10.00,   -- 1点=10円
  copay_rate                DECIMAL(5,4) NOT NULL DEFAULT 0.1000,  -- 10% = 0.1000

  /* ---------- 税率・端数処理 ---------- */
  tax_rate_default          DECIMAL(4,2) NOT NULL DEFAULT 0.10,    -- 10%は0.10（小数）
  tax_rounding_method       ENUM('floor','round','ceil') NOT NULL DEFAULT 'round',
  tax_rounding_scope        ENUM('line','total') NOT NULL DEFAULT 'line',

  /* ---------- インボイス/帳票ヘッダ ---------- */
  invoice_qualified_number  VARCHAR(32)  NULL,
  invoice_number_format     VARCHAR(64)  NULL,   -- 例: 'INV-{YYYY}-{SEQ6}'
  clinic_display_name       VARCHAR(128) NULL,
  clinic_address            VARCHAR(255) NULL,
  clinic_phone              VARCHAR(32)  NULL,

  /* ---------- 監査/削除・並行制御（v1p9方針） ---------- */
  row_version               BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at                DATETIME NULL,

  /* ---------- 作成・更新 ---------- */
  created_at                DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  /* 一覧最適化（v1p9の共通方針） */
  KEY idx_clinic_settings_list (deleted_at, updated_at, id)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  ROW_FORMAT=DYNAMIC;
