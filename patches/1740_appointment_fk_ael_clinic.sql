/* 1740_appointment_fk_ael_clinic.sql */
-- @phase: fk
-- @provides: fk:fk_ael_clinic
-- @requires: table:appointment_event_links, table:clinics

ALTER TABLE appointment_event_links
  ADD CONSTRAINT fk_ael_clinic
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE;
