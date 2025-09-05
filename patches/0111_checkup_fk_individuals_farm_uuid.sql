/* 111_checkup_fk_individuals_farm_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_individuals_farm_uuid
-- @requires: table:individuals, table:farms

ALTER TABLE individuals
  ADD CONSTRAINT fk_individuals_farm_uuid FOREIGN KEY (farm_uuid)    REFERENCES farms(uuid)      ON UPDATE CASCADE ON DELETE RESTRICT;
