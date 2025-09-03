/* 1231_treatment_tr_treatment_sets_bu_rowver.sql */
-- @phase: trigger
-- @provides: trigger:bu_treatment_sets_rowver
-- @requires: table:treatment_sets
-- 役割: clinic_uuid の不変ガード＋row_version自動更新。原文どおり。

DROP TRIGGER IF EXISTS bu_treatment_sets_rowver;

DELIMITER $$
CREATE TRIGGER bu_treatment_sets_rowver
BEFORE UPDATE ON treatment_sets
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid <> OLD.clinic_uuid THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'clinic_uuid is immutable on treatment_sets';
  END IF;
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;
