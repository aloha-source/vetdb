/* 1620_appointment_tr_appointments_bi_uuid_v7.sql */
-- @phase: trigger
-- @provides: trigger:tr_appointments_bi_uuid_v7
-- @requires: table:appointments, function:uuid_v7_bin

/* 再デプロイ安全化（トリガ個別） */
DROP TRIGGER IF EXISTS tr_appointments_bi_uuid_v7;

DELIMITER $$
CREATE TRIGGER tr_appointments_bi_uuid_v7
BEFORE INSERT ON appointments
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;
