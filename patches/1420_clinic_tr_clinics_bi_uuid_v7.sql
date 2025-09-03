/* 1420_clinic_tr_clinics_bi_uuid_v7.sql */
-- @phase: trigger
-- @provides: trigger:tr_clinics_bi_uuid_v7
-- @requires: table:clinics, function:uuid_v7_bin
-- 役割: UUID自動採番（未指定時のみ）。原文どおり。

/* 再デプロイ安全化（トリガ個別） */
DROP TRIGGER IF EXISTS tr_clinics_bi_uuid_v7;

DELIMITER $$
CREATE TRIGGER tr_clinics_bi_uuid_v7
BEFORE INSERT ON clinics
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;
