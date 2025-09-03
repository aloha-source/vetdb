/* 710_chart_idx_chart_headers.sql */
-- @phase: idx
-- @provides: index:idx_ch_clinic_list, index:idx_chart_headers_period, index:idx_chart_headers_status, index:idx_chart_headers_individual, index:idx_chart_headers_farm, index:idx_chart_headers_outcome, index:idx_chart_headers_dis1, index:idx_chart_headers_dis2, index:idx_chart_headers_dis3, index:idx_ch_list
-- @requires: table:chart_headers

CREATE INDEX idx_ch_clinic_list            ON chart_headers(clinic_uuid, updated_at, id);
CREATE INDEX idx_chart_headers_period      ON chart_headers(fiscal_year, claim_month);
CREATE INDEX idx_chart_headers_status      ON chart_headers(status);
CREATE INDEX idx_chart_headers_individual  ON chart_headers(individual_uuid);
CREATE INDEX idx_chart_headers_farm        ON chart_headers(farm_uuid);
CREATE INDEX idx_chart_headers_outcome     ON chart_headers(outcome_code);
CREATE INDEX idx_chart_headers_dis1        ON chart_headers(disease1_code);
CREATE INDEX idx_chart_headers_dis2        ON chart_headers(disease2_code);
CREATE INDEX idx_chart_headers_dis3        ON chart_headers(disease3_code);
CREATE INDEX idx_ch_list                   ON chart_headers(updated_at, id);
