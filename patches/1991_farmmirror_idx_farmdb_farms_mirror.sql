/* 1991_farmmirror_idx_farmdb_farms_mirror.sql */
-- @phase: idx
-- @provides: index:idx_fdb_farms_clinic_list, index:idx_fdb_farms_updated, index:idx_fdb_farms_name
-- @requires: table:farmdb_farms_mirror

CREATE INDEX idx_fdb_farms_clinic_list ON farmdb_farms_mirror (clinic_uuid, deleted_at, updated_at, id);
CREATE INDEX idx_fdb_farms_updated     ON farmdb_farms_mirror (updated_at_source);
CREATE INDEX idx_fdb_farms_name        ON farmdb_farms_mirror (name);
