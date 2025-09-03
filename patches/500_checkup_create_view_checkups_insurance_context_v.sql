/* 500_checkup_create_view_checkups_insurance_context_v.sql */
-- @phase: create
-- @provides: view:checkups_insurance_context_v
-- @requires: table:checkups, table:individuals, table:farms

DROP VIEW IF EXISTS checkups_insurance_context_v;

CREATE OR REPLACE VIEW checkups_insurance_context_v AS
SELECT
  c.uuid AS checkup_uuid,
  f.non_insured AS farm_non_insured,
  CASE WHEN f.non_insured = 1 THEN 'private' ELSE 'insurance' END AS preferred_pay_type
FROM checkups c
JOIN individuals i ON i.uuid = c.individual_uuid
JOIN farms f       ON f.uuid = i.farm_uuid;
