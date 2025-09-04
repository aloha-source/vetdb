/* 2009_receipt_tr_receipt_header_drafts_bi_clinic_inherit.sql */
-- @phase: trigger
-- @feature: receipt
-- @provides: trigger:tr_receipt_header_drafts_bi_clinic_inherit
-- @requires: table:receipt_header_drafts, table:farms
-- 備考: 原文の命名・ロジックをそのまま分離（BIで farm→clinic 継承）

DROP TRIGGER IF EXISTS tr_receipt_header_drafts_bi_clinic_inherit;
DELIMITER $$
CREATE TRIGGER tr_receipt_header_drafts_bi_clinic_inherit
BEFORE INSERT ON receipt_header_drafts
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid IS NULL AND NEW.farm_uuid IS NOT NULL THEN
    SELECT f.clinic_uuid INTO NEW.clinic_uuid
      FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
  END IF;
END $$
DELIMITER ;
