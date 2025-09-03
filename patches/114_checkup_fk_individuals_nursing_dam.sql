/* 114_checkup_fk_individuals_nursing_dam.sql */
-- @phase: fk
-- @provides: fk:fk_individuals_nursing_dam
-- @requires: table:individuals

ALTER TABLE individuals
  ADD CONSTRAINT fk_individuals_nursing_dam FOREIGN KEY (nursing_dam_uuid)  REFERENCES individuals(uuid) ON UPDATE CASCADE ON DELETE SET NULL;
