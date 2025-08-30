/* =========================
   #8 disease_master — 調整後
   変更点:
   - major_name/middle_name/minor_name を VARCHAR(32) に統一
   - display_name を VARCHAR(66) に調整（32 + 1 + 32 + 1）
   - 名称索引プレフィックスを (32,32) に更新
   ========================= */

DROP TABLE IF EXISTS disease_master;
CREATE TABLE IF NOT EXISTS disease_master (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid BINARY(16) NOT NULL UNIQUE,

  -- 正規コード（6桁・先頭ゼロ保持）
  code6 CHAR(6) NOT NULL,

  -- 派生コード（検索補助）
  major_code  CHAR(2) GENERATED ALWAYS AS (SUBSTR(code6,1,2)) VIRTUAL,
  middle_code CHAR(2) GENERATED ALWAYS AS (SUBSTR(code6,3,2)) VIRTUAL,
  minor_code  CHAR(2) GENERATED ALWAYS AS (SUBSTR(code6,5,2)) VIRTUAL,
  display_code CHAR(8) GENERATED ALWAYS AS (
    CONCAT(SUBSTR(code6,1,2),'-',SUBSTR(code6,3,2),'-',SUBSTR(code6,5,2))
  ) STORED,

  -- 名称（※ここを統一）
  major_name   VARCHAR(32)  NOT NULL,   -- CHANGED
  middle_name  VARCHAR(32)  NOT NULL,   -- CHANGED
  minor_name   VARCHAR(32)  NOT NULL,   -- CHANGED

  -- 例: 「中分類名（小分類名）」→ 最大長 32+1+32+1=66
  display_name VARCHAR(66) GENERATED ALWAYS AS
    (CONCAT(middle_name, '（', minor_name, '）')) STORED,  -- CHANGED

  legal_note    TEXT NULL,
  is_active     TINYINT(1) NOT NULL DEFAULT 1,
  is_reportable TINYINT(1) NOT NULL DEFAULT 0,

  -- 監査
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at  DATETIME NULL,
  row_version BIGINT UNSIGNED NOT NULL DEFAULT 1,

  -- 制約・索引
  UNIQUE KEY uq_disease_code6 (code6),
  CHECK (code6 REGEXP '^[0-9]{6}$'),
  INDEX idx_disease_major (major_code),
  INDEX idx_disease_mm    (major_code, middle_code),
  INDEX idx_disease_name  (is_active, middle_name(32), minor_name(32)), -- CHANGED
  INDEX idx_quality       (deleted_at, updated_at, id)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  ROW_FORMAT=DYNAMIC;

-- UUID自動採番（v7想定。未定義なら UNHEX(REPLACE(UUID(),'-','')) に置換可）
DROP TRIGGER IF EXISTS bi_disease_master_uuid;
CREATE TRIGGER bi_disease_master_uuid
BEFORE INSERT ON disease_master
FOR EACH ROW
  SET NEW.uuid = COALESCE(NEW.uuid, uuid_v7_bin());


/* =========================
   disease_rinkoku_rules — 調整後
   ※名称列は無いため今回の変更は波及なし（DDLは従来と同等）
   ========================= */

DROP TABLE IF EXISTS disease_rinkoku_rules;
CREATE TABLE IF NOT EXISTS disease_rinkoku_rules (
  id   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid BINARY(16) NOT NULL UNIQUE,

  -- 対象病名
  disease_id INT UNSIGNED NOT NULL,   -- ↔ disease_master(id)

  -- 凛告候補（申告理由の短文）
  rinkoku_text   VARCHAR(128) NOT NULL,
  display_order  SMALLINT UNSIGNED NOT NULL DEFAULT 100,

  -- 運用
  is_active  TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  -- 取得用索引・FK
  INDEX idx_drr_fetch (disease_id, is_active, display_order, id),
  CONSTRAINT fk_drr_disease
    FOREIGN KEY (disease_id) REFERENCES disease_master(id)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  ROW_FORMAT=DYNAMIC;

-- UUID自動採番
DROP TRIGGER IF EXISTS bi_drr_uuid;
CREATE TRIGGER bi_drr_uuid
BEFORE INSERT ON disease_rinkoku_rules
FOR EACH ROW
  SET NEW.uuid = COALESCE(NEW.uuid, uuid_v7_bin());
