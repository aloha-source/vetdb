SET NAMES utf8mb4;

/* =========================================================
   vetDB — p018.2  clinics / clinic_settings（UUID不変版）
   ---------------------------------------------------------
   目的:
   - clinics.uuid を「不変」にする（UPDATEでの連鎖事故を防止）
   - clinic_settings は 1院1行（clinic_uuid UNIQUE）
   - コード/照合/行フォーマットは全体方針に準拠
     ENGINE=InnoDB, CHARSET=utf8mb4, COLLATE=utf8mb4_unicode_ci, ROW_FORMAT=DYNAMIC

   注意:
   - 本DDLは新規インストール想定。既存環境では ALTER に分解してください。
   - クリニックの追加採番は uuid_v7_bin() を用いるため、先に関数を用意しておくこと。
   ========================================================= */

/* 再デプロイ安全化（存在すればDROP） */
DROP TRIGGER IF EXISTS tr_clinics_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_clinics_bu_rowver;
DROP TABLE   IF EXISTS clinic_settings;
DROP TABLE   IF EXISTS clinics;

/* =========================================================
   clinics — クリニック（院）マスタ
   ---------------------------------------------------------
   方針:
   - uuid はアプリ内の主識別子。**不変**（UPDATEで変更させない）。
   - subdomain / custom_domain は NULL許容の一意制約（いずれか利用）。
   - 一覧/差分系の標準索引 (deleted_at, updated_at, id) を付与。
   - row_version は楽観ロック/差分検知用に+1する。
   ========================================================= */
CREATE TABLE clinics (
  id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid              BINARY(16) NOT NULL,                 -- ★不変／更新不可（トリガで固定）
  name              VARCHAR(120) NOT NULL,               -- 例: 〇〇動物病院
  phone             VARCHAR(50)  NULL,
  email             VARCHAR(255) NULL,

  /* サブドメイン/独自ドメイン（どちらも任意／NULL重複OK、値が入れば一意） */
  subdomain         VARCHAR(63)  NULL,
  custom_domain     VARCHAR(255) NULL,

  postal_code       VARCHAR(16)  NULL,
  address_line1     VARCHAR(255) NULL,
  address_line2     VARCHAR(255) NULL,

  notes             TEXT NULL,                           -- 院内メモ（公開しない想定）

  /* 監査・運用列 */
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at        DATETIME NULL,
  row_version       BIGINT UNSIGNED NOT NULL DEFAULT 1,

  /* 一意/索引 */
  UNIQUE KEY uq_clinics_uuid          (uuid),
  UNIQUE KEY uq_clinics_subdomain     (subdomain),
  UNIQUE KEY uq_clinics_custom_domain (custom_domain),
  KEY        idx_clinics_list         (deleted_at, updated_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

/* UUID自動採番（未指定時のみ） */
DELIMITER $$
CREATE TRIGGER tr_clinics_bi_uuid_v7
BEFORE INSERT ON clinics
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END$$
DELIMITER ;

/* UUID不変＋row_versionインクリメント（★重要） */
DELIMITER $$
CREATE TRIGGER tr_clinics_bu_rowver
BEFORE UPDATE ON clinics
FOR EACH ROW
BEGIN
  /* UUIDは不変：誤更新による連鎖CASCADE事故を防止 */
  SET NEW.uuid = OLD.uuid;
  /* 楽観ロック／差分検知 */
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;

/* =========================================================
   clinic_settings — 院ごとの運用/帳票設定（1院1行）
   ---------------------------------------------------------
   方針:
   - clinic_uuid UNIQUE で 1院1行。
   - 請求点数/自費レート/税率/端数処理などを保持（最低限）。
   - 帳票系: ロゴパス/フッター文/請求窓口担当/インボイス登録番号 等。
   - FKは clinics(uuid) に対して ON UPDATE CASCADE / ON DELETE RESTRICT。
   - row_version は編集ごとに+1。
   ========================================================= */
CREATE TABLE clinic_settings (
  id                           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  clinic_uuid                  BINARY(16) NOT NULL,     -- ↔ clinics.uuid（1院1行）
  /* 会計系既定値 */
  yen_per_point                DECIMAL(8,2) NOT NULL DEFAULT 0.00,
  copay_rate                   DECIMAL(5,2) NOT NULL DEFAULT 0.00,   -- 例: 30.00 (=30%)
  default_tax_rate             DECIMAL(4,2) NOT NULL DEFAULT 0.00,   -- 例: 10.00 (=10%)
  price_rounding               ENUM('none','round','ceil','floor') NOT NULL DEFAULT 'round',
  price_rounding_unit          INT UNSIGNED NOT NULL DEFAULT 1,      -- 1/10/100 など

  /* 帳票/表示 */
  billing_contact_name         VARCHAR(128) NULL,       -- 請求窓口担当者名（運用表示）
  invoice_logo_path            VARCHAR(255) NULL,       -- 帳票ロゴ（S3等のパス）
  receipt_footer_text          VARCHAR(255) NULL,       -- レシート定型フッター
  invoice_registration_number  VARCHAR(14)  NULL,       -- 例: 'T' + 13桁

  /* 監査・運用列 */
  created_at                   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at                   DATETIME NULL,
  row_version                  BIGINT UNSIGNED NOT NULL DEFAULT 1,

  /* 一意/索引/FK */
  UNIQUE KEY uq_clinic_settings_clinic (clinic_uuid),
  KEY        idx_clinic_settings_list  (deleted_at, updated_at, id),
  CONSTRAINT fk_clinic_settings_clinic
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE RESTRICT,

  /* 任意: インボイス登録番号の形式検証（対応エンジンのみ有効） */
  CONSTRAINT chk_clinic_settings_invoice_reg
    CHECK (invoice_registration_number IS NULL
           OR invoice_registration_number REGEXP '^T[0-9]{13}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

/* row_versionのインクリメント（UUIDは保持していないため固定不要） */
DELIMITER $$
DROP TRIGGER IF EXISTS tr_clinic_settings_bu_rowver;
CREATE TRIGGER tr_clinic_settings_bu_rowver
BEFORE UPDATE ON clinic_settings
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END$$
DELIMITER ;
