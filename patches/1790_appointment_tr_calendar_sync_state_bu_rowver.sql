/* 1790_appointment_tr_calendar_sync_state_bu_rowver.sql */
-- @phase: trigger
-- @provides: trigger:tr_calendar_sync_state_bu_rowver
-- @requires: table:calendar_sync_state

DROP TRIGGER IF EXISTS tr_calendar_sync_state_bu_rowver;

DELIMITER $$
CREATE TRIGGER tr_calendar_sync_state_bu_rowver
BEFORE UPDATE ON calendar_sync_state
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END $$
DELIMITER ;
