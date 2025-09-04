/* 1810_appointment_idx_appointment_fulfillments.sql */
-- @phase: idx
-- @provides: index:uq_appt_visit, index:idx_visit, index:idx_fulfill_list
-- @requires: table:appointment_fulfillments

CREATE UNIQUE INDEX uq_appt_visit  ON appointment_fulfillments (appointment_uuid, visit_uuid);
CREATE INDEX idx_visit             ON appointment_fulfillments (visit_uuid);
CREATE INDEX idx_fulfill_list      ON appointment_fulfillments (created_at, id);
