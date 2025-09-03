/* 690_chart_tr_chd_bi_uuid_v7.sql */
-- @phase: trigger
-- @provides: trigger:tr_chart_header_drafts_bi_uuid_v7
-- @requires: table:chart_header_drafts, function:uuid_v7_bin

DROP TRIGGER IF EXISTS tr_chart_header_drafts_bi_uuid_v7;

DELIMITER $$
CREATE TRIGGER tr_chart_header_drafts_bi_uuid_v7
BEFORE INSERT ON chart_header_drafts
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid) = 0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;
