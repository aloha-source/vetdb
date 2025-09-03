/* 113_checkup_fk_individuals_genetic_dam.sql */
-- @phase: fk
-- @provides: fk:fk_individuals_genetic_dam
-- @requires: table:individuals

ALTER TABLE individuals
  ADD CONSTRAINT fk_individuals_genetic_dam FOREIGN KEY (genetic_dam_uuid)  REFERENCES individuals(uuid) ON UPDATE CASCADE ON DELETE SET NULL;
