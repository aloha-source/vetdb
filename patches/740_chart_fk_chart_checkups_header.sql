/* 740_chart_fk_chart_checkups_header.sql */
-- @phase: fk
-- @provides: fk:fk_chart_checkups_header
-- @requires: table:chart_checkups, table:chart_headers

ALTER TABLE chart_checkups
  ADD CONSTRAINT fk_chart_checkups_header
    FOREIGN KEY (chart_uuid) REFERENCES chart_headers(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE;
