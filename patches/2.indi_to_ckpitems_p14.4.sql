/* ===================================================================
   vetDB — p014.3 改版（非加入＝常に自費／UI優先・DB最小）
   -------------------------------------------------------------------
   目的:
     - 非加入牧場では checkup_items.pay_type を private 固定（UI）。
     - 加入牧場では insurance を優先表示（UI）。
     - DB は最小構成：UUID/row_version のみトリガ、保険ガードは行わない。
     - アプリ層（API）で insurance 選択時のみ非加入を1回JOIN検証。

   主な変更:
     - farms に non_insured を追加（牧場単位の既定ポリシー）。
     - checkups から claim_exclusion / has_insurance_cached を削除（廃止）。
     - checkup_items.pay_type は ENUM('insurance','private') のまま、DEFAULT 'private' を推奨。
     - ビュー checkups_insurance_context_v を新設（UIの初期値/制御用）。
     - p017 の receipt_header_drafts_uuid は維持（FKあり）。本DDLでは最小スタブを併設。

   ノート:
     - 文字コード/照合順序/ROW_FORMAT は p012+ 系の既定を踏襲。
     - UTC 保存・表示はアプリ側でタイムゾーン変換。
   =================================================================== */

SET NAMES utf8mb4;

/* ================================================================
   再デプロイ安全化（存在すれば削除）
   - farms/users は既存運用前提のため DROP しない
   ================================================================ */
DROP VIEW    IF EXISTS checkups_insurance_context_v;
DROP VIEW    IF EXISTS checkups_hex_v;
DROP VIEW    IF EXISTS individuals_hex_v;

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

/* receipt_header_drafts は FK整合のためスタブ同梱（本番は p017 正式DDLに置換） */
DROP TABLE IF EXISTS receipt_header_drafts;

/* ================================================================
   UUIDユーティリティ関数（p012系）
   - BINARY(16) を基本とし、HEX表示/変換/UUIDv7生成を提供
   ================================================================ */
DELIMITER $$

DROP FUNCTION IF EXISTS uuid_bin_to_hex $$
CREATE FUNCTION uuid_bin_to_hex(b BINARY(16)) RETURNS CHAR(32)
DETERMINISTIC
BEGIN
  RETURN LOWER(HEX(b));
END$$

DROP FUNCTION IF EXISTS uuid_hex_to_bin $$
CREATE FUNCTION uuid_hex_to_bin(s VARCHAR(36)) RETURNS BINARY(16)
DETERMINISTIC
BEGIN
  RETURN UNHEX(REPLACE(LOWER(s), '-', ''));
END$$

DROP FUNCTION IF EXISTS uuid_v7_str $$
CREATE FUNCTION uuid_v7_str() RETURNS CHAR(36)
NOT DETERMINISTIC
BEGIN
  /* 擬似 UUIDv7: ミリ秒エポック + 乱数（検証用）。
     実運用はDB/アプリ側で正式実装に置換可。 */
  DECLARE ts_ms BIGINT UNSIGNED;
  DECLARE ts_hex CHAR(12);
  DECLARE r12 INT UNSIGNED;
  DECLARE ver_hi CHAR(4);
  DECLARE var_hi CHAR(4);
  DECLARE tail CHAR(12);
  DECLARE t_hi CHAR(8);
  DECLARE t_mid CHAR(4);

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
CREATE FUNCTION uuid_v7_bin() RETURNS BINARY(16)
NOT DETERMINISTIC
BEGIN
  RETURN uuid_hex_to_bin(uuid_v7_str());
END$$

DELIMITER ;

/* ================================================================
   farms: 非加入既定フラグを追加（ALTER）
   ------------------------------------------------
   - 非加入の牧場は常に自費（UI固定／APIも強制）。
   - DBは IF NOT EXISTS を利用（対応版MySQL/MariaDB想定）。
   - 既に存在する場合はスキップ。
   ================================================================ */
ALTER TABLE farms
  ADD COLUMN IF NOT EXISTS non_insured TINYINT(1) NOT NULL DEFAULT 0;
-- 既存環境での重複作成を避けるため、インデックス作成は必要に応じて実行
-- CREATE INDEX idx_farms_non_insured ON farms(non_insured);

/* ================================================================
   receipt_header_drafts（p017の最小スタブ）
   ------------------------------------------------
   - checkups.receipt_header_drafts_uuid の FK 受け皿
   - 本番では p017 正式DDL（列/索引/トリガ）に差し替え
   ================================================================ */
CREATE TABLE receipt_header_drafts (
  id   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid BINARY(16) NOT NULL UNIQUE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

/* ================================================================
   individuals（p014.3 構成踏襲）
   ------------------------------------------------
   - UUID: BINARY(16) / v7想定（自動採番トリガ）
   - farm_uuid: farms.uuid（ON UPDATE CASCADE / ON DELETE RESTRICT）
   - user_uuid: 担当者メモ用途（NULL許容/ON DELETE SET NULL）
   - 母参照: genetic/nursing を分離、自己参照禁止 CHECK
   - row_version: 楽観ロック（更新ごとに +1）
   - 一覧最適化索引: (deleted_at, updated_at, id)
   ================================================================ */
CREATE TABLE individuals (
  id                    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                  BINARY(16) NOT NULL UNIQUE,
  farm_uuid             BINARY(16) NOT NULL,      -- ↔ farms.uuid
  user_uuid             BINARY(16) NULL,          -- ↔ users.uuid（任意・担当メモ）

  name                  VARCHAR(100) NULL,
  ear_tag               CHAR(10) NULL,            -- 全国一意10桁（NULL可）
  status                ENUM('active','sold','dead','culled') NOT NULL DEFAULT 'active',
  gender                ENUM('female','male','cast','unknown') NOT NULL DEFAULT 'unknown',
  birth_date            DATE NULL,
  death_date            DATE NULL,

  sire_name             VARCHAR(100) NULL,        -- 父は名称メモのみ（FKなし）

  genetic_dam_uuid      BINARY(16) NULL,          -- 自己参照（遺伝母）
  nursing_dam_uuid      BINARY(16) NULL,          -- 自己参照（哺育母）
  genetic_dam_ear_tag   CHAR(10) NULL,
  genetic_dam_name      VARCHAR(100) NULL,
  nursing_dam_ear_tag   CHAR(10) NULL,
  nursing_dam_name      VARCHAR(100) NULL,

  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at            DATETIME NULL,
  row_version           BIGINT UNSIGNED NOT NULL DEFAULT 1,

  UNIQUE KEY uq_individuals_ear_tag (ear_tag),
  KEY idx_individuals_farm_name   (farm_uuid, name),
  KEY idx_individuals_farm_birth  (farm_uuid, birth_date),
  KEY idx_individuals_farm_status (farm_uuid, status),
  KEY idx_individuals_genetic_dam (genetic_dam_uuid),
  KEY idx_individuals_nursing_dam (nursing_dam_uuid),
  KEY idx_individuals_list        (deleted_at, updated_at, id),

  CONSTRAINT fk_individuals_farm_uuid
    FOREIGN KEY (farm_uuid) REFERENCES farms(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,

  CONSTRAINT fk_individuals_user_uuid
    FOREIGN KEY (user_uuid) REFERENCES users(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL,

  CONSTRAINT fk_individuals_genetic_dam
    FOREIGN KEY (genetic_dam_uuid) REFERENCES individuals(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL,

  CONSTRAINT fk_individuals_nursing_dam
    FOREIGN KEY (nursing_dam_uuid) REFERENCES individuals(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL,

  CONSTRAINT chk_individuals_no_self_genetic CHECK (genetic_dam_uuid IS NULL OR genetic_dam_uuid <> uuid),
  CONSTRAINT chk_individuals_no_self_nursing CHECK (nursing_dam_uuid IS NULL OR nursing_dam_uuid <> uuid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER tr_individuals_bi_uuid_v7
BEFORE INSERT ON individuals
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$

CREATE TRIGGER tr_individuals_bu_rowver
BEFORE UPDATE ON individuals
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;

/* 読みやすいHEXビュー（API/デバッグ用） */
CREATE OR REPLACE VIEW individuals_hex_v AS
SELECT
  id,
  uuid_bin_to_hex(uuid)              AS uuid_hex,
  uuid_bin_to_hex(farm_uuid)         AS farm_uuid_hex,
  uuid_bin_to_hex(user_uuid)         AS user_uuid_hex,
  name, ear_tag, status, gender,
  birth_date, death_date, sire_name,
  uuid_bin_to_hex(genetic_dam_uuid)  AS genetic_dam_uuid_hex,
  genetic_dam_ear_tag, genetic_dam_name,
  uuid_bin_to_hex(nursing_dam_uuid)  AS nursing_dam_uuid_hex,
  nursing_dam_ear_tag, nursing_dam_name,
  deleted_at, created_at, updated_at
FROM individuals;

/* ================================================================
   visits（p014.3 構成踏襲）
   ------------------------------------------------
   - farm_uuid: 訪問先（FK）。個体farmと一致チェックはアプリ層で実施。
   - visit_started_at: 未指定時は UTC 現在時刻（BIトリガ）。
   - row_version: 楽観ロック。
   ================================================================ */
CREATE TABLE visits (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid             BINARY(16) NOT NULL UNIQUE,
  farm_uuid        BINARY(16) NOT NULL,               -- ↔ farms.uuid
  visit_started_at DATETIME NOT NULL,
  visit_ended_at   DATETIME NULL,
  location_text    VARCHAR(180) NULL,
  note             VARCHAR(255) NULL,

  row_version      BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at       DATETIME NULL,
  created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  KEY idx_visits_farm         (farm_uuid),
  KEY idx_visits_farm_started (farm_uuid, visit_started_at),
  KEY idx_visits_started      (visit_started_at),
  KEY idx_visits_list         (deleted_at, updated_at, id),

  CONSTRAINT fk_visits_farm_uuid
    FOREIGN KEY (farm_uuid) REFERENCES farms(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER bi_visits_uuid
BEFORE INSERT ON visits
FOR EACH ROW
BEGIN
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

/* ================================================================
   checkups（p014.3 改版：2列廃止／rhdは維持）
   ------------------------------------------------
   - 廃止: claim_exclusion / has_insurance_cached（UI/APIで不要化）。
   - 維持: receipt_header_drafts_uuid（p017 直付け）。
   - visit_uuid: NULL許容（訪問削除時は SET NULL）。
   - individual_uuid: 必須（個体基準）。
   - chart_header_uuid: 将来のスナップ弱リンク（FKなし）。
   - SOAP/TPR/経過: 記録用。
   ================================================================ */
CREATE TABLE checkups (
  id                 INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid               BINARY(16) NOT NULL UNIQUE,
  visit_uuid         BINARY(16) NULL,                 -- ↔ visits.uuid（SET NULL）
  individual_uuid    BINARY(16) NOT NULL,             -- ↔ individuals.uuid（RESTRICT）

  /* p017: レシート草稿への直付け（草稿削除で自動デタッチ） */
  receipt_header_drafts_uuid BINARY(16) NULL,         -- ↔ receipt_header_drafts.uuid

  /* 将来の確定カルテ弱リンク（FKなし） */
  chart_header_uuid  BINARY(16) NULL,

  /* SOAP */
  s_subjective       TEXT NULL,
  o_objective        TEXT NULL,
  a_assessment       TEXT NULL,
  p_plan             TEXT NULL,

  /* TPR */
  temp_c             DECIMAL(4,1) NULL,
  pulse_bpm          SMALLINT UNSIGNED NULL,
  resp_bpm           SMALLINT UNSIGNED NULL,

  /* 現症・経過 */
  clinical_course    TEXT NULL,

  /* 運用 */
  status             ENUM('draft','ready') NOT NULL DEFAULT 'draft',
  created_by         INT UNSIGNED NULL,

  row_version        BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at         DATETIME NULL,
  created_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  /* 索引 */
  INDEX idx_checkups_visit              (visit_uuid),
  INDEX idx_checkups_individual         (individual_uuid),
  INDEX idx_checkups_visit_ind_crt      (visit_uuid, individual_uuid, created_at),
  INDEX idx_checkups_visit_ind_uuid     (visit_uuid, individual_uuid, uuid),
  INDEX idx_checkups_chart_header       (chart_header_uuid),
  KEY   idx_checkups_list               (deleted_at, updated_at, id),
  KEY   idx_checkups_rhd                (receipt_header_drafts_uuid, id),

  /* 外部キー */
  CONSTRAINT fk_checkups_visit_uuid
    FOREIGN KEY (visit_uuid) REFERENCES visits(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL,

  CONSTRAINT fk_checkups_individual_uuid
    FOREIGN KEY (individual_uuid) REFERENCES individuals(uuid)
    ON UPDATE RESTRICT ON DELETE RESTRICT,

  CONSTRAINT fk_checkups_rhd
    FOREIGN KEY (receipt_header_drafts_uuid) REFERENCES receipt_header_drafts(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci ROW_FORMAT = DYNAMIC;

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
DELIMITER ;

/* ================================================================
   checkup_items（p014.3 構成踏襲 / DEFAULT 'private' 推奨）
   ------------------------------------------------
   - pay_type: 'insurance' / 'private'（加入→混合可、非加入→UI固定で private）
   - 非加入ガードはトリガ不採用（アプリ層で insurance 選択時のみ検証）。
   - 点数/価格の両立。row_version による楽観ロック。
   ================================================================ */
CREATE TABLE checkup_items (
  id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                BINARY(16) NOT NULL UNIQUE,
  checkup_uuid        BINARY(16) NOT NULL,             -- ↔ checkups.uuid
  treatment_uuid      BINARY(16) NULL,                 -- 任意参照（マスタ未確定でも可）

  description         VARCHAR(255) NOT NULL,
  qty_unit            VARCHAR(32) NULL,
  quantity            DECIMAL(10,2) NOT NULL DEFAULT 1,

  pay_type            ENUM('insurance','private') NOT NULL DEFAULT 'private',

  /* 点数/価格の両立 */
  unit_b_points       INT UNSIGNED NOT NULL DEFAULT 0,
  unit_a_points       INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_points     INT UNSIGNED NOT NULL DEFAULT 0,

  yen_per_point       DECIMAL(8,2) NOT NULL DEFAULT 0.00,
  unit_price_yen      INT UNSIGNED NOT NULL DEFAULT 0,
  subtotal_price_yen  INT UNSIGNED NOT NULL DEFAULT 0,

  tax_rate            DECIMAL(4,2) NOT NULL DEFAULT 0.00,
  subtotal_yen        INT UNSIGNED NOT NULL DEFAULT 0,

  row_version         BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at          DATETIME NULL,
  created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  INDEX idx_checkup_items_parent (checkup_uuid, pay_type),
  KEY   idx_checkup_items_list   (deleted_at, updated_at, id),

  CONSTRAINT fk_checkup_items_checkup
    FOREIGN KEY (checkup_uuid) REFERENCES checkups(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci ROW_FORMAT = DYNAMIC;

DELIMITER $$
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

/* ================================================================
   ビュー: UI/API 補助
   ------------------------------------------------
   1) checkups_hex_v:
      - BINARY(16) を HEX で可読化。
      - 廃止列（claim_exclusion / has_insurance_cached）は出力しない。
      - receipt_header_drafts_uuid は方針どおり非出力（内部用途）。

   2) checkups_insurance_context_v:
      - checkup → individual → farm をJOINし、牧場の加入/非加入を返す。
      - UIの既定値に使う preferred_pay_type を同時に返す。
        * 非加入  : 'private'
        * 加入    : 'insurance'
      - API では “insurance が選択された時だけ” これを参照して検証する。
   ================================================================ */
CREATE OR REPLACE VIEW checkups_hex_v AS
SELECT
  id,
  uuid_bin_to_hex(uuid)              AS uuid_hex,
  uuid_bin_to_hex(visit_uuid)        AS visit_uuid_hex,
  uuid_bin_to_hex(individual_uuid)   AS individual_uuid_hex,
  uuid_bin_to_hex(chart_header_uuid) AS chart_header_uuid_hex,
  s_subjective, o_objective, a_assessment, p_plan,
  temp_c, pulse_bpm, resp_bpm,
  clinical_course,
  status, created_by,
  deleted_at, created_at, updated_at
FROM checkups;

CREATE OR REPLACE VIEW checkups_insurance_context_v AS
SELECT
  c.uuid AS checkup_uuid,
  f.non_insured AS farm_non_insured,
  CASE WHEN f.non_insured = 1 THEN 'private' ELSE 'insurance' END AS preferred_pay_type
FROM checkups c
JOIN individuals i ON i.uuid = c.individual_uuid
JOIN farms f       ON f.uuid = i.farm_uuid;
