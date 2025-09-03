/* 231_checkup_tr_visits_bu_rowver.sql */
-- @phase: trigger
-- @provides: trigger:bu_visits_rowver
-- @requires: table:visits

DROP TRIGGER IF EXISTS bu_visits_rowver;

DELIMITER $$

CREATE TRIGGER bu_visits_rowver
BEFORE UPDATE ON visits
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$

DELIMITER ;
