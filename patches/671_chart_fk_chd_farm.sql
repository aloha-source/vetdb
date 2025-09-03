/* 671_chart_fk_chd_farm.sql */
-- @phase: fk
-- @provides: fk:fk_chd_farm
-- @requires: table:chart_header_drafts, table:farms

ALTER TABLE chart_header_drafts
  ADD CONSTRAINT fk_chd_farm
    FOREIGN KEY (farm_uuid) REFERENCES farms(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT;
