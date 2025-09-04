/* 1615_appointment_fk_appointments_created_by_vet.sql */
-- @phase: fk
-- @provides: fk:fk_appt_created_by_vet
-- @requires: table:appointments, table:vet_users

ALTER TABLE appointments
  ADD CONSTRAINT fk_appt_created_by_vet
    FOREIGN KEY (created_by_vet_uuid) REFERENCES vet_users(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL;
