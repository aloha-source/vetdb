/* 640_chart_fk_dccr_disease.sql */
-- @phase: fk
-- @provides: fk:fk_dccr_disease
-- @requires: table:disease_chief_complaint_rules, table:disease_master

ALTER TABLE disease_chief_complaint_rules
  ADD CONSTRAINT fk_dccr_disease
  FOREIGN KEY (disease_id) REFERENCES disease_master(id)
  ON UPDATE CASCADE ON DELETE CASCADE;
