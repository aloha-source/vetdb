/* 1920_farmmirror_tr_farms_bi_uuid_v7.sql */
-- @phase: trigger
-- @provides: trigger:tr_farms_bi_uuid_v7
-- @requires: table:farms, function:uuid_v7_bin
-- 役割: UUID未指定時の自動採番（原文どおり）

DROP TRIGGER IF EXISTS tr_farms_bi_uuid_v7;
DELIMITER $$
CREATE TRIGGER tr_farms_bi_uuid_v7
BEFORE INSERT ON farms
FOR EACH ROW
BEGIN
  /* UUIDはBINARY(16)/v7想定。未指定時のみ自動採番。 */
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;
