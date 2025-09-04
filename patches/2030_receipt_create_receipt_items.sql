/* 2030_receipt_create_receipt_items.sql */
-- @phase: create
-- @feature: receipt
-- @provides: table:receipt_items
-- @requires: table:receipt_checkups

DROP TABLE IF EXISTS receipt_items;
CREATE TABLE IF NOT EXISTS receipt_items (
  id                     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  receipt_checkup_uuid   BINARY(16) NOT NULL,                       -- ↔ receipt_checkups.uuid（弱リンク）
  clinic_uuid            BINARY(16) NULL,                           -- 親CKPから固定継承
  source_checkup_item_id INT UNSIGNED NOT NULL,                     -- 由来：checkup_items.id

  /* マスタ/入力の当時値スナップ（印字・再現に必要な範囲を保持） */
  description            VARCHAR(255) NOT NULL,                     -- 例: 処置/薬品名
  qty_unit               VARCHAR(32)  NULL,                         -- 例: mL, 回, 錠...
  quantity               DECIMAL(10,2) NOT NULL DEFAULT 1,

  /* 点数/自由価格の両立 */
  pay_type               ENUM('insurance','private') NOT NULL DEFAULT 'insurance',
  unit_b_points          INT UNSIGNED NOT NULL DEFAULT 0,
  unit_a_points          INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_points        INT UNSIGNED NOT NULL DEFAULT 0,
  yen_per_point          DECIMAL(8,2) NOT NULL DEFAULT 0.00,

  unit_price_yen         INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_price_yen     INT UNSIGNED NOT NULL DEFAULT 0,

  /* 税と金額（行で算出→ヘッダで合算） */
  tax_rate               DECIMAL(4,2) NOT NULL DEFAULT 0.00,
  subtotal_yen           INT UNSIGNED NOT NULL DEFAULT 0,           -- 税抜
  tax_yen                INT UNSIGNED NOT NULL DEFAULT 0,
  total_yen              INT UNSIGNED NOT NULL DEFAULT 0,           -- 税込

  note                   VARCHAR(255) NULL,
  created_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
