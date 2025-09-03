/* 431_checkup_tr_checkup_items_bu_rowver.sql */
-- @phase: trigger
-- @provides: trigger:tr_checkup_items_bu_rowver
-- @requires: table:checkup_items

DROP TRIGGER IF EXISTS tr_checkup_items_bu_rowver;

DELIMITER $$

CREATE TRIGGER tr_checkup_items_bu_rowver
BEFORE UPDATE ON checkup_items
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$

DELIMITER ;
