/* checkups分割時に混入したスタブのためアーカイブ。010_checkup_create_receipt_header_drafts.sql */
-- @phase: create
-- @provides: table:receipt_header_drafts
-- @requires:

DROP TABLE IF EXISTS receipt_header_drafts;

CREATE TABLE receipt_header_drafts (
  id   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid BINARY(16) NOT NULL UNIQUE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
