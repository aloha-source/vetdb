SET NAMES utf8mb4;

/* ======================================================================
   Insurance Enrollment — Fresh Install (Global / Tenant = FARM via farm_uuid)
   ----------------------------------------------------------------------
   方針
     • テナントは farm 単位（farm_uuid: BINARY(16)）。
     • 多病院表示は farms 側の clinic_uuid を参照（本テーブルには保持しない＝グローバル）。
     • 代表行は farm 単位で決定（today-valid優先→end DESC→start DESC→id DESC）。
     • 監査/整合: v1p9 準拠（row_version, deleted_at, list index）。
   前提
     • MySQL 8.0+（ウィンドウ関数使用）
     • farms(uuid) が存在
   ====================================================================== */

/* 0) 依存ビューを先にDROP（再定義のため） */
DROP VIEW IF EXISTS `insurance_current_status`;
DROP VIEW IF EXISTS `insurance_current`;

/* 1) 本体テーブル：グローバル（clinic列は持たない） */
DROP TABLE IF EXISTS `insurance_enrollments`;
CREATE TABLE IF NOT EXISTS `insurance_enrollments` (
  /* 識別子（AUTO_INCREMENT 主キー） */
  `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

  /* テナント（FARM単位, BINARY(16) UUIDv7想定） */
  `farm_uuid` BINARY(16) NOT NULL,

  /* 加入者コード（共済番号など8桁を想定） */
  `subscriber_code` CHAR(8) NOT NULL,

  /* 入力ステータス（英語ENUM：入力値の状態） */
  `status` ENUM('insured','non_insured','unknown') NOT NULL DEFAULT 'unknown',

  /* 期間（端NULL許容）— 両端NULLは today-valid とみなす */
  `start_date` DATE NULL,
  `end_date`   DATE NULL,

  /* 任意付帯 */
  `fiscal_year` YEAR NULL,
  `source_note` VARCHAR(255) NULL,

  /* 無効化(取消)と理由 — voided 行は代表選定から除外 */
  `voided_at`   DATETIME NULL,
  `void_reason` VARCHAR(255) NULL,

  /* v1p9: 楽観ロック & 論理削除 & 監査 */
  `row_version` BIGINT UNSIGNED NOT NULL DEFAULT 1,
  `deleted_at`  DATETIME NULL,
  `created_by`  INT UNSIGNED NULL,
  `created_at`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  /* 期間検索・代表化前の絞り込みで有効 */
  INDEX `idx_farm_dates` (`farm_uuid`, `start_date`, `end_date`),

  /* コード検索・監査用 */
  INDEX `idx_code` (`subscriber_code`),

  /* 一覧最適化（差分同期や更新順ソート） */
  KEY `idx_enroll_list` (`deleted_at`, `updated_at`, `id`),

  /* 期間整合性（NULLはスルー） */
  CHECK ( `start_date` IS NULL OR `end_date` IS NULL OR `start_date` <= `end_date` ),

  /* FK（維持）：farm_uuid → farms.uuid */
  CONSTRAINT `fk_ins_enro_farm`
    FOREIGN KEY (`farm_uuid`) REFERENCES `farms`(`uuid`)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  ROW_FORMAT=DYNAMIC;

/* 2) トリガ — row_version 自動インクリメント（clinic継承系は削除済み） */
DROP TRIGGER IF EXISTS `tr_insurance_enrollments_rowver_bu`;
DELIMITER $$
CREATE TRIGGER `tr_insurance_enrollments_rowver_bu`
BEFORE UPDATE ON `insurance_enrollments`
FOR EACH ROW
BEGIN
  SET NEW.`row_version` = OLD.`row_version` + 1;
END$$
DELIMITER ;

/* 3) 代表1行ビュー（グローバル：farm単位、clinic非依存） */
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

/* 4) ラベルビュー（clinic列なし／グローバル） */
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
