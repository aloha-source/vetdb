/* 2036_receipt_tr_receipt_items_bi_clinic_inherit.sql */
-- @phase: trigger
-- @feature: receipt
-- @provides: trigger:tr_receipt_items_bi_clinic_inherit
-- @requires: table:receipt_items, table:receipt_checkups

DROP TRIGGER IF EXISTS tr_receipt_items_bi_clinic_inherit;
DELIMITER $$
CREATE TRIGGER tr_receipt_items_bi_clinic_inherit
BEFORE INSERT ON receipt_items
FOR EACH ROW
BEGIN
  DECLARE v_item_clinic BINARY(16);

  /* 親CKPから clinic_uuid を固定継承 */
  IF NEW.clinic_uuid IS NULL THEN
    SELECT c.clinic_uuid INTO v_item_clinic
      FROM receipt_checkups c WHERE c.uuid = NEW.receipt_checkup_uuid LIMIT 1;
    SET NEW.clinic_uuid = v_item_clinic;
  END IF;
END $$
DELIMITER ;
