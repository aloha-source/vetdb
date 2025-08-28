/* ===================================================================
   vetDB schema install (based on p014.1 / visits.draft / checkups_p012.2)
   [p014.2:2025-08-29] 反映した変更（要約）
     - individuals.user_uuid を「担当者記録」用途に降格（NULL可, ON DELETE SET NULL）
       + 担当者名テキスト responsible_user_name を追加
     - visits.farm_uuid → farms.uuid に FK を新設（ON UPDATE CASCADE / ON DELETE RESTRICT）
     - checkups.visit_uuid → visits.uuid を ON DELETE SET NULL（NULL許容）へ変更
     - individuals.farm_uuid → farms.uuid は CASCADE/RESTRICT のまま（維持）
     - checkups.individual_uuid → individuals.uuid は RESTRICT のまま（維持）
     - バリデーションはアプリ側アンカーロックで実施（DBトリガは追加しない）
     - 推奨インデックスの追加/明示（visit_uuid / individual_uuid / farm_uuid / list index）
   =================================================================== */

SET NAMES utf8mb4;

-- ================================================================
-- UUIDユーティリティ関数（p012系そのまま）
--   ※既存環境にある場合は DROP IF EXISTS で安全に再作成
-- ================================================================
DELIMITER $$

DROP FUNCTION IF EXISTS uuid_bin_to_hex $$
CREATE FUNCTION uuid_bin_to_hex(b BINARY(16))
RETURNS CHAR(32) DETERMINISTIC
BEGIN
  RETURN LOWER(HEX(b));
END$$

DROP FUNCTION IF EXISTS uuid_hex_to_bin $$
CREATE FUNCTION uuid_hex_to_bin(s VARCHAR(36))
RETURNS BINARY(16) DETERMINISTIC
BEGIN
  RETURN UNHEX(REPLACE(LOWER(s), '-', ''));
END$$

DROP FUNCTION IF EXISTS uuid_v7_str $$
CREATE FUNCTION uuid_v7_str()
RETURNS CHAR(36) NOT DETERMINISTIC
BEGIN
  DECLARE ts_ms BIGINT UNSIGNED;
  DECLARE ts_hex CHAR(12);
  DECLARE r12 INT UNSIGNED;
  DECLARE ver_hi CHAR(4);
  DECLARE var_hi CHAR(4);
  DECLARE tail CHAR(12);
  DECLARE t_hi CHAR(8);
  DECLARE t_mid CHAR(4);

  SET ts_ms = CAST(ROUND(UNIX_TIMESTAMP(CURRENT_TIMESTAMP(3))*1000) AS UNSIGNED);
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
RETURNS BINARY(16) NOT DETERMINISTIC
BEGIN
  RETURN uuid_hex_to_bin(uuid_v7_str());
END$$
DELIMITER ;

-- ================================================================
-- 再デプロイ安全化（既存オブジェクトDROP）
--   ※「既存のものは変更せず含める」方針に沿い、各テーブル定義内の
--     トリガは元DDLの内容を踏襲して再定義します。
-- ================================================================
DROP VIEW  IF EXISTS checkups_hex_v;
DROP VIEW  IF EXISTS individuals_hex_v;

DROP TRIGGER IF EXISTS tr_individuals_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_individuals_bu_rowver;
DROP TRIGGER IF EXISTS bi_visits_uuid;
DROP TRIGGER IF EXISTS bu_visits_rowver;
DROP TRIGGER IF EXISTS tr_checkups_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_checkups_bu_rowver;
DROP TRIGGER IF EXISTS tr_checkup_items_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_checkup_items_bu_rowver;

DROP TABLE IF EXISTS checkup_items;
DROP TABLE IF EXISTS checkups;
DROP TABLE IF EXISTS visits;
DROP TABLE IF EXISTS individuals;

-- ================================================================
-- individuals（p014.1 をベースに変更適用）
--   - user_uuid: 担当者記録用に降格（NULL可, ON DELETE SET NULL）
--   - responsible_user_name: 担当者名をテキスト保持（UI表示/監査用）
--   - 既存のUUID自動採番/row_versionトリガは「変更せず」含める
--   - FK: farm_uuid → farms.uuid は CASCADE/RESTRICT のまま
-- ================================================================
CREATE TABLE individuals (
  id                    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,         -- サロゲートPK
  uuid                  BINARY(16) NOT NULL UNIQUE,                      -- UUIDv7(bin16)（アプリ/既存TRGで採番）
  farm_uuid             BINARY(16) NOT NULL,                             -- ↔ farms.uuid
  user_uuid             BINARY(16) NULL,                                 -- [p014.2][降格] 担当者UUID（NULL可）
  responsible_user_name VARCHAR(100) NULL,                               -- [p014.2][new] 担当者名（自由記述）

  name                  VARCHAR(100) NULL,
  ear_tag               CHAR(10) NULL,                                   -- 全国一意10桁（NULL可）
  status                ENUM('active','sold','dead','culled') NOT NULL DEFAULT 'active',
  gender                ENUM('female','male','cast','unknown') NOT NULL DEFAULT 'unknown',
  birth_date            DATE NULL,
  death_date            DATE NULL,

  sire_name             VARCHAR(100) NULL,                               -- 父はメモのみ（FKなし）

  genetic_dam_uuid      BINARY(16) NULL,                                 -- 自己参照（遺伝母）
  nursing_dam_uuid      BINARY(16) NULL,                                 -- 自己参照（哺育母）

  -- 母確定時スナップ（帳票/検索）
  genetic_dam_ear_tag   CHAR(10) NULL,
  genetic_dam_name      VARCHAR(100) NULL,
  nursing_dam_ear_tag   CHAR(10) NULL,
  nursing_dam_name      VARCHAR(100) NULL,

  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at            DATETIME NULL,                                   -- ソフトデリート
  row_version           BIGINT UNSIGNED NOT NULL DEFAULT 1,              -- 楽観ロック（既存TRGで+1）

  UNIQUE KEY uq_individuals_ear_tag (ear_tag),

  -- 推奨インデックス
  KEY idx_individuals_farm_name   (farm_uuid, name),
  KEY idx_individuals_farm_birth  (farm_uuid, birth_date),
  KEY idx_individuals_farm_status (farm_uuid, status),
  KEY idx_individuals_genetic_dam (genetic_dam_uuid),
  KEY idx_individuals_nursing_dam (nursing_dam_uuid),
  KEY idx_individuals_list        (deleted_at, updated_at, id),

  -- 外部キー
  CONSTRAINT fk_individuals_farm_uuid
    FOREIGN KEY (farm_uuid) REFERENCES farms(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,                    -- （維持）

  CONSTRAINT fk_individuals_user_uuid                        -- [p014.2] 降格（null可/削除時null）
    FOREIGN KEY (user_uuid) REFERENCES users(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL,

  -- 自己参照FK（母リンク）
  CONSTRAINT fk_individuals_genetic_dam
    FOREIGN KEY (genetic_dam_uuid) REFERENCES individuals(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_individuals_nursing_dam
    FOREIGN KEY (nursing_dam_uuid) REFERENCES individuals(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL,

  -- 自傷防止（母=自分は禁止）
  CONSTRAINT chk_individuals_no_self_genetic
    CHECK (genetic_dam_uuid IS NULL OR genetic_dam_uuid <> uuid),
  CONSTRAINT chk_individuals_no_self_nursing
    CHECK (nursing_dam_uuid IS NULL OR nursing_dam_uuid <> uuid)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  ROW_FORMAT=DYNAMIC;

-- 既存の individuals トリガ（p014.1のまま）――変更せず再定義
DELIMITER $$
CREATE TRIGGER tr_individuals_bi_uuid_v7
BEFORE INSERT ON individuals
FOR EACH ROW
BEGIN
  -- uuid 未指定/全ゼロなら UUIDv7(bin16) を自動採番
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$

CREATE TRIGGER tr_individuals_bu_rowver
BEFORE UPDATE ON individuals
FOR EACH ROW
BEGIN
  -- row_version を自動加算（アプリの楽観ロックと整合）
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;

-- 可読ビュー（HEX表示）
CREATE OR REPLACE VIEW individuals_hex_v AS
SELECT
  id,
  uuid_bin_to_hex(uuid)        AS uuid_hex,
  uuid_bin_to_hex(farm_uuid)   AS farm_uuid_hex,
  uuid_bin_to_hex(user_uuid)   AS user_uuid_hex,
  responsible_user_name,
  name, ear_tag, status, gender, birth_date, death_date, sire_name,
  uuid_bin_to_hex(genetic_dam_uuid)  AS genetic_dam_uuid_hex,
  genetic_dam_ear_tag, genetic_dam_name,
  uuid_bin_to_hex(nursing_dam_uuid)  AS nursing_dam_uuid_hex,
  nursing_dam_ear_tag, nursing_dam_name,
  deleted_at, created_at, updated_at
FROM individuals;

-- ================================================================
-- visits（visits.draft をベースに FKを追加）
--   - farm_uuid → farms.uuid に FK 新設（CASCADE/RESTRICT）
--   - 既存のUUID自動採番/row_versionトリガは「変更せず」含める
-- ================================================================
CREATE TABLE visits (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid             BINARY(16) NOT NULL UNIQUE,          -- UUIDv7(bin16)
  farm_uuid        BINARY(16) NOT NULL,                 -- ↔ farms.uuid（本版でFK化）
  visit_started_at DATETIME NOT NULL,                   -- UTC保存（表示はアプリTZ）
  visit_ended_at   DATETIME NULL,
  location_text    VARCHAR(180) NULL,
  note             VARCHAR(255) NULL,
  row_version      BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at       DATETIME NULL,
  created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  -- 推奨インデックス
  KEY idx_visits_farm             (farm_uuid),                   -- [p014.2][add] farm絞り
  KEY idx_visits_farm_started     (farm_uuid, visit_started_at),
  KEY idx_visits_started          (visit_started_at),
  KEY idx_visits_list             (deleted_at, updated_at, id),

  -- 新設FK：未登録farmへのvisitを物理的に防止
  CONSTRAINT fk_visits_farm_uuid
    FOREIGN KEY (farm_uuid) REFERENCES farms(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  ROW_FORMAT=DYNAMIC;

-- 既存の visits トリガ（visits.draftのまま）――変更せず再定義
DELIMITER $$
CREATE TRIGGER bi_visits_uuid
BEFORE INSERT ON visits
FOR EACH ROW
BEGIN
  -- uuid 未指定/全ゼロは自動採番、開始時刻未指定はUTC現在
  IF NEW.uuid IS NULL OR NEW.uuid = 0x00000000000000000000000000000000 THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
  IF NEW.visit_started_at IS NULL THEN
    SET NEW.visit_started_at = UTC_TIMESTAMP();
  END IF;
END$$

CREATE TRIGGER bu_visits_rowver
BEFORE UPDATE ON visits
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;

-- ================================================================
-- checkups / checkup_items（checkups_p012.2 をベースに変更適用）
--   - checkups.visit_uuid: NULL許容 + ON DELETE SET NULL（visit削除で接続解除）
--   - checkups.individual_uuid: RESTRICT のまま
--   - 既存のUUID自動採番/row_versionトリガは「変更せず」含める
--   - chart_header_uuid は弱リンク（FKなし、索引のみ）＊元ポリシー踏襲
-- ================================================================
CREATE TABLE checkups (
  id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid              BINARY(16) NOT NULL UNIQUE,        -- UUIDv7(bin16)

  visit_uuid        BINARY(16) NULL,                   -- [p014.2] NULL許容へ変更
  individual_uuid   BINARY(16) NOT NULL,               -- ↔ individuals.uuid (RESTRICT)
  chart_header_uuid BINARY(16) NULL,                   -- 弱リンク（FKなし）

  -- SOAP
  s_subjective      TEXT NULL,
  o_objective       TEXT NULL,
  a_assessment      TEXT NULL,
  p_plan            TEXT NULL,

  -- TPR
  temp_c            DECIMAL(4,1) NULL,
  pulse_bpm         SMALLINT UNSIGNED NULL,
  resp_bpm          SMALLINT UNSIGNED NULL,

  -- 現症・経過
  clinical_course   TEXT NULL,

  -- 請求/運用
  claim_exclusion       ENUM('none','no_insurance','manual') NOT NULL DEFAULT 'none',
  has_insurance_cached  TINYINT(1) NOT NULL DEFAULT 0,
  status                ENUM('draft','ready') NOT NULL DEFAULT 'draft',
  created_by            INT UNSIGNED NULL,

  row_version       BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at        DATETIME NULL,
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  -- 推奨インデックス
  INDEX idx_checkups_visit           (visit_uuid),                      -- 割当/未割当の切替
  INDEX idx_checkups_individual      (individual_uuid),                 -- JOIN用
  INDEX idx_checkups_visit_ind_crt   (visit_uuid, individual_uuid, created_at),
  INDEX idx_checkups_visit_ind_uuid  (visit_uuid, individual_uuid, uuid),
  INDEX idx_checkups_chart_header    (chart_header_uuid),               -- 弱リンク用
  KEY   idx_checkups_list            (deleted_at, updated_at, id),      -- 安定一覧・差分

  -- 外部キー
  CONSTRAINT fk_checkups_visit_uuid
    FOREIGN KEY (visit_uuid) REFERENCES visits(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL,  -- [p014.2] visit削除で接続解除
  CONSTRAINT fk_checkups_individual_uuid
    FOREIGN KEY (individual_uuid) REFERENCES individuals(uuid)
    ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE       = utf8mb4_unicode_ci
  ROW_FORMAT    = DYNAMIC;

CREATE TABLE checkup_items (
  id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                 BINARY(16) NOT NULL UNIQUE,     -- UUIDv7(bin16)
  checkup_uuid         BINARY(16) NOT NULL,            -- ↔ checkups.uuid
  treatment_uuid       BINARY(16) NULL,                -- 任意参照
  description          VARCHAR(255) NOT NULL,
  qty_unit             VARCHAR(32) NULL,
  quantity             DECIMAL(10,2) NOT NULL DEFAULT 1,
  pay_type             ENUM('insurance','private') NOT NULL,
  unit_b_points        INT UNSIGNED NOT NULL DEFAULT 0,
  unit_a_points        INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_points      INT UNSIGNED NOT NULL DEFAULT 0,
  yen_per_point        DECIMAL(8,2) NOT NULL DEFAULT 0.00,
  unit_price_yen       INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_price_yen   INT UNSIGNED NOT NULL DEFAULT 0,
  tax_rate             DECIMAL(4,2) NOT NULL DEFAULT 0.00,
  subtotal_yen         INT UNSIGNED NOT NULL DEFAULT 0,

  row_version          BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at           DATETIME NULL,
  created_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  -- 推奨インデックス
  INDEX idx_checkup_items_parent (checkup_uuid, pay_type),
  KEY   idx_checkup_items_list   (deleted_at, updated_at, id),

  CONSTRAINT fk_checkup_items_checkup
    FOREIGN KEY (checkup_uuid) REFERENCES checkups(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE       = utf8mb4_unicode_ci
  ROW_FORMAT    = DYNAMIC;

-- 既存の checkups / checkup_items トリガ（p012.2のまま）――変更せず再定義
DELIMITER $$
CREATE TRIGGER tr_checkups_bi_uuid_v7
BEFORE INSERT ON checkups
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$

CREATE TRIGGER tr_checkups_bu_rowver
BEFORE UPDATE ON checkups
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$

CREATE TRIGGER tr_checkup_items_bi_uuid_v7
BEFORE INSERT ON checkup_items
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$

CREATE TRIGGER tr_checkup_items_bu_rowver
BEFORE UPDATE ON checkup_items
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;

-- 可読ビュー（HEX表示）
CREATE OR REPLACE VIEW checkups_hex_v AS
SELECT
  id,
  uuid_bin_to_hex(uuid)            AS uuid_hex,
  uuid_bin_to_hex(visit_uuid)      AS visit_uuid_hex,
  uuid_bin_to_hex(individual_uuid) AS individual_uuid_hex,
  uuid_bin_to_hex(chart_header_uuid) AS chart_header_uuid_hex,
  s_subjective, o_objective, a_assessment, p_plan,
  temp_c, pulse_bpm, resp_bpm,
  clinical_course,
  claim_exclusion, has_insurance_cached, status, created_by,
  deleted_at, created_at, updated_at
FROM checkups;
