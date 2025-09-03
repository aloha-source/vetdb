/* 620_chart_tr_disease_master_bi_uuid_v7.sql */
-- @phase: trigger
-- @provides: trigger:tr_disease_master_bi_uuid_v7
-- @requires: table:disease_master, function:uuid_v7_bin

DROP TRIGGER IF EXISTS tr_disease_master_bi_uuid_v7;

DELIMITER $$
CREATE TRIGGER tr_disease_master_bi_uuid_v7
BEFORE INSERT ON disease_master
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid) = 0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;
