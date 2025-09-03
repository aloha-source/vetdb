/* 211_checkup_fk_visits_farm_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_visits_farm_uuid
-- @requires: table:visits, table:farms

ALTER TABLE visits
  ADD CONSTRAINT fk_visits_farm_uuid   FOREIGN KEY (farm_uuid)   REFERENCES farms(uuid)   ON UPDATE CASCADE ON DELETE RESTRICT;
