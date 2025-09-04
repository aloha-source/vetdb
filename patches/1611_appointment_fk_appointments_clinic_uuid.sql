/* 1611_appointment_fk_appointments_clinic_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_appt_clinic_uuid
-- @requires: table:appointments, table:clinics

ALTER TABLE appointments
  ADD CONSTRAINT fk_appt_clinic_uuid
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL;
