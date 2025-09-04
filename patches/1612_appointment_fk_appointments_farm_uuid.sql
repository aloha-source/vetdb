/* 1612_appointment_fk_appointments_farm_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_appt_farm_uuid
-- @requires: table:appointments, table:farms

ALTER TABLE appointments
  ADD CONSTRAINT fk_appt_farm_uuid
    FOREIGN KEY (farm_uuid) REFERENCES farms(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL;
