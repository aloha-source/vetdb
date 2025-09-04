/* 1600_appointment_create_appointments.sql */
-- @phase: create
-- @provides: table:appointments
-- @requires: table:clinics, table:farms, table:individuals, table:vet_users, function:uuid_v7_bin
-- 備考: 索引/外部キー/トリガは分離。本文は原文と同一機能。

SET NAMES utf8mb4;

/* 再デプロイ安全化（本体テーブル） */
DROP TABLE IF EXISTS appointments;

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
  updated_at                  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
