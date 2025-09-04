/* 2005_receipt_idx_receipt_header_drafts.sql */
-- @phase: idx
-- @feature: receipt
-- @provides: index:idx_receipt_drafts_list, index:idx_receipt_drafts_farm, index:idx_receipt_drafts_clinic
-- @requires: table:receipt_header_drafts

CREATE INDEX idx_receipt_drafts_list   ON receipt_header_drafts (deleted_at, updated_at, id);
CREATE INDEX idx_receipt_drafts_farm   ON receipt_header_drafts (farm_uuid,   deleted_at, updated_at, id);
CREATE INDEX idx_receipt_drafts_clinic ON receipt_header_drafts (clinic_uuid, deleted_at, updated_at, id);
