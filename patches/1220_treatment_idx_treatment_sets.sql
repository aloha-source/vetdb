/* 1220_treatment_idx_treatment_sets.sql */
-- @phase: idx
-- @provides: index:idx_ts_owner, index:idx_visibility, index:idx_quality, index:idx_clinic_list
-- @requires: table:treatment_sets

CREATE INDEX idx_ts_owner     ON treatment_sets (user_uuid, is_active, sequence_no);
CREATE INDEX idx_visibility   ON treatment_sets (visibility);
CREATE INDEX idx_quality      ON treatment_sets (deleted_at, updated_at, id);
CREATE INDEX idx_clinic_list  ON treatment_sets (clinic_uuid, deleted_at, updated_at, id);
