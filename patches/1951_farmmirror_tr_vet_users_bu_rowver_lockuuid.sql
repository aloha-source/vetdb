/* 1951_farmmirror_tr_vet_users_bu_rowver_lockuuid.sql */
-- @phase: trigger
-- @provides: trigger:tr_vet_users_bu_rowver_lockuuid
-- @requires: table:vet_users

DROP TRIGGER IF EXISTS tr_vet_users_bu_rowver_lockuuid;
DELIMITER $$
CREATE TRIGGER tr_vet_users_bu_rowver_lockuuid
BEFORE UPDATE ON vet_users
FOR EACH ROW
BEGIN
  SET NEW.uuid = OLD.uuid;
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;
