/* 330_checkup_tr_checkups.sql */
-- @phase: trigger
-- @provides: trigger:tr_checkups_bi_uuid_v7, trigger:tr_checkups_bu_rowver
-- @requires: table:checkups, function:uuid_v7_bin, table:visits, table:individuals

DROP TRIGGER IF EXISTS tr_checkups_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_checkups_bu_rowver;

DELIMITER $$

CREATE TRIGGER tr_checkups_bi_uuid_v7
BEFORE INSERT ON checkups
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;

  /* CSIFH: 優先 visit.clinic_uuid → 無ければ individual.clinic_uuid を継承 */
  IF NEW.clinic_uuid IS NULL OR NEW.clinic_uuid = UNHEX(REPEAT('0',32)) THEN
    IF NEW.visit_uuid IS NOT NULL THEN
      SELECT v.clinic_uuid INTO @cu FROM visits v WHERE v.uuid = NEW.visit_uuid LIMIT 1;
    ELSE
      SELECT i.clinic_uuid INTO @cu FROM individuals i WHERE i.uuid = NEW.individual_uuid LIMIT 1;
    END IF;
    SET NEW.clinic_uuid = @cu;
  END IF;
END$$

CREATE TRIGGER tr_checkups_bu_rowver
BEFORE UPDATE ON checkups
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$

DELIMITER ;
