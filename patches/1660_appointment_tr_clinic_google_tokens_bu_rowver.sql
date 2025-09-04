/* 1660_appointment_tr_clinic_google_tokens_bu_rowver.sql */
-- @phase: trigger
-- @provides: trigger:tr_clinic_google_tokens_bu_rowver
-- @requires: table:clinic_google_tokens

DROP TRIGGER IF EXISTS tr_clinic_google_tokens_bu_rowver;

DELIMITER $$
CREATE TRIGGER tr_clinic_google_tokens_bu_rowver
BEFORE UPDATE ON clinic_google_tokens
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END $$
DELIMITER ;
