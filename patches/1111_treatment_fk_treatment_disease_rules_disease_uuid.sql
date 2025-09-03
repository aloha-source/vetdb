/* 1111_treatment_fk_treatment_disease_rules_disease_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_tdr_disease_uuid
-- @requires: table:treatment_disease_rules, table:disease_master

ALTER TABLE treatment_disease_rules
  ADD CONSTRAINT fk_tdr_disease_uuid
    FOREIGN KEY (disease_uuid)   REFERENCES disease_master(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT;
