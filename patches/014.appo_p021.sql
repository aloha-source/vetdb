SET NAMES utf8mb4;

-- =========================================================
-- vetDB v1p7-mt — Google Calendar（代表アカウント×共有カレンダー）
-- 方針：
--  - 予定(appointments)は clinic/farm が消えても残す → ON DELETE SET NULL
--  - 連携側（tokens/settings/sync_state/AEL/fulfillments）は親が消えたら掃除 → ON DELETE CASCADE
--  - 付け替え＝「連携病院を変えたら、その時点以降に作られた予定のみ連携」
--  - すべて ROW_FORMAT=DYNAMIC / utf8mb4_unicode_ci
--  - uuid_v7_bin() が無ければ UUID_TO_BIN(UUID(), TRUE) に置換可
--
-- 【WORKER PLAYBOOK（概要）】
--  1) 同期対象の抽出
--     SELECT * FROM appointments ap
--      WHERE ap.deleted_at IS NULL
--        AND ap.clinic_uuid IS NOT NULL             -- 連携有効フラグ
--        AND ap.start_at >= NOW() - INTERVAL 1 DAY; -- 任意の再送ウィンドウ
--
--  2) 連携に必要な設定の取得（テナント＝ap.clinic_uuid）
--     - clinic_google_tokens: 代表トークンを取得・リフレッシュ
--     - clinic_calendar_settings: calendar_id を取得
--
--  3) AEL（リンク表）のアップサート・冪等化
--     - まず AEL を (clinic_uuid, appointment_uuid, google_calendar_id) で検索
--     - 無ければ Google の events.list を
--       privateExtendedProperty=appointment_uuid=<ap.uuid> で再探索
--       見つかれば update、無ければ insert
--     - payload には extendedProperties.private.appointment_uuid を必ず設定
--     - 成功後、AEL: google_event_id, etag, status='synced', synced_at を更新
--
--  4) 削除・キャンセル
--     - DBで ap.deleted_at IS NOT NULL または ap.status='cancelled' を検出したら
--       Google events.delete → AEL.status='deleted' に更新（必要ならAEL削除）
--
--  5) 差分同期（任意）
--     - calendar_sync_state(sync_token) を使い、events.list(syncToken=...) で追加/更新/削除を取り込み
--     - 410 Gone ならフルからやり直して新しい nextSyncToken を保存
--
--  6) 連携病院の付け替え（運用）
--     - farms.clinic_uuid を新クリニックへ更新
--     - 既存の未来予定は appointments.clinic_uuid=NULL で“連携停止”（以後の新規のみ連携）
--     - 既存AELは削除（以後の誤更新防止）
--       DELETE ael FROM appointment_event_links ael
--       JOIN appointments ap ON ap.uuid=ael.appointment_uuid
--        WHERE ap.farm_uuid=:farm AND ap.start_at>=NOW() AND ap.deleted_at IS NULL;
-- =========================================================


/* ---------- 事前：既存トリガを落とす（再作成のため） ---------- */
DROP TRIGGER IF EXISTS tr_appointments_bi_uuid_v7;
DROP TRIGGER IF EXISTS tr_appointments_bu_rowver;
DROP TRIGGER IF EXISTS tr_clinic_google_tokens_bu_rowver;
DROP TRIGGER IF EXISTS tr_clinic_calendar_settings_bu_rowver;
DROP TRIGGER IF EXISTS tr_appointment_event_links_bu_rowver;
DROP TRIGGER IF EXISTS tr_calendar_sync_state_bu_rowver;
DROP TRIGGER IF EXISTS tr_appointment_fulfillments_bu_rowver;

/* ---------- 依存の深い順にDROP ---------- */
DROP TABLE IF EXISTS appointment_fulfillments;
DROP TABLE IF EXISTS appointment_event_links;
DROP TABLE IF EXISTS calendar_sync_state;
DROP TABLE IF EXISTS clinic_calendar_settings;
DROP TABLE IF EXISTS clinic_google_tokens;
DROP TABLE IF EXISTS appointments;


/* =========================================================
   1) 予定本体（Appointments = Googleへ送る元）
   - clinic_uuid / farm_uuid は ON DELETE SET NULL（予定を残す）
   - clinic_uuid IS NULL は“連携停止”を意味する（ワーカーは同期しない）
   ========================================================= */
CREATE TABLE appointments (
  id                          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  clinic_uuid                 BINARY(16) NULL,               -- ↔ clinics.uuid（SET NULL方針）
  uuid                        BINARY(16) NOT NULL UNIQUE,    -- 予定の一意ID（v7推奨）
  farm_uuid                   BINARY(16) NULL,               -- ↔ farms.uuid（SET NULL）
  individual_uuid             BINARY(16) NULL,               -- ↔ individuals.uuid（SET NULL）
  organizer_vet_user_uuid     BINARY(16) NULL,               -- ↔ vet_users.uuid（SET NULL）
  created_by_vet_uuid         BINARY(16) NULL,               -- ↔ vet_users.uuid（SET NULL）
  updated_by_vet_user_uuid    BINARY(16) NULL,               -- ↔ vet_users.uuid（SET NULL）

  title                       VARCHAR(255) NOT NULL,
  note                        TEXT NULL,
  location_text               VARCHAR(255) NULL,
  start_at                    DATETIME NOT NULL,             -- UTC
  end_at                      DATETIME NOT NULL,             -- UTC
  time_zone                   VARCHAR(64) NULL,              -- 例: 'Asia/Tokyo'
  status                      ENUM('draft','scheduled','cancelled','archived')
                                NOT NULL DEFAULT 'scheduled',

  row_version                 BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at                  DATETIME NULL,
  created_at                  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  KEY idx_appt_list (deleted_at, updated_at, id),
  KEY idx_appt_tenant_time (clinic_uuid, start_at, end_at),
  KEY idx_appt_farm_time (farm_uuid, start_at, end_at),
  KEY idx_appt_individual (individual_uuid),
  KEY idx_appt_org (organizer_vet_user_uuid),

  CONSTRAINT fk_appt_clinic_uuid
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_appt_farm_uuid
    FOREIGN KEY (farm_uuid) REFERENCES farms(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_appt_individual_uuid
    FOREIGN KEY (individual_uuid) REFERENCES individuals(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_appt_organizer_vet
    FOREIGN KEY (organizer_vet_user_uuid) REFERENCES vet_users(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_appt_created_by_vet
    FOREIGN KEY (created_by_vet_uuid) REFERENCES vet_users(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_appt_updated_by_vet
    FOREIGN KEY (updated_by_vet_user_uuid) REFERENCES vet_users(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER tr_appointments_bi_uuid_v7
BEFORE INSERT ON appointments
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid = UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$

CREATE TRIGGER tr_appointments_bu_rowver
BEFORE UPDATE ON appointments
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END $$
DELIMITER ;


/* =========================================================
   2) 代表アカウントのOAuthトークン（クリニック単位）
   - クリニック削除で自動掃除 → ON DELETE CASCADE
   ========================================================= */
CREATE TABLE clinic_google_tokens (
  id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  clinic_uuid          BINARY(16) NOT NULL,                 -- ↔ clinics.uuid
  google_email         VARCHAR(255) NOT NULL,
  access_token_enc     TEXT NOT NULL,                       -- 暗号化済み
  refresh_token_enc    TEXT NOT NULL,                       -- 暗号化済み
  token_type           VARCHAR(32) NULL,
  scopes               TEXT NULL,
  expires_at           DATETIME NULL,
  revoked_at           DATETIME NULL,

  row_version          BIGINT UNSIGNED NOT NULL DEFAULT 1,
  created_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  UNIQUE KEY uq_clinic_token (clinic_uuid),
  KEY idx_tokens_list (updated_at, id),
  KEY idx_google_email (google_email),

  CONSTRAINT fk_clinic_token_clinic
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER tr_clinic_google_tokens_bu_rowver
BEFORE UPDATE ON clinic_google_tokens
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END $$
DELIMITER ;


/* =========================================================
   3) 共有カレンダー設定（クリニック単位）
   - クリニック削除で自動掃除 → ON DELETE CASCADE
   ========================================================= */
CREATE TABLE clinic_calendar_settings (
  id                          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  clinic_uuid                 BINARY(16) NOT NULL,           -- ↔ clinics.uuid
  calendar_id                 VARCHAR(255) NOT NULL,         -- '...@group.calendar.google.com'
  calendar_summary            VARCHAR(255) NULL,
  sync_owner_vet_user_uuid    BINARY(16) NULL,               -- ↔ vet_users.uuid（SET NULL）

  row_version                 BIGINT UNSIGNED NOT NULL DEFAULT 1,
  created_at                  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  UNIQUE KEY uq_clinic_calendar (clinic_uuid),
  KEY idx_calendar_id (calendar_id),
  KEY idx_clinic_calendar_list (updated_at, id),

  CONSTRAINT fk_clinic_calendar_clinic
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_clinic_calendar_sync_owner
    FOREIGN KEY (sync_owner_vet_user_uuid) REFERENCES vet_users(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER tr_clinic_calendar_settings_bu_rowver
BEFORE UPDATE ON clinic_calendar_settings
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END $$
DELIMITER ;


/* =========================================================
   4) Googleイベント対応表（AEL：共有カレンダー1件に集約）
   - テナント境界を保持しつつ、親消滅で掃除 → CASCADE
   - UNIQUE: (clinic_uuid, appointment_uuid, google_calendar_id)
   ========================================================= */
CREATE TABLE appointment_event_links (
  id                     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  clinic_uuid            BINARY(16) NOT NULL,           -- ↔ clinics.uuid（CASCADE）
  appointment_uuid       BINARY(16) NOT NULL,           -- ↔ appointments.uuid（CASCADE）
  google_calendar_id     VARCHAR(255) NOT NULL,
  google_event_id        VARCHAR(255) NOT NULL,
  ical_uid               VARCHAR(255) NULL,
  etag                   VARCHAR(255) NULL,
  writer_vet_user_uuid   BINARY(16) NULL,               -- ↔ vet_users.uuid（SET NULL, 監査用）
  status                 ENUM('pending','synced','failed','deleted','skipped')
                           NOT NULL DEFAULT 'pending',
  synced_at              DATETIME NULL,

  row_version            BIGINT UNSIGNED NOT NULL DEFAULT 1,
  created_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  UNIQUE KEY uq_link_per_calendar (clinic_uuid, appointment_uuid, google_calendar_id),
  KEY idx_link_gcal (google_calendar_id, google_event_id),
  KEY idx_link_writer (writer_vet_user_uuid),
  KEY idx_ael_list (updated_at, id),

  CONSTRAINT fk_ael_clinic
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_ael_appt
    FOREIGN KEY (appointment_uuid) REFERENCES appointments(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_ael_writer_vet
    FOREIGN KEY (writer_vet_user_uuid) REFERENCES vet_users(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER tr_appointment_event_links_bu_rowver
BEFORE UPDATE ON appointment_event_links
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END $$
DELIMITER ;


/* =========================================================
   5) 差分同期トークン（カレンダー単位）
   - クリニック削除で掃除 → CASCADE
   ========================================================= */
CREATE TABLE calendar_sync_state (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  clinic_uuid   BINARY(16) NOT NULL,                -- ↔ clinics.uuid（CASCADE）
  calendar_id   VARCHAR(255) NOT NULL,
  sync_token    TEXT NOT NULL,

  row_version   BIGINT UNSIGNED NOT NULL DEFAULT 1,
  updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                  ON UPDATE CURRENT_TIMESTAMP,

  UNIQUE KEY uq_calendar_sync (clinic_uuid, calendar_id),
  KEY idx_calendar (calendar_id),
  KEY idx_css_list (updated_at, id),

  CONSTRAINT fk_sync_clinic
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER tr_calendar_sync_state_bu_rowver
BEFORE UPDATE ON calendar_sync_state
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END $$
DELIMITER ;


/* =========================================================
   6) 予定→実施の疎結合（Visits＝記録 / Appointments＝予定）
   - 親が消えたら紐付けも掃除 → CASCADE
   ========================================================= */
CREATE TABLE appointment_fulfillments (
  id                 INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  clinic_uuid        BINARY(16) NOT NULL,           -- ↔ clinics.uuid（CASCADE）
  appointment_uuid   BINARY(16) NOT NULL,           -- ↔ appointments.uuid（CASCADE）
  visit_uuid         BINARY(16) NOT NULL,           -- ↔ visits.uuid（CASCADE）
  fulfilled_at       DATETIME NOT NULL,
  note               VARCHAR(255) NULL,

  row_version        BIGINT UNSIGNED NOT NULL DEFAULT 1,
  created_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

  UNIQUE KEY uq_appt_visit (appointment_uuid, visit_uuid),
  KEY idx_visit (visit_uuid),
  KEY idx_fulfill_list (created_at, id),

  CONSTRAINT fk_fulfill_clinic
    FOREIGN KEY (clinic_uuid) REFERENCES clinics(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_fulfill_appt
    FOREIGN KEY (appointment_uuid) REFERENCES appointments(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_fulfill_visit
    FOREIGN KEY (visit_uuid) REFERENCES visits(uuid)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

DELIMITER $$
CREATE TRIGGER tr_appointment_fulfillments_bu_rowver
BEFORE UPDATE ON appointment_fulfillments
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END $$
DELIMITER ;


-- =========================================================
-- （任意）整合性監視ビュー：ズレ検知
--  A) farmとappointmentsのテナント不一致
--  B) AELとappointmentsのテナント不一致
--  0件であることを健康指標にする
-- =========================================================
/*
CREATE OR REPLACE VIEW v_appt_tenant_mismatch AS
SELECT
  ap.uuid            AS appointment_uuid,
  ap.clinic_uuid     AS appt_clinic,
  f.clinic_uuid      AS farm_clinic,
  ap.farm_uuid,
  ap.start_at, ap.end_at, ap.title
FROM appointments ap
JOIN farms f ON f.uuid = ap.farm_uuid
WHERE ap.deleted_at IS NULL
  AND (ap.clinic_uuid IS NULL OR ap.clinic_uuid <> f.clinic_uuid);

CREATE OR REPLACE VIEW v_ael_tenant_mismatch AS
SELECT
  ael.appointment_uuid,
  ael.clinic_uuid   AS ael_clinic,
  ap.clinic_uuid    AS appt_clinic,
  ael.google_calendar_id,
  ael.google_event_id,
  ap.start_at, ap.end_at, ap.title
FROM appointment_event_links ael
JOIN appointments ap ON ap.uuid = ael.appointment_uuid
WHERE ap.deleted_at IS NULL
  AND (ap.clinic_uuid IS NULL OR ael.clinic_uuid <> ap.clinic_uuid);
*/
