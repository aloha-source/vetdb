/* 1320_treatment_idx_treatment_set_items.sql */
-- @phase: idx
-- @provides: index:uq_tsi_item, index:idx_tsi_set_seq, index:idx_treatment, index:idx_quality, index:idx_clinic_list
-- @requires: table:treatment_set_items

CREATE UNIQUE INDEX uq_tsi_item     ON treatment_set_items (set_uuid, treatment_uuid);
CREATE INDEX idx_tsi_set_seq        ON treatment_set_items (set_uuid, sequence_no);
CREATE INDEX idx_treatment          ON treatment_set_items (treatment_uuid);
CREATE INDEX idx_quality            ON treatment_set_items (deleted_at, updated_at, id);
CREATE INDEX idx_clinic_list        ON treatment_set_items (clinic_uuid, deleted_at, updated_at, id);
