/* 310_checkup_fk_checkups_clinic_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_checkups_clinic_uuid
-- @requires: table:checkups, table:clinics

ALTER TABLE checkups
  ADD CONSTRAINT fk_checkups_clinic_uuid   FOREIGN KEY (clinic_uuid)  REFERENCES clinics(uuid)     ON UPDATE CASCADE ON DELETE RESTRICT;
