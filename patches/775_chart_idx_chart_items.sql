/* 775_chart_idx_chart_items.sql */
-- @phase: idx
-- @provides: index:idx_chart_items_parent, index:idx_ci_clinic
-- @requires: table:chart_items

CREATE INDEX idx_chart_items_parent ON chart_items(chart_checkup_uuid, within_checkup_line_no);
CREATE INDEX idx_ci_clinic         ON chart_items(clinic_uuid, chart_checkup_uuid);
