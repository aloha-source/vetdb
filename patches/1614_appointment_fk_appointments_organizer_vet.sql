/* 1614_appointment_fk_appointments_organizer_vet.sql */
-- @phase: fk
-- @provides: fk:fk_appt_organizer_vet
-- @requires: table:appointments, table:vet_users

ALTER TABLE appointments
  ADD CONSTRAINT fk_appt_organizer_vet
    FOREIGN KEY (organizer_vet_user_uuid) REFERENCES vet_users(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL;
