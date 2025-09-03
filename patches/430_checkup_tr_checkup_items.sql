/* 430_checkup_tr_checkup_items_bi_uuid_v7.sql */
-- @phase: trigger
-- @provides: trigger:tr_checkup_items_bi_uuid_v7
-- @requires: table:checkup_items, function:uuid_v7_bin, table:checkups

DROP TRIGGER IF EXISTS tr_checkup_items_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_checkup_items_bi_clinic;

DELIMITER $$

CREATE TRIGGER tr_checkup_items_bi_uuid_v7
BEFORE INSERT ON checkup_items
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;

  /* CSIFH: 親checkupsの clinic_uuid を継承（履歴固定） */
  IF NEW.clinic_uuid IS NULL OR NEW.clinic_uuid = UNHEX(REPEAT('0',32)) THEN
    SELECT c.clinic_uuid INTO @cu FROM checkups c WHERE c.uuid = NEW.checkup_uuid LIMIT 1;
    SET NEW.clinic_uuid = @cu;
  END IF;
END$$

DELIMITER ;
