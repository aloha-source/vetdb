-- ============================================================
-- 3) 親テーブル：visits
-- ============================================================
CREATE TABLE visits (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid       BINARY(16) NOT NULL UNIQUE,

  -- 必要に応じて業務カラムを追加
  -- visit_date DATE NULL,

  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_visits_bi_uuid_v7
BEFORE INSERT ON visits
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid)=0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;

CREATE OR REPLACE VIEW visits_hex_v AS
SELECT
  id,
  uuid_bin_to_hex(uuid) AS uuid_hex,
  created_at, updated_at
FROM visits;