/* 320_checkup_idx_checkups.sql */
-- @phase: idx
-- @provides: index:idx_checkups_visit, index:idx_checkups_individual, index:idx_checkups_visit_ind_crt, index:idx_checkups_visit_ind_uuid, index:idx_checkups_chart_header, index:idx_checkups_list, index:idx_checkups_rhd, index:idx_checkups_clinic
-- @requires: table:checkups

CREATE INDEX idx_checkups_visit           ON checkups(visit_uuid);
CREATE INDEX idx_checkups_individual      ON checkups(individual_uuid);
CREATE INDEX idx_checkups_visit_ind_crt   ON checkups(visit_uuid, individual_uuid, created_at);
CREATE INDEX idx_checkups_visit_ind_uuid  ON checkups(visit_uuid, individual_uuid, uuid);
CREATE INDEX idx_checkups_chart_header    ON checkups(chart_header_uuid);
CREATE INDEX idx_checkups_list            ON checkups(deleted_at, updated_at, id);
CREATE INDEX idx_checkups_rhd             ON checkups(receipt_header_drafts_uuid, id);
CREATE INDEX idx_checkups_clinic          ON checkups(clinic_uuid, created_at);
