SET NAMES utf8mb4;

DROP TRIGGER IF EXISTS tr_clinics_bi_uuid;
DROP TRIGGER IF EXISTS tr_clinics_bu_rowver;

CREATE TABLE IF NOT EXISTS clinics (
  id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

  /* 一意識別子（v7 UUID推奨） */
  uuid                BINARY(16) NOT NULL UNIQUE,

  /* 管理・内部用の正式名称（帳票表示は clinic_settings 側で上書き可） */
  name                VARCHAR(128) NOT NULL,

  /* テナント解決キー（どちらか/両方を利用） */
  subdomain           VARCHAR(63)  NULL,           -- 例: foo → https://foo.example.com
  custom_domain       VARCHAR(255) NULL,           -- 例: https://clinic-foo.jp

  /* 運用属性（UI/帳票の既定値） */
  time_zone           VARCHAR(64)  NOT NULL DEFAULT 'Asia/Tokyo',  -- IANA TZ
  locale              VARCHAR(16)  NOT NULL DEFAULT 'ja-JP',       -- BCP47
  currency            CHAR(3)      NOT NULL DEFAULT 'JPY',         -- ISO-4217
  country_code        CHAR(2)      NULL,                           -- ISO-3166-1

  /* サポート窓口（運用連絡先。帳票の連絡先は settings 側で上書き可能） */
  support_email       VARCHAR(191) NULL,
  support_phone       VARCHAR(32)  NULL,

  /* 内部メモ（監査ログではない。自由記入） */
  notes               TEXT NULL,

  /* 運用状態 */
  status              ENUM('active','suspended','closed') NOT NULL DEFAULT 'active',

  /* ドメイン検証（任意運用） */
  domain_verified_at  DATETIME NULL,

  /* 監査・並行制御（v1p9） */
  row_version         BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at          DATETIME NULL,

  /* 作成・更新時刻 */
  created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  /* 一覧・差分最適化インデックス（v1p9既定形） */
  KEY idx_clinics_list (deleted_at, updated_at, id),

  /* 解決キー（NULL許容のユニーク） */
  UNIQUE KEY uq_clinics_subdomain     (subdomain),
  UNIQUE KEY uq_clinics_custom_domain (custom_domain),

  /* 名称検索の補助 */
  INDEX idx_clinics_name (name)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  ROW_FORMAT=DYNAMIC;

-- UUID自動付与（アプリ側で付与するなら不要）
CREATE TRIGGER tr_clinics_bi_uuid
BEFORE INSERT ON clinics
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END;

-- 楽観ロック: 更新ごとに row_version を +1
CREATE TRIGGER tr_clinics_bu_rowver
BEFORE UPDATE ON clinics
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END;

