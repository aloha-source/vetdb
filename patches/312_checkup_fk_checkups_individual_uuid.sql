/* 312_checkup_fk_checkups_individual_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_checkups_individual_uuid
-- @requires: table:checkups, table:individuals

ALTER TABLE checkups
  ADD CONSTRAINT fk_checkups_individual_uuid FOREIGN KEY (individual_uuid) REFERENCES individuals(uuid) ON UPDATE RESTRICT ON DELETE RESTRICT;
