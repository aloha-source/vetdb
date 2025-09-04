/* 1995_farmmirror_idx_farmdb_farm_users_mirror.sql */
-- @phase: idx
-- @provides: index:idx_fdb_farm_users_clinic_list, index:idx_fdb_farm_users_farm, index:idx_fdb_farm_users_email
-- @requires: table:farmdb_farm_users_mirror

CREATE INDEX idx_fdb_farm_users_clinic_list ON farmdb_farm_users_mirror (clinic_uuid, deleted_at, updated_at, id);
CREATE INDEX idx_fdb_farm_users_farm        ON farmdb_farm_users_mirror (farm_uuid, display_name);
CREATE INDEX idx_fdb_farm_users_email       ON farmdb_farm_users_mirror (email);
