/* 1616_appointment_fk_appointments_updated_by_vet.sql */
-- @phase: fk
-- @provides: fk:fk_appt_updated_by_vet
-- @requires: table:appointments, table:vet_users

ALTER TABLE appointments
  ADD CONSTRAINT fk_appt_updated_by_vet
    FOREIGN KEY (updated_by_vet_user_uuid) REFERENCES vet_users(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL;
