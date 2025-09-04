/* 1700_appointment_fk_clinic_calendar_settings_sync_owner.sql */
-- @phase: fk
-- @provides: fk:fk_clinic_calendar_sync_owner
-- @requires: table:clinic_calendar_settings, table:vet_users

ALTER TABLE clinic_calendar_settings
  ADD CONSTRAINT fk_clinic_calendar_sync_owner
    FOREIGN KEY (sync_owner_vet_user_uuid) REFERENCES vet_users(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL;
