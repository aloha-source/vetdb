/* ===========================
   p028 — header_links（DATETIME(6)版）
   =========================== */
SET NAMES utf8mb4;

-- ── 再デプロイ安全化 ─────────────────────────────────────────────
DROP TRIGGER IF EXISTS tr_header_links_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_header_links_bu_rowver;
DROP TABLE  IF EXISTS header_links;

-- =========================================================
-- 汎用中間リンク表（header_table単位でアクティブ重複禁止／target_uuidは1本）
-- 仕様:
--  - ヘッダ種別は header_table（実テーブル名）で表現。header_typeは不使用
--  - リンク対象は target_uuid 1本で保持（farm/individual/checkup/item いずれでも可）
--  - “同じ header_table 内”でのみアクティブ重複（deleted_at IS NULL）を禁止
--  - 別の header_table 間（例：chart_headers と withdrawal_headers）は非干渉
--  - excludeは使わず、リンクしない＝採用しない
--  - header_uuid は弱リンク（FKなし）。存在検証はアプリ/手続き側で実施
-- =========================================================
CREATE TABLE header_links (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '内部ID',
  uuid              BINARY(16)      NOT NULL                COMMENT '行UUID（v7想定）',

  -- ▼ ヘッダ側（弱リンク）
  header_table      VARCHAR(64)     NOT NULL                COMMENT 'ヘッダのテーブル名（例: chart_headers, withdrawal_headers）',
  header_uuid       BINARY(16)      NOT NULL                COMMENT 'ヘッダ行のUUID（弱リンク）',

  -- ▼ ターゲット（粒度は設定に委ね、ここではUUIDのみを1本保持）
  target_uuid       BINARY(16)      NOT NULL                COMMENT 'リンク対象のUUID（farm/individual/checkup/item のいずれか）',

  -- ▼ 並び/監査
  sort_index        INT             NULL                    COMMENT '手動並び',
  row_version       BIGINT UNSIGNED NOT NULL DEFAULT 1      COMMENT '楽観ロック',
  created_at        DATETIME(6)     NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at        DATETIME(6)     NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  deleted_at        DATETIME(6)     NULL,

  -- ▼（A）ヘッダ行内の重複禁止：同一ヘッダに同一ターゲットを二重登録させない
  --     ※ deleted_at を含めない＝過去行は UPSERT/復活（undelete）で再利用
  UNIQUE KEY uq_hdr_row (header_table, header_uuid, target_uuid),

  -- ▼（B）“同一ヘッダテーブル内”のアクティブ重複禁止（生成列で未削除時だけ鍵を効かせる）
  lock_header_table VARCHAR(64)
    GENERATED ALWAYS AS (IF(deleted_at IS NULL, header_table, NULL)) PERSISTENT,
  lock_target_uuid  BINARY(16)
    GENERATED ALWAYS AS (IF(deleted_at IS NULL, target_uuid,  NULL)) PERSISTENT,
  UNIQUE KEY uq_active_scope (lock_header_table, lock_target_uuid),

  -- ▼ 代表索引
  KEY idx_hdr_list (header_table, header_uuid, deleted_at, id),
  KEY idx_tgt      (target_uuid, deleted_at, id),
  KEY idx_rev      (deleted_at, updated_at, id),

  PRIMARY KEY (id)
)
ENGINE=InnoDB
DEFAULT CHARSET = utf8mb4
COLLATE = utf8mb4_unicode_ci
ROW_FORMAT = DYNAMIC
COMMENT='header_table×target_uuid を1表でリンク。header_table内のみアクティブ重複をUNIQUEで禁止';

-- ▼ UUID自動採番（uuid_v7_bin() が存在する前提）
DELIMITER $$
CREATE TRIGGER tr_header_links_bi_uuid_v7
BEFORE INSERT ON header_links
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;

-- ▼ row_version 自動加算
DELIMITER $$
CREATE TRIGGER tr_header_links_bu_rowver
BEFORE UPDATE ON header_links
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;
