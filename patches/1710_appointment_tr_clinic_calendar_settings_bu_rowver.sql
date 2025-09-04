/* 1710_appointment_tr_clinic_calendar_settings_bu_rowver.sql */
-- @phase: trigger
-- @provides: trigger:tr_clinic_calendar_settings_bu_rowver
-- @requires: table:clinic_calendar_settings

DROP TRIGGER IF EXISTS tr_clinic_calendar_settings_bu_rowver;

DELIMITER $$
CREATE TRIGGER tr_clinic_calendar_settings_bu_rowver
BEFORE UPDATE ON clinic_calendar_settings
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END $$
DELIMITER ;
