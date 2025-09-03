/* 130_checkup_tr_individuals.sql */
-- @phase: trigger
-- @provides: trigger:tr_individuals_bi_uuid_v7, trigger:tr_individuals_bu_rowver
-- @requires: table:individuals, function:uuid_v7_bin, table:farms

DROP TRIGGER IF EXISTS tr_individuals_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_individuals_bu_rowver;
DROP TRIGGER IF EXISTS tr_individuals_bi_clinic;

DELIMITER $$

CREATE TRIGGER tr_individuals_bi_uuid_v7
BEFORE INSERT ON individuals
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;

  /* CSIFH: 親farmsの clinic_uuid を継承（履歴固定） */
  IF NEW.clinic_uuid IS NULL OR NEW.clinic_uuid = UNHEX(REPEAT('0',32)) THEN
    SELECT f.clinic_uuid INTO @cu FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
    SET NEW.clinic_uuid = @cu;
  END IF;
END$$

CREATE TRIGGER tr_individuals_bu_rowver
BEFORE UPDATE ON individuals
FOR EACH ROW
BEGIN
  /* 履歴固定方針のため clinic_uuid は自動更新しない（必要時はアプリで明示更新） */
  SET NEW.row_version = OLD.row_version + 1;
END$$

DELIMITER ;
