/* 1921_farmmirror_tr_farms_bu_rowver_lockuuid.sql */
-- @phase: trigger
-- @provides: trigger:tr_farms_bu_rowver_lockuuid
-- @requires: table:farms
-- 役割: UUID固定＋row_versionインクリメント（原文どおり）

DROP TRIGGER IF EXISTS tr_farms_bu_rowver_lockuuid;
DELIMITER $$
CREATE TRIGGER tr_farms_bu_rowver_lockuuid
BEFORE UPDATE ON farms
FOR EACH ROW
BEGIN
  /* UUIDは不変・row_versionは+1。clinic_uuidの付け替えはFKが整合性を担保。 */
  SET NEW.uuid = OLD.uuid;
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;
