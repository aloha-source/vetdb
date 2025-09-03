/* 693_chart_tr_chd_bu_rowver.sql */
-- @phase: trigger
-- @provides: trigger:tr_chart_header_drafts_bu_rowver
-- @requires: table:chart_header_drafts

DROP TRIGGER IF EXISTS tr_chart_header_drafts_bu_rowver;

DELIMITER $$
CREATE TRIGGER tr_chart_header_drafts_bu_rowver
BEFORE UPDATE ON chart_header_drafts
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END $$
DELIMITER ;
