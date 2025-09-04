/* 1690_appointment_fk_clinic_calendar_settings_clinic.sql */
-- @phase: fk
-- @provides: fk:fk_clinic_calendar_clinic
-- @requires: table:clinic_calendar_settings, table:clinics

ALTER TABLE clinic_calendar_settings
  ADD CONSTRAINT fk_clinic_calendar_clinic
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE;
