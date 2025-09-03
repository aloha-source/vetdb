/* 745_chart_idx_chart_checkups.sql */
-- @phase: idx
-- @provides: index:uq_chart_checkups_hdr_seq, index:idx_chart_checkups_hdr, index:idx_cc_clinic
-- @requires: table:chart_checkups

CREATE UNIQUE INDEX uq_chart_checkups_hdr_seq ON chart_checkups(chart_uuid, seq_no);
CREATE INDEX idx_chart_checkups_hdr          ON chart_checkups(chart_uuid);
CREATE INDEX idx_cc_clinic                   ON chart_checkups(clinic_uuid, chart_uuid);
