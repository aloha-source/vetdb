SET NAMES utf8mb4;

/* =========================================================
   VetDB — SoT + farmDB mirrors（users系の命名整理版・最終DDL）
   変更点:
     - farms から non_insured カラムとその索引を削除
   命名:
     - vet_users   : 獣医（VetDBユーザー）※farm_users同型＋clinic_branch_name
     - farm_users  : 農家ユーザー（VetDB側 SoT, 各farmに所属）
     - farmdb_farm_users_mirror : 農家ユーザー（FarmDB側の写し）※farm_usersと同型
   共通方針:
     - UUID=BINARY(16)（v7想定）/ utf8mb4_unicode_ci
     - row_version は BEFORE UPDATE で +1（mirrorの farmdb_farms_mirror は除外）
     - mirrorにはFK/CHECKは張らない
   ========================================================= */


/* =========================================================
   0) farms — SoT（個体/請求の基点）
   ========================================================= */
DROP TABLE IF EXISTS farms;
CREATE TABLE farms (
  id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid              BINARY(16) NOT NULL,

  name              VARCHAR(120) NOT NULL,
  billing_name      VARCHAR(120) NULL,
  billing_address   VARCHAR(255) NULL,

  row_hash          CHAR(64) NULL,                  -- 任意：差分検出用

  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                  ON UPDATE CURRENT_TIMESTAMP,
  deleted_at        DATETIME NULL,
  row_version       BIGINT UNSIGNED NOT NULL DEFAULT 1,

  UNIQUE KEY uq_farms_uuid (uuid),
  KEY idx_farms_name (name),
  KEY idx_farms_list (deleted_at, updated_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DROP TRIGGER IF EXISTS tr_farms_bi_uuid_v7;
DELIMITER $$
CREATE TRIGGER tr_farms_bi_uuid_v7
BEFORE INSERT ON farms
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS tr_farms_bu_rowver_lockuuid;
DELIMITER $$
CREATE TRIGGER tr_farms_bu_rowver_lockuuid
BEFORE UPDATE ON farms
FOR EACH ROW
BEGIN
  SET NEW.uuid = OLD.uuid;
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;


/* =========================================================
   1) vet_users — SoT（獣医：VetDBユーザー）
   - farm_users と同型の基本項目＋分院名 clinic_branch_name を追加
   ========================================================= */
DROP TABLE IF EXISTS vet_users;
CREATE TABLE vet_users (
  id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                BINARY(16) NOT NULL,

  display_name        VARCHAR(100) NOT NULL,
  email               VARCHAR(255) NULL,
  phone               VARCHAR(50)  NULL,
  role_label          VARCHAR(100) NULL,       -- 例: 院長/獣医師/スタッフ
  clinic_branch_name  VARCHAR(120) NULL,       -- 分院名（多院対応はしないためテキスト）

  created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                     ON UPDATE CURRENT_TIMESTAMP,
  deleted_at          DATETIME NULL,
  row_version         BIGINT UNSIGNED NOT NULL DEFAULT 1,

  UNIQUE KEY uq_vet_users_uuid (uuid),
  KEY idx_vet_users_name  (display_name),
  KEY idx_vet_users_email (email),
  KEY idx_vet_users_list  (deleted_at, updated_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DROP TRIGGER IF EXISTS tr_vet_users_bi_uuid_v7;
DELIMITER $$
CREATE TRIGGER tr_vet_users_bi_uuid_v7
BEFORE INSERT ON vet_users
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS tr_vet_users_bu_rowver_lockuuid;
DELIMITER $$
CREATE TRIGGER tr_vet_users_bu_rowver_lockuuid
BEFORE UPDATE ON vet_users
FOR EACH ROW
BEGIN
  SET NEW.uuid = OLD.uuid;                -- UUIDは不変
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;


/* =========================================================
   2) farm_users — SoT（農家ユーザー：各farmに所属）
   ========================================================= */
DROP TABLE IF EXISTS farm_users;
CREATE TABLE farm_users (
  id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid           BINARY(16) NOT NULL,
  farm_uuid      BINARY(16) NOT NULL,           -- ↔ farms.uuid（所属farm）

  display_name   VARCHAR(100) NOT NULL,
  email          VARCHAR(255) NULL,
  phone          VARCHAR(50)  NULL,
  role_label     VARCHAR(100) NULL,             -- 例: 場長/経理/担当

  created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                ON UPDATE CURRENT_TIMESTAMP,
  deleted_at     DATETIME NULL,
  row_version    BIGINT UNSIGNED NOT NULL DEFAULT 1,

  UNIQUE KEY uq_farm_users_uuid (uuid),
  KEY idx_farm_users_farm     (farm_uuid, display_name),
  KEY idx_farm_users_email    (email),
  KEY idx_farm_users_list     (deleted_at, updated_at, id),

  CONSTRAINT fk_farm_users_farm
    FOREIGN KEY (farm_uuid) REFERENCES farms(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DROP TRIGGER IF EXISTS tr_farm_users_bi_uuid_v7;
DELIMITER $$
CREATE TRIGGER tr_farm_users_bi_uuid_v7
BEFORE INSERT ON farm_users
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS tr_farm_users_bu_rowver_lockuuid;
DELIMITER $$
CREATE TRIGGER tr_farm_users_bu_rowver_lockuuid
BEFORE UPDATE ON farm_users
FOR EACH ROW
BEGIN
  SET NEW.uuid = OLD.uuid;
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;


/* =========================================================
   3) farmDB mirrors — farms（読み取り専用）
   ========================================================= */
DROP TABLE IF EXISTS farmdb_farms_mirror;
CREATE TABLE farmdb_farms_mirror (
  id                 INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid               BINARY(16) NOT NULL,      -- farmDB側 farm.uuid
  name               VARCHAR(120) NOT NULL,
  billing_name       VARCHAR(120) NULL,
  billing_address    VARCHAR(255) NULL,

  deleted_at         DATETIME NULL,
  updated_at_source  DATETIME NULL,            -- farmDB側の更新時刻

  created_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                   ON UPDATE CURRENT_TIMESTAMP,

  UNIQUE KEY uq_fdb_farms_uuid (uuid),
  KEY idx_fdb_farms_name (name),
  KEY idx_fdb_farms_updated (updated_at_source)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DROP TRIGGER IF EXISTS tr_fdb_farms_bi_uuid_v7;
DELIMITER $$
CREATE TRIGGER tr_fdb_farms_bi_uuid_v7
BEFORE INSERT ON farmdb_farms_mirror
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS tr_fdb_farms_bu_lock_uuid;
DELIMITER $$
CREATE TRIGGER tr_fdb_farms_bu_lock_uuid
BEFORE UPDATE ON farmdb_farms_mirror
FOR EACH ROW
BEGIN
  SET NEW.uuid = OLD.uuid;   -- mirrorのUUIDは不変
END$$
DELIMITER ;


/* =========================================================
   4) farmDB mirrors — individuals（読み取り専用）
   - vetDB individuals（p014.4）と同型（FK/CHECKなし）
   ========================================================= */
DROP TABLE IF EXISTS farmdb_individuals_mirror;
CREATE TABLE farmdb_individuals_mirror (
  id                    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                  BINARY(16) NOT NULL UNIQUE,
  farm_uuid             BINARY(16) NOT NULL,      -- FKは張らない
  user_uuid             BINARY(16) NULL,

  name                  VARCHAR(100) NULL,
  ear_tag               CHAR(10) NULL,
  status                ENUM('active','sold','dead','culled') NOT NULL DEFAULT 'active',
  gender                ENUM('female','male','cast','unknown') NOT NULL DEFAULT 'unknown',
  birth_date            DATE NULL,
  death_date            DATE NULL,

  sire_name             VARCHAR(100) NULL,

  genetic_dam_uuid      BINARY(16) NULL,
  nursing_dam_uuid      BINARY(16) NULL,
  genetic_dam_ear_tag   CHAR(10) NULL,
  genetic_dam_name      VARCHAR(100) NULL,
  nursing_dam_ear_tag   CHAR(10) NULL,
  nursing_dam_name      VARCHAR(100) NULL,

  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                   ON UPDATE CURRENT_TIMESTAMP,
  deleted_at            DATETIME NULL,
  row_version           BIGINT UNSIGNED NOT NULL DEFAULT 1,

  UNIQUE KEY uq_fdb_individuals_ear_tag (ear_tag),
  KEY idx_fdb_individuals_farm_name   (farm_uuid, name),
  KEY idx_fdb_individuals_farm_birth  (farm_uuid, birth_date),
  KEY idx_fdb_individuals_farm_status (farm_uuid, status),
  KEY idx_fdb_individuals_genetic_dam (genetic_dam_uuid),
  KEY idx_fdb_individuals_nursing_dam (nursing_dam_uuid),
  KEY idx_fdb_individuals_list        (deleted_at, updated_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DROP TRIGGER IF EXISTS tr_fdb_individuals_bi_uuid_v7;
DELIMITER $$
CREATE TRIGGER tr_fdb_individuals_bi_uuid_v7
BEFORE INSERT ON farmdb_individuals_mirror
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS tr_fdb_individuals_bu_rowver_lockuuid;
DELIMITER $$
CREATE TRIGGER tr_fdb_individuals_bu_rowver_lockuuid
BEFORE UPDATE ON farmdb_individuals_mirror
FOR EACH ROW
BEGIN
  SET NEW.uuid = OLD.uuid;
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;


/* =========================================================
   5) farmDB mirrors — farm_users（読み取り専用・改称版）
   - 名称: farmdb_farm_users_mirror
   - 内容: vetDBの farm_users と同型（FKなし）
   ========================================================= */
DROP TABLE IF EXISTS farmdb_farm_users_mirror;
CREATE TABLE farmdb_farm_users_mirror (
  id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid           BINARY(16) NOT NULL,
  farm_uuid      BINARY(16) NOT NULL,           -- 所属farm（FKは張らない）

  display_name   VARCHAR(100) NOT NULL,
  email          VARCHAR(255) NULL,
  phone          VARCHAR(50)  NULL,
  role_label     VARCHAR(100) NULL,

  created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                ON UPDATE CURRENT_TIMESTAMP,
  deleted_at     DATETIME NULL,
  row_version    BIGINT UNSIGNED NOT NULL DEFAULT 1,

  UNIQUE KEY uq_fdb_farm_users_uuid (uuid),
  KEY idx_fdb_farm_users_farm   (farm_uuid, display_name),
  KEY idx_fdb_farm_users_email  (email),
  KEY idx_fdb_farm_users_list   (deleted_at, updated_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DROP TRIGGER IF EXISTS tr_fdb_farm_users_bi_uuid_v7;
DELIMITER $$
CREATE TRIGGER tr_fdb_farm_users_bi_uuid_v7
BEFORE INSERT ON farmdb_farm_users_mirror
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS tr_fdb_farm_users_bu_rowver_lockuuid;
DELIMITER $$
CREATE TRIGGER tr_fdb_farm_users_bu_rowver_lockuuid
BEFORE UPDATE ON farmdb_farm_users_mirror
FOR EACH ROW
BEGIN
  SET NEW.uuid = OLD.uuid;
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;


/* =========================================================
   6) entity_links — SoT と farmDBミラーの対応表
   ========================================================= */
DROP TABLE IF EXISTS entity_links;
CREATE TABLE entity_links (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  entity_type   ENUM('farm','individual','farm_user') NOT NULL,
  local_uuid    BINARY(16) NOT NULL,   -- VetDB（SoT）側 UUID
  remote_uuid   BINARY(16) NOT NULL,   -- farmDB（mirror）側 UUID
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

  UNIQUE KEY uq_entity_link (entity_type, local_uuid, remote_uuid),
  KEY idx_entity_link_local  (entity_type, local_uuid),
  KEY idx_entity_link_remote (entity_type, remote_uuid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
