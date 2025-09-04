/* 1940_farmmirror_idx_vet_users.sql */
-- @phase: idx
-- @provides: index:uq_vet_users_uuid, index:idx_vet_users_name, index:idx_vet_users_email, index:idx_vet_users_list, index:idx_vet_users_clinic_list
-- @requires: table:vet_users

CREATE UNIQUE INDEX uq_vet_users_uuid        ON vet_users (uuid);
CREATE INDEX        idx_vet_users_name       ON vet_users (display_name);
CREATE INDEX        idx_vet_users_email      ON vet_users (email);
CREATE INDEX        idx_vet_users_list       ON vet_users (deleted_at, updated_at, id);
CREATE INDEX        idx_vet_users_clinic_list ON vet_users (clinic_uuid, deleted_at, updated_at, id);
