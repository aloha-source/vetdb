/* 1310_treatment_fk_treatment_set_items_set_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_tsi_set_uuid
-- @requires: table:treatment_set_items, table:treatment_sets

ALTER TABLE treatment_set_items
  ADD CONSTRAINT fk_tsi_set_uuid
    FOREIGN KEY (set_uuid)       REFERENCES treatment_sets(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT;
