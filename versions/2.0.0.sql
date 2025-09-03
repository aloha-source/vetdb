/* ============================================================
  VetDB 2.0.0 — クリーンインストールDDL（MariaDB 10.5）
  方針：PWA=32桁hex／DB=BINARY(16)／API境界でのみ変換／v7自動付与

  ■全体方針
    - クライアント（PWA）は UUID を **32桁hex（小文字・ダッシュ無し）** で扱う。
    - APIでは受信時に **uuid_hex_to_bin(:hex)** で BINARY(16) に変換、
      返却時は **uuid_bin_to_hex(col)** で小文字hexに変換して返す。
    - DBのすべての UUID カラムは **BINARY(16)**（省サイズ・索引効率・v7の時系列局所性）。
    - UUID 未指定（クライアント発番不可）の場合は、DBトリガが **UUID v7** を自動付与。
    - テーブルごとに **DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci** を明示。
    - **checkups は p012 方針を採用**。
      ※本リクエストにより **chart_header_uuid を先行導入**（NULL可）。
        ただし **chart_headers テーブルは後日**追加予定のため、FKは**コメントアウト**で準備のみ。

  ■このDDLに含まれるもの
    1) UUID ユーティリティ関数：hex⇄bin、v7生成
    2) 3テーブル（parents→childrenの順）：individuals, visits, checkups
    3) BEFORE INSERT トリガ：uuid未指定なら v7 を自動採番
    4) 管理/デバッグ用ビュー（*_hex_v）：可読hexで一覧

  ■インデックス方針（checkups）
    - **UNIQUE(visit_uuid, individual_uuid)** は置かない（同一 visit×individual で複数診療可）
    - 探索用： (visit_uuid, individual_uuid, created_at) / (visit_uuid, individual_uuid, uuid)
    - 請求・連携用の先行インデックス： (chart_header_uuid, claim_exclusion, has_insurance_cached, individual_uuid)
      （chart_headers が無くても作成可。将来FK追加時の探索効率を確保）

  ■API境界の使い方（例）
    - 受信（32桁hex→BINARY16）: INSERT ... uuid_hex_to_bin(:uuid_hex) ...
    - 返却（BINARY16→32桁hex）: SELECT uuid_bin_to_hex(uuid) AS uuid_hex ...
============================================================ */

-- ============================================================
-- 0) ユーティリティ関数（hex⇄bin, v7生成）
-- ============================================================
DELIMITER $$

DROP FUNCTION IF EXISTS uuid_bin_to_hex $$
CREATE FUNCTION uuid_bin_to_hex(b BINARY(16))
RETURNS CHAR(32)
DETERMINISTIC
BEGIN
  RETURN LOWER(HEX(b));
END$$

DROP FUNCTION IF EXISTS uuid_hex_to_bin $$
CREATE FUNCTION uuid_hex_to_bin(s VARCHAR(36))
RETURNS BINARY(16)
DETERMINISTIC
BEGIN
  -- PWAは本来 32桁hex を送る前提だが、ダッシュ付きを混ぜても受けられるように REPLACE
  RETURN UNHEX(REPLACE(LOWER(s), '-', ''));
END$$

DROP FUNCTION IF EXISTS uuid_v7_str $$
CREATE FUNCTION uuid_v7_str()
RETURNS CHAR(36)
NOT DETERMINISTIC
BEGIN
  -- v7: 48bit epoch(ms) + ver/var + 54bit rand 相当
  DECLARE ts_ms BIGINT UNSIGNED;  DECLARE ts_hex CHAR(12);
  DECLARE r12 INT UNSIGNED;       DECLARE ver_hi CHAR(4);
  DECLARE var_hi CHAR(4);         DECLARE tail CHAR(12);
  DECLARE t_hi CHAR(8);           DECLARE t_mid CHAR(4);

  SET ts_ms  = CAST(ROUND(UNIX_TIMESTAMP(CURRENT_TIMESTAMP(3))*1000) AS UNSIGNED);
  SET ts_hex = LPAD(HEX(ts_ms),12,'0');

  SET r12    = FLOOR(RAND()*POW(2,12));
  SET ver_hi = CONCAT('7', LPAD(HEX(r12),3,'0'));
  SET var_hi = CONCAT(ELT(FLOOR(RAND()*4)+1,'8','9','a','b'),
                      LPAD(HEX(FLOOR(RAND()*POW(2,12))),3,'0'));
  SET tail   = LPAD(HEX(FLOOR(RAND()*POW(2,48))),12,'0');

  SET t_hi  = LEFT(ts_hex,8);
  SET t_mid = SUBSTRING(ts_hex,9,4);

  RETURN LOWER(CONCAT(t_hi,'-',t_mid,'-',ver_hi,'-',var_hi,'-',tail));
END$$

DROP FUNCTION IF EXISTS uuid_v7_bin $$
CREATE FUNCTION uuid_v7_bin()
RETURNS BINARY(16)
NOT DETERMINISTIC
BEGIN
  RETURN uuid_hex_to_bin(uuid_v7_str());
END$$

DELIMITER ;

-- ============================================================
-- 1) 既存オブジェクト掃除（再デプロイ安全化）
-- ============================================================
DROP VIEW IF EXISTS checkups_hex_v;
DROP VIEW IF EXISTS visits_hex_v;
DROP VIEW IF EXISTS individuals_hex_v;

DROP TRIGGER IF EXISTS tr_checkups_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_visits_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_individuals_bi_uuid_v7;

DROP TABLE IF EXISTS checkups;
DROP TABLE IF EXISTS visits;
DROP TABLE IF EXISTS individuals;

-- ============================================================
-- 2) 親テーブル：individuals
-- ============================================================
CREATE TABLE individuals (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid       BINARY(16) NOT NULL UNIQUE,

  -- 必要に応じて業務カラムを追加
  -- name     VARCHAR(255) NULL,

  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_individuals_bi_uuid_v7
BEFORE INSERT ON individuals
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid)=0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;

CREATE OR REPLACE VIEW individuals_hex_v AS
SELECT
  id,
  uuid_bin_to_hex(uuid) AS uuid_hex,
  created_at, updated_at
FROM individuals;

-- ============================================================
-- 3) 親テーブル：visits
-- ============================================================
CREATE TABLE visits (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid       BINARY(16) NOT NULL UNIQUE,

  -- 必要に応じて業務カラムを追加
  -- visit_date DATE NULL,

  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_visits_bi_uuid_v7
BEFORE INSERT ON visits
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid)=0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;

CREATE OR REPLACE VIEW visits_hex_v AS
SELECT
  id,
  uuid_bin_to_hex(uuid) AS uuid_hex,
  created_at, updated_at
FROM visits;

-- ============================================================
-- 4) 子テーブル：checkups（p012 方針＋ chart_header_uuid 先行導入）
-- ============================================================
CREATE TABLE checkups (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

  -- 主キー相当の一意UUID（BINARY16）
  uuid             BINARY(16) NOT NULL UNIQUE,

  -- 親FK（BINARY16）
  visit_uuid       BINARY(16) NOT NULL,   -- ↔ visits.uuid
  individual_uuid  BINARY(16) NOT NULL,   -- ↔ individuals.uuid

  -- 先行導入：将来 chart_headers.uuid を参照する予定（現時点ではFK未設定）
  chart_header_uuid BINARY(16) NULL,      -- ↔ (future) chart_headers.uuid

  -- SOAP（p1命名）
  s_subjective     TEXT NULL,
  o_objective      TEXT NULL,
  a_assessment     TEXT NULL,
  p_plan           TEXT NULL,

  -- TPR（p1命名）
  temp_c           DECIMAL(4,1) NULL,             -- 体温[℃]
  pulse_bpm        SMALLINT UNSIGNED NULL,        -- 脈拍[bpm]
  resp_bpm         SMALLINT UNSIGNED NULL,        -- 呼吸[bpm]

  -- 現症・経過
  clinical_course  TEXT NULL,

  -- 請求/運用
  claim_exclusion        ENUM('none','no_insurance','manual') NOT NULL DEFAULT 'none',
  has_insurance_cached   TINYINT(1) NOT NULL DEFAULT 0,

  status           ENUM('draft','ready') NOT NULL DEFAULT 'draft',

  created_by       INT UNSIGNED NULL,
  deleted_at       DATETIME NULL,

  created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  -- 制約・索引
  -- （p012に合わせて）UNIQUE(visit_uuid, individual_uuid) は置かない（複数診療を許可）
  INDEX idx_checkups_visit (visit_uuid),
  INDEX idx_checkups_individual (individual_uuid),

  -- よく使う探索のための複合索引（どちらか/両方運用可）
  INDEX idx_checkups_visit_individual_created (visit_uuid, individual_uuid, created_at),
  INDEX idx_checkups_visit_individual_uuid    (visit_uuid, individual_uuid, uuid),

  -- 先行インデックス：将来の請求連携・探索用（chart_headers 未導入でも作成可）
  INDEX idx_claim (chart_header_uuid, claim_exclusion, has_insurance_cached, individual_uuid),

  -- 外部キー（命名規則を統一）
  CONSTRAINT fk_checkups_visit_uuid
    FOREIGN KEY (visit_uuid) REFERENCES visits(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_checkups_individual_uuid
    FOREIGN KEY (individual_uuid) REFERENCES individuals(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT

  -- ▼TODO（2.0.1 以降）：chart_headers 導入後にFKを追加
  -- ALTER TABLE checkups
  --   ADD CONSTRAINT fk_checkups_chart_header_uuid
  --     FOREIGN KEY (chart_header_uuid) REFERENCES chart_headers(uuid)
  --     ON UPDATE CASCADE ON DELETE SET NULL;
) ENGINE=InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_checkups_bi_uuid_v7
BEFORE INSERT ON checkups
FOR EACH ROW
BEGIN
  -- アプリが uuid を送らない/NULL の場合のみ自動採番（v7, BINARY16）
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid)=0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;

CREATE OR REPLACE VIEW checkups_hex_v AS
SELECT
  id,
  uuid_bin_to_hex(uuid)              AS uuid_hex,
  uuid_bin_to_hex(visit_uuid)        AS visit_uuid_hex,
  uuid_bin_to_hex(individual_uuid)   AS individual_uuid_hex,
  uuid_bin_to_hex(chart_header_uuid) AS chart_header_uuid_hex,
  s_subjective, o_objective, a_assessment, p_plan,
  temp_c, pulse_bpm, resp_bpm, clinical_course,
  claim_exclusion, has_insurance_cached, status,
  created_by, deleted_at, created_at, updated_at
FROM checkups;

-- ============================================================
-- 5) 参考：API側SQLスニペット（hex⇄binは境界のみ）
-- ============================================================
-- 作成（クライアントが v7 を付与できる場合）：
-- INSERT INTO checkups (uuid, visit_uuid, individual_uuid, chart_header_uuid, a_assessment)
-- VALUES (
--   uuid_hex_to_bin(:uuid_hex),                 -- 32桁hex → BINARY16
--   uuid_hex_to_bin(:visit_uuid_hex),
--   uuid_hex_to_bin(:individual_uuid_hex),
--   IFNULL(uuid_hex_to_bin(:chart_header_uuid_hex), NULL),
--   :assessment
-- );
-- SELECT uuid_bin_to_hex(uuid) AS uuid_hex FROM checkups WHERE id = LAST_INSERT_ID();

-- 作成（クライアントが uuid 未指定の場合）：
-- INSERT INTO checkups (visit_uuid, individual_uuid, chart_header_uuid, a_assessment)
-- VALUES (
--   uuid_hex_to_bin(:visit_uuid_hex),
--   uuid_hex_to_bin(:individual_uuid_hex),
--   IFNULL(uuid_hex_to_bin(:chart_header_uuid_hex), NULL),
--   :assessment
-- );
-- SELECT uuid_bin_to_hex(uuid) AS uuid_hex FROM checkups WHERE id = LAST_INSERT_ID();

-- 取得（一覧/詳細、visit×individual で時系列）：
-- SELECT uuid_bin_to_hex(uuid) AS uuid_hex, a_assessment, created_at
-- FROM checkups
-- WHERE visit_uuid = uuid_hex_to_bin(:visit_uuid_hex)
--   AND individual_uuid = uuid_hex_to_bin(:individual_uuid_hex)
-- ORDER BY created_at ASC, uuid ASC; -- 同着は uuid(v7) でブレイク
