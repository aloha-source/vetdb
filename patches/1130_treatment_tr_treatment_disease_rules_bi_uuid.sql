/* 1130_treatment_tr_treatment_disease_rules_bi_uuid.sql */
-- @phase: trigger
-- @provides: trigger:bi_treatment_disease_rules_uuid
-- @requires: table:treatment_disease_rules, function:uuid_v7_bin, table:treatment_master
-- 役割: UUID自動採番＋clinic_uuidの親継承（NULL時のみ）。原文どおり。

DROP TRIGGER IF EXISTS bi_treatment_disease_rules_uuid;

DELIMITER $$
CREATE TRIGGER bi_treatment_disease_rules_uuid
BEFORE INSERT ON treatment_disease_rules
FOR EACH ROW
BEGIN
  DECLARE v_parent_clinic BINARY(16);
  SET NEW.uuid = COALESCE(NEW.uuid, uuid_v7_bin());

  /* 親（treatment_master）から clinic_uuid を継承（NULL時のみ設定：最低適用） */
  IF NEW.clinic_uuid IS NULL THEN
    SELECT tm.clinic_uuid INTO v_parent_clinic
      FROM treatment_master tm
     WHERE tm.uuid = NEW.treatment_uuid
     LIMIT 1;
    SET NEW.clinic_uuid = v_parent_clinic;
  END IF;
END$$
DELIMITER ;
