SET NAMES utf8mb4;

/* ===================================================================
   vetDB — p014.4 改版（CSIFH-PureMirror v1 適用）
   -------------------------------------------------------------------
   目的（多病院対応 / 履歴固定）:
   - 各実データ行に clinic_uuid を「当時値」として固定保存。
   - 親の clinic_uuid を BEFORE INSERT トリガで継承（事後更新はしない）。
   - これにより、後から farms の所属クリニックを付け替えても、
     過去データの「属していた院」で高速絞り込みが可能。

   既存の保険方針は維持:
   - 非加入牧場では checkup_items.pay_type は UIで private 固定。
   - 加入牧場では insurance を優先表示（UI）。
   - DB側の保険ガードは非実装（APIで insurance 選択時のみJOIN検証）。

   依存:
   - clinics(uuid BINARY(16) PK) が存在すること（p018.2 等）。
   - farms に clinic_uuid BINARY(16) NOT NULL（FK→clinics(uuid)）が存在すること。

   注意:
   - 本DDLは新規インストール想定。再デプロイ簡略化のため DROP を先行。
   - 既存環境へは「列追加＋移行UPDATE＋トリガ追加」の順で段階適用すること。
   =================================================================== */

/* ================================================================
   再デプロイ安全化（存在すればDROP）
   - farms/users/clinics等の親は既存運用前提のため DROP しない
   ================================================================ */
DROP VIEW IF EXISTS checkups_insurance_context_v;
DROP VIEW IF EXISTS checkups_hex_v;
DROP VIEW IF EXISTS individuals_hex_v;

DROP TRIGGER IF EXISTS tr_individuals_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_individuals_bu_rowver;
DROP TRIGGER IF EXISTS tr_individuals_bi_clinic;

DROP TRIGGER IF EXISTS bi_visits_uuid;
DROP TRIGGER IF EXISTS bu_visits_rowver;
DROP TRIGGER IF EXISTS tr_visits_bi_clinic;

DROP TRIGGER IF EXISTS tr_checkups_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_checkups_bu_rowver;
DROP TRIGGER IF EXISTS tr_checkups_bi_clinic;

DROP TRIGGER IF EXISTS tr_checkup_items_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_checkup_items_bu_rowver;
DROP TRIGGER IF EXISTS tr_checkup_items_bi_clinic;

DROP TABLE IF EXISTS checkup_items;
DROP TABLE IF EXISTS checkups;
DROP TABLE IF EXISTS visits;
DROP TABLE IF EXISTS individuals;

/* receipt_header_drafts は FK整合のための最小スタブ（本番は p017 正式DDLで置換） */
DROP TABLE IF EXISTS receipt_header_drafts;

/* ================================================================
   UUIDユーティリティ関数（p012系踏襲）
   ================================================================ */
DELIMITER $$

DROP FUNCTION IF EXISTS uuid_bin_to_hex $$
CREATE FUNCTION uuid_bin_to_hex(b BINARY(16)) RETURNS CHAR(32) DETERMINISTIC
BEGIN
  RETURN LOWER(HEX(b));
END$$

DROP FUNCTION IF EXISTS uuid_hex_to_bin $$
CREATE FUNCTION uuid_hex_to_bin(s VARCHAR(36)) RETURNS BINARY(16) DETERMINISTIC
BEGIN
  RETURN UNHEX(REPLACE(LOWER(s), '-', ''));
END$$

DROP FUNCTION IF EXISTS uuid_v7_str $$
CREATE FUNCTION uuid_v7_str() RETURNS CHAR(36) NOT DETERMINISTIC
BEGIN
  /* 擬似 UUIDv7: ミリ秒エポック + 乱数（検証用） */
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
  SET r12 = FLOOR(RAND()*POW(2,12));
  SET ver_hi = CONCAT('7', LPAD(HEX(r12),3,'0'));
  SET var_hi = CONCAT(ELT(FLOOR(RAND()*4)+1,'8','9','a','b'), LPAD(HEX(FLOOR(RAND()*POW(2,12))),3,'0'));
  SET tail = LPAD(HEX(FLOOR(RAND()*POW(2,48))),12,'0');

  SET t_hi = LEFT(ts_hex,8);
  SET t_mid = SUBSTRING(ts_hex,9,4);
  RETURN LOWER(CONCAT(t_hi,'-',t_mid,'-',ver_hi,'-',var_hi,'-',tail));
END$$

DROP FUNCTION IF EXISTS uuid_v7_bin $$
CREATE FUNCTION uuid_v7_bin() RETURNS BINARY(16) NOT DETERMINISTIC
BEGIN
  RETURN uuid_hex_to_bin(uuid_v7_str());
END$$

DELIMITER ;

/* ================================================================
   individuals
   ------------------------------------------------
   - clinic_uuid: 親farmsの当時値を固定保存（BI継承）。
   - farm_uuid: ON UPDATE CASCADE / ON DELETE RESTRICT。
   - 母参照: 自己参照分離・自己リンク禁止CHECK。
   - row_version: 楽観ロック。
   - 院用索引: idx_individuals_clinic(clinic_uuid, id)
   ================================================================ */
CREATE TABLE individuals (
  id                    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                  BINARY(16) NOT NULL UNIQUE,
  clinic_uuid           BINARY(16) NOT NULL,   -- ★ CSIFH: 所属院（履歴固定）
  farm_uuid             BINARY(16) NOT NULL,   -- ↔ farms.uuid
  user_uuid             BINARY(16) NULL,       -- ↔ users.uuid（担当メモ）
  name                  VARCHAR(100) NULL,
  ear_tag               CHAR(10) NULL,         -- 全国一意10桁（NULL可）
  status                ENUM('active','sold','dead','culled') NOT NULL DEFAULT 'active',
  gender                ENUM('female','male','cast','unknown') NOT NULL DEFAULT 'unknown',
  birth_date            DATE NULL,
  death_date            DATE NULL,
  sire_name             VARCHAR(100) NULL,     -- 父は名称メモのみ
  genetic_dam_uuid      BINARY(16) NULL,       -- 自己参照（遺伝母）
  nursing_dam_uuid      BINARY(16) NULL,       -- 自己参照（哺育母）
  genetic_dam_ear_tag   CHAR(10) NULL,
  genetic_dam_name      VARCHAR(100) NULL,
  nursing_dam_ear_tag   CHAR(10) NULL,
  nursing_dam_name      VARCHAR(100) NULL,
  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at            DATETIME NULL,
  row_version           BIGINT UNSIGNED NOT NULL DEFAULT 1,

  UNIQUE KEY uq_individuals_ear_tag (ear_tag),
  KEY idx_individuals_farm_name (farm_uuid, name),
  KEY idx_individuals_farm_birth (farm_uuid, birth_date),
  KEY idx_individuals_farm_status (farm_uuid, status),
  KEY idx_individuals_genetic_dam (genetic_dam_uuid),
  KEY idx_individuals_nursing_dam (nursing_dam_uuid),
  KEY idx_individuals_list (deleted_at, updated_at, id),
  KEY idx_individuals_clinic (clinic_uuid, id),

  CONSTRAINT fk_individuals_clinic_uuid   FOREIGN KEY (clinic_uuid)  REFERENCES clinics(uuid)    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_individuals_farm_uuid     FOREIGN KEY (farm_uuid)    REFERENCES farms(uuid)      ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_individuals_user_uuid     FOREIGN KEY (user_uuid)    REFERENCES users(uuid)      ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_individuals_genetic_dam   FOREIGN KEY (genetic_dam_uuid)  REFERENCES individuals(uuid) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_individuals_nursing_dam   FOREIGN KEY (nursing_dam_uuid)  REFERENCES individuals(uuid) ON UPDATE CASCADE ON DELETE SET NULL,
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

  /* CSIFH: 親farmsの clinic_uuid を継承（履歴固定） */
  IF NEW.clinic_uuid IS NULL OR NEW.clinic_uuid = UNHEX(REPEAT('0',32)) THEN
    SELECT f.clinic_uuid INTO @cu FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
    SET NEW.clinic_uuid = @cu;
  END IF;
END$$

CREATE TRIGGER tr_individuals_bu_rowver
BEFORE UPDATE ON individuals
FOR EACH ROW
BEGIN
  /* 履歴固定方針のため clinic_uuid は自動更新しない（必要時はアプリで明示更新） */
  SET NEW.row_version = OLD.row_version + 1;
END$$

DELIMITER ;

/* 可読HEXビュー（clinic_uuid_hex を追加） */
CREATE OR REPLACE VIEW individuals_hex_v AS
SELECT
  id,
  uuid_bin_to_hex(uuid)         AS uuid_hex,
  uuid_bin_to_hex(clinic_uuid)  AS clinic_uuid_hex,
  uuid_bin_to_hex(farm_uuid)    AS farm_uuid_hex,
  uuid_bin_to_hex(user_uuid)    AS user_uuid_hex,
  name, ear_tag, status, gender, birth_date, death_date, sire_name,
  uuid_bin_to_hex(genetic_dam_uuid)  AS genetic_dam_uuid_hex,
  genetic_dam_ear_tag, genetic_dam_name,
  uuid_bin_to_hex(nursing_dam_uuid)  AS nursing_dam_uuid_hex,
  nursing_dam_ear_tag, nursing_dam_name,
  deleted_at, created_at, updated_at
FROM individuals;

/* ================================================================
   visits
   ------------------------------------------------
   - clinic_uuid: 親farmsの当時値を固定保存（BI継承）。
   - visit_started_at: NULLならUTC現在時刻に初期化。
   - 院用索引: idx_visits_clinic(clinic_uuid, visit_started_at)
   ================================================================ */
CREATE TABLE visits (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid             BINARY(16) NOT NULL UNIQUE,
  clinic_uuid      BINARY(16) NOT NULL,   -- ★ CSIFH
  farm_uuid        BINARY(16) NOT NULL,   -- ↔ farms.uuid
  visit_started_at DATETIME NOT NULL,
  visit_ended_at   DATETIME NULL,
  location_text    VARCHAR(180) NULL,
  note             VARCHAR(255) NULL,
  row_version      BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at       DATETIME NULL,
  created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  KEY idx_visits_farm (farm_uuid),
  KEY idx_visits_farm_started (farm_uuid, visit_started_at),
  KEY idx_visits_started (visit_started_at),
  KEY idx_visits_list (deleted_at, updated_at, id),
  KEY idx_visits_clinic (clinic_uuid, visit_started_at),

  CONSTRAINT fk_visits_clinic_uuid FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_visits_farm_uuid   FOREIGN KEY (farm_uuid)   REFERENCES farms(uuid)   ON UPDATE CASCADE ON DELETE RESTRICT
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

  /* CSIFH: 親farmsの clinic_uuid を継承（履歴固定） */
  IF NEW.clinic_uuid IS NULL OR NEW.clinic_uuid = UNHEX(REPEAT('0',32)) THEN
    SELECT f.clinic_uuid INTO @cu FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
    SET NEW.clinic_uuid = @cu;
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
   checkups
   ------------------------------------------------
   - clinic_uuid: 優先 visit から、無ければ individual から継承（履歴固定）。
   - visit_uuid: NULL許容（親visit削除時は SET NULL）。
   - receipt_header_drafts_uuid: p017 直付け方針を維持。
   - 院用索引: idx_checkups_clinic(clinic_uuid, created_at)
   ================================================================ */
CREATE TABLE checkups (
  id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid         BINARY(16) NOT NULL UNIQUE,
  clinic_uuid  BINARY(16) NOT NULL,          -- ★ CSIFH
  visit_uuid   BINARY(16) NULL,              -- ↔ visits.uuid（SET NULL）
  individual_uuid BINARY(16) NOT NULL,       -- ↔ individuals.uuid（RESTRICT）

  /* p017: レシート草稿への直付け（草稿削除で自動デタッチ） */
  receipt_header_drafts_uuid BINARY(16) NULL, -- ↔ receipt_header_drafts.uuid

  /* 将来の確定カルテ弱リンク（FKなし） */
  chart_header_uuid BINARY(16) NULL,

  /* SOAP */
  s_subjective TEXT NULL,
  o_objective  TEXT NULL,
  a_assessment TEXT NULL,
  p_plan       TEXT NULL,

  /* TPR */
  temp_c     DECIMAL(4,1) NULL,
  pulse_bpm  SMALLINT UNSIGNED NULL,
  resp_bpm   SMALLINT UNSIGNED NULL,

  /* 現症・経過 */
  clinical_course TEXT NULL,

  /* 運用 */
  status      ENUM('draft','ready') NOT NULL DEFAULT 'draft',
  created_by  INT UNSIGNED NULL,
  row_version BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at  DATETIME NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  /* 索引 */
  INDEX idx_checkups_visit (visit_uuid),
  INDEX idx_checkups_individual (individual_uuid),
  INDEX idx_checkups_visit_ind_crt (visit_uuid, individual_uuid, created_at),
  INDEX idx_checkups_visit_ind_uuid (visit_uuid, individual_uuid, uuid),
  INDEX idx_checkups_chart_header (chart_header_uuid),
  KEY   idx_checkups_list (deleted_at, updated_at, id),
  KEY   idx_checkups_rhd (receipt_header_drafts_uuid, id),
  KEY   idx_checkups_clinic (clinic_uuid, created_at),

  /* 外部キー */
  CONSTRAINT fk_checkups_clinic_uuid   FOREIGN KEY (clinic_uuid)  REFERENCES clinics(uuid)     ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_checkups_visit_uuid    FOREIGN KEY (visit_uuid)   REFERENCES visits(uuid)      ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_checkups_individual_uuid FOREIGN KEY (individual_uuid) REFERENCES individuals(uuid) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_checkups_rhd           FOREIGN KEY (receipt_header_drafts_uuid) REFERENCES receipt_header_drafts(uuid) ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci ROW_FORMAT = DYNAMIC;

DELIMITER $$

CREATE TRIGGER tr_checkups_bi_uuid_v7
BEFORE INSERT ON checkups
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;

  /* CSIFH: 優先 visit.clinic_uuid → 無ければ individual.clinic_uuid を継承 */
  IF NEW.clinic_uuid IS NULL OR NEW.clinic_uuid = UNHEX(REPEAT('0',32)) THEN
    IF NEW.visit_uuid IS NOT NULL THEN
      SELECT v.clinic_uuid INTO @cu FROM visits v WHERE v.uuid = NEW.visit_uuid LIMIT 1;
    ELSE
      SELECT i.clinic_uuid INTO @cu FROM individuals i WHERE i.uuid = NEW.individual_uuid LIMIT 1;
    END IF;
    SET NEW.clinic_uuid = @cu;
  END IF;
END$$

CREATE TRIGGER tr_checkups_bu_rowver
BEFORE UPDATE ON checkups
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$

DELIMITER ;

/* 可読HEXビュー（clinic_uuid_hex を追加） */
CREATE OR REPLACE VIEW checkups_hex_v AS
SELECT
  id,
  uuid_bin_to_hex(uuid)         AS uuid_hex,
  uuid_bin_to_hex(clinic_uuid)  AS clinic_uuid_hex,
  uuid_bin_to_hex(visit_uuid)   AS visit_uuid_hex,
  uuid_bin_to_hex(individual_uuid) AS individual_uuid_hex,
  uuid_bin_to_hex(chart_header_uuid) AS chart_header_uuid_hex,
  s_subjective, o_objective, a_assessment, p_plan,
  temp_c, pulse_bpm, resp_bpm, clinical_course,
  status, created_by, deleted_at, created_at, updated_at
FROM checkups;

/* ================================================================
   checkup_items
   ------------------------------------------------
   - clinic_uuid: 親checkupsの当時値を固定保存（BI継承）。
   - 保険/自費の両立カラムは据え置き。DEFAULT 'private' 推奨。
   - 院用索引: idx_checkup_items_clinic(clinic_uuid, id)
   ================================================================ */
CREATE TABLE checkup_items (
  id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                BINARY(16) NOT NULL UNIQUE,
  clinic_uuid         BINARY(16) NOT NULL,   -- ★ CSIFH
  checkup_uuid        BINARY(16) NOT NULL,   -- ↔ checkups.uuid
  treatment_uuid      BINARY(16) NULL,       -- 任意参照（マスタ未確定でも可）
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
  KEY   idx_checkup_items_list (deleted_at, updated_at, id),
  KEY   idx_checkup_items_clinic (clinic_uuid, id),

  CONSTRAINT fk_checkup_items_clinic FOREIGN KEY (clinic_uuid)  REFERENCES clinics(uuid)  ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_checkup_items_checkup FOREIGN KEY (checkup_uuid) REFERENCES checkups(uuid) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci ROW_FORMAT = DYNAMIC;

DELIMITER $$

CREATE TRIGGER tr_checkup_items_bi_uuid_v7
BEFORE INSERT ON checkup_items
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;

  /* CSIFH: 親checkupsの clinic_uuid を継承（履歴固定） */
  IF NEW.clinic_uuid IS NULL OR NEW.clinic_uuid = UNHEX(REPEAT('0',32)) THEN
    SELECT c.clinic_uuid INTO @cu FROM checkups c WHERE c.uuid = NEW.checkup_uuid LIMIT 1;
    SET NEW.clinic_uuid = @cu;
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
   1) checkups_insurance_context_v:
      - checkup → individual → farm をJOINし、牧場の加入/非加入を返す。
      - UIの既定値に使う preferred_pay_type も返す。
      - 参照列は既存方針どおり簡潔に（clinic列は必要な画面のみ別途参照）。
   ================================================================ */
CREATE OR REPLACE VIEW checkups_insurance_context_v AS
SELECT
  c.uuid AS checkup_uuid,
  f.non_insured AS farm_non_insured,
  CASE WHEN f.non_insured = 1 THEN 'private' ELSE 'insurance' END AS preferred_pay_type
FROM checkups c
JOIN individuals i ON i.uuid = c.individual_uuid
JOIN farms f       ON f.uuid = i.farm_uuid;

/* ================================================================
   receipt_header_drafts — 最小スタブ
   ------------------------------------------------
   - p017 正式DDLに置換される前提。ここではFK満たすためだけにuuidを用意。
   ================================================================ */
CREATE TABLE receipt_header_drafts (
  id   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid BINARY(16) NOT NULL UNIQUE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
