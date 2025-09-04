/* 1950_farmmirror_tr_vet_users_bi_uuid_v7.sql */
-- @phase: trigger
-- @provides: trigger:tr_vet_users_bi_uuid_v7
-- @requires: table:vet_users, function:uuid_v7_bin

DROP TRIGGER IF EXISTS tr_vet_users_bi_uuid_v7;
DELIMITER $$
CREATE TRIGGER tr_vet_users_bi_uuid_v7
BEFORE INSERT ON vet_users
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;
