/* 1520_insurance_idx_insurance_enrollments.sql */
-- @phase: idx
-- @provides: index:idx_farm_dates, index:idx_code, index:idx_enroll_list
-- @requires: table:insurance_enrollments
-- 役割: 原文の INDEX/KEY を分離（名称・列順そのまま）

CREATE INDEX `idx_farm_dates` ON `insurance_enrollments` (`farm_uuid`, `start_date`, `end_date`);
CREATE INDEX `idx_code`       ON `insurance_enrollments` (`subscriber_code`);
CREATE INDEX `idx_enroll_list` ON `insurance_enrollments` (`deleted_at`, `updated_at`, `id`);
