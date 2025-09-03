/* 1311_treatment_fk_treatment_set_items_treatment_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_tsi_treatment_uuid
-- @requires: table:treatment_set_items, table:treatment_master

ALTER TABLE treatment_set_items
  ADD CONSTRAINT fk_tsi_treatment_uuid
    FOREIGN KEY (treatment_uuid) REFERENCES treatment_master(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT;
