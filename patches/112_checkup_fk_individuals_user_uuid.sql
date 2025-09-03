/* 112_checkup_fk_individuals_user_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_individuals_user_uuid
-- @requires: table:individuals, table:users

ALTER TABLE individuals
  ADD CONSTRAINT fk_individuals_user_uuid FOREIGN KEY (user_uuid)    REFERENCES users(uuid)      ON UPDATE CASCADE ON DELETE SET NULL;
