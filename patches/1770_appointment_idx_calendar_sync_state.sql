/* 1770_appointment_idx_calendar_sync_state.sql */
-- @phase: idx
-- @provides: index:uq_calendar_sync, index:idx_calendar, index:idx_css_list
-- @requires: table:calendar_sync_state

CREATE UNIQUE INDEX uq_calendar_sync ON calendar_sync_state (clinic_uuid, calendar_id);
CREATE INDEX idx_calendar           ON calendar_sync_state (calendar_id);
CREATE INDEX idx_css_list           ON calendar_sync_state (updated_at, id);
