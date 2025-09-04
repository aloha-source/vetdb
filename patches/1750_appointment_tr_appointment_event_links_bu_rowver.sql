/* 1750_appointment_tr_appointment_event_links_bu_rowver.sql */
-- @phase: trigger
-- @provides: trigger:tr_appointment_event_links_bu_rowver
-- @requires: table:appointment_event_links

DROP TRIGGER IF EXISTS tr_appointment_event_links_bu_rowver;

DELIMITER $$
CREATE TRIGGER tr_appointment_event_links_bu_rowver
BEFORE UPDATE ON appointment_event_links
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END $$
DELIMITER ;
