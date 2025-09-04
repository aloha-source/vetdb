/* 1822_appointment_fk_appointment_fulfillments_visit.sql */
-- @phase: fk
-- @provides: fk:fk_fulfill_visit
-- @requires: table:appointment_fulfillments, table:visits

ALTER TABLE appointment_fulfillments
  ADD CONSTRAINT fk_fulfill_visit
    FOREIGN KEY (visit_uuid) REFERENCES visits(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE;
