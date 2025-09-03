SET NAMES utf8mb4;

/* ======================================================================
   Insurance Enrollment — Fresh Install (Long-Comment Edition, v1p9 style)
   ----------------------------------------------------------------------
   目的
     - 農家（farm_user）ごとの保険加入履歴を「追記主義」で管理し、
       「今日有効な1行 or 最終記録の1行」に“自動代表化”するビューを提供する。
     - 画面・集計は、原則ビュー（insurance_current / insurance_current_status）を参照すれば足りる。

   v1p9 ポリシー
     - 楽観ロック: row_version（BIGINT UNSIGNED）
     - 論理削除: deleted_at
     - 一覧最適化インデックス: (deleted_at, updated_at, id)

   ENUM（英語）
     - status: 'insured' | 'non_insured' | 'unknown'
       ※“入力値の状態”。ビュー側の“最終ラベル”とは別物。

   無効化の二段構え
     - voided_at : 誤登録等の取消（監査上は残す）
     - deleted_at: 削除相当（最終手段）

   期間扱い
     - start_date / end_date は片側 NULL を許容（最小入力で運用可）
     - 両端 NULL も許容し、ビュー上は “常に today-valid” と扱う
     - CHECK制約で start_date <= end_date（NULL はスルー）

   ビュー要点
     - insurance_current
       * farm_user_id ごとに ROW_NUMBER() で代表行を1行に確定
       * 優先: 「今日有効」→（なければ）「最終記録」（end DESC → start DESC → id DESC）
       * days_to_end を算出（end_date が NULL なら NULL）

     - insurance_current_status
       * UI/集計向け “最終ラベル” を英語で提供
         'active' / 'renewal_overdue' / 'renewal_due_soon' / 'non_insured' / 'insured' / 'unknown'

   前提
     - MySQL 8.0+（Window関数使用）
   ====================================================================== */


/* ----------------------------------------------------------------------
   0) 依存ビュー先にDROP（定義順序の都合）
   ---------------------------------------------------------------------- */
DROP VIEW IF EXISTS `insurance_current_status`;
DROP VIEW IF EXISTS `insurance_current`;


/* ----------------------------------------------------------------------
   1) 本体テーブル
   ---------------------------------------------------------------------- */
DROP TABLE IF EXISTS `insurance_enrollments`;
CREATE TABLE IF NOT EXISTS `insurance_enrollments` (
  /* 識別子（AUTO_INCREMENT 主キー）
     - 歴史的背景により主キーは INT。
     - 監査・タイブレークに id を用いる（新しい=大きい）。 */
  `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

  /* 所有者（テナント）側識別 */
  `farm_user_id` INT UNSIGNED NOT NULL,

  /* 加入者コード（共済番号など8桁を想定） */
  `subscriber_code` CHAR(8) NOT NULL,

  /* 入力ステータス（英語）
     - insured : 加入として入力
     - non_insured : 非加入として入力
     - unknown : 不明/未判定
     ※「今日有効かどうか」はビュー側（期間判定）で判断。 */
  `status` ENUM('insured','non_insured','unknown') NOT NULL DEFAULT 'unknown',

  /* 期間（端NULL許容）— 両端NULLも today-valid */
  `start_date` DATE NULL,
  `end_date`   DATE NULL,

  /* 会計年度（任意） */
  `fiscal_year` YEAR NULL,

  /* 情報源・備考（任意） */
  `source_note` VARCHAR(255) NULL,

  /* 無効化(取消)と理由 — voided 行はランキング対象から除外 */
  `voided_at`   DATETIME NULL,
  `void_reason` VARCHAR(255) NULL,

  /* v1p9: 楽観ロック & 論理削除 & 監査 */
  `row_version` BIGINT UNSIGNED NOT NULL DEFAULT 1,  -- 更新毎に+1
  `deleted_at`  DATETIME NULL,                       -- 削除相当（最終手段）
  `created_by`  INT UNSIGNED NULL,                   -- 誰が作成したか（任意）
  `created_at`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  /* 期間検索・代表化前の絞り込みで有効 */
  INDEX `idx_user_dates` (`farm_user_id`, `start_date`, `end_date`),

  /* コード検索・監査用 */
  INDEX `idx_code` (`subscriber_code`),

  /* v1p9: 一覧最適化（差分同期や更新順ソートで有効） */
  KEY `idx_enroll_list` (`deleted_at`, `updated_at`, `id`),

  /* 期間整合性（NULLはスルー）
     - 一部MySQLでは CHECK を無視するためアプリ層検証も併用推奨。 */
  CHECK ( `start_date` IS NULL OR `end_date` IS NULL OR `start_date` <= `end_date` ),

  /* ★ 追加: FK（farm_user_id → farm_users.id）*/
  CONSTRAINT `fk_ins_enro_farm_user`
    FOREIGN KEY (`farm_user_id`) REFERENCES `farm_users`(`id`)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


/* ----------------------------------------------------------------------
   2) row_version 自動インクリメント用トリガ
      - アプリ側で管理する場合は本トリガは不要。
   ---------------------------------------------------------------------- */
DROP TRIGGER IF EXISTS `tr_insurance_enrollments_rowver_bu`;
DELIMITER $$
CREATE TRIGGER `tr_insurance_enrollments_rowver_bu`
BEFORE UPDATE ON `insurance_enrollments`
FOR EACH ROW
BEGIN
  /* 更新のたびに row_version を +1。
     競合検知: UPDATE ... WHERE row_version=:client_version で0件なら競合。 */
  SET NEW.`row_version` = OLD.`row_version` + 1;
END$$
DELIMITER ;


/* ----------------------------------------------------------------------
   3) 現在有効 or 最終記録 を1行に代表化するビュー
      名称: insurance_current
   ---------------------------------------------------------------------- */
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

    /* 代表順位（昇順）:
       0: today-valid（最優先）, 1: not today-valid（後回し）
       次に期限の新しさ→開始日の新しさ→新しいid を優先。 */
    ROW_NUMBER() OVER (
      PARTITION BY e.farm_user_id
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
  /* ランキング対象外（取消・削除相当は除外） */
  WHERE e.voided_at IS NULL AND e.deleted_at IS NULL
)
SELECT
  r.*,
  /* 残日数: end_date が存在するときのみ算出（DATEDIFF=a-b） */
  CASE WHEN r.end_date IS NULL THEN NULL
       ELSE DATEDIFF(r.end_date, CURDATE())
  END AS days_to_end
FROM ranked r
/* 代表行のみ */
WHERE r.rn = 1;


/* ----------------------------------------------------------------------
   4) UI / 集計向け “最終ラベル” ビュー
      名称: insurance_current_status
   ---------------------------------------------------------------------- */
CREATE VIEW `insurance_current_status` AS
SELECT
  c.farm_user_id,
  c.subscriber_code,
  c.start_date,
  c.end_date,
  c.days_to_end,
  /* 最終ラベル（英語／ENUMに追従） */
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
