/* 1421_clinic_tr_clinics_bu_rowver.sql */
-- @phase: trigger
-- @provides: trigger:tr_clinics_bu_rowver
-- @requires: table:clinics
-- 役割: UUID不変＋row_versionインクリメント。原文どおり。

/* 再デプロイ安全化（トリガ個別） */
DROP TRIGGER IF EXISTS tr_clinics_bu_rowver;

DELIMITER $$
CREATE TRIGGER tr_clinics_bu_rowver
BEFORE UPDATE ON clinics
FOR EACH ROW
BEGIN
  /* UUIDは不変：誤更新による連鎖CASCADE事故を防止 */
  SET NEW.uuid = OLD.uuid;
  /* 楽観ロック／差分検知 */
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;
