/* 220_checkup_idx_visits.sql */
-- @phase: idx
-- @provides: index:idx_visits_farm, index:idx_visits_farm_started, index:idx_visits_started, index:idx_visits_list, index:idx_visits_clinic
-- @requires: table:visits

CREATE INDEX idx_visits_farm         ON visits(farm_uuid);
CREATE INDEX idx_visits_farm_started ON visits(farm_uuid, visit_started_at);
CREATE INDEX idx_visits_started      ON visits(visit_started_at);
CREATE INDEX idx_visits_list         ON visits(deleted_at, updated_at, id);
CREATE INDEX idx_visits_clinic       ON visits(clinic_uuid, visit_started_at);
