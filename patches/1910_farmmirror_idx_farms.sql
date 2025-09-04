/* 1910_farmmirror_idx_farms.sql */
-- @phase: idx
-- @provides: index:uq_farms_uuid, index:uq_farms_uuid_clinic, index:idx_farms_name, index:idx_farms_list, index:idx_farms_clinic_list
-- @requires: table:farms

CREATE UNIQUE INDEX uq_farms_uuid         ON farms (uuid);
CREATE UNIQUE INDEX uq_farms_uuid_clinic  ON farms (uuid, clinic_uuid); -- 合成FK参照先
CREATE INDEX        idx_farms_name        ON farms (name);
CREATE INDEX        idx_farms_list        ON farms (deleted_at, updated_at, id);
CREATE INDEX        idx_farms_clinic_list ON farms (clinic_uuid, deleted_at, updated_at, id);
