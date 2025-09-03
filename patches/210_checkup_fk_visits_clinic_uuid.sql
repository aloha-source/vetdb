/* 210_checkup_fk_visits_clinic_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_visits_clinic_uuid
-- @requires: table:visits, table:clinics

ALTER TABLE visits
  ADD CONSTRAINT fk_visits_clinic_uuid FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid) ON UPDATE CASCADE ON DELETE RESTRICT;
