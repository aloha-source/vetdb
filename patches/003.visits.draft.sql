/* ---------------------------------------------------------
   visits — 訪問記録（予定ではなく実施ログ）
   方針:
     - UUIDは BINARY(16) / UUIDv7 を BEFORE INSERT で自動採番
     - UTC保存（表示はアプリ側でTZ変換）
     - row_version による楽観ロック（BEFORE UPDATEで+1）
     - list用複合索引 (deleted_at, updated_at, id)
     - FlowA: 個体は checkups 側で visit に紐付ける（visitsには individual_uuid を置かない）
   依存:
     - uuid_v7_bin(), uuid_bin_to_hex(), uuid_hex_to_bin() は p012.2 で作成済み想定
   --------------------------------------------------------- */

DROP TABLE IF EXISTS `visits`;

CREATE TABLE IF NOT EXISTS `visits` (
  `id`               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT 'サロゲートID',
  `uuid`             BINARY(16) NOT NULL UNIQUE COMMENT 'UUIDv7 (bin16)',
  `farm_uuid`        BINARY(16) NOT NULL COMMENT '訪問先Farm（FKは任意、別DBミラー可）',

  `visit_started_at` DATETIME   NOT NULL COMMENT '訪問開始(UTC)',
  `visit_ended_at`   DATETIME   NULL     COMMENT '訪問終了(UTC)',
  `location_text`    VARCHAR(180) NULL   COMMENT '地名/目印（任意）',
  `note`             VARCHAR(255) NULL   COMMENT '簡易メモ（任意）',

  `row_version`      BIGINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '楽観ロック用',
  `deleted_at`       DATETIME NULL,
  `created_at`       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  -- 一覧/範囲クエリ最適化
  INDEX `idx_visits_farm_started` (`farm_uuid`, `visit_started_at`),
  INDEX `idx_visits_started` (`visit_started_at`),
  KEY   `idx_visits_list` (`deleted_at`, `updated_at`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Farm単位の訪問実施ログ。個体はcheckups経由で紐付ける';

/* ---------- トリガ: UUID自動付与（UUIDv7/bin16） ---------- */
DROP TRIGGER IF EXISTS `bi_visits_uuid`;
DELIMITER $$
CREATE TRIGGER `bi_visits_uuid`
BEFORE INSERT ON `visits`
FOR EACH ROW
BEGIN
  -- uuid未指定なら自動採番（全ゼロ対策も含む）
  IF NEW.`uuid` IS NULL OR NEW.`uuid` = 0x00000000000000000000000000000000 THEN
    SET NEW.`uuid` = uuid_v7_bin();
  END IF;

  -- visit_started_at未指定なら現在UTCで初期化
  IF NEW.`visit_started_at` IS NULL THEN
    SET NEW.`visit_started_at` = UTC_TIMESTAMP();
  END IF;
END$$
DELIMITER ;

/* ---------- トリガ: row_version自動インクリメント ---------- */
DROP TRIGGER IF EXISTS `bu_visits_rowver`;
DELIMITER $$
CREATE TRIGGER `bu_visits_rowver`
BEFORE UPDATE ON `visits`
FOR EACH ROW
BEGIN
  SET NEW.`row_version` = OLD.`row_version` + 1;
END$$
DELIMITER ;

/* ----（任意）デバッグ用ビュー：hex表記でUUIDを確認したい場合 ----
DROP VIEW IF EXISTS v_visits_text;
CREATE VIEW v_visits_text AS
SELECT
  id,
  LOWER(uuid_bin_to_hex(uuid)) AS uuid,
  LOWER(uuid_bin_to_hex(farm_uuid)) AS farm_uuid,
  visit_started_at, visit_ended_at,
  location_text, note,
  row_version, deleted_at, created_at, updated_at
FROM visits;
-- ---------------------------------------------------------- */
