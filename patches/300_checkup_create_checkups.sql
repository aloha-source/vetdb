/* 300_checkup_create_checkups.sql */
-- @phase: create
-- @provides: table:checkups
-- @requires: table:clinics, table:visits, table:individuals, table:receipt_header_drafts, function:uuid_v7_bin

DROP TABLE IF EXISTS checkups;

CREATE TABLE checkups (
  id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid         BINARY(16) NOT NULL UNIQUE,
  clinic_uuid  BINARY(16) NOT NULL,          -- ★ CSIFH
  visit_uuid   BINARY(16) NULL,              -- ↔ visits.uuid（SET NULL）
  individual_uuid BINARY(16) NOT NULL,       -- ↔ individuals.uuid（RESTRICT）

  /* p017: レシート草稿への直付け（草稿削除で自動デタッチ） */
  receipt_header_drafts_uuid BINARY(16) NULL, -- ↔ receipt_header_drafts.uuid

  /* 将来の確定カルテ弱リンク（FKなし） */
  chart_header_uuid BINARY(16) NULL,

  /* SOAP */
  s_subjective TEXT NULL,
  o_objective  TEXT NULL,
  a_assessment TEXT NULL,
  p_plan       TEXT NULL,

  /* TPR */
  temp_c     DECIMAL(4,1) NULL,
  pulse_bpm  SMALLINT UNSIGNED NULL,
  resp_bpm   SMALLINT UNSIGNED NULL,

  /* 現症・経過 */
  clinical_course TEXT NULL,

  /* 運用 */
  status      ENUM('draft','ready') NOT NULL DEFAULT 'draft',
  created_by  INT UNSIGNED NULL,
  row_version BIGINT UNSIGNED NOT NULL DEFAULT 1,
  deleted_at  DATETIME NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci ROW_FORMAT = DYNAMIC;
