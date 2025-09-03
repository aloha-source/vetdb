/* 650_chart_idx_disease_chief_complaint_rules.sql */
-- @phase: idx
-- @provides: index:idx_dccr_fetch, index:idx_dccr_text
-- @requires: table:disease_chief_complaint_rules

CREATE INDEX idx_dccr_fetch ON disease_chief_complaint_rules(disease_id, is_active, display_order, id);
CREATE INDEX idx_dccr_text  ON disease_chief_complaint_rules(chief_complaint_text);
