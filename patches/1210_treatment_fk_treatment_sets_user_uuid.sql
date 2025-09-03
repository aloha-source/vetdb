/* 1210_treatment_fk_treatment_sets_user_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_treatment_sets_user_uuid
-- @requires: table:treatment_sets, table:users

ALTER TABLE treatment_sets
  ADD CONSTRAINT fk_treatment_sets_user_uuid
    FOREIGN KEY (user_uuid) REFERENCES users(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT;
