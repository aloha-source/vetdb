/* 1440_clinic_fk_clinic_settings_clinic_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_clinic_settings_clinic
-- @requires: table:clinic_settings, table:clinics
-- 役割: clinics(uuid) への強整合。原文どおり（ON UPDATE CASCADE / ON DELETE RESTRICT）。

ALTER TABLE clinic_settings
  ADD CONSTRAINT fk_clinic_settings_clinic
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT;
