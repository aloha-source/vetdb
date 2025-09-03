/* 680_chart_idx_chart_header_drafts.sql */
-- @phase: idx
-- @provides: index:idx_chd_clinic_list, index:idx_hdr_drafts_open, index:idx_hdr_drafts_period, index:idx_hdr_drafts_dis1, index:idx_hdr_drafts_dis2, index:idx_hdr_drafts_dis3, index:idx_hdr_drafts_farm, index:idx_hdr_drafts_list
-- @requires: table:chart_header_drafts

CREATE INDEX idx_chd_clinic_list     ON chart_header_drafts(clinic_uuid, deleted_at, updated_at, id);
CREATE INDEX idx_hdr_drafts_open     ON chart_header_drafts(individual_uuid, draft_status, created_at);
CREATE INDEX idx_hdr_drafts_period   ON chart_header_drafts(fiscal_year, claim_month);
CREATE INDEX idx_hdr_drafts_dis1     ON chart_header_drafts(disease1_code);
CREATE INDEX idx_hdr_drafts_dis2     ON chart_header_drafts(disease2_code);
CREATE INDEX idx_hdr_drafts_dis3     ON chart_header_drafts(disease3_code);
CREATE INDEX idx_hdr_drafts_farm     ON chart_header_drafts(farm_uuid);
CREATE INDEX idx_hdr_drafts_list     ON chart_header_drafts(deleted_at, updated_at, id);
