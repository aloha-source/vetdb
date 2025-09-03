/* 781_chart_tr_chart_items_bi_clinic.sql */
-- @phase: trigger
-- @provides: trigger:tr_chart_items_bi_clinic
-- @requires: table:chart_items, table:chart_checkups

DROP TRIGGER IF EXISTS tr_chart_items_bi_clinic;

DELIMITER $$
/* CSIFH: INSERT時に親 chart_checkups の clinic_uuid を継承して固定 */
CREATE TRIGGER tr_chart_items_bi_clinic
BEFORE INSERT ON chart_items
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid IS NULL OR LENGTH(NEW.clinic_uuid) = 0 THEN
    SELECT cc.clinic_uuid INTO NEW.clinic_uuid
      FROM chart_checkups cc
     WHERE cc.uuid = NEW.chart_checkup_uuid
     LIMIT 1;
  END IF;
END $$
DELIMITER ;
