/* ============================================================
  checkups — BINARY(16) 版（MariaDB 10.5）／クライアント32桁hex・API境界のみ変換

  ■方針
    - クライアント（PWA）は UUID を **32桁hex（小文字、ダッシュ無し）** で扱う。
    - APIでは受信時に **UNHEX(…)=BINARY(16)** へ、返却時は **LOWER(HEX(…))** へ変換。
    - DBはすべて **BINARY(16)** で保存し、JOIN/索引/容量を最適化。
    - UUID未指定（クライアント発番できない）時は、**DBトリガが v7 を自動付与**。
    - GUIの可読用途は **ビュー** で提供（本体テーブルはクリーンを維持）。

  ■カラム/外部キー
    - `uuid` / `visit_uuid` / `individual_uuid` / `chart_header_uuid` は **BINARY(16)**。
    - `visits` / `individuals` / `chart_headers` 側の `uuid` も **BINARY(16) + UNIQUE** 前提。
    - （旧コメント）訪問のFK名は要望どおり **fk_visit_uuid1**。
    - （修正）FK命名規則に合わせ **fk_checkups_visit_uuid** に統一。

  ■文字コード（整合性）
    - 本テーブルは **DEFAULT CHARSET = utf8mb4, COLLATE = utf8mb4_unicode_ci** を明示。
    - アプリ内の他テーブルも **同一** に統一（混在は JOIN/比較で不具合の元）。
      例: ALTER DATABASE your_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

  ■API境界の使い方（例）
    - 受信: 32桁hex → `UNHEX(:uuid_hex)` で渡す（未指定なら NULL）
    - 返却: `SELECT LOWER(HEX(uuid)) AS uuid_hex ...`

  ■備考
    - レプリケーションは、関数で RAND() を使うため **ROWベース**推奨。
    - 親行はすでに存在していること（**親→子の順でINSERT**）。
============================================================ */

-- ========== ユーティリティ関数（hex⇄bin, v7生成） ==========
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
  -- PWAは 32桁hex を送る前提だが、ダッシュ付きを混ぜても受けられるように REPLACE
  RETURN UNHEX(REPLACE(LOWER(s), '-', ''));
END$$

DROP FUNCTION IF EXISTS uuid_v7_str $$
CREATE FUNCTION uuid_v7_str()
RETURNS CHAR(36)
NOT DETERMINISTIC
BEGIN
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

-- ========== 再デプロイ安全化 ==========
DROP TRIGGER IF EXISTS tr_checkups_bi_uuid_v7;
DROP VIEW IF EXISTS checkups_hex_v;
DROP TABLE IF EXISTS checkups;

-- ========== 本体テーブル ==========
CREATE TABLE IF NOT EXISTS checkups (
  id                     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

  -- 主キー相当の一意UUID（BINARY16）
  uuid                   BINARY(16) NOT NULL UNIQUE,

  -- 親FK（BINARY16）
  visit_uuid             BINARY(16) NOT NULL,      -- ↔ visits.uuid
  individual_uuid        BINARY(16) NOT NULL,      -- ↔ individuals.uuid
  chart_header_uuid      BINARY(16) NULL,          -- ↔ chart_headers.uuid

  -- SOAP（p1命名）
  s_subjective           TEXT NULL,
  o_objective            TEXT NULL,
  a_assessment           TEXT NULL,
  p_plan                 TEXT NULL,

  -- TPR（p1命名）
  temp_c                 DECIMAL(4,1) NULL,        -- 体温[℃]
  pulse_bpm              SMALLINT UNSIGNED NULL,   -- 脈拍[bpm]
  resp_bpm               SMALLINT UNSIGNED NULL,   -- 呼吸[bpm]

  -- 現症・経過
  clinical_course        TEXT NULL,

  -- 請求/運用（#2系）
  claim_exclusion        ENUM('none','no_insurance','manual') NOT NULL DEFAULT 'none',
  has_insurance_cached   TINYINT(1) NOT NULL DEFAULT 0,

  status                 ENUM('draft','ready') NOT NULL DEFAULT 'draft',

  created_by             INT UNSIGNED NULL,
  deleted_at             DATETIME NULL,

  created_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  -- 制約・索引
  -- （旧コメント）UNIQUE KEY uq_checkups_visit_individual (visit_uuid, individual_uuid),
  -- （修正）同一 visit×individual で複数の checkups を許可するため UNIQUE を撤去。
  --         代替として探索用の複合インデックスを追加（下記）。

  INDEX idx_checkups_visit (visit_uuid),
  INDEX idx_checkups_individual (individual_uuid),

  -- ▼追加：探索・並び用の複合インデックス（どちらか/両方運用可）
  INDEX idx_checkups_visit_individual_created (visit_uuid, individual_uuid, created_at),
  INDEX idx_checkups_visit_individual_uuid    (visit_uuid, individual_uuid, uuid),

  INDEX idx_claim (chart_header_uuid, claim_exclusion, has_insurance_cached, individual_uuid),

  -- 外部キー（命名規則を統一）
  CONSTRAINT fk_checkups_visit_uuid
    FOREIGN KEY (visit_uuid) REFERENCES visits(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,

  CONSTRAINT fk_checkups_individual_uuid
    FOREIGN KEY (individual_uuid) REFERENCES individuals(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,

  CONSTRAINT fk_checkups_chart_header_uuid
    FOREIGN KEY (chart_header_uuid) REFERENCES chart_headers(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci;

-- ========== BEFORE INSERT: uuid 未指定なら DB が v7 を自動付与 ==========
DELIMITER $$
CREATE TRIGGER tr_checkups_bi_uuid_v7
BEFORE INSERT ON checkups
FOR EACH ROW
BEGIN
  -- アプリが uuid を送らない/NULL の場合のみ自動採番（v7, BINARY16）
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid) = 0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;

-- 5) checkup_items（p012準拠）
CREATE TABLE IF NOT EXISTS checkup_items (
  id                     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                   BINARY(16) NOT NULL UNIQUE,
  checkup_uuid           BINARY(16) NOT NULL,            -- ↔ checkups.uuid
  treatment_uuid         BINARY(16) NULL,                -- 任意参照
  description            VARCHAR(255) NOT NULL,

  qty_unit               VARCHAR(32) NULL,
  quantity               DECIMAL(10,2) NOT NULL DEFAULT 1,

  pay_type               ENUM('insurance','private') NOT NULL,

  unit_b_points          INT UNSIGNED NOT NULL DEFAULT 0,
  unit_a_points          INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_points        INT UNSIGNED NOT NULL DEFAULT 0,
  yen_per_point          DECIMAL(8,2) NOT NULL DEFAULT 0.00,

  unit_price_yen         INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_price_yen     INT UNSIGNED NOT NULL DEFAULT 0,

  tax_rate               DECIMAL(4,2) NOT NULL DEFAULT 0.00,
  subtotal_yen           INT UNSIGNED NOT NULL DEFAULT 0,

  deleted_at             DATETIME NULL,
  created_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  INDEX idx_checkup_items_parent (checkup_uuid, pay_type),

  CONSTRAINT fk_checkup_items_checkup
    FOREIGN KEY (checkup_uuid) REFERENCES checkups(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$
CREATE TRIGGER tr_checkup_items_bi_uuid_v7
BEFORE INSERT ON checkup_items
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR LENGTH(NEW.uuid) = 0 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$
DELIMITER ;

-- ========== 管理・デバッグ用ビュー（返却時にhex文字列で見たい時） ==========
/*
  本番アプリはBINARY16を直接扱い、返却時に HEX() で文字列化すればよい。
  ただし、GUI/手検証で可読にしたい場合はこのビューを使う。
  ※本体テーブルはクリーンのまま（生成列など付けない）。
*/
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
