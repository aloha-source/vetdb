/* 1613_appointment_fk_appointments_individual_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_appt_individual_uuid
-- @requires: table:appointments, table:individuals

ALTER TABLE appointments
  ADD CONSTRAINT fk_appt_individual_uuid
    FOREIGN KEY (individual_uuid) REFERENCES individuals(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL;
