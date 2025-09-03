/* 331_checkup_tr_checkups_bu_rowver.sql */
-- @phase: trigger
-- @provides: trigger:tr_checkups_bu_rowver
-- @requires: table:checkups

DROP TRIGGER IF EXISTS tr_checkups_bu_rowver;

DELIMITER $$

CREATE TRIGGER tr_checkups_bu_rowver
BEFORE UPDATE ON checkups
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$

DELIMITER ;
