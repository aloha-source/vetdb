/* 1540_insurance_create_view_insurance_current.sql */
-- @phase: view
-- @provides: view:insurance_current
-- @requires: table:insurance_enrollments
-- 役割: FARM単位の代表1行ビュー（today-valid 優先 → end DESC → start DESC → id DESC）

/* 再デプロイ安全化（依存ビューの再定義に備える） */
DROP VIEW IF EXISTS `insurance_current`;

CREATE VIEW `insurance_current` AS
WITH ranked AS (
  SELECT
    e.*,
    /* 今日有効？（端NULL許容） */
    CASE
      WHEN (e.start_date IS NULL OR e.start_date <= CURDATE())
       AND (e.end_date   IS NULL OR e.end_date   >= CURDATE())
      THEN 1 ELSE 0
    END AS is_today_valid,
    /* 代表順位: today-valid → end DESC → start DESC → id DESC */
    ROW_NUMBER() OVER (
      PARTITION BY e.farm_uuid
      ORDER BY
        CASE
          WHEN (e.start_date IS NULL OR e.start_date <= CURDATE())
           AND (e.end_date   IS NULL OR e.end_date   >= CURDATE())
          THEN 0 ELSE 1
        END,
        COALESCE(e.end_date,  '9999-12-31') DESC,
        COALESCE(e.start_date,'9999-12-31') DESC,
        e.id DESC
    ) AS rn
  FROM `insurance_enrollments` e
  WHERE e.voided_at IS NULL AND e.deleted_at IS NULL
)
SELECT
  r.id,
  r.farm_uuid,
  r.subscriber_code,
  r.status,
  r.start_date,
  r.end_date,
  r.fiscal_year,
  r.source_note,
  r.voided_at,
  r.void_reason,
  r.row_version,
  r.deleted_at,
  r.created_by,
  r.created_at,
  r.updated_at,
  r.is_today_valid,
  CASE WHEN r.end_date IS NULL THEN NULL
       ELSE DATEDIFF(r.end_date, CURDATE())
  END AS days_to_end
FROM ranked r
WHERE r.rn = 1;
