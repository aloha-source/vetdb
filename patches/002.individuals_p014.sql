/* ============================================================
   ユーティリティ関数群
   - UUIDバイナリ/文字列の相互変換
   - UUID v7（時系列ソート性あり）の生成
   - 見本: checkups_p012.2.sql 準拠
   ============================================================ */
DELIMITER $$

/* BIN(16) → HEX文字列32桁へ変換 */
DROP FUNCTION IF EXISTS uuid_bin_to_hex $$
CREATE FUNCTION uuid_bin_to_hex(b BINARY(16)) RETURNS CHAR(32)
DETERMINISTIC
BEGIN
  RETURN LOWER(HEX(b));
END$$

/* UUID文字列（36桁/32桁/ダッシュ混在可）→ BIN(16) に変換 */
DROP FUNCTION IF EXISTS uuid_hex_to_bin $$
CREATE FUNCTION uuid_hex_to_bin(s VARCHAR(36)) RETURNS BINARY(16)
DETERMINISTIC
BEGIN
  RETURN UNHEX(REPLACE(LOWER(s), '-', ''));
END$$

/* UUID v7 を文字列として生成（ソートフレンドリ、ランダムビット含む） */
DROP FUNCTION IF EXISTS uuid_v7_str $$
CREATE FUNCTION uuid_v7_str() RETURNS CHAR(36)
NOT DETERMINISTIC
BEGIN
  DECLARE ts_ms BIGINT UNSIGNED; DECLARE ts_hex CHAR(12);
  DECLARE r12 INT UNSIGNED; DECLARE ver_hi CHAR(4);
  DECLARE var_hi CHAR(4); DECLARE tail CHAR(12);
  DECLARE t_hi CHAR(8); DECLARE t_mid CHAR(4);

  -- 現在時刻をミリ秒単位に変換
  SET ts_ms = CAST(ROUND(UNIX_TIMESTAMP(CURRENT_TIMESTAMP(3))*1000) AS UNSIGNED);
  -- HEX化（12桁、先頭ゼロ埋め）
  SET ts_hex = LPAD(HEX(ts_ms),12,'0');

  -- ランダムビット生成
  SET r12 = FLOOR(RAND()*POW(2,12));
  SET ver_hi = CONCAT('7', LPAD(HEX(r12),3,'0'));  -- UUIDバージョン=7
  SET var_hi = CONCAT(ELT(FLOOR(RAND()*4)+1,'8','9','a','b'),
                      LPAD(HEX(FLOOR(RAND()*POW(2,12))),3,'0'));
  SET tail = LPAD(HEX(FLOOR(RAND()*POW(2,48))),12,'0');

  -- UUID各部位を組み立て
  SET t_hi = LEFT(ts_hex,8);
  SET t_mid = SUBSTRING(ts_hex,9,4);

  RETURN LOWER(CONCAT(t_hi,'-',t_mid,'-',ver_hi,'-',var_hi,'-',tail));
END$$

/* UUID v7 を BINARY(16) として生成 */
DROP FUNCTION IF EXISTS uuid_v7_bin $$
CREATE FUNCTION uuid_v7_bin() RETURNS BINARY(16)
NOT DETERMINISTIC
BEGIN
  RETURN uuid_hex_to_bin(uuid_v7_str());
END$$

DELIMITER ;

/* ============================================================
   再デプロイ安全化
   - テーブル/トリガ/ビューを事前DROP
   ============================================================ */
DROP TRIGGER IF EXISTS tr_individuals_bi_uuid_v7;
DROP VIEW IF EXISTS individuals_hex_v;
DROP TABLE IF EXISTS individuals;

/* ============================================================
   individuals テーブル
   目的:
   - 農場に属する個体（牛など）の基本情報を管理
   - uuid: BIN(16) をSoTキーとする（UUID v7）
   - 母子関係（遺伝母/哺育母）を分離管理
   - 父情報はメモのみ
   - ソフトデリート対応
   ============================================================ */
CREATE TABLE individuals (
  id                      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, -- サロゲートPK（内部用）

  uuid                    BINARY(16)  NOT NULL UNIQUE,             -- グローバル一意ID（UUID v7, BIN16）
  farm_uuid               BINARY(16)  NOT NULL,                    -- 所属農場（farms.uuid, BIN16）
  user_uuid               BINARY(16)  NOT NULL,                    -- 登録/所有ユーザ（users.uuid, BIN16）

  name                    VARCHAR(100) NULL,                       -- 個体名（任意）
  ear_tag                 CHAR(10)     NULL,                       -- 耳標（全国一意10桁、未付与時NULL）
  status                  ENUM('active','sold','dead','culled')    -- 個体状態
                           NOT NULL DEFAULT 'active',              -- culled=廃用淘汰

  gender                  ENUM('female','male','cast','unknown')   -- 性別
                           NOT NULL DEFAULT 'unknown',             -- genders参照廃止→ENUM化

  birth_date              DATE         NULL,                       -- 生年月日
  death_date              DATE         NULL,                       -- 死亡日（任意記録）

  sire_name               VARCHAR(100) NULL,                       -- 父牛名（メモのみ、FKなし）

  genetic_dam_uuid        BINARY(16)   NULL,                       -- 遺伝母 UUID（自己参照FK）
  nursing_dam_uuid        BINARY(16)   NULL,                       -- 哺育母 UUID（自己参照FK）

  -- 母牛確定時のスナップ（帳票/検索用に保持）
  genetic_dam_ear_tag     CHAR(10)     NULL,
  genetic_dam_name        VARCHAR(100) NULL,
  nursing_dam_ear_tag     CHAR(10)     NULL,
  nursing_dam_name        VARCHAR(100) NULL,

  created_at              DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, 
  updated_at              DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at              DATETIME NULL,                           -- ソフトデリート（NULL=有効）

  UNIQUE KEY uq_individuals_ear_tag (ear_tag),                      -- 耳標は全国一意、NULLは重複可

  -- インデックス設計（検索/一覧用）
  KEY idx_individuals_farm_name   (farm_uuid, name),
  KEY idx_individuals_farm_birth  (farm_uuid, birth_date),
  KEY idx_individuals_farm_status (farm_uuid, status),
  KEY idx_individuals_genetic_dam (genetic_dam_uuid),
  KEY idx_individuals_nursing_dam (nursing_dam_uuid),

  -- 外部キー（farm/userは削除不可、参照整合性を保持）
  CONSTRAINT fk_individuals_farm_uuid
    FOREIGN KEY (farm_uuid) REFERENCES farms(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,

  CONSTRAINT fk_individuals_user_uuid
    FOREIGN KEY (user_uuid) REFERENCES users(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,

  -- 自己参照FK（母リンク）
  -- 母個体が削除された場合は子の dam_uuid を NULL化（当時の耳標/名前メモは保持）
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
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  ROW_FORMAT=DYNAMIC;

/* ============================================================
   トリガ
   - INSERT時に uuid が NULL またはゼロUUIDなら
     uuid_v7_bin() を自動採番
   ============================================================ */
DELIMITER $$
CREATE TRIGGER tr_individuals_bi_uuid_v7
BEFORE INSERT ON individuals
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;

/* ============================================================
   HEX表現ビュー
   - UUID(BIN16)を文字列HEX化して確認・デバッグ用
   ============================================================ */
CREATE OR REPLACE VIEW individuals_hex_v AS
SELECT
  id,
  uuid_bin_to_hex(uuid)             AS uuid_hex,
  uuid_bin_to_hex(farm_uuid)        AS farm_uuid_hex,
  uuid_bin_to_hex(user_uuid)        AS user_uuid_hex,
  name, ear_tag, status, gender, birth_date, death_date, sire_name,
  uuid_bin_to_hex(genetic_dam_uuid) AS genetic_dam_uuid_hex,
  genetic_dam_ear_tag, genetic_dam_name,
  uuid_bin_to_hex(nursing_dam_uuid) AS nursing_dam_uuid_hex,
  nursing_dam_ear_tag, nursing_dam_name,
  deleted_at, created_at, updated_at
FROM individuals;
