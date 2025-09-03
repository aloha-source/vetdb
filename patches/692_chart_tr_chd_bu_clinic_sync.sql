/* 692_chart_tr_chd_bu_clinic_sync.sql */
-- @phase: trigger
-- @provides: trigger:tr_chart_header_drafts_bu_clinic_sync
-- @requires: table:chart_header_drafts, table:farms

DROP TRIGGER IF EXISTS tr_chart_header_drafts_bu_clinic_sync;

DELIMITER $$
/* 任意：draft 内で farm_uuid を変更した場合に clinic_uuid も再継承して整合させる */
CREATE TRIGGER tr_chart_header_drafts_bu_clinic_sync
BEFORE UPDATE ON chart_header_drafts
FOR EACH ROW
BEGIN
  IF NEW.farm_uuid <> OLD.farm_uuid THEN
    SELECT f.clinic_uuid INTO NEW.clinic_uuid
      FROM farms f
     WHERE f.uuid = NEW.farm_uuid
     LIMIT 1;
  END IF;
  /* row_version の更新は既存トリガで実施 */
END $$
DELIMITER ;
