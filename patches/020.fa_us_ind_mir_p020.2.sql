SET NAMES utf8mb4;

/* =========================================================
   VetDB — SoT + farmDB mirrors
   CSIFH-PureMirror v1 適用／p020.1 改修 完全DDL（長文コメント付き）
   ---------------------------------------------------------
   ■このファイルの目的
     - 「多病院対応（CSIFH）」と「farmDB純ミラー運用」を、p020.1系の
       SoT/Mirror 構成へ反映した“新規インストール用DDL”を提示します。
     - farm_users の clinic 参照は「冗長な二重FK」を避けるため、
       親 farms への【合成FK】(farm_uuid, clinic_uuid) を採用します。
       （= 子の clinic は必ず親の clinic と一致する）

   ■CSIFH-PureMirror v1 の要点（再掲）
     1) SoTは clinic_uuid を NOT NULL + FK（院所属を厳格化）
     2) Mirrorは farmDB の値を無加工で保持（clinic_uuid を含む／NULL可）
        → FK/推定/トリガは一切つけない“純ミラー”
     3) 可視性は常に「clinic一致」。NULLは誰にも見えない（未所属BOXのみ）。
     4) 履歴は chart_headers/visits の clinic_uuid で算出（mirrorに依存しない）
     5) 取り込み・突合のために entity_links を採用（院越境はDBで拒否）

   ■本DDLで定義するテーブル
     - SoT:        farms, vet_users, farm_users
     - Mirrors:    farmdb_farms_mirror, farmdb_individuals_mirror, farmdb_farm_users_mirror
     - Link-Table: entity_links（remote⇔local 1:1 対応／院スコープ厳格）

   ■前提（必須）
     - clinics(uuid BINARY(16)) が存在していること
     - 関数 uuid_v7_bin() が存在していること
     - individuals（SoT）が未導入の場合でも本DDLは動作しますが、
       entity_links のトリガの「individual分岐」を使う際は individuals が必要です。
       （必要なければ individual 分岐は利用しない／あとから有効化してください）
   ========================================================= */


/* =========================================================
 0) farms — SoT（個体/請求の基点）
   ---------------------------------------------------------
   ■設計方針
     - すべてのSoTは clinic 所属を厳格化 → clinic_uuid NOT NULL + FK。
     - farm は院付け替えがあり得るため ON UPDATE CASCADE / ON DELETE RESTRICT。
     - 一覧・差分同期向けの標準インデックスを付与。
     - farm_users からの【合成FK】の参照先となるため、
       (uuid, clinic_uuid) の UNIQUE を追加（MySQLの合成FK要件）。

   ■主な索引
     - uq_farms_uuid           : uuidの一意性（アプリ内での主識別子）
     - uq_farms_uuid_clinic    : 合成FKの参照先（farm_usersから参照）
     - idx_farms_clinic_list   : 院別一覧（deleted_at, updated_at併用）
   ========================================================= */
DROP TABLE IF EXISTS farms;
CREATE TABLE farms (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid             BINARY(16) NOT NULL,
  clinic_uuid      BINARY(16) NOT NULL,              -- ↔ clinics.uuid（院所属・厳格）
  name             VARCHAR(120) NOT NULL,
  billing_name     VARCHAR(120) NULL,
  billing_address  VARCHAR(255) NULL,

  row_hash         CHAR(64) NULL,                    -- 任意：差分検出や外部同期の補助
  created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at       DATETIME NULL,                    -- ソフトデリート（論理削除）
  row_version      BIGINT UNSIGNED NOT NULL DEFAULT 1, -- 楽観ロック/差分検知

  UNIQUE KEY uq_farms_uuid (uuid),
  /* 合成FKの参照先要件を満たすため、(uuid, clinic_uuid) を UNIQUE にする */
  UNIQUE KEY uq_farms_uuid_clinic (uuid, clinic_uuid),

  KEY idx_farms_name (name),
  KEY idx_farms_list (deleted_at, updated_at, id),
  KEY idx_farms_clinic_list (clinic_uuid, deleted_at, updated_at, id),

  CONSTRAINT fk_farms_clinic
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DROP TRIGGER IF EXISTS tr_farms_bi_uuid_v7;
DELIMITER $$
CREATE TRIGGER tr_farms_bi_uuid_v7
BEFORE INSERT ON farms
FOR EACH ROW
BEGIN
  /* UUIDはBINARY(16)/v7想定。未指定時のみ自動採番。 */
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
  /* UUIDは不変・row_versionは+1。clinic_uuidの付け替えはFKが整合性を担保。 */
  SET NEW.uuid = OLD.uuid;
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;


/* =========================================================
 1) vet_users — SoT（獣医・院内ユーザー）
   ---------------------------------------------------------
   ■設計方針
     - すべての vet_users は必ず clinic に所属（NOT NULL + FK）。
     - 一覧・検索キー（display_name/email）を付与。
     - row_version による編集競合検知。

   ■注意
     - 認証やロールはアプリ層/別テーブルで扱う想定。本テーブルは基本プロフィール。
   ========================================================= */
DROP TABLE IF EXISTS vet_users;
CREATE TABLE vet_users (
  id                 INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid               BINARY(16) NOT NULL,
  clinic_uuid        BINARY(16) NOT NULL,            -- ↔ clinics.uuid
  display_name       VARCHAR(100) NOT NULL,
  email              VARCHAR(255) NULL,
  phone              VARCHAR(50) NULL,
  role_label         VARCHAR(100) NULL,              -- 例: 院長/獣医師/スタッフ
  clinic_branch_name VARCHAR(120) NULL,              -- 分院メモ（UI補助）

  created_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at         DATETIME NULL,
  row_version        BIGINT UNSIGNED NOT NULL DEFAULT 1,

  UNIQUE KEY uq_vet_users_uuid (uuid),
  KEY idx_vet_users_name (display_name),
  KEY idx_vet_users_email (email),
  KEY idx_vet_users_list (deleted_at, updated_at, id),
  KEY idx_vet_users_clinic_list (clinic_uuid, deleted_at, updated_at, id),

  CONSTRAINT fk_vet_users_clinic
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT
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
  SET NEW.uuid = OLD.uuid;
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;


/* =========================================================
 2) farm_users — SoT（農家ユーザー：farmに従属）
   ---------------------------------------------------------
   ■設計方針（重要）
     - farm_users は必ず「どこかの farm に所属」し、結果として clinic も決まる。
     - 子側に clinic_uuid を持たせるのは「院別スコープ検索の高速化」のため。
     - ただし clinics への単独FKは冗長。代わりに【合成FK】を採用し、
       子(farm_uuid, clinic_uuid) → 親(farms.uuid, farms.clinic_uuid) を強制一致。
     - 親farmの付け替えや clinic の変更に対して、ON UPDATE CASCADE で追随。

   ■合成FKの効果
     - 「子のclinicと親のclinicの不一致」をDBが拒否（アプリのバグ耐性）
     - clinics への重複FKを排除し、参照経路を親farmに集約（スキーマ簡潔）

   ■トリガ
     - 挿入/親変更時に、親farmから clinic_uuid を自動継承（書き忘れ防止）。
   ========================================================= */
DROP TABLE IF EXISTS farm_users;
CREATE TABLE farm_users (
  id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid         BINARY(16) NOT NULL,

  farm_uuid    BINARY(16) NOT NULL,                 -- ↔ farms.uuid
  clinic_uuid  BINARY(16) NOT NULL,                 -- 院スコープ検索用に保持（親から継承）

  display_name VARCHAR(100) NOT NULL,
  email        VARCHAR(255) NULL,
  phone        VARCHAR(50) NULL,
  role_label   VARCHAR(100) NULL,                   -- 例: 場長/経理/担当

  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at   DATETIME NULL,
  row_version  BIGINT UNSIGNED NOT NULL DEFAULT 1,

  UNIQUE KEY uq_farm_users_uuid (uuid),
  KEY idx_farm_users_farm (farm_uuid, display_name),
  KEY idx_farm_users_email (email),
  KEY idx_farm_users_list (deleted_at, updated_at, id),
  KEY idx_farm_users_clinic_list (clinic_uuid, deleted_at, updated_at, id),

  /* ☆合成FK：子(farm_uuid, clinic_uuid) → 親(farms.uuid, farms.clinic_uuid) */
  CONSTRAINT fk_fu_farm_clinic
    FOREIGN KEY (farm_uuid, clinic_uuid)
    REFERENCES farms (uuid, clinic_uuid)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DROP TRIGGER IF EXISTS tr_farm_users_bi_uuid_v7;
DELIMITER $$
CREATE TRIGGER tr_farm_users_bi_uuid_v7
BEFORE INSERT ON farm_users
FOR EACH ROW
BEGIN
  DECLARE v_clinic BINARY(16);

  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;

  /* 親farmから clinic_uuid を継承（手入力・取り違えの防止） */
  SELECT f.clinic_uuid INTO v_clinic
    FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
  SET NEW.clinic_uuid = v_clinic;
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS tr_farm_users_bu_rowver_lockuuid;
DELIMITER $$
CREATE TRIGGER tr_farm_users_bu_rowver_lockuuid
BEFORE UPDATE ON farm_users
FOR EACH ROW
BEGIN
  DECLARE v_clinic BINARY(16);

  SET NEW.uuid = OLD.uuid;                    -- UUIDは不変
  SET NEW.row_version = OLD.row_version + 1;  -- 楽観ロック

  /* 親farmの変更や親側clinic付け替えに追随（再継承） */
  SELECT f.clinic_uuid INTO v_clinic
    FROM farms f WHERE f.uuid = NEW.farm_uuid LIMIT 1;
  SET NEW.clinic_uuid = v_clinic;
END$$
DELIMITER ;


/* =========================================================
 3) farmDB mirrors — farms（READ ONLY / 純ミラー）
   ---------------------------------------------------------
   ■設計方針
     - farmDBが正（SoT）。本ミラーは farmDB の列・値を無加工で保持。
     - clinic_uuid は farmDBの値をそのまま（NULL可）。FK/推定/トリガなし。
     - 院スコープ一覧・差分取込・名前検索を想定した索引のみ付与。
   ========================================================= */
DROP TABLE IF EXISTS farmdb_farms_mirror;
CREATE TABLE farmdb_farms_mirror (
  id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid              BINARY(16) NOT NULL UNIQUE,     -- farmDB側 farm.uuid
  clinic_uuid       BINARY(16) NULL,                -- farmDBの値そのまま（NULL可）
  name              VARCHAR(120) NOT NULL,
  billing_name      VARCHAR(120) NULL,
  billing_address   VARCHAR(255) NULL,
  deleted_at        DATETIME NULL,                  -- 外部削除の鏡像（tombstone）
  updated_at_source DATETIME NULL,                  -- farmDB側の更新時刻（差分カーソル用）

  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  KEY idx_fdb_farms_clinic_list (clinic_uuid, deleted_at, updated_at, id),
  KEY idx_fdb_farms_updated     (updated_at_source),
  KEY idx_fdb_farms_name        (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;


/* =========================================================
 4) farmDB mirrors — individuals（READ ONLY / 純ミラー）
   ---------------------------------------------------------
   ■設計方針
     - clinic_uuid は farmDBの値をそのまま（NULL可）。FK/推定/トリガなし。
     - 耳標の品質（外部の一意性担保）に依存するため UNIQUE は置かず、通常INDEX。
     - 性別・状態は v1p10/v1p5 の整合に合わせた ENUM 定義を採用。

   ■注意
     - row_version は“同期監視用の軽量フラグ”として保持（厳密ロック用途ではない）。
   ========================================================= */
DROP TABLE IF EXISTS farmdb_individuals_mirror;
CREATE TABLE farmdb_individuals_mirror (
  id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid                 BINARY(16) NOT NULL UNIQUE,
  clinic_uuid          BINARY(16) NULL,             -- farmDB由来（NULL可）
  farm_uuid            BINARY(16) NOT NULL,         -- 参照先もfarmDBのUUID（FKなし）
  user_uuid            BINARY(16) NULL,

  name                 VARCHAR(100) NULL,
  ear_tag              CHAR(10) NULL,
  status               ENUM('active','sold','dead','culled') NOT NULL DEFAULT 'active',
  gender               ENUM('female','male','cast','unknown') NOT NULL DEFAULT 'unknown',
  birth_date           DATE NULL,
  death_date           DATE NULL,
  sire_name            VARCHAR(100) NULL,

  genetic_dam_uuid     BINARY(16) NULL,
  nursing_dam_uuid     BINARY(16) NULL,
  genetic_dam_ear_tag  CHAR(10) NULL,
  genetic_dam_name     VARCHAR(100) NULL,
  nursing_dam_ear_tag  CHAR(10) NULL,
  nursing_dam_name     VARCHAR(100) NULL,

  created_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at           DATETIME NULL,
  row_version          BIGINT UNSIGNED NOT NULL DEFAULT 1,

  KEY idx_fdb_individuals_clinic_list (clinic_uuid, deleted_at, updated_at, id),
  KEY idx_fdb_individuals_farm        (farm_uuid, name),
  KEY idx_fdb_individuals_birth       (birth_date),
  KEY idx_fdb_individuals_ear_tag     (ear_tag),
  KEY idx_fdb_individuals_parents     (genetic_dam_uuid, nursing_dam_uuid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;


/* =========================================================
 5) farmDB mirrors — farm_users（READ ONLY / 純ミラー）
   ---------------------------------------------------------
   ■設計方針
     - ミラーは常に無加工。clinic_uuid は farmDBの値のまま（NULL可）。
     - FK/推定/トリガなし。院スコープ・farm紐付け・メール検索向けの索引のみ。
   ========================================================= */
DROP TABLE IF EXISTS farmdb_farm_users_mirror;
CREATE TABLE farmdb_farm_users_mirror (
  id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid         BINARY(16) NOT NULL UNIQUE,
  clinic_uuid  BINARY(16) NULL,            -- farmDB由来（NULL可）
  farm_uuid    BINARY(16) NOT NULL,
  display_name VARCHAR(100) NOT NULL,
  email        VARCHAR(255) NULL,
  phone        VARCHAR(50) NULL,
  role_label   VARCHAR(100) NULL,

  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at   DATETIME NULL,
  row_version  BIGINT UNSIGNED NOT NULL DEFAULT 1,

  KEY idx_fdb_farm_users_clinic_list (clinic_uuid, deleted_at, updated_at, id),
  KEY idx_fdb_farm_users_farm        (farm_uuid, display_name),
  KEY idx_fdb_farm_users_email       (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;


/* =========================================================
 6) entity_links — remote(mirror) と local(SoT) の対応表
   ---------------------------------------------------------
   ■役割
     - farmDBミラー（remote）と VetDB SoT（local）の 1:1 対応表。
     - 取り込み/突合/逆同期の基盤。院越境はDBで拒否。
     - clinic_uuid は「local側から強制確定」。手入力は不可（トリガで上書き）。

   ■制約
     - remote重複禁止: UNIQUE(entity_type, source_system, remote_uuid)
     - 院越境禁止: remote側にclinicが付いており、localと不一致なら拒否。
       （remote側がNULLのときは“未所属→収容”のため許容）

   ■備考
     - entity_type に 'individual' を含みます。individuals（SoT）が未導入の環境では
       当面 'farm' / 'farm_user' での運用に限定するか、individual分岐の使用を控えてください。
   ========================================================= */
DROP TABLE IF EXISTS entity_links;
CREATE TABLE entity_links (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

  clinic_uuid   BINARY(16) NOT NULL,                  -- ← local 由来（トリガで確定）
  entity_type   ENUM('farm','individual','farm_user') NOT NULL,
  source_system ENUM('farmdb') NOT NULL DEFAULT 'farmdb',

  local_uuid    BINARY(16) NOT NULL,                  -- VetDB SoT 側 UUID
  remote_uuid   BINARY(16) NOT NULL,                  -- farmDB mirror 側 UUID

  is_primary    TINYINT(1) NOT NULL DEFAULT 1,        -- 将来: 多対1許容時の“主”印
  note          VARCHAR(255) NULL,

  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  UNIQUE KEY uq_entity_links_remote (entity_type, source_system, remote_uuid),
  KEY idx_entity_links_local  (entity_type, local_uuid),
  KEY idx_entity_links_clinic (clinic_uuid, entity_type, updated_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

/* ▼スコープ/整合トリガ
   - 挿入/更新の度に、local側から clinic_uuid を確定し、remote側clinicとの越境を拒否。
   - 'individual' 分岐は individuals（SoT）が存在する前提。未導入なら当面使用しないか、
     分岐をコメントアウトして適用してください。 */
DROP TRIGGER IF EXISTS tr_entity_links_bi_scope;
DELIMITER $$
CREATE TRIGGER tr_entity_links_bi_scope
BEFORE INSERT ON entity_links
FOR EACH ROW
BEGIN
  DECLARE v_local_clinic  BINARY(16);
  DECLARE v_remote_clinic BINARY(16);

  /* 1) local 側 clinic を確定（entity_typeに応じて参照先が異なる） */
  CASE NEW.entity_type
    WHEN 'farm' THEN
      SELECT clinic_uuid INTO v_local_clinic
        FROM farms WHERE uuid = NEW.local_uuid LIMIT 1;

    WHEN 'farm_user' THEN
      /* farm_users は合成FKにより (farm_uuid, clinic_uuid) が親と常に一致 */
      SELECT clinic_uuid INTO v_local_clinic
        FROM farm_users WHERE uuid = NEW.local_uuid LIMIT 1;

    WHEN 'individual' THEN
      /* 注意: individuals（SoT）が必要。未導入ならこの分岐は利用しないこと。 */
      SELECT f.clinic_uuid INTO v_local_clinic
        FROM individuals i
        JOIN farms f ON f.uuid = i.farm_uuid
       WHERE i.uuid = NEW.local_uuid
       LIMIT 1;
  END CASE;
  SET NEW.clinic_uuid = v_local_clinic;

  /* 2) remote 側 clinic を取得して院越境を拒否（NULLは許容＝未所属→収容） */
  CASE NEW.entity_type
    WHEN 'farm' THEN
      SELECT clinic_uuid INTO v_remote_clinic
        FROM farmdb_farms_mirror WHERE uuid = NEW.remote_uuid LIMIT 1;

    WHEN 'farm_user' THEN
      SELECT clinic_uuid INTO v_remote_clinic
        FROM farmdb_farm_users_mirror WHERE uuid = NEW.remote_uuid LIMIT 1;

    WHEN 'individual' THEN
      SELECT clinic_uuid INTO v_remote_clinic
        FROM farmdb_individuals_mirror WHERE uuid = NEW.remote_uuid LIMIT 1;
  END CASE;

  IF v_remote_clinic IS NOT NULL AND v_remote_clinic <> v_local_clinic THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Cross-clinic link is not allowed';
  END IF;
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS tr_entity_links_bu_scope;
DELIMITER $$
CREATE TRIGGER tr_entity_links_bu_scope
BEFORE UPDATE ON entity_links
FOR EACH ROW
BEGIN
  DECLARE v_local_clinic  BINARY(16);
  DECLARE v_remote_clinic BINARY(16);

  CASE NEW.entity_type
    WHEN 'farm' THEN
      SELECT clinic_uuid INTO v_local_clinic
        FROM farms WHERE uuid = NEW.local_uuid LIMIT 1;

    WHEN 'farm_user' THEN
      SELECT clinic_uuid INTO v_local_clinic
        FROM farm_users WHERE uuid = NEW.local_uuid LIMIT 1;

    WHEN 'individual' THEN
      SELECT f.clinic_uuid INTO v_local_clinic
        FROM individuals i
        JOIN farms f ON f.uuid = i.farm_uuid
       WHERE i.uuid = NEW.local_uuid
       LIMIT 1;
  END CASE;
  SET NEW.clinic_uuid = v_local_clinic;

  CASE NEW.entity_type
    WHEN 'farm' THEN
      SELECT clinic_uuid INTO v_remote_clinic
        FROM farmdb_farms_mirror WHERE uuid = NEW.remote_uuid LIMIT 1;

    WHEN 'farm_user' THEN
      SELECT clinic_uuid INTO v_remote_clinic
        FROM farmdb_farm_users_mirror WHERE uuid = NEW.remote_uuid LIMIT 1;

    WHEN 'individual' THEN
      SELECT clinic_uuid INTO v_remote_clinic
        FROM farmdb_individuals_mirror WHERE uuid = NEW.remote_uuid LIMIT 1;
  END CASE;

  IF v_remote_clinic IS NOT NULL AND v_remote_clinic <> v_local_clinic THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Cross-clinic link is not allowed';
  END IF;
END$$
DELIMITER ;
