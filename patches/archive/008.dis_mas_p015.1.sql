/* =========================================================
   #8 disease_master
   目的: 疾病コード(6桁)と名称(大/中/小)のマスタ
   規模: 100〜200行想定、参照頻度が高く更新稀
   方針:
     - 参照キーは code6（6桁, 一意）と id（INT PK）
     - uuid は BINARY(16)（v7想定）で付番（トリガで自動）
     - 名称3列は 10文字程度想定 → VARCHAR(32)で統一
     - display_* は生成列（MariaDBでは PERSISTENT を使用）
     - 一覧最適化用の複合索引 (deleted_at, updated_at, id) を付与
     - utf8mb4 + ROW_FORMAT=DYNAMIC を明示
   MariaDB 10.5 留意:
     - 生成列の保存型は STORED ではなく PERSISTENT を使用
     - CHECK は 10.2+ で有効
   ========================================================= */

DROP TABLE IF EXISTS disease_master;
CREATE TABLE IF NOT EXISTS disease_master (
  -- 主キー（自動採番）。参照は基本これか code6 を用いる
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

  -- グローバル識別子（クライアント/連携用）。BINARY(16)で省容量
  uuid BINARY(16) NOT NULL UNIQUE,

  -- 正規疾病コード（6桁, 先頭ゼロ保持）。外部文書・カルテでの照合に使用
  code6 CHAR(6) NOT NULL,

  /* -------- 生成列（検索補助） --------
     major/middle/minor は code6 のサブパートを切り出して保持。
     VIRTUAL: 計算コスト最小／実ストレージ非消費。
  */
  major_code  CHAR(2) GENERATED ALWAYS AS (SUBSTR(code6,1,2)) VIRTUAL,
  middle_code CHAR(2) GENERATED ALWAYS AS (SUBSTR(code6,3,2)) VIRTUAL,
  minor_code  CHAR(2) GENERATED ALWAYS AS (SUBSTR(code6,5,2)) VIRTUAL,

  /* 表示用のフォーマット済コード。
     MariaDB 10.5: 保存型は PERSISTENT を使用（※STORED ではない）
     → 並び替え/検索に利用する場面で I/O を抑制できる
  */
  display_code CHAR(8) GENERATED ALWAYS AS (
    CONCAT(SUBSTR(code6,1,2),'-',SUBSTR(code6,3,2),'-',SUBSTR(code6,5,2))
  ) PERSISTENT,  -- CHANGED: STORED → PERSISTENT（MariaDB 10.5）

  /* -------- 名称（実体） --------
     10文字前後想定だが余裕を見て32。UTF-8でも1Bヘッダの範囲に収まる
  */
  major_name   VARCHAR(32)  NOT NULL,  -- 大分類名（章レベル）
  middle_name  VARCHAR(32)  NOT NULL,  -- 中分類名（検索で最も使う）
  minor_name   VARCHAR(32)  NOT NULL,  -- 小分類名（症状名など）

  /* 例: 「中分類名（小分類名）」。
     最大長 32 + 1 + 32 + 1 = 66 → VARCHAR(66)
     PERSISTENT: 一覧表示での描画コストを削減
  */
  display_name VARCHAR(66) GENERATED ALWAYS AS
    (CONCAT(middle_name, '（', minor_name, '）')) PERSISTENT,  -- CHANGED: STORED → PERSISTENT

  -- 法令・届出関連の備考（任意）
  legal_note TEXT NULL,

  -- 運用フラグ
  is_active     TINYINT(1) NOT NULL DEFAULT 1,  -- 0で非表示（論理的に廃止）
  is_reportable TINYINT(1) NOT NULL DEFAULT 0,  -- 届出対象か

  -- 監査系（ソフトデリート + 楽観ロック）
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at  DATETIME NULL,
  row_version BIGINT UNSIGNED NOT NULL DEFAULT 1,

  /* 制約・索引
     - code6 は一意（重複登録防止）
     - CHECK で6桁数字を厳格化（アプリ側と二重防御）
     - major/middle はコード検索用の補助索引
     - 名称は is_active を先頭にした前方一致系の複合プレフィックス索引
     - 一覧最適化（削除フラグ/更新時刻/PK）の複合索引
  */
  UNIQUE KEY uq_disease_code6 (code6),
  CHECK (code6 REGEXP '^[0-9]{6}$'),
  INDEX idx_disease_major (major_code),
  INDEX idx_disease_mm    (major_code, middle_code),
  INDEX idx_disease_name  (is_active, middle_name(32), minor_name(32)),
  INDEX idx_quality       (deleted_at, updated_at, id)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  ROW_FORMAT=DYNAMIC;

-- UUIDの自動採番（v7想定）。未実装環境では UNHEX(REPLACE(UUID(),'-','')) で代替可
DROP TRIGGER IF EXISTS bi_disease_master_uuid;
CREATE TRIGGER bi_disease_master_uuid
BEFORE INSERT ON disease_master
FOR EACH ROW
  SET NEW.uuid = COALESCE(NEW.uuid, uuid_v7_bin());


/* =========================================================
   disease_rinkoku_rules
   目的: 病名ごとの凛告（申告理由）候補を提示する最小ルール集
   規模: 病名×数語。UIでの選択肢提示を高速化
   方針:
     - disease_id で disease_master に従属
     - rinkoku_text は短文（最大128）
     - is_active と display_order で表示制御
     - 取得用複合索引 (disease_id, is_active, display_order, id)
   ========================================================= */

DROP TABLE IF EXISTS disease_rinkoku_rules;
CREATE TABLE IF NOT EXISTS disease_rinkoku_rules (
  id   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid BINARY(16) NOT NULL UNIQUE,

  -- 対象の病名。disease_master(id) に従属
  disease_id INT UNSIGNED NOT NULL,

  -- 凛告候補（UIに出す短い語句）。日本語想定で余裕を見て128
  rinkoku_text   VARCHAR(128) NOT NULL,

  -- 表示順。小さいほど上位に表示
  display_order  SMALLINT UNSIGNED NOT NULL DEFAULT 100,

  -- 運用フラグ/監査
  is_active  TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  -- 代表的な取得クエリを満たす複合索引
  INDEX idx_drr_fetch (disease_id, is_active, display_order, id),

  -- 親マスタのコード編集に追随（更新CASCADE）/削除制限（RESTRICT）
  CONSTRAINT fk_drr_disease
    FOREIGN KEY (disease_id) REFERENCES disease_master(id)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  ROW_FORMAT=DYNAMIC;

-- UUIDの自動採番（v7想定）
DROP TRIGGER IF EXISTS bi_drr_uuid;
CREATE TRIGGER bi_drr_uuid
BEFORE INSERT ON disease_rinkoku_rules
FOR EACH ROW
  SET NEW.uuid = COALESCE(NEW.uuid, uuid_v7_bin());
