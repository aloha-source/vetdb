/* 1020_treatment_fk_treatment_master_clinic_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_ttm_clinic_uuid
-- @requires: table:treatment_master, table:clinics
-- 原文: treatment_master のみ clinics にFKを付与

ALTER TABLE treatment_master
  ADD CONSTRAINT fk_ttm_clinic_uuid
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT;
