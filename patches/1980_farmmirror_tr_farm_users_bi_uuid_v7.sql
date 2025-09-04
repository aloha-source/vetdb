/* 1980_farmmirror_tr_farm_users_bi_uuid_v7.sql */
-- @phase: trigger
-- @provides: trigger:tr_farm_users_bi_uuid_v7
-- @requires: table:farm_users, table:farms, function:uuid_v7_bin

DROP TRIGGER IF EXISTS tr_farm_users_bi_uuid_v7;
DELIMITER $$
CREATE TRIGGER tr_farm_users_bi_uuid_v7
BEFORE INSERT ON farm_users
FOR EACH ROW
BEGIN
  DECLARE v_clinic BINARY(16);

  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;

  /* 親farmから clinic_uuid を継承（手入力・取り違えの防止） */
  SELECT f.clinic_uuid INTO v_clinic
    FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
  SET NEW.clinic_uuid = v_clinic;
END$$
DELIMITER ;
