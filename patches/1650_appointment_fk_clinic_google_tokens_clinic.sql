/* 1650_appointment_fk_clinic_google_tokens_clinic.sql */
-- @phase: fk
-- @provides: fk:fk_clinic_token_clinic
-- @requires: table:clinic_google_tokens, table:clinics

ALTER TABLE clinic_google_tokens
  ADD CONSTRAINT fk_clinic_token_clinic
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE;
