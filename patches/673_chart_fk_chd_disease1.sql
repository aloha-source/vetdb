/* 673_chart_fk_chd_disease1.sql */
-- @phase: fk
-- @provides: fk:fk_chd_dis1
-- @requires: table:chart_header_drafts, table:disease_master

ALTER TABLE chart_header_drafts
  ADD CONSTRAINT fk_chd_dis1 FOREIGN KEY (disease1_code) REFERENCES disease_master(code6)
    ON UPDATE CASCADE ON DELETE SET NULL;
