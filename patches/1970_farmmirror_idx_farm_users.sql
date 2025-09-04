/* 1970_farmmirror_idx_farm_users.sql */
-- @phase: idx
-- @provides: index:uq_farm_users_uuid, index:idx_farm_users_farm, index:idx_farm_users_email, index:idx_farm_users_list, index:idx_farm_users_clinic_list
-- @requires: table:farm_users

CREATE UNIQUE INDEX uq_farm_users_uuid        ON farm_users (uuid);
CREATE INDEX        idx_farm_users_farm       ON farm_users (farm_uuid, display_name);
CREATE INDEX        idx_farm_users_email      ON farm_users (email);
CREATE INDEX        idx_farm_users_list       ON farm_users (deleted_at, updated_at, id);
CREATE INDEX        idx_farm_users_clinic_list ON farm_users (clinic_uuid, deleted_at, updated_at, id);
