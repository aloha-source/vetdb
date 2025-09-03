/* 670_chart_fk_chd_individual.sql */
-- @phase: fk
-- @provides: fk:fk_chd_individual
-- @requires: table:chart_header_drafts, table:individuals

ALTER TABLE chart_header_drafts
  ADD CONSTRAINT fk_chd_individual
    FOREIGN KEY (individual_uuid) REFERENCES individuals(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT;
