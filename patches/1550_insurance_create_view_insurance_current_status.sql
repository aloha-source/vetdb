/* 1550_insurance_create_view_insurance_current_status.sql */
-- @phase: view
-- @provides: view:insurance_current_status
-- @requires: view:insurance_current
-- 役割: ラベル化ビュー（active / renewal_due_soon など）。clinic列は持たない。

/* 再デプロイ安全化（このビュー自身の再定義） */
DROP VIEW IF EXISTS `insurance_current_status`;

CREATE VIEW `insurance_current_status` AS
SELECT
  c.farm_uuid,
  c.subscriber_code,
  c.start_date,
  c.end_date,
  c.days_to_end,
  CASE
    WHEN c.is_today_valid = 1 THEN 'active'
    WHEN c.end_date IS NOT NULL AND c.end_date < CURDATE() THEN 'renewal_overdue'
    WHEN c.end_date IS NOT NULL
         AND c.end_date >= CURDATE()
         AND c.end_date <= (CURDATE() + INTERVAL 30 DAY)
      THEN 'renewal_due_soon'
    WHEN c.status = 'non_insured' THEN 'non_insured'
    WHEN c.status = 'insured'     THEN 'insured'
    ELSE 'unknown'
  END AS current_status
FROM `insurance_current` c;
