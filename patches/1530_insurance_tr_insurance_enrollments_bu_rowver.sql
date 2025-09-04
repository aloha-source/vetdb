/* 1530_insurance_tr_insurance_enrollments_bu_rowver.sql */
-- @phase: trigger
-- @provides: trigger:tr_insurance_enrollments_rowver_bu
-- @requires: table:insurance_enrollments
-- 役割: row_version の自動インクリメント。原文どおり。

/* 再デプロイ安全化（トリガ個別） */
DROP TRIGGER IF EXISTS `tr_insurance_enrollments_rowver_bu`;

DELIMITER $$
CREATE TRIGGER `tr_insurance_enrollments_rowver_bu`
BEFORE UPDATE ON `insurance_enrollments`
FOR EACH ROW
BEGIN
  SET NEW.`row_version` = OLD.`row_version` + 1;
END$$
DELIMITER ;
