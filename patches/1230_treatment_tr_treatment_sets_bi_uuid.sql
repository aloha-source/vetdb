/* 1230_treatment_tr_treatment_sets_bi_uuid.sql */
-- @phase: trigger
-- @provides: trigger:bi_treatment_sets_uuid
-- @requires: table:treatment_sets, function:uuid_v7_bin, table:users
-- 役割: UUID自動採番＋usersからclinic_uuid継承（NULL時のみ）。原文どおり。

DROP TRIGGER IF EXISTS bi_treatment_sets_uuid;

DELIMITER $$
CREATE TRIGGER bi_treatment_sets_uuid
BEFORE INSERT ON treatment_sets
FOR EACH ROW
BEGIN
  DECLARE v_user_clinic BINARY(16);
  SET NEW.uuid = COALESCE(NEW.uuid, uuid_v7_bin());

  /* 親（users）から clinic_uuid を継承（NULL時のみ設定：最低適用） */
  IF NEW.clinic_uuid IS NULL THEN
    SELECT u.clinic_uuid INTO v_user_clinic
      FROM users u
     WHERE u.uuid = NEW.user_uuid
     LIMIT 1;
    SET NEW.clinic_uuid = v_user_clinic;
  END IF;
END$$
DELIMITER ;
