/* 131_checkup_tr_individuals_bu_rowver.sql */
-- @phase: trigger
-- @provides: trigger:tr_individuals_bu_rowver
-- @requires: table:individuals

DROP TRIGGER IF EXISTS tr_individuals_bu_rowver;

DELIMITER $$

CREATE TRIGGER tr_individuals_bu_rowver
BEFORE UPDATE ON individuals
FOR EACH ROW
BEGIN
  /* 履歴固定方針のため clinic_uuid は自動更新しない（必要時はアプリで明示更新） */
  SET NEW.row_version = OLD.row_version + 1;
END$$

DELIMITER ;
