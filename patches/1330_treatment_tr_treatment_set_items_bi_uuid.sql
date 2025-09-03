/* 1330_treatment_tr_treatment_set_items_bi_uuid.sql */
-- @phase: trigger
-- @provides: trigger:bi_treatment_set_items_uuid
-- @requires: table:treatment_set_items, function:uuid_v7_bin, table:treatment_sets
-- 役割: UUID自動採番＋treatment_setsからclinic_uuid継承（NULL時のみ）。原文どおり。

DROP TRIGGER IF EXISTS bi_treatment_set_items_uuid;

DELIMITER $$
CREATE TRIGGER bi_treatment_set_items_uuid
BEFORE INSERT ON treatment_set_items
FOR EACH ROW
BEGIN
  DECLARE v_set_clinic BINARY(16);
  SET NEW.uuid = COALESCE(NEW.uuid, uuid_v7_bin());

  /* 親（treatment_sets）から clinic_uuid を継承（NULL時のみ設定：最低適用） */
  IF NEW.clinic_uuid IS NULL THEN
    SELECT ts.clinic_uuid INTO v_set_clinic
      FROM treatment_sets ts
     WHERE ts.uuid = NEW.set_uuid
     LIMIT 1;
    SET NEW.clinic_uuid = v_set_clinic;
  END IF;
END$$
DELIMITER ;
