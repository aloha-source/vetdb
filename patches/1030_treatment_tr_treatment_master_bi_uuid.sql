/* 1030_treatment_tr_treatment_master_bi_uuid.sql */
-- @phase: trigger
-- @provides: trigger:bi_treatment_master_uuid
-- @requires: table:treatment_master, function:uuid_v7_bin
-- 役割: UUID自動採番（NULL時）。原文どおり。

DROP TRIGGER IF EXISTS bi_treatment_master_uuid;

DELIMITER $$
CREATE TRIGGER bi_treatment_master_uuid
BEFORE INSERT ON treatment_master
FOR EACH ROW
BEGIN
  SET NEW.uuid = COALESCE(NEW.uuid, uuid_v7_bin());
END$$
DELIMITER ;
