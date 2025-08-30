DROP TABLE IF EXISTS disease_master;
CREATE TABLE IF NOT EXISTS disease_master (
  id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid              CHAR(36) NOT NULL UNIQUE,

  -- 正規コード（6桁・先頭ゼロ保持）
  code6             CHAR(6)  NOT NULL,  -- 例: '045501'

  -- 派生列（検索性向上）
  major_code        CHAR(2)  GENERATED ALWAYS AS (SUBSTR(code6,1,2)) VIRTUAL,
  middle_code       CHAR(2)  GENERATED ALWAYS AS (SUBSTR(code6,3,2)) VIRTUAL,
  minor_code        CHAR(2)  GENERATED ALWAYS AS (SUBSTR(code6,5,2)) VIRTUAL,
  display_code      CHAR(8)  GENERATED ALWAYS AS
                     (CONCAT(SUBSTR(code6,1,2),'-',SUBSTR(code6,3,2),'-',SUBSTR(code6,5,2))) STORED,

  -- 名称
  major_name        VARCHAR(100) NOT NULL,
  middle_name       VARCHAR(255) NOT NULL,
  minor_name        VARCHAR(255) NOT NULL,
  display_name      VARCHAR(300) GENERATED ALWAYS AS
                     (CONCAT(middle_name, '（', minor_name, '）')) STORED,

  legal_note        TEXT NULL,
  is_active         TINYINT(1) NOT NULL DEFAULT 1,
  is_reportable     TINYINT(1) NOT NULL DEFAULT 0,

  -- 監査
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at        DATETIME NULL,
  row_version       BIGINT UNSIGNED NOT NULL DEFAULT 1,

  -- 制約・索引
  UNIQUE KEY uq_disease_code6 (code6),
  CHECK (code6 REGEXP '^[0-9]{6}$'),
  INDEX idx_disease_major (major_code),
  INDEX idx_disease_mm    (major_code, middle_code),
  INDEX idx_disease_name  (is_active, middle_name, minor_name),
  INDEX idx_quality       (deleted_at, updated_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
