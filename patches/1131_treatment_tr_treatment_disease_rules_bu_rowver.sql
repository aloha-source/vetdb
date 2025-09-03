/* 1131_treatment_tr_treatment_disease_rules_bu_rowver.sql */
-- @phase: trigger
-- @provides: trigger:bu_treatment_disease_rules_rowver
-- @requires: table:treatment_disease_rules
-- 役割: clinic_uuid の不変ガード＋row_version自動更新。原文どおり。

DROP TRIGGER IF EXISTS bu_treatment_disease_rules_rowver;

DELIMITER $$
CREATE TRIGGER bu_treatment_disease_rules_rowver
BEFORE UPDATE ON treatment_disease_rules
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid <> OLD.clinic_uuid THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'clinic_uuid is immutable on treatment_disease_rules';
  END IF;
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;
