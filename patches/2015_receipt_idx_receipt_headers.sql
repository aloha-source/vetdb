/* 2015_receipt_idx_receipt_headers.sql */
-- @phase: idx
-- @feature: receipt
-- @provides: index:uq_receipt_headers_no, index:idx_rcpt_hdr_draft, index:idx_rcpt_hdr_issued, index:idx_rcpt_hdr_status, index:idx_rcpt_hdr_farm, index:idx_rcpt_hdr_clinic
-- @requires: table:receipt_headers

CREATE UNIQUE INDEX uq_receipt_headers_no ON receipt_headers (receipt_no);
CREATE INDEX idx_rcpt_hdr_draft  ON receipt_headers (receipt_header_drafts_uuid, issued_at);
CREATE INDEX idx_rcpt_hdr_issued ON receipt_headers (issued_at, id);
CREATE INDEX idx_rcpt_hdr_status ON receipt_headers (status, issued_at, id);
CREATE INDEX idx_rcpt_hdr_farm   ON receipt_headers (farm_uuid, issued_at, id);
CREATE INDEX idx_rcpt_hdr_clinic ON receipt_headers (clinic_uuid, issued_at, id);
