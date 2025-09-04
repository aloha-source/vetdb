/* 1741_appointment_fk_ael_appt.sql */
-- @phase: fk
-- @provides: fk:fk_ael_appt
-- @requires: table:appointment_event_links, table:appointments

ALTER TABLE appointment_event_links
  ADD CONSTRAINT fk_ael_appt
    FOREIGN KEY (appointment_uuid) REFERENCES appointments(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE;
