SET NAMES utf8mb4;

/* =========================================================
   clinics — テナント（病院）親テーブル
   方針:
     - BINARY(16) UUID（v7推奨）
     - サブドメイン/独自ドメインでテナント解決（NULL許容UNIQUE）
     - v1p9流: row_version, SoftDelete, 一覧索引
     - 帳票系の表示・税設定は clinic_settings 側へ集約
   ========================================================= */

-- 再デプロイ安全化（既存トリガ削除）
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


/* =========================================================
   clinic_settings — クリニック共通設定（p018.1 拡張版）
   追加点:
     - clinic_uuid BINARY(16) NOT NULL UNIQUE（多病院対応のテナントキー）
     - billing_contact_name VARCHAR(128)
     - invoice_logo_path VARCHAR(255)
     - receipt_footer_text VARCHAR(255)
     - receipt_footer_invoice_number CHAR(14)（T+13桁, フッター用）
   方針:
     - 税率は小数表現（10% = 0.10）
     - yen_per_point: DECIMAL(8,2), copay_rate: DECIMAL(5,4)
     - 端数処理: ENUM('floor','round','ceil'), 適用範囲: ENUM('line','total')
     - 一覧索引 v1p9形（deleted_at, updated_at, id）
     - clinics へのFKは張らず、アプリ層でテナントスコープを徹底
   ========================================================= */

-- 新規インストール用
CREATE TABLE IF NOT EXISTS clinic_settings (
  id                         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

  /* 多病院対応のテナントキー（1院=1行を UNIQUEで強制） */
  clinic_uuid                BINARY(16) NOT NULL,
  UNIQUE KEY uq_clinic_settings_one (clinic_uuid),

  /* ---------- 請求・点数関連 ---------- */
  yen_per_point              DECIMAL(8,2)  NOT NULL DEFAULT 10.00,  -- 1点=10円
  copay_rate                 DECIMAL(5,4)  NOT NULL DEFAULT 0.1000, -- 10% = 0.1000

  /* ---------- 税率・端数処理 ---------- */
  tax_rate_default           DECIMAL(4,2)  NOT NULL DEFAULT 0.10,   -- 10%は0.10（小数）
  tax_rounding_method        ENUM('floor','round','ceil') NOT NULL DEFAULT 'round',
  tax_rounding_scope         ENUM('line','total')        NOT NULL DEFAULT 'line',

  /* ---------- インボイス/帳票ヘッダ ---------- */
  invoice_qualified_number   VARCHAR(32)  NULL,
  invoice_number_format      VARCHAR(64)  NULL,  -- 例: 'INV-{YYYY}-{SEQ6}'
  clinic_display_name        VARCHAR(128) NULL,
  clinic_address             VARCHAR(255) NULL,
  clinic_phone               VARCHAR(32)  NULL,

  /* NEW: 請求窓口担当者名（帳票/経理運用に利用） */
  billing_contact_name       VARCHAR(128) NULL,

  /* NEW: 帳票ロゴ（S3等のパス想定） */
  invoice_logo_path          VARCHAR(255) NULL,

  /* NEW: レシート定型フッター */
  receipt_footer_text        VARCHAR(255) NULL,

  /* NEW: フッター用インボイス登録番号（T+13桁） */
  receipt_footer_invoice_number CHAR(14) NULL
    COMMENT '適格請求書発行事業者番号（T+13桁）; フッター表示用',

  /* ---------- 監査/削除・並行制御（v1p9方針） ---------- */
  row_version                BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at                 DATETIME NULL,

  /* ---------- 作成・更新 ---------- */
  created_at                 DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                 DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  /* 一覧最適化（v1p9の共通方針） */
  KEY idx_clinic_settings_list (deleted_at, updated_at, id)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  ROW_FORMAT=DYNAMIC;

/* 形式厳格化を行いたい場合（対応環境のみ有効化）：
ALTER TABLE clinic_settings
  ADD CONSTRAINT chk_receipt_footer_invoice_number_format
  CHECK (
    receipt_footer_invoice_number IS NULL
    OR receipt_footer_invoice_number REGEXP '^T[0-9]{13}$'
  );
*/
