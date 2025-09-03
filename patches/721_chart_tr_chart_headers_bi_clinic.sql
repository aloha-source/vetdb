/* 721_chart_tr_chart_headers_bi_clinic.sql */
-- @phase: trigger
-- @provides: trigger:tr_chart_headers_bi_clinic
-- @requires: table:chart_headers, table:farms

DROP TRIGGER IF EXISTS tr_chart_headers_bi_clinic;

DELIMITER $$
/* CSIFH: INSERT時に farms.clinic_uuid を継承して固定（確定スナップの当時値） */
CREATE TRIGGER tr_chart_headers_bi_clinic
BEFORE INSERT ON chart_headers
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid IS NULL OR LENGTH(NEW.clinic_uuid) = 0 THEN
    SELECT f.clinic_uuid INTO NEW.clinic_uuid
      FROM farms f
     WHERE f.uuid = NEW.farm_uuid
     LIMIT 1;
  END IF;
END $$
DELIMITER ;
