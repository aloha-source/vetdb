/* 2027_receipt_tr_receipt_checkups_bi_clinic_inherit.sql */
-- @phase: trigger
-- @feature: receipt
-- @provides: trigger:tr_receipt_checkups_bi_clinic_inherit
-- @requires: table:receipt_checkups, table:receipt_headers

DROP TRIGGER IF EXISTS tr_receipt_checkups_bi_clinic_inherit;
DELIMITER $$
CREATE TRIGGER tr_receipt_checkups_bi_clinic_inherit
BEFORE INSERT ON receipt_checkups
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid IS NULL THEN
    SELECT h.clinic_uuid INTO NEW.clinic_uuid
      FROM receipt_headers h WHERE h.uuid = NEW.receipt_header_uuid LIMIT 1;
  END IF;
END $$
DELIMITER ;
