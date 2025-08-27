/* =========================================================
   checkups / checkup_items — p012.1 準拠＋指定4点のみ適用
   変更点:
     1) row_version 追加（両テーブル）
     2) list index 追加（(deleted_at, updated_at, id)）
     3) ゼロUUID混入防止（0x00.. → 自動採番）
     4) ROW_FORMAT=DYNAMIC 明示
   ポリシー変更:
     - checkups.chart_header_uuid は弱いリンク（FKなし、索引のみ）
   ========================================================= */

/* ========== ユーティリティ関数（p012.1 そのまま） ========== */
DELIMITER $$
DROP FUNCTION IF EXISTS uuid_bin_to_hex $$
CREATE FUNCTION uuid_bin_to_hex(b BINARY(16)) RETURNS CHAR(32) DETERMINISTIC
BEGIN
  RETURN LOWER(HEX(b));
END$$

DROP FUNCTION IF EXISTS uuid_hex_to_bin $$
CREATE FUNCTION uuid_hex_to_bin(s VARCHAR(36)) RETURNS BINARY(16) DETERMINISTIC
BEGIN
  -- ダッシュ混在も受容
  RETURN UNHEX(REPLACE(LOWER(s), '-', ''));
END$$

DROP FUNCTION IF EXISTS uuid_v7_str $$
CREATE FUNCTION uuid_v7_str() RETURNS CHAR(36) NOT DETERMINISTIC
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

  SET r12 = FLOOR(RAND()*POW(2,12));
  SET ver_hi = CONCAT('7', LPAD(HEX(r12),3,'0'));
  SET var_hi = CONCAT(ELT(FLOOR(RAND()*4)+1,'8','9','a','b'),
                      LPAD(HEX(FLOOR(RAND()*POW(2,12))),3,'0'));
  SET tail = LPAD(HEX(FLOOR(RAND()*POW(2,48))),12,'0');

  SET t_hi  = LEFT(ts_hex,8);
  SET t_mid = SUBSTRING(ts_hex,9,4);

  RETURN LOWER(CONCAT(t_hi,'-',t_mid,'-',ver_hi,'-',var_hi,'-',tail));
END$$

DROP FUNCTION IF EXISTS uuid_v7_bin $$
CREATE FUNCTION uuid_v7_bin() RETURNS BINARY(16) NOT DETERMINISTIC
BEGIN
  RETURN uuid_hex_to_bin(uuid_v7_str());
END$$
DELIMITER ;

/* ========== 再デプロイ安全化 ========== */
DROP TRIGGER IF EXISTS tr_checkups_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_checkups_bu_rowver;
DROP VIEW    IF EXISTS checkups_hex_v;
DROP TABLE   IF EXISTS checkup_items;
DROP TABLE   IF EXISTS checkups;

/* ========== 本体テーブル：checkups（p012.1＋4点｜弱リンク） ========== */
CREATE TABLE IF NOT EXISTS checkups (
  id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

  -- 主キー相当の一意UUID（BINARY16）
  uuid              BINARY(16) NOT NULL UNIQUE,

  -- 親（BINARY16）
  visit_uuid        BINARY(16) NOT NULL,   -- ↔ visits.uuid
  individual_uuid   BINARY(16) NOT NULL,   -- ↔ individuals.uuid
  chart_header_uuid BINARY(16) NULL,       -- スナップへの弱リンク（FKなし）

  -- SOAP（p012.1 命名）
  s_subjective      TEXT NULL,
  o_objective       TEXT NULL,
  a_assessment      TEXT NULL,
  p_plan            TEXT NULL,

  -- TPR（p012.1 命名）
  temp_c            DECIMAL(4,1) NULL,           -- 体温[℃]
  pulse_bpm         SMALLINT UNSIGNED NULL,      -- 脈拍[bpm]
  resp_bpm          SMALLINT UNSIGNED NULL,      -- 呼吸[bpm]

  -- 現症・経過
  clinical_course   TEXT NULL,

  -- 請求/運用（p012.1）
  claim_exclusion       ENUM('none','no_insurance','manual') NOT NULL DEFAULT 'none',
  has_insurance_cached  TINYINT(1) NOT NULL DEFAULT 0,
  status                ENUM('draft','ready') NOT NULL DEFAULT 'draft',
  created_by            INT UNSIGNED NULL,

  /* 追加1) row_version */
  row_version       BIGINT UNSIGNED NOT NULL DEFAULT 1,

  deleted_at        DATETIME NULL,
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  -- 索引（p012.1 既存＋弱リンク用の単一列索引を追加）
  INDEX idx_checkups_visit (visit_uuid),
  INDEX idx_checkups_individual (individual_uuid),
  INDEX idx_checkups_visit_individual_created (visit_uuid, individual_uuid, created_at),
  INDEX idx_checkups_visit_individual_uuid    (visit_uuid, individual_uuid, uuid),
  INDEX idx_claim (chart_header_uuid, claim_exclusion, has_insurance_cached, individual_uuid),
  INDEX idx_checkups_chart_header (chart_header_uuid),  -- ★弱リンク用の単一列索引

  /* 追加2) list index */
  KEY   idx_checkups_list (deleted_at, updated_at, id),

  -- 外部キー（chart_header_uuid 以外は従来通り）
  CONSTRAINT fk_checkups_visit_uuid
    FOREIGN KEY (visit_uuid)      REFERENCES visits(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_checkups_individual_uuid
    FOREIGN KEY (individual_uuid) REFERENCES individuals(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT

  -- ★chart_header_uuid へのFKは張らない（弱リンク）
) ENGINE=InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

/* ========== BEFORE INSERT: uuid 未指定/ゼロなら v7 自動付与（変更点3） ========== */
DELIMITER $$
CREATE TRIGGER tr_checkups_bi_uuid_v7
BEFORE INSERT ON checkups
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$

/* ========== BEFORE UPDATE: row_version 自動インクリメント（変更点1） ========== */
CREATE TRIGGER tr_checkups_bu_rowver
BEFORE UPDATE ON checkups
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;

/* ========== 明細テーブル：checkup_items（p012.1＋4点） ========== */
CREATE TABLE IF NOT EXISTS checkup_items (
  id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                 BINARY(16) NOT NULL UNIQUE,

  checkup_uuid         BINARY(16) NOT NULL,  -- ↔ checkups.uuid
  treatment_uuid       BINARY(16) NULL,      -- 任意参照

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

  /* 追加1) row_version */
  row_version          BIGINT UNSIGNED NOT NULL DEFAULT 1,

  deleted_at           DATETIME NULL,
  created_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  INDEX idx_checkup_items_parent (checkup_uuid, pay_type),

  /* 追加2) list index */
  KEY   idx_checkup_items_list (deleted_at, updated_at, id),

  CONSTRAINT fk_checkup_items_checkup
    FOREIGN KEY (checkup_uuid) REFERENCES checkups(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
/* ========== BEFORE INSERT: uuid 未指定/ゼロなら v7 自動付与（変更点3） ========== */
CREATE TRIGGER tr_checkup_items_bi_uuid_v7
BEFORE INSERT ON checkup_items
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$

/* ========== BEFORE UPDATE: row_version 自動インクリメント（変更点1） ========== */
CREATE TRIGGER tr_checkup_items_bu_rowver
BEFORE UPDATE ON checkup_items
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;

/* ========== 可読ビュー（p012.1 そのまま） ========== */
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
  claim_exclusion, has_insurance_cached, status, created_by,
  deleted_at, created_at, updated_at
FROM checkups;
