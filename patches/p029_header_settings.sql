/* ===========================
   p029 — header_settings（DATETIME(6)版）
   =========================== */
SET NAMES utf8mb4;

-- ── 再デプロイ安全化 ─────────────────────────────────────────────
DROP TRIGGER IF EXISTS tr_header_settings_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_header_settings_bu_rowver;
DROP TABLE  IF EXISTS header_settings;

-- =========================================================
-- header_settings — ヘッダ行ごとのスナップ方針（期間= start/end のみ）
-- p028(header_links)と同じ (header_table, header_uuid) でヘッダを弱リンク
-- =========================================================
CREATE TABLE header_settings (
  id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '内部ID',
  uuid                 BINARY(16)      NOT NULL                COMMENT '行UUID（v7想定）',

  -- ▼ ヘッダ識別（弱リンク：FKなし）
  header_table         VARCHAR(64)     NOT NULL                COMMENT 'ヘッダの実テーブル名（例: chart_headers 等）',
  header_uuid          BINARY(16)      NOT NULL                COMMENT '当該ヘッダ行のUUID（弱リンク）',

  -- ▼ 表示系
  display_title        VARCHAR(128)    NOT NULL                COMMENT '表示用タイトルテキスト（UI見出し）',
  note                 TEXT            NULL                    COMMENT '補足メモ',

  -- ▼ 抽出の基点
  target_table         VARCHAR(64)     NOT NULL                COMMENT 'ターゲットテーブル（例: checkups, visits 等）',
  target_date_column   VARCHAR(64)     NULL                    COMMENT '期間判定に用いる日付/日時列（NULL時はdocsnap既定を使用）',

  -- ▼ 取得期間（半開区間で統一）
  period_start_date    DATE            NULL                    COMMENT '開始日（含む）。NULLなら下限なし',
  period_end_date      DATE            NULL                    COMMENT '終了日（含まない）。NULLなら上限なし',
  CHECK (period_end_date IS NULL OR period_start_date IS NULL OR period_end_date > period_start_date),

  -- ▼ フィルタ（WHERE句断片；先頭にWHERE/AND不要）
  checkups_where_sql        TEXT       NULL                    COMMENT 'checkups向け条件（例: visit_type=\"home\"）',
  checkup_items_where_sql   TEXT       NULL                    COMMENT 'checkup_items向け条件（例: pay_type=\"insurance\"）',

  -- ▼ 上流スナップに含めるテーブル（JSON配列）
  upstream_tables_json  LONGTEXT       NULL                    COMMENT '例: [\"farms\",\"individuals\",\"visits\",\"checkups\",\"checkup_items\"]',
  CHECK (upstream_tables_json IS NULL OR JSON_VALID(upstream_tables_json)),

  -- ▼ 並び順と件数
  order_by_sql          TEXT           NULL                    COMMENT 'ORDER BY 断片（例: visit_date DESC, id DESC）',
  limit_rows            INT            NULL                    COMMENT '抽出上限（NULLで無制限）',

  -- ▼ docsnap拡張（将来用）
  docsnap_options_json  LONGTEXT       NULL                    COMMENT '命名テンプレ/列プレフィックス等（JSON）',
  CHECK (docsnap_options_json IS NULL OR JSON_VALID(docsnap_options_json)),

  -- ▼ 運用/監査
  is_active             TINYINT(1)     NOT NULL DEFAULT 1      COMMENT '1=有効/0=無効',
  row_version           BIGINT UNSIGNED NOT NULL DEFAULT 1     COMMENT '楽観ロック',
  created_at            DATETIME(6)     NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at            DATETIME(6)     NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  deleted_at            DATETIME(6)     NULL,

  -- ▼ 1ヘッダ=1設定（論理削除後の復活も同一キーで扱う）
  UNIQUE KEY uq_header_settings_one (header_table, header_uuid),

  -- ▼ 代表索引
  KEY idx_hs_hdr   (header_table, header_uuid, deleted_at, id),
  KEY idx_hs_list  (header_table, is_active, deleted_at, updated_at, id),
  KEY idx_hs_title (display_title),
  KEY idx_hs_rev   (deleted_at, updated_at, id),

  PRIMARY KEY (id)
)
ENGINE=InnoDB
DEFAULT CHARSET = utf8mb4
COLLATE = utf8mb4_unicode_ci
ROW_FORMAT = DYNAMIC
COMMENT='ヘッダ行単位のdocsnap方針。期間は start/end のみ（半開区間）。';

-- ▼ UUID自動採番
DELIMITER $$
CREATE TRIGGER tr_header_settings_bi_uuid_v7
BEFORE INSERT ON header_settings
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;

-- ▼ row_version 自動加算
DELIMITER $$
CREATE TRIGGER tr_header_settings_bu_rowver
BEFORE UPDATE ON header_settings
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;
