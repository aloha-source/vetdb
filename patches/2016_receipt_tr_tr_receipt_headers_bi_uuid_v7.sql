/* 2016_receipt_tr_tr_receipt_headers_bi_uuid_v7.sql */
-- @phase: trigger
-- @feature: receipt
-- @provides: trigger:tr_receipt_headers_bi_uuid_v7
-- @requires: table:receipt_headers, function:uuid_v7_bin

DROP TRIGGER IF EXISTS tr_receipt_headers_bi_uuid_v7;
DELIMITER $$
CREATE TRIGGER tr_receipt_headers_bi_uuid_v7
BEFORE INSERT ON receipt_headers
FOR EACH ROW
BEGIN
  DECLARE v_hdr_clinic BINARY(16);

  /* uuid未指定なら v7 を自動採番 */
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid)=0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;

  /* 発行時に farm → clinic を固定継承（アプリが直接セットしても可） */
  IF NEW.clinic_uuid IS NULL AND NEW.farm_uuid IS NOT NULL THEN
    SELECT f.clinic_uuid INTO v_hdr_clinic
      FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
    SET NEW.clinic_uuid = v_hdr_clinic;
  END IF;
END $$
DELIMITER ;
