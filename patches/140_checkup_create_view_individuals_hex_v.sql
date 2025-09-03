/* 140_checkup_create_view_individuals_hex_v.sql */
-- @phase: create
-- @provides: view:individuals_hex_v
-- @requires: function:uuid_bin_to_hex, table:individuals

DROP VIEW IF EXISTS individuals_hex_v;

CREATE OR REPLACE VIEW individuals_hex_v AS
SELECT
  id,
  uuid_bin_to_hex(uuid)         AS uuid_hex,
  uuid_bin_to_hex(clinic_uuid)  AS clinic_uuid_hex,
  uuid_bin_to_hex(farm_uuid)    AS farm_uuid_hex,
  uuid_bin_to_hex(user_uuid)    AS user_uuid_hex,
  name, ear_tag, status, gender, birth_date, death_date, sire_name,
  uuid_bin_to_hex(genetic_dam_uuid)  AS genetic_dam_uuid_hex,
  genetic_dam_ear_tag, genetic_dam_name,
  uuid_bin_to_hex(nursing_dam_uuid)  AS nursing_dam_uuid_hex,
  nursing_dam_ear_tag, nursing_dam_name,
  deleted_at, created_at, updated_at
FROM individuals;
