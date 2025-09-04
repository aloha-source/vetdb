/* 1621_appointment_tr_appointments_bu_rowver.sql */
-- @phase: trigger
-- @provides: trigger:tr_appointments_bu_rowver
-- @requires: table:appointments

/* 再デプロイ安全化（トリガ個別） */
DROP TRIGGER IF EXISTS tr_appointments_bu_rowver;

DELIMITER $$
CREATE TRIGGER tr_appointments_bu_rowver
BEFORE UPDATE ON appointments
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END $$
DELIMITER ;
