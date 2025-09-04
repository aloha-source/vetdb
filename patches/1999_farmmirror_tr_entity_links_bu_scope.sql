/* 1999_farmmirror_tr_entity_links_bu_scope.sql */
-- @phase: trigger
-- @provides: trigger:tr_entity_links_bu_scope
-- @requires: table:entity_links, table:farms, table:farm_users, table:farmdb_*_mirror, table:individuals(任意)

DROP TRIGGER IF EXISTS tr_entity_links_bu_scope;
DELIMITER $$
CREATE TRIGGER tr_entity_links_bu_scope
BEFORE UPDATE ON entity_links
FOR EACH ROW
BEGIN
  DECLARE v_local_clinic  BINARY(16);
  DECLARE v_remote_clinic BINARY(16);

  CASE NEW.entity_type
    WHEN 'farm' THEN
      SELECT clinic_uuid INTO v_local_clinic
        FROM farms WHERE uuid = NEW.local_uuid LIMIT 1;

    WHEN 'farm_user' THEN
      SELECT clinic_uuid INTO v_local_clinic
        FROM farm_users WHERE uuid = NEW.local_uuid LIMIT 1;

    WHEN 'individual' THEN
      SELECT f.clinic_uuid INTO v_local_clinic
        FROM individuals i
        JOIN farms f ON f.uuid = i.farm_uuid
       WHERE i.uuid = NEW.local_uuid
       LIMIT 1;
  END CASE;
  SET NEW.clinic_uuid = v_local_clinic;

  CASE NEW.entity_type
    WHEN 'farm' THEN
      SELECT clinic_uuid INTO v_remote_clinic
        FROM farmdb_farms_mirror WHERE uuid = NEW.remote_uuid LIMIT 1;

    WHEN 'farm_user' THEN
      SELECT clinic_uuid INTO v_remote_clinic
        FROM farmdb_farm_users_mirror WHERE uuid = NEW.remote_uuid LIMIT 1;

    WHEN 'individual' THEN
      SELECT clinic_uuid INTO v_remote_clinic
        FROM farmdb_individuals_mirror WHERE uuid = NEW.remote_uuid LIMIT 1;
  END CASE;

  IF v_remote_clinic IS NOT NULL AND v_remote_clinic <> v_local_clinic THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Cross-clinic link is not allowed';
  END IF;
END$$
DELIMITER ;
