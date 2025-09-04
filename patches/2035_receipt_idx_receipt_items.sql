/* 2035_receipt_idx_receipt_items.sql */
-- @phase: idx
-- @feature: receipt
-- @provides: index:uq_rcptitem_ckp_src, index:idx_rcpt_items_ckpuuid, index:idx_rcpt_items_source, index:idx_rcpt_items_clinic
-- @requires: table:receipt_items

CREATE UNIQUE INDEX uq_rcptitem_ckp_src   ON receipt_items (receipt_checkup_uuid, source_checkup_item_id);
CREATE INDEX        idx_rcpt_items_ckpuuid ON receipt_items (receipt_checkup_uuid, id);
CREATE INDEX        idx_rcpt_items_source  ON receipt_items (source_checkup_item_id);
CREATE INDEX        idx_rcpt_items_clinic  ON receipt_items (clinic_uuid, receipt_checkup_uuid, id);
