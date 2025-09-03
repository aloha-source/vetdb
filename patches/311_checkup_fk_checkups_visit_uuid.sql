/* 311_checkup_fk_checkups_visit_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_checkups_visit_uuid
-- @requires: table:checkups, table:visits

ALTER TABLE checkups
  ADD CONSTRAINT fk_checkups_visit_uuid    FOREIGN KEY (visit_uuid)   REFERENCES visits(uuid)      ON UPDATE CASCADE ON DELETE SET NULL;
