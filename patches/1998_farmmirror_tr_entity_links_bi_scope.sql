/* 1998_farmmirror_tr_entity_links_bi_scope.sql */
-- @phase: trigger
-- @provides: trigger:tr_entity_links_bi_scope
-- @requires: table:entity_links, table:farms, table:farm_users, table:farmdb_*_mirror, table:individuals(任意)
-- 役割: local由来clinicの強制確定＋remote clinicとの越境拒否（原文どおり）

DROP TRIGGER IF EXISTS tr_entity_links_bi_scope;
DELIMITER $$
CREATE TRIGGER tr_entity_links_bi_scope
BEFORE INSERT ON entity_links
FOR EACH ROW
BEGIN
  DECLARE v_local_clinic  BINARY(16);
  DECLARE v_remote_clinic BINARY(16);

  /* 1) local 側 clinic を確定（entity_typeに応じて参照先が異なる） */
  CASE NEW.entity_type
    WHEN 'farm' THEN
      SELECT clinic_uuid INTO v_local_clinic
        FROM farms WHERE uuid = NEW.local_uuid LIMIT 1;

    WHEN 'farm_user' THEN
      /* farm_users は合成FKにより (farm_uuid, clinic_uuid) が親と常に一致 */
      SELECT clinic_uuid INTO v_local_clinic
        FROM farm_users WHERE uuid = NEW.local_uuid LIMIT 1;

    WHEN 'individual' THEN
      /* 注意: individuals（SoT）が必要。未導入ならこの分岐は利用しないこと。 */
      SELECT f.clinic_uuid INTO v_local_clinic
        FROM individuals i
        JOIN farms f ON f.uuid = i.farm_uuid
       WHERE i.uuid = NEW.local_uuid
       LIMIT 1;
  END CASE;
  SET NEW.clinic_uuid = v_local_clinic;

  /* 2) remote 側 clinic を取得して院越境を拒否（NULLは許容＝未所属→収容） */
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
