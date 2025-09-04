/* 1821_appointment_fk_appointment_fulfillments_appt.sql */
-- @phase: fk
-- @provides: fk:fk_fulfill_appt
-- @requires: table:appointment_fulfillments, table:appointments

ALTER TABLE appointment_fulfillments
  ADD CONSTRAINT fk_fulfill_appt
    FOREIGN KEY (appointment_uuid) REFERENCES appointments(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE;
