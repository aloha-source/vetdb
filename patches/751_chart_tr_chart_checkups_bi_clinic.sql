/* 751_chart_tr_chart_checkups_bi_clinic.sql */
-- @phase: trigger
-- @provides: trigger:tr_chart_checkups_bi_clinic
-- @requires: table:chart_checkups, table:chart_headers

DROP TRIGGER IF EXISTS tr_chart_checkups_bi_clinic;

DELIMITER $$
/* CSIFH: INSERT時に親 chart_headers の clinic_uuid を継承して固定 */
CREATE TRIGGER tr_chart_checkups_bi_clinic
BEFORE INSERT ON chart_checkups
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid IS NULL OR LENGTH(NEW.clinic_uuid) = 0 THEN
    SELECT ch.clinic_uuid INTO NEW.clinic_uuid
      FROM chart_headers ch
     WHERE ch.uuid = NEW.chart_uuid
     LIMIT 1;
  END IF;
END $$
DELIMITER ;
