/* 1500_insurance_create_insurance_enrollments.sql */
-- @phase: create
-- @provides: table:insurance_enrollments
-- @requires: table:farms
-- 方針: 原文どおりの列定義とCHECK。索引とFKは別ファイルへ移設。
-- 備考: MySQL 8.0+（ウィンドウ関数はビュー側で使用）

SET NAMES utf8mb4;

/* 再デプロイ安全化（本体テーブル） */
DROP TABLE IF EXISTS `insurance_enrollments`;

CREATE TABLE IF NOT EXISTS `insurance_enrollments` (
  /* 識別子（AUTO_INCREMENT 主キー） */
  `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

  /* テナント（FARM単位, BINARY(16) UUIDv7想定） */
  `farm_uuid` BINARY(16) NOT NULL,

  /* 加入者コード（共済番号など8桁を想定） */
  `subscriber_code` CHAR(8) NOT NULL,

  /* 入力ステータス（英語ENUM：入力値の状態） */
  `status` ENUM('insured','non_insured','unknown') NOT NULL DEFAULT 'unknown',

  /* 期間（端NULL許容）— 両端NULLは today-valid とみなす */
  `start_date` DATE NULL,
  `end_date`   DATE NULL,

  /* 任意付帯 */
  `fiscal_year` YEAR NULL,
  `source_note` VARCHAR(255) NULL,

  /* 無効化(取消)と理由 — voided 行は代表選定から除外 */
  `voided_at`   DATETIME NULL,
  `void_reason` VARCHAR(255) NULL,

  /* v1p9: 楽観ロック & 論理削除 & 監査 */
  `row_version` BIGINT UNSIGNED NOT NULL DEFAULT 1,
  `deleted_at`  DATETIME NULL,
  `created_by`  INT UNSIGNED NULL,
  `created_at`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  /* 期間整合性（NULLはスルー） */
  CHECK ( `start_date` IS NULL OR `end_date` IS NULL OR `start_date` <= `end_date` )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  ROW_FORMAT=DYNAMIC;
