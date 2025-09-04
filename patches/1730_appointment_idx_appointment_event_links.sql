/* 1730_appointment_idx_appointment_event_links.sql */
-- @phase: idx
-- @provides: index:uq_link_per_calendar, index:idx_link_gcal, index:idx_link_writer, index:idx_ael_list
-- @requires: table:appointment_event_links

CREATE UNIQUE INDEX uq_link_per_calendar ON appointment_event_links (clinic_uuid, appointment_uuid, google_calendar_id);
CREATE INDEX idx_link_gcal   ON appointment_event_links (google_calendar_id, google_event_id);
CREATE INDEX idx_link_writer ON appointment_event_links (writer_vet_user_uuid);
CREATE INDEX idx_ael_list    ON appointment_event_links (updated_at, id);
