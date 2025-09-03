/* 120_checkup_idx_individuals.sql */
-- @phase: idx
-- @provides: index:uq_individuals_ear_tag, index:idx_individuals_farm_name, index:idx_individuals_farm_birth, index:idx_individuals_farm_status, index:idx_individuals_genetic_dam, index:idx_individuals_nursing_dam, index:idx_individuals_list, index:idx_individuals_clinic
-- @requires: table:individuals

CREATE UNIQUE INDEX uq_individuals_ear_tag ON individuals(ear_tag);
CREATE INDEX idx_individuals_farm_name   ON individuals(farm_uuid, name);
CREATE INDEX idx_individuals_farm_birth  ON individuals(farm_uuid, birth_date);
CREATE INDEX idx_individuals_farm_status ON individuals(farm_uuid, status);
CREATE INDEX idx_individuals_genetic_dam ON individuals(genetic_dam_uuid);
CREATE INDEX idx_individuals_nursing_dam ON individuals(nursing_dam_uuid);
CREATE INDEX idx_individuals_list        ON individuals(deleted_at, updated_at, id);
CREATE INDEX idx_individuals_clinic      ON individuals(clinic_uuid, id);
