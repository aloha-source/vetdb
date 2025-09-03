/* 1120_treatment_idx_treatment_disease_rules.sql */
-- @phase: idx
-- @provides: index:uq_tdr_pair, index:idx_tdr_treat, index:idx_tdr_dis, index:idx_quality, index:idx_clinic_list
-- @requires: table:treatment_disease_rules

CREATE UNIQUE INDEX uq_tdr_pair    ON treatment_disease_rules (treatment_uuid, disease_uuid);
CREATE INDEX idx_tdr_treat         ON treatment_disease_rules (treatment_uuid);
CREATE INDEX idx_tdr_dis           ON treatment_disease_rules (disease_uuid);
CREATE INDEX idx_quality           ON treatment_disease_rules (deleted_at, updated_at, id);
CREATE INDEX idx_clinic_list       ON treatment_disease_rules (clinic_uuid, deleted_at, updated_at, id);
