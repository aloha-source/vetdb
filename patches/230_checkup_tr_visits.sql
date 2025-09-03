/* 230_checkup_tr_visits.sql */
-- @phase: trigger
-- @provides: trigger:bi_visits_uuid, trigger:bu_visits_rowver
-- @requires: table:visits, function:uuid_v7_bin, table:farms

DROP TRIGGER IF EXISTS bi_visits_uuid;
DROP TRIGGER IF EXISTS bu_visits_rowver;
DROP TRIGGER IF EXISTS tr_visits_bi_clinic;

DELIMITER $$

CREATE TRIGGER bi_visits_uuid
BEFORE INSERT ON visits
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = 0x00000000000000000000000000000000 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
  IF NEW.visit_started_at IS NULL THEN
    SET NEW.visit_started_at = UTC_TIMESTAMP();
  END IF;

  /* CSIFH: 親farmsの clinic_uuid を継承（履歴固定） */
  IF NEW.clinic_uuid IS NULL OR NEW.clinic_uuid = UNHEX(REPEAT('0',32)) THEN
    SELECT f.clinic_uuid INTO @cu FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
    SET NEW.clinic_uuid = @cu;
  END IF;
END$$

CREATE TRIGGER bu_visits_rowver
BEFORE UPDATE ON visits
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$

DELIMITER ;
