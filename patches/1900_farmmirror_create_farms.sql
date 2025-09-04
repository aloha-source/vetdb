/* 1900_farmmirror_create_farms.sql */
-- @phase: create
-- @provides: table:farms
-- @requires: table:clinics, function:uuid_v7_bin
-- 備考: 索引/UNIQUE/FK/トリガは別ファイルへ分離（本文は原文の列定義を維持）

--SET NAMES utf8mb4;はinitに分離

DROP TABLE IF EXISTS farms;
CREATE TABLE farms (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid             BINARY(16) NOT NULL,
  clinic_uuid      BINARY(16) NOT NULL,              -- ↔ clinics.uuid（院所属・厳格）
  name             VARCHAR(120) NOT NULL,
  billing_name     VARCHAR(120) NULL,
  billing_address  VARCHAR(255) NULL,

  row_hash         CHAR(64) NULL,                    -- 任意：差分検出や外部同期の補助
  created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at       DATETIME NULL,                    -- ソフトデリート（論理削除）
  row_version      BIGINT UNSIGNED NOT NULL DEFAULT 1 -- 楽観ロック/差分検知
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
