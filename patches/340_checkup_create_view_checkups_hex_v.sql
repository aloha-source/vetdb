/* 340_checkup_create_view_checkups_hex_v.sql */
-- @phase: create
-- @provides: view:checkups_hex_v
-- @requires: function:uuid_bin_to_hex, table:checkups

DROP VIEW IF EXISTS checkups_hex_v;

CREATE OR REPLACE VIEW checkups_hex_v AS
SELECT
  id,
  uuid_bin_to_hex(uuid)         AS uuid_hex,
  uuid_bin_to_hex(clinic_uuid)  AS clinic_uuid_hex,
  uuid_bin_to_hex(visit_uuid)   AS visit_uuid_hex,
  uuid_bin_to_hex(individual_uuid) AS individual_uuid_hex,
  uuid_bin_to_hex(chart_header_uuid) AS chart_header_uuid_hex,
  s_subjective, o_objective, a_assessment, p_plan,
  temp_c, pulse_bpm, resp_bpm, clinical_course,
  status, created_by, deleted_at, created_at, updated_at
FROM checkups;
