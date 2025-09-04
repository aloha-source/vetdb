/* 1981_farmmirror_tr_farm_users_bu_rowver_lockuuid.sql */
-- @phase: trigger
-- @provides: trigger:tr_farm_users_bu_rowver_lockuuid
-- @requires: table:farm_users, table:farms

DROP TRIGGER IF EXISTS tr_farm_users_bu_rowver_lockuuid;
DELIMITER $$
CREATE TRIGGER tr_farm_users_bu_rowver_lockuuid
BEFORE UPDATE ON farm_users
FOR EACH ROW
BEGIN
  DECLARE v_clinic BINARY(16);

  SET NEW.uuid = OLD.uuid;                    -- UUIDは不変
  SET NEW.row_version = OLD.row_version + 1;  -- 楽観ロック

  /* 親farmの変更や親側clinic付け替えに追随（再継承） */
  SELECT f.clinic_uuid INTO v_clinic
    FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
  SET NEW.clinic_uuid = v_clinic;
END$$
DELIMITER ;
