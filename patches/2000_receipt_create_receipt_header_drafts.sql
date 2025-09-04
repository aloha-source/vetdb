/* 2000_receipt_create_receipt_header_drafts.sql */
-- @phase: create
-- @feature: receipt
-- @provides: table:receipt_header_drafts
-- @requires: function:uuid_v7_bin, table:farms
-- 備考: インデックス/一意/外部キー/トリガは別ファイルで付与（原文列定義は維持）

SET NAMES utf8mb4;

DROP TABLE IF EXISTS receipt_header_drafts;
CREATE TABLE IF NOT EXISTS receipt_header_drafts (
  id                    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                  BINARY(16) NOT NULL UNIQUE,                  -- v7 UUID（下書きの識別）

  /* 任意のスコープ（印字や絞り込み用） */
  farm_uuid             BINARY(16) NULL,
  clinic_uuid           BINARY(16) NULL,                             -- 当時の所属院（可変：farm変更時に再継承）
  title                 VARCHAR(120) NULL,
  note                  VARCHAR(255) NULL,

  /* 状態遷移（発行で issued に） */
  status                ENUM('open','closed','issued') NOT NULL DEFAULT 'open',
  issued_at             DATETIME NULL,                               -- issued 遷移時刻
  issued_by_user_id     INT UNSIGNED NULL,
  issued_receipt_uuid   BINARY(16) NULL,                             -- 対応する receipt_headers.uuid（作成後にセット）

  /* クリニック設定スナップ（draft時点の値） */
  yen_per_point         DECIMAL(8,2) NOT NULL DEFAULT 10.00,         -- 例: 1点=10円
  copay_rate            DECIMAL(5,4) NOT NULL DEFAULT 0.1000,        -- 例: 10% は 0.1000
  tax_rounding          ENUM('floor','round','ceil') NOT NULL DEFAULT 'round',

  /* 集計（税抜→税→税込） */
  total_b_points        INT UNSIGNED NOT NULL DEFAULT 0,
  total_a_points        INT UNSIGNED NOT NULL DEFAULT 0,
  total_price_yen       INT UNSIGNED NOT NULL DEFAULT 0,             -- 自由価格（税抜）
  subtotal_yen          INT UNSIGNED NOT NULL DEFAULT 0,             -- 点換算円 + 自由価格（税抜）
  tax_yen               INT UNSIGNED NOT NULL DEFAULT 0,
  total_insurance_yen   INT UNSIGNED NOT NULL DEFAULT 0,             -- 税込（保険）
  total_private_yen     INT UNSIGNED NOT NULL DEFAULT 0,             -- 税込（自由）
  patient_copay_yen     INT UNSIGNED NOT NULL DEFAULT 0,             -- 患者負担
  insurer_pay_yen       INT UNSIGNED NOT NULL DEFAULT 0,             -- 保険者負担

  /* 監査（可変テーブルなので row_version / deleted_at を保持） */
  created_by            INT UNSIGNED NULL,
  updated_by            INT UNSIGNED NULL,
  row_version           BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at            DATETIME NULL,
  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
