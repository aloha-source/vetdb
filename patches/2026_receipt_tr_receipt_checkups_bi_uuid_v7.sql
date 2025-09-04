/* 2026_receipt_tr_receipt_checkups_bi_uuid_v7.sql */
-- @phase: trigger
-- @feature: receipt
-- @provides: trigger:tr_receipt_checkups_bi_uuid_v7
-- @requires: table:receipt_checkups, function:uuid_v7_bin

DROP TRIGGER IF EXISTS tr_receipt_checkups_bi_uuid_v7;
DELIMITER $$
CREATE TRIGGER tr_receipt_checkups_bi_uuid_v7
BEFORE INSERT ON receipt_checkups
FOR EACH ROW
BEGIN
  DECLARE v_ckp_clinic BINARY(16);

  /* uuid未指定なら v7 を自動採番（items が参照するため必須） */
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid)=0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;

  /* ヘッダから clinic_uuid を固定継承 */
  IF NEW.clinic_uuid IS NULL THEN
    SELECT h.clinic_uuid INTO v_ckp_clinic
      FROM receipt_headers h WHERE h.uuid = NEW.receipt_header_uuid LIMIT 1;
    SET NEW.clinic_uuid = v_ckp_clinic;
  END IF;
END $$
DELIMITER ;
