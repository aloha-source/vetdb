/* 2025_receipt_idx_receipt_checkups.sql */
-- @phase: idx
-- @feature: receipt
-- @provides: index:uq_rcpt_hdr_src, index:idx_rcpt_ckp_hdr, index:idx_rcpt_ckp_src, index:idx_rcpt_ckp_clinic
-- @requires: table:receipt_checkups

CREATE UNIQUE INDEX uq_rcpt_hdr_src   ON receipt_checkups (receipt_header_uuid, source_checkup_uuid);
CREATE INDEX        idx_rcpt_ckp_hdr  ON receipt_checkups (receipt_header_uuid, id);
CREATE INDEX        idx_rcpt_ckp_src  ON receipt_checkups (source_checkup_uuid);
CREATE INDEX        idx_rcpt_ckp_clinic ON receipt_checkups (clinic_uuid, receipt_header_uuid, id);
