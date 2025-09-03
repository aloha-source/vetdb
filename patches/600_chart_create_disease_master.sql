/* 600_chart_create_disease_master.sql */
-- @phase: create
-- @provides: table:disease_master
-- @requires: function:uuid_v7_bin

SET NAMES utf8mb4;

/* 再デプロイ安全化 */
DROP TRIGGER IF EXISTS tr_disease_master_bi_uuid_v7;
DROP TABLE IF EXISTS disease_master;

CREATE TABLE IF NOT EXISTS disease_master (
  id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,            
  uuid              BINARY(16) NOT NULL UNIQUE,                         

  code6             CHAR(6) NOT NULL UNIQUE,                            
  major_name        VARCHAR(32) NOT NULL,                               
  middle_name       VARCHAR(32) NOT NULL,                               
  minor_name        VARCHAR(32) NOT NULL,                               

  major_code        CHAR(2) AS (SUBSTRING(code6, 1, 2)) VIRTUAL,        
  middle_code       CHAR(2) AS (SUBSTRING(code6, 3, 2)) VIRTUAL,        
  minor_code        CHAR(2) AS (SUBSTRING(code6, 5, 2)) VIRTUAL,        

  display_code      VARCHAR(8)
    AS (CONCAT_WS('-', major_code, middle_code, minor_code)) PERSISTENT,
  display_name      VARCHAR(255)
    AS (CONCAT_WS(' / ', major_name, middle_name, minor_name)) PERSISTENT,

  is_active         TINYINT(1) NOT NULL DEFAULT 1,                     
  row_version       BIGINT UNSIGNED NOT NULL DEFAULT 1,                
  deleted_at        DATETIME NULL,                                     
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  CHECK (code6 REGEXP '^[0-9]{6}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
