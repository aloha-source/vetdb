/* 2007_receipt_tr_tr_receipt_header_drafts_bi_uuid_v7.sql */
-- @phase: trigger
-- @feature: receipt
-- @provides: trigger:tr_receipt_header_drafts_bi_uuid_v7
-- @requires: table:receipt_header_drafts, function:uuid_v7_bin

DROP TRIGGER IF EXISTS tr_receipt_header_drafts_bi_uuid_v7;
DELIMITER $$
CREATE TRIGGER tr_receipt_header_drafts_bi_uuid_v7
BEFORE INSERT ON receipt_header_drafts
FOR EACH ROW
BEGIN
  DECLARE v_clinic BINARY(16);

  /* uuid未指定なら v7 を自動採番 */
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid)=0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;

  /* 挿入時に farm → clinic を継承（弱参照 / FKはfarmにのみ） */
  IF NEW.clinic_uuid IS NULL AND NEW.farm_uuid IS NOT NULL THEN
    SELECT f.clinic_uuid INTO v_clinic
      FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
    SET NEW.clinic_uuid = v_clinic;
  END IF;
END $$
DELIMITER ;
