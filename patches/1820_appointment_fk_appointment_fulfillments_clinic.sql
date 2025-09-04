/* 1820_appointment_fk_appointment_fulfillments_clinic.sql */
-- @phase: fk
-- @provides: fk:fk_fulfill_clinic
-- @requires: table:appointment_fulfillments, table:clinics

ALTER TABLE appointment_fulfillments
  ADD CONSTRAINT fk_fulfill_clinic
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE;
