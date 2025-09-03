/* 1460_clinic_tr_clinic_settings_bu_rowver.sql */
-- @phase: trigger
-- @provides: trigger:tr_clinic_settings_bu_rowver
-- @requires: table:clinic_settings
-- 役割: row_version の自動インクリメント。原文どおり。

/* 再デプロイ安全化（トリガ個別） */
DROP TRIGGER IF EXISTS tr_clinic_settings_bu_rowver;

DELIMITER $$
CREATE TRIGGER tr_clinic_settings_bu_rowver
BEFORE UPDATE ON clinic_settings
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;
