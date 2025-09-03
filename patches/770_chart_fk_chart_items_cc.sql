/* 770_chart_fk_chart_items_cc.sql */
-- @phase: fk
-- @provides: fk:fk_chart_items_cc
-- @requires: table:chart_items, table:chart_checkups

ALTER TABLE chart_items
  ADD CONSTRAINT fk_chart_items_cc
    FOREIGN KEY (chart_checkup_uuid) REFERENCES chart_checkups(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE;
