/* 1680_appointment_idx_clinic_calendar_settings.sql */
-- @phase: idx
-- @provides: index:uq_clinic_calendar, index:idx_calendar_id, index:idx_clinic_calendar_list
-- @requires: table:clinic_calendar_settings

CREATE UNIQUE INDEX uq_clinic_calendar    ON clinic_calendar_settings (clinic_uuid);
CREATE INDEX        idx_calendar_id       ON clinic_calendar_settings (calendar_id);
CREATE INDEX        idx_clinic_calendar_list ON clinic_calendar_settings (updated_at, id);
