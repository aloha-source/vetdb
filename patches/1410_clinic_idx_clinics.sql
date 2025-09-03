/* 1410_clinic_idx_clinics.sql */
-- @phase: idx
-- @provides: index:uq_clinics_uuid, index:uq_clinics_subdomain, index:uq_clinics_custom_domain, index:idx_clinics_list
-- @requires: table:clinics
-- 原文の UNIQUE/KEY をそのまま移設（名称・列順を維持）

CREATE UNIQUE INDEX uq_clinics_uuid          ON clinics(uuid);
CREATE UNIQUE INDEX uq_clinics_subdomain     ON clinics(subdomain);
CREATE UNIQUE INDEX uq_clinics_custom_domain ON clinics(custom_domain);
CREATE INDEX        idx_clinics_list         ON clinics(deleted_at, updated_at, id);
