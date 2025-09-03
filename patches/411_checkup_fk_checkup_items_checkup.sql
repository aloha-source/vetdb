/* 411_checkup_fk_checkup_items_checkup.sql */
-- @phase: fk
-- @provides: fk:fk_checkup_items_checkup
-- @requires: table:checkup_items, table:checkups

ALTER TABLE checkup_items
  ADD CONSTRAINT fk_checkup_items_checkup FOREIGN KEY (checkup_uuid) REFERENCES checkups(uuid) ON UPDATE CASCADE ON DELETE CASCADE;
