/* =====================================================================
   vetDB treatment_* install — p016.1r6（disease_uuid 統一 / p016.1 準拠）
   仕様（要点）:
     • on-label: treatment_disease_rules に (treatment_uuid, disease_uuid) が存在 → true
       - disease_specific が非空なら UI に任意表示
     • off-label: 表示なし／DB禁止なし（存在判定のみ）
     • UUID: BINARY(16) v7 を COALESCE(NEW.uuid, uuid_v7_bin()) で自動採番
     • 文字コード: utf8mb4 / COLLATE=utf8mb4_unicode_ci / ROW_FORMAT=DYNAMIC
     • 一覧索引: idx_quality(deleted_at, updated_at, id)
     • 維持: idx_visibility（sets）, idx_treatment（set_items）
   ===================================================================== */

SET NAMES utf8mb4;

/* -------------------------------------------------------------
   再デプロイ安全化（依存順: 子 → 親）
------------------------------------------------------------- */
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
  1) treatment_master — 処置/薬剤マスタ
     - スナップ元: name/qty_unit/default_pay_type/current_*/tax_rate/usage_text
     - usage_text に「全体向け注意（旧global_advice）」も含める（一本化）
===================================================================== */
CREATE TABLE IF NOT EXISTS treatment_master (
  id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                 BINARY(16) NOT NULL UNIQUE,                   -- UUIDv7(bin16)
  code                 VARCHAR(50)  NOT NULL,                        -- 院内/製剤コード（空不可）
  name                 VARCHAR(255) NOT NULL,                        -- 表示名
  type                 ENUM('procedure','medication') NOT NULL,      -- 区分
  qty_unit             VARCHAR(32)  NOT NULL,                        -- 単位（checkup_items と統一）
  default_pay_type     ENUM('insurance','private') NOT NULL DEFAULT 'insurance',

  -- 点数/価格（整数運用）
  current_b_points     INT UNSIGNED NULL,
  current_a_points     INT UNSIGNED NULL,
  current_price_yen    INT UNSIGNED NULL,

  -- 税率（例 0.10）— checkup_items と同桁
  tax_rate             DECIMAL(4,2) NOT NULL,

  -- 任意メタ（一本化: 全体向け注意・用法等）
  dosage_per_kg        DECIMAL(10,4) NULL,                           -- 体重1kgあたり
  usage_text           TEXT NULL,

  -- 運用
  is_active            TINYINT(1) NOT NULL DEFAULT 1,
  created_at           DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at           DATETIME  NULL,                                -- SoftDelete
  row_version          BIGINT UNSIGNED NOT NULL DEFAULT 1,            -- 楽観ロック

  -- 索引
  UNIQUE KEY uq_ttm_code (code),
  KEY    idx_ttm_active (is_active, name),
  KEY    idx_quality (deleted_at, updated_at, id)
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
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;

/* =====================================================================
  2) treatment_disease_rules — 適用可病名の割当（存在判定＋任意テキスト）
     - 行が存在 → on-label
     - disease_specific が非空なら UI に任意表示（病名特異の注意）
     - ★ disease_id → disease_uuid（BINARY(16)）に統一
===================================================================== */
CREATE TABLE IF NOT EXISTS treatment_disease_rules (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid             BINARY(16) NOT NULL UNIQUE,           -- UUIDv7(bin16)
  treatment_uuid   BINARY(16) NOT NULL,                  -- ↔ treatment_master.uuid
  disease_uuid     BINARY(16) NOT NULL,                  -- ↔ disease_master.uuid（★変更点）
  disease_specific TEXT NULL,                            -- on-label時の任意表示文（病名特異）
  is_active        TINYINT(1) NOT NULL DEFAULT 1,
  created_at       DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at       DATETIME  NULL,
  row_version      BIGINT UNSIGNED NOT NULL DEFAULT 1,

  UNIQUE KEY uq_tdr_pair (treatment_uuid, disease_uuid), -- 重複禁止
  KEY idx_tdr_treat (treatment_uuid),
  KEY idx_tdr_dis   (disease_uuid),
  KEY idx_quality   (deleted_at, updated_at, id),

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
  SET NEW.uuid = COALESCE(NEW.uuid, uuid_v7_bin());
END$$

CREATE TRIGGER bu_treatment_disease_rules_rowver
BEFORE UPDATE ON treatment_disease_rules
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;

/* =====================================================================
  3) treatment_sets — 個人/共有セット（所有者: users.uuid）
     - idx_visibility で一覧最適化
===================================================================== */
CREATE TABLE IF NOT EXISTS treatment_sets (
  id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid         BINARY(16) NOT NULL UNIQUE,               -- UUIDv7(bin16)
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

  CONSTRAINT fk_treatment_sets_user_uuid
    FOREIGN KEY (user_uuid) REFERENCES users(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER bi_treatment_sets_uuid
BEFORE INSERT ON treatment_sets
FOR EACH ROW
BEGIN
  SET NEW.uuid = COALESCE(NEW.uuid, uuid_v7_bin());
END$$

CREATE TRIGGER bu_treatment_sets_rowver
BEFORE UPDATE ON treatment_sets
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;

/* =====================================================================
  4) treatment_set_items — セット構成要素
     - idx_treatment(treatment_uuid) を維持（逆引き最適化）
     - 展開は全行ON（フラグ不要）／preset_quantity があれば最優先
===================================================================== */
CREATE TABLE IF NOT EXISTS treatment_set_items (
  id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid            BINARY(16) NOT NULL UNIQUE,            -- UUIDv7(bin16)
  set_uuid        BINARY(16) NOT NULL,                   -- ↔ treatment_sets.uuid
  treatment_uuid  BINARY(16) NOT NULL,                   -- ↔ treatment_master.uuid
  sequence_no     INT UNSIGNED NOT NULL DEFAULT 1,
  preset_quantity DECIMAL(10,2) NULL,                    -- p016.1方針（10,2）

  created_at      DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at      DATETIME  NULL,
  row_version     BIGINT UNSIGNED NOT NULL DEFAULT 1,

  UNIQUE KEY uq_tsi_item (set_uuid, treatment_uuid),     -- 同一セット×同一処置は1回
  KEY idx_tsi_set_seq (set_uuid, sequence_no),
  KEY idx_treatment (treatment_uuid),
  KEY idx_quality   (deleted_at, updated_at, id),

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
  SET NEW.uuid = COALESCE(NEW.uuid, uuid_v7_bin());
END$$

CREATE TRIGGER bu_treatment_set_items_rowver
BEFORE UPDATE ON treatment_set_items
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;
