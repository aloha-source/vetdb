/* 2008_receipt_tr_receipt_header_drafts_bu_rowver.sql */
-- @phase: trigger
-- @feature: receipt
-- @provides: trigger:tr_receipt_header_drafts_bu_rowver
-- @requires: table:receipt_header_drafts

DROP TRIGGER IF EXISTS tr_receipt_header_drafts_bu_rowver;
DELIMITER $$
CREATE TRIGGER tr_receipt_header_drafts_bu_rowver
BEFORE UPDATE ON receipt_header_drafts
FOR EACH ROW
BEGIN
  DECLARE v_clinic2 BINARY(16);

  /* 楽観ロック：row_version 自動インクリメント */
  SET NEW.row_version = OLD.row_version + 1;

  /* farm_uuid 変更時は clinic_uuid を再継承 */
  IF (NEW.farm_uuid <> OLD.farm_uuid) OR (NEW.clinic_uuid IS NULL AND NEW.farm_uuid IS NOT NULL) THEN
    SELECT f.clinic_uuid INTO v_clinic2
      FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
    SET NEW.clinic_uuid = v_clinic2;
  END IF;
END $$
DELIMITER ;
