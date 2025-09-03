/* 313_checkup_fk_checkups_rhd.sql */
-- @phase: fk
-- @provides: fk:fk_checkups_rhd
-- @requires: table:checkups, table:receipt_header_drafts

ALTER TABLE checkups
  ADD CONSTRAINT fk_checkups_rhd           FOREIGN KEY (receipt_header_drafts_uuid) REFERENCES receipt_header_drafts(uuid) ON UPDATE CASCADE ON DELETE SET NULL;
