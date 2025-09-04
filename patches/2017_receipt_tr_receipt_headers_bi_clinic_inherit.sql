/* 2017_receipt_tr_receipt_headers_bi_clinic_inherit.sql */
-- @phase: trigger
-- @feature: receipt
-- @provides: trigger:tr_receipt_headers_bi_clinic_inherit
-- @requires: table:receipt_headers, table:farms
-- 備考: 原文「tr_receipt_headers_bi_clinic_inherit」をそのまま分離

DROP TRIGGER IF EXISTS tr_receipt_headers_bi_clinic_inherit;
DELIMITER $$
CREATE TRIGGER tr_receipt_headers_bi_clinic_inherit
BEFORE INSERT ON receipt_headers
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid IS NULL AND NEW.farm_uuid IS NOT NULL THEN
    SELECT f.clinic_uuid INTO NEW.clinic_uuid
      FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
  END IF;
END $$
DELIMITER ;
