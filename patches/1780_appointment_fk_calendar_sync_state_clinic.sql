/* 1780_appointment_fk_calendar_sync_state_clinic.sql */
-- @phase: fk
-- @provides: fk:fk_sync_clinic
-- @requires: table:calendar_sync_state, table:clinics

ALTER TABLE calendar_sync_state
  ADD CONSTRAINT fk_sync_clinic
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE;
