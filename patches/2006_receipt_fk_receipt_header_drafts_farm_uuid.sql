/* 2006_receipt_fk_receipt_header_drafts_farm_uuid.sql */
-- @phase: fk
-- @feature: receipt
-- @provides: fk:fk_rcpt_drafts_farm
-- @requires: table:receipt_header_drafts, table:farms

ALTER TABLE receipt_header_drafts
  ADD CONSTRAINT fk_rcpt_drafts_farm
    FOREIGN KEY (farm_uuid) REFERENCES farms(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT;
