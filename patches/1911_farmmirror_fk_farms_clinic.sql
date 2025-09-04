/* 1911_farmmirror_fk_farms_clinic.sql */
-- @phase: fk
-- @provides: fk:fk_farms_clinic
-- @requires: table:farms, table:clinics

ALTER TABLE farms
  ADD CONSTRAINT fk_farms_clinic
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT;
