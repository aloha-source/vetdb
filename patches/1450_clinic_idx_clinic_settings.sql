/* 1450_clinic_idx_clinic_settings.sql */
-- @phase: idx
-- @provides: index:uq_clinic_settings_clinic, index:idx_clinic_settings_list
-- @requires: table:clinic_settings
-- 原文の UNIQUE/KEY を移設（名称・列順を維持）

CREATE UNIQUE INDEX uq_clinic_settings_clinic ON clinic_settings(clinic_uuid);
CREATE INDEX        idx_clinic_settings_list  ON clinic_settings(deleted_at, updated_at, id);
