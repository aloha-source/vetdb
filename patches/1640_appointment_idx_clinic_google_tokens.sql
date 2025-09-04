/* 1640_appointment_idx_clinic_google_tokens.sql */
-- @phase: idx
-- @provides: index:uq_clinic_token, index:idx_tokens_list, index:idx_google_email
-- @requires: table:clinic_google_tokens

CREATE UNIQUE INDEX uq_clinic_token ON clinic_google_tokens (clinic_uuid);
CREATE INDEX idx_tokens_list       ON clinic_google_tokens (updated_at, id);
CREATE INDEX idx_google_email      ON clinic_google_tokens (google_email);
