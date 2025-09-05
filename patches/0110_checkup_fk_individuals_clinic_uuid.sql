/* 110_checkup_fk_individuals_clinic_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_individuals_clinic_uuid
-- @requires: table:individuals, table:clinics

ALTER TABLE individuals
  ADD CONSTRAINT fk_individuals_clinic_uuid FOREIGN KEY (clinic_uuid)  REFERENCES clinics(uuid)    ON UPDATE CASCADE ON DELETE RESTRICT;
