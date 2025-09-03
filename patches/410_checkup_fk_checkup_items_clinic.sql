/* 410_checkup_fk_checkup_items_clinic.sql */
-- @phase: fk
-- @provides: fk:fk_checkup_items_clinic
-- @requires: table:checkup_items, table:clinics

ALTER TABLE checkup_items
  ADD CONSTRAINT fk_checkup_items_clinic FOREIGN KEY (clinic_uuid)  REFERENCES clinics(uuid)  ON UPDATE CASCADE ON DELETE RESTRICT;
