/* 1971_farmmirror_fk_farm_users_farm_clinic.sql */
-- @phase: fk
-- @provides: fk:fk_fu_farm_clinic
-- @requires: table:farm_users, table:farms (unique: uq_farms_uuid_clinic)

ALTER TABLE farm_users
  ADD CONSTRAINT fk_fu_farm_clinic
    FOREIGN KEY (farm_uuid, clinic_uuid)
    REFERENCES farms (uuid, clinic_uuid)
    ON UPDATE CASCADE
    ON DELETE RESTRICT;
