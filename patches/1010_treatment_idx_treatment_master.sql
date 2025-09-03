/* 1010_treatment_idx_treatment_master.sql */
-- @phase: idx
-- @provides: index:uq_ttm_clinic_code, index:idx_ttm_active, index:idx_quality, index:idx_clinic_list
-- @requires: table:treatment_master
-- 原文のUNIQUE/KEYをCREATE INDEXへ移設（名称・列順は原文どおり）

CREATE UNIQUE INDEX uq_ttm_clinic_code ON treatment_master (clinic_uuid, code);         -- ★院別一意
CREATE INDEX idx_ttm_active   ON treatment_master (is_active, name);
CREATE INDEX idx_quality      ON treatment_master (deleted_at, updated_at, id);
CREATE INDEX idx_clinic_list  ON treatment_master (clinic_uuid, deleted_at, updated_at, id);
