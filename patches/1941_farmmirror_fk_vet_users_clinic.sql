/* 1941_farmmirror_fk_vet_users_clinic.sql */
-- @phase: fk
-- @provides: fk:fk_vet_users_clinic
-- @requires: table:vet_users, table:clinics

ALTER TABLE vet_users
  ADD CONSTRAINT fk_vet_users_clinic
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT;
