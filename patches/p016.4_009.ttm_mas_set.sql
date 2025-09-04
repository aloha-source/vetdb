/* =====================================================================
   vetDB treatment_* install — p016.3 (CSIFH-PureMirror v1 / FK=master-only)
   方針:
     • clinic_uuid(BINARY(16)) を全表に追加して当時値固定
     • 子表は BEFORE INSERT で clinic_uuid を親から継承（NULL時のみ）
     • clinic_uuid は全表で更新禁止（不変ガード）
     • clinics への FK は treatment_master のみに付与（他表は付与しない）
     • 院別一覧 idx_clinic_list(clinic_uuid, deleted_at, updated_at, id)
     • disease_uuid(BINARY(16)) を維持（p016.2準拠）
   変更点:
     • treatment_master.code の一意性を院別へ: UNIQUE (clinic_uuid, code)
   前提:
     • clinics(uuid), users(uuid, clinic_uuid), disease_master(uuid) が先に存在
   ===================================================================== */

SET NAMES utf8mb4;

/* 再デプロイ安全化（依存順: 子 → 親） */
DROP TRIGGER IF EXISTS bi_treatment_set_items_uuid;
DROP TRIGGER IF EXISTS bu_treatment_set_items_rowver;
DROP TRIGGER IF EXISTS bi_treatment_sets_uuid;
DROP TRIGGER IF EXISTS bu_treatment_sets_rowver;
DROP TRIGGER IF EXISTS bi_treatment_disease_rules_uuid;
DROP TRIGGER IF EXISTS bu_treatment_disease_rules_rowver;
DROP TRIGGER IF EXISTS bi_treatment_master_uuid;
DROP TRIGGER IF EXISTS bu_treatment_master_rowver;

DROP TABLE IF EXISTS treatment_set_items;
DROP TABLE IF EXISTS treatment_sets;
DROP TABLE IF EXISTS treatment_disease_rules;
DROP TABLE IF EXISTS treatment_master;

/* =====================================================================
  1) treatment_master — 処置/薬剤マスタ（ルート）
     - clinic_uuid はアプリ必須（以後、不変）
     - clinics への FK を付与（この表のみ）
     - code は院別一意 UNIQUE(clinic_uuid, code)
===================================================================== */
CREATE TABLE IF NOT EXISTS treatment_master (
  id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                 BINARY(16) NOT NULL UNIQUE,                   -- UUIDv7(bin16)
  clinic_uuid          BINARY(16) NOT NULL,                          -- ↔ clinics.uuid（当時値・不変）
  code                 VARCHAR(50)  NOT NULL,                        -- 院内/製剤コード
  name                 VARCHAR(255) NOT NULL,                        -- 表示名
  type                 ENUM('procedure','medication') NOT NULL,      -- 区分
  qty_unit             VARCHAR(32)  NOT NULL,                        -- 単位
  default_pay_type     ENUM('insurance','private') NOT NULL DEFAULT 'insurance',

  /* 点数/価格（整数運用） */
  current_b_points     INT UNSIGNED NULL,
  current_a_points     INT UNSIGNED NULL,
  current_price_yen    INT UNSIGNED NULL,

  /* 税率（例 0.10） */
  tax_rate             DECIMAL(4,2) NOT NULL,

  /* 任意メタ（一本化: 全体向け注意・用法等） */
  dosage_per_kg        DECIMAL(10,4) NULL,                           -- 体重1kgあたり
  usage_text           TEXT NULL,

  /* 運用 */
  is_active            TINYINT(1) NOT NULL DEFAULT 1,
  created_at           DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at           DATETIME  NULL,                                -- SoftDelete
  row_version          BIGINT UNSIGNED NOT NULL DEFAULT 1,            -- 楽観ロック

  /* 索引 */
  UNIQUE KEY uq_ttm_clinic_code (clinic_uuid, code),                  -- ★院別一意
  KEY    idx_ttm_active (is_active, name),
  KEY    idx_quality (deleted_at, updated_at, id),
  KEY    idx_clinic_list (clinic_uuid, deleted_at, updated_at, id),

  /* FK（この表のみ clinics を参照） */
  CONSTRAINT fk_ttm_clinic_uuid
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER bi_treatment_master_uuid
BEFORE INSERT ON treatment_master
FOR EACH ROW
BEGIN
  SET NEW.uuid = COALESCE(NEW.uuid, uuid_v7_bin());
END$$

CREATE TRIGGER bu_treatment_master_rowver
BEFORE UPDATE ON treatment_master
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid <> OLD.clinic_uuid THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'clinic_uuid is immutable on treatment_master';
  END IF;
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;

/* =====================================================================
  2) treatment_disease_rules — 適用可病名（存在判定＋任意表示）
     - clinic_uuid を親（treatment_master）から継承（NULL時のみ）
     - clinics への FK は付けない
     - disease_uuid は p016.2 の方針を維持
===================================================================== */
CREATE TABLE IF NOT EXISTS treatment_disease_rules (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid             BINARY(16) NOT NULL UNIQUE,           -- UUIDv7(bin16)
  clinic_uuid      BINARY(16) NOT NULL,                  -- 当時値（FKなし）
  treatment_uuid   BINARY(16) NOT NULL,                  -- ↔ treatment_master.uuid
  disease_uuid     BINARY(16) NOT NULL,                  -- ↔ disease_master.uuid
  disease_specific TEXT NULL,                            -- on-label時の任意表示文（病名特異）
  is_active        TINYINT(1) NOT NULL DEFAULT 1,
  created_at       DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at       DATETIME  NULL,
  row_version      BIGINT UNSIGNED NOT NULL DEFAULT 1,

  UNIQUE KEY uq_tdr_pair (treatment_uuid, disease_uuid),
  KEY idx_tdr_treat (treatment_uuid),
  KEY idx_tdr_dis   (disease_uuid),
  KEY idx_quality   (deleted_at, updated_at, id),
  KEY idx_clinic_list (clinic_uuid, deleted_at, updated_at, id),

  CONSTRAINT fk_tdr_treatment_uuid
    FOREIGN KEY (treatment_uuid) REFERENCES treatment_master(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_tdr_disease_uuid
    FOREIGN KEY (disease_uuid)   REFERENCES disease_master(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER bi_treatment_disease_rules_uuid
BEFORE INSERT ON treatment_disease_rules
FOR EACH ROW
BEGIN
  DECLARE v_parent_clinic BINARY(16);
  SET NEW.uuid = COALESCE(NEW.uuid, uuid_v7_bin());

  /* 親（treatment_master）から clinic_uuid を継承（NULL時のみ設定：最低適用） */
  IF NEW.clinic_uuid IS NULL THEN
    SELECT tm.clinic_uuid INTO v_parent_clinic
      FROM treatment_master tm
     WHERE tm.uuid = NEW.treatment_uuid
     LIMIT 1;
    SET NEW.clinic_uuid = v_parent_clinic;
  END IF;
END$$

CREATE TRIGGER bu_treatment_disease_rules_rowver
BEFORE UPDATE ON treatment_disease_rules
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid <> OLD.clinic_uuid THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'clinic_uuid is immutable on treatment_disease_rules';
  END IF;
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;

/* =====================================================================
  3) treatment_sets — 個人/共有セット（所有者: users.uuid）
     - clinic_uuid を親（users）から継承（NULL時のみ）
     - clinics への FK は付けない
===================================================================== */
CREATE TABLE IF NOT EXISTS treatment_sets (
  id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid         BINARY(16) NOT NULL UNIQUE,               -- UUIDv7(bin16)
  clinic_uuid  BINARY(16) NOT NULL,                      -- 当時値（FKなし）
  user_uuid    BINARY(16) NOT NULL,                      -- ↔ users.uuid
  name         VARCHAR(100) NOT NULL,
  note         VARCHAR(255) NULL,
  sequence_no  INT UNSIGNED NOT NULL DEFAULT 1,
  visibility   ENUM('private','shared') NOT NULL DEFAULT 'shared',
  is_active    TINYINT(1) NOT NULL DEFAULT 1,

  created_at   DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at   DATETIME  NULL,
  row_version  BIGINT UNSIGNED NOT NULL DEFAULT 1,

  KEY idx_ts_owner (user_uuid, is_active, sequence_no),
  KEY idx_visibility (visibility),
  KEY idx_quality  (deleted_at, updated_at, id),
  KEY idx_clinic_list (clinic_uuid, deleted_at, updated_at, id),

  CONSTRAINT fk_treatment_sets_user_uuid
    FOREIGN KEY (user_uuid) REFERENCES users(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER bi_treatment_sets_uuid
BEFORE INSERT ON treatment_sets
FOR EACH ROW
BEGIN
  DECLARE v_user_clinic BINARY(16);
  SET NEW.uuid = COALESCE(NEW.uuid, uuid_v7_bin());

  /* 親（users）から clinic_uuid を継承（NULL時のみ設定：最低適用） */
  IF NEW.clinic_uuid IS NULL THEN
    SELECT u.clinic_uuid INTO v_user_clinic
      FROM users u
     WHERE u.uuid = NEW.user_uuid
     LIMIT 1;
    SET NEW.clinic_uuid = v_user_clinic;
  END IF;
END$$

CREATE TRIGGER bu_treatment_sets_rowver
BEFORE UPDATE ON treatment_sets
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid <> OLD.clinic_uuid THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'clinic_uuid is immutable on treatment_sets';
  END IF;
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;

/* =====================================================================
  4) treatment_set_items — セット構成要素
     - clinic_uuid を親（treatment_sets）から継承（NULL時のみ）
     - clinics への FK は付けない
===================================================================== */
CREATE TABLE IF NOT EXISTS treatment_set_items (
  id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid            BINARY(16) NOT NULL UNIQUE,            -- UUIDv7(bin16)
  clinic_uuid     BINARY(16) NOT NULL,                   -- 当時値（FKなし）
  set_uuid        BINARY(16) NOT NULL,                   -- ↔ treatment_sets.uuid
  treatment_uuid  BINARY(16) NOT NULL,                   -- ↔ treatment_master.uuid
  sequence_no     INT UNSIGNED NOT NULL DEFAULT 1,
  preset_quantity DECIMAL(10,2) NULL,                    -- p016.2方針（10,2）

  created_at      DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at      DATETIME  NULL,
  row_version     BIGINT UNSIGNED NOT NULL DEFAULT 1,

  UNIQUE KEY uq_tsi_item (set_uuid, treatment_uuid),
  KEY idx_tsi_set_seq (set_uuid, sequence_no),
  KEY idx_treatment (treatment_uuid),
  KEY idx_quality   (deleted_at, updated_at, id),
  KEY idx_clinic_list (clinic_uuid, deleted_at, updated_at, id),

  CONSTRAINT fk_tsi_set_uuid
    FOREIGN KEY (set_uuid)       REFERENCES treatment_sets(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_tsi_treatment_uuid
    FOREIGN KEY (treatment_uuid) REFERENCES treatment_master(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER bi_treatment_set_items_uuid
BEFORE INSERT ON treatment_set_items
FOR EACH ROW
BEGIN
  DECLARE v_set_clinic BINARY(16);
  SET NEW.uuid = COALESCE(NEW.uuid, uuid_v7_bin());

  /* 親（treatment_sets）から clinic_uuid を継承（NULL時のみ設定：最低適用） */
  IF NEW.clinic_uuid IS NULL THEN
    SELECT ts.clinic_uuid INTO v_set_clinic
      FROM treatment_sets ts
     WHERE ts.uuid = NEW.set_uuid
     LIMIT 1;
    SET NEW.clinic_uuid = v_set_clinic;
  END IF;
END$$

CREATE TRIGGER bu_treatment_set_items_rowver
BEFORE UPDATE ON treatment_set_items
FOR EACH ROW
BEGIN
  IF NEW.clinic_uuid <> OLD.clinic_uuid THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'clinic_uuid is immutable on treatment_set_items';
  END IF;
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;
