/* 1110_treatment_fk_treatment_disease_rules_treatment_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_tdr_treatment_uuid
-- @requires: table:treatment_disease_rules, table:treatment_master

ALTER TABLE treatment_disease_rules
  ADD CONSTRAINT fk_tdr_treatment_uuid
    FOREIGN KEY (treatment_uuid) REFERENCES treatment_master(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT;
