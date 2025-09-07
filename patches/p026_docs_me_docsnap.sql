SET NAMES utf8mb4;

-- =======================================================================
-- 現場発行書類：4種（docsnap v1 組み込み版／非JSON）
--   1) 診断書 (Medical Certificate)
--   2) ワクチン証明書 (Vaccination Certificate)
--   3) 休薬期間通知書 (Withdrawal Period Notice)
--   4) 妊娠鑑定書 (Pregnancy Diagnosis Certificate)
-- 設計要点:
--   • v_doc_*        … 発行"元"ビュー（アンカー = checkups.uuid）
--   • v_docsnap_*    … 発行"済"スナップ（列は <prefix>_col で保存。prefix='checkups'）
--   • *_mirror       … ME v1 ミラー（updated_at → updated_at_source に改名）
--   • docsnap v1     … 汎用SPで「ビュー1行 → スナップ1行」固化（COLUMNS_MISMATCH/SOURCE_NOT_FOUND）
--   • ME v1          … mirror_targets にスナップ表を登録（2分毎の sp_mirror_all() で反映）
-- 依存:
--   • checkups(uuid, farm_uuid, individual_uuid, performed_at, note, updated_at, deleted_at)
--   • checkup_items(checkup_uuid, item_type, label, value_text, numeric_value, unit,
--                   withdrawal_days, vaccine_name, result, method, updated_at, deleted_at)
--   • individuals(uuid, name, ear_tag, updated_at)
--   • farms(uuid, clinic_uuid, name, updated_at)
--   • 関数 uuid_v7_bin() が存在
-- =======================================================================


/* =======================================================================
   1) v_doc_medical_certificate — 診断書（非JSON）
   ======================================================================= */
DROP VIEW IF EXISTS v_doc_medical_certificate;
CREATE VIEW v_doc_medical_certificate AS
SELECT
  c.uuid                AS uuid,                 -- アンカー（checkups.uuid）
  f.clinic_uuid         AS clinic_uuid,
  c.farm_uuid           AS farm_uuid,
  c.individual_uuid     AS individual_uuid,
  i.name                AS individual_name,
  i.ear_tag             AS ear_tag,
  c.performed_at        AS performed_at,
  'Medical Certificate' AS title,
  -- 所見/診断の要約（改行区切り）
  (
    SELECT GROUP_CONCAT(
             CONCAT(
               ci.label, ': ',
               COALESCE(ci.value_text, CAST(ci.numeric_value AS CHAR)),
               IF(ci.unit IS NOT NULL AND ci.unit<>'', CONCAT(' ', ci.unit), '')
             )
             ORDER BY ci.label SEPARATOR '\n'
           )
    FROM checkup_items ci
    WHERE ci.checkup_uuid = c.uuid
      AND ci.deleted_at IS NULL
      AND ci.item_type IN ('finding','diagnosis')
  ) AS diagnosis_summary,
  c.note                AS checkup_note,
  -- 最終更新（参照要素の最大）
  GREATEST(
    c.updated_at,
    IFNULL((SELECT MAX(ci.updated_at)
              FROM checkup_items ci
             WHERE ci.checkup_uuid=c.uuid AND ci.deleted_at IS NULL
               AND ci.item_type IN ('finding','diagnosis')), '1970-01-01'),
    i.updated_at,
    f.updated_at
  ) AS updated_at
FROM checkups c
JOIN individuals i ON i.uuid=c.individual_uuid
JOIN farms      f ON f.uuid=c.farm_uuid
WHERE c.deleted_at IS NULL;


/* =======================================================================
   2) v_doc_vaccination_certificate — ワクチン証明書（非JSON）
   ======================================================================= */
DROP VIEW IF EXISTS v_doc_vaccination_certificate;
CREATE VIEW v_doc_vaccination_certificate AS
SELECT
  c.uuid                         AS uuid,
  f.clinic_uuid                  AS clinic_uuid,
  c.farm_uuid                    AS farm_uuid,
  c.individual_uuid              AS individual_uuid,
  i.name                         AS individual_name,
  i.ear_tag                      AS ear_tag,
  c.performed_at                 AS performed_at,
  'Vaccination Certificate'      AS title,
  -- その時点までの履歴（新しい順・改行区切り）
  (
    SELECT GROUP_CONCAT(
             CONCAT(
               DATE_FORMAT(c2.performed_at, '%Y-%m-%d'), ' ',
               COALESCE(ci.vaccine_name, ci.label),
               IF(ci.value_text IS NOT NULL AND ci.value_text<>'',
                  CONCAT(' - ', ci.value_text), '')
             )
             ORDER BY c2.performed_at DESC SEPARATOR '\n'
           )
      FROM checkups c2
      JOIN checkup_items ci ON ci.checkup_uuid=c2.uuid
     WHERE c2.individual_uuid=c.individual_uuid
       AND c2.deleted_at IS NULL
       AND ci.deleted_at IS NULL
       AND ci.item_type IN ('vaccine','prevention')
       AND c2.performed_at <= c.performed_at
  ) AS history_text,
  GREATEST(
    c.updated_at,
    IFNULL((
      SELECT MAX(ci.updated_at)
        FROM checkups c2
        JOIN checkup_items ci ON ci.checkup_uuid=c2.uuid
       WHERE c2.individual_uuid=c.individual_uuid
         AND c2.deleted_at IS NULL
         AND ci.deleted_at IS NULL
         AND ci.item_type IN ('vaccine','prevention')
         AND c2.performed_at <= c.performed_at
    ), '1970-01-01'),
    i.updated_at,
    f.updated_at
  ) AS updated_at
FROM checkups c
JOIN individuals i ON i.uuid=c.individual_uuid
JOIN farms      f ON f.uuid=c.farm_uuid
WHERE c.deleted_at IS NULL;


/* =======================================================================
   3) v_doc_withdrawal_notice — 休薬期間通知書（非JSON）
   ======================================================================= */
DROP VIEW IF EXISTS v_doc_withdrawal_notice;
CREATE VIEW v_doc_withdrawal_notice AS
SELECT
  c.uuid                         AS uuid,
  f.clinic_uuid                  AS clinic_uuid,
  c.farm_uuid                    AS farm_uuid,
  c.individual_uuid              AS individual_uuid,
  i.name                         AS individual_name,
  i.ear_tag                      AS ear_tag,
  c.performed_at                 AS performed_at,
  'Withdrawal Period Notice'     AS title,
  -- 最大休薬日数
  (
    SELECT IFNULL(MAX(COALESCE(ci.withdrawal_days,0)),0)
    FROM checkup_items ci
    WHERE ci.checkup_uuid=c.uuid
      AND ci.deleted_at IS NULL
      AND ci.item_type IN ('medication','drug_admin','rx')
  ) AS max_withdrawal_days,
  -- 休薬満了日（最大を適用）
  (
    SELECT DATE_ADD(
             c.performed_at,
             INTERVAL IFNULL(MAX(COALESCE(ci.withdrawal_days,0)),0) DAY
           )
    FROM checkup_items ci
    WHERE ci.checkup_uuid=c.uuid
      AND ci.deleted_at IS NULL
      AND ci.item_type IN ('medication','drug_admin','rx')
  ) AS withdrawal_until,
  -- 詳細（降順・改行区切り）
  (
    SELECT GROUP_CONCAT(
             CONCAT(
               ci.label, ': ',
               COALESCE(ci.withdrawal_days,0), ' days (until ',
               DATE_FORMAT(DATE_ADD(c.performed_at, INTERVAL COALESCE(ci.withdrawal_days,0) DAY), '%Y-%m-%d'),
               ')'
             )
             ORDER BY COALESCE(ci.withdrawal_days,0) DESC, ci.label
             SEPARATOR '\n'
           )
    FROM checkup_items ci
    WHERE ci.checkup_uuid=c.uuid
      AND ci.deleted_at IS NULL
      AND ci.item_type IN ('medication','drug_admin','rx')
  ) AS withdrawal_details_text,
  GREATEST(
    c.updated_at,
    IFNULL((SELECT MAX(ci.updated_at)
              FROM checkup_items ci
             WHERE ci.checkup_uuid=c.uuid
               AND ci.deleted_at IS NULL
               AND ci.item_type IN ('medication','drug_admin','rx')), '1970-01-01'),
    i.updated_at,
    f.updated_at
  ) AS updated_at
FROM checkups c
JOIN individuals i ON i.uuid=c.individual_uuid
JOIN farms      f ON f.uuid=c.farm_uuid
WHERE c.deleted_at IS NULL;


/* =======================================================================
   4) v_doc_pregnancy_certificate — 妊娠鑑定書（非JSON）
   ======================================================================= */
DROP VIEW IF EXISTS v_doc_pregnancy_certificate;
CREATE VIEW v_doc_pregnancy_certificate AS
SELECT
  c.uuid                               AS uuid,
  f.clinic_uuid                        AS clinic_uuid,
  c.farm_uuid                          AS farm_uuid,
  c.individual_uuid                    AS individual_uuid,
  i.name                               AS individual_name,
  i.ear_tag                            AS ear_tag,
  c.performed_at                       AS performed_at,
  'Pregnancy Diagnosis Certificate'    AS title,
  -- 判定結果（result → value_text の順で代表値）
  (
    SELECT COALESCE(
             MAX(CASE WHEN ci.result IS NOT NULL THEN ci.result END),
             MAX(CASE WHEN ci.value_text IS NOT NULL THEN ci.value_text END),
             'unknown'
           )
    FROM checkup_items ci
    WHERE ci.checkup_uuid=c.uuid
      AND ci.deleted_at IS NULL
      AND ci.item_type='pregnancy_exam'
  ) AS result_text,
  -- 実施方法（重複排除のカンマ区切り）
  (
    SELECT GROUP_CONCAT(DISTINCT COALESCE(ci.method, ci.label) ORDER BY COALESCE(ci.method, ci.label) SEPARATOR ', ')
    FROM checkup_items ci
    WHERE ci.checkup_uuid=c.uuid
      AND ci.deleted_at IS NULL
      AND ci.item_type='pregnancy_exam'
  ) AS methods_text,
  GREATEST(
    c.updated_at,
    IFNULL((SELECT MAX(ci.updated_at)
              FROM checkup_items ci
             WHERE ci.checkup_uuid=c.uuid
               AND ci.deleted_at IS NULL
               AND ci.item_type='pregnancy_exam'), '1970-01-01'),
    i.updated_at,
    f.updated_at
  ) AS updated_at
FROM checkups c
JOIN individuals i ON i.uuid=c.individual_uuid
JOIN farms      f ON f.uuid=c.farm_uuid
WHERE c.deleted_at IS NULL;



/* =======================================================================
   5) docsnap v1 — 汎用ターゲット＆SP（全列 prefix 保存／エラー制御）
   ======================================================================= */

-- A) docsnap 対象一覧
DROP TABLE IF EXISTS docsnap_targets;
CREATE TABLE docsnap_targets (
  id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  doc_kind     VARCHAR(64)  NOT NULL,     -- 例: 'medical_certificate'
  src_view     VARCHAR(64)  NOT NULL,     -- 例: 'v_doc_medical_certificate'
  dest_table   VARCHAR(64)  NOT NULL,     -- 例: 'v_docsnap_medical_certificate'
  dest_prefix  VARCHAR(64)  NOT NULL,     -- 例: 'checkups'  ← スナップ列は 'checkups_*'
  where_col    VARCHAR(64)  NOT NULL DEFAULT 'uuid',
  is_enabled   TINYINT(1)   NOT NULL DEFAULT 1,
  UNIQUE KEY uq_docsnap_kind (doc_kind)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- B) 1件発行（ビュー1行 → スナップ1行）
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_docsnap_insert_one $$
CREATE PROCEDURE sp_docsnap_insert_one(
  IN p_target_id   INT UNSIGNED,
  IN p_source_uuid BINARY(16)
)
proc:BEGIN
  DECLARE v_src_view    VARCHAR(64);
  DECLARE v_dest_table  VARCHAR(64);
  DECLARE v_where_col   VARCHAR(64);
  DECLARE v_prefix      VARCHAR(64);
  DECLARE v_db          VARCHAR(64);
  DECLARE v_cols_insert LONGTEXT;
  DECLARE v_cols_select LONGTEXT;
  DECLARE v_src_cnt     INT;
  DECLARE v_join_cnt    INT;
  DECLARE v_sql         LONGTEXT;

  SELECT src_view, dest_table, dest_prefix, where_col
    INTO v_src_view, v_dest_table, v_prefix, v_where_col
  FROM docsnap_targets
  WHERE id=p_target_id AND is_enabled=1
  LIMIT 1;
  IF v_src_view IS NULL THEN LEAVE proc; END IF;

  SET v_db = DATABASE();
  SET SESSION group_concat_max_len = 1024*1024;

  -- ビューの全カラム数
  SELECT COUNT(*) INTO v_src_cnt
    FROM INFORMATION_SCHEMA.COLUMNS s
   WHERE s.TABLE_SCHEMA=v_db AND s.TABLE_NAME=v_src_view;

  -- ビュー列 s に対応するスナップ列 d = CONCAT(prefix,'_',s.COLUMN_NAME)
  SELECT
    GROUP_CONCAT(CONCAT('`', d.COLUMN_NAME, '`') ORDER BY s.ORDINAL_POSITION SEPARATOR ', '),
    GROUP_CONCAT(CONCAT('s.`', s.COLUMN_NAME, '`') ORDER BY s.ORDINAL_POSITION SEPARATOR ', '),
    COUNT(*)
    INTO v_cols_insert, v_cols_select, v_join_cnt
  FROM INFORMATION_SCHEMA.COLUMNS s
  JOIN INFORMATION_SCHEMA.COLUMNS d
    ON d.TABLE_SCHEMA=v_db
   AND d.TABLE_NAME  =v_dest_table
   AND d.COLUMN_NAME =CONCAT(v_prefix, '_', s.COLUMN_NAME)
  WHERE s.TABLE_SCHEMA=v_db AND s.TABLE_NAME=v_src_view;

  IF v_join_cnt IS NULL THEN SET v_join_cnt=0; END IF;

  -- 列不一致はシグナル
  IF v_join_cnt <> v_src_cnt THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='COLUMNS_MISMATCH';
  END IF;

  -- 挿入実行（システム列 uuid/issued_at 等はスナップ側のデフォルト/トリガで付与）
  SET v_sql = CONCAT(
    'INSERT INTO `', v_dest_table, '` (', v_cols_insert, ') ',
    'SELECT ', v_cols_select, ' ',
    'FROM `', v_src_view, '` s ',
    'WHERE s.`', v_where_col, '` = ? ',
    'LIMIT 1'
  );
  PREPARE s1 FROM v_sql; EXECUTE s1 USING p_source_uuid; DEALLOCATE PREPARE s1;

  IF ROW_COUNT() = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='SOURCE_NOT_FOUND';
  END IF;

  SELECT ROW_COUNT() AS rows_inserted;
END $$

-- C) 使いやすい薄いラッパ（doc_kind 指定）
DROP PROCEDURE IF EXISTS sp_docsnap_issue $$
CREATE PROCEDURE sp_docsnap_issue(
  IN p_doc_kind    VARCHAR(64),
  IN p_source_uuid BINARY(16)
)
BEGIN
  DECLARE v_id INT UNSIGNED;
  SELECT id INTO v_id
    FROM docsnap_targets
   WHERE doc_kind=p_doc_kind AND is_enabled=1
   LIMIT 1;
  IF v_id IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DOC_KIND_NOT_CONFIGURED';
  END IF;
  CALL sp_docsnap_insert_one(v_id, p_source_uuid);
END $$

DELIMITER ;



/* =======================================================================
   6) スナップ保存テーブル（発行済み）
   • 列はすべて 'checkups_' プレフィックス（= ビューの列名へ一括対応）
   • システム列（uuid/issued_at/row_version/created_at/updated_at）は独立
   ======================================================================= */

-- 共通トリガの雛形を各テーブルに用意（uuid採番・row_version加算）
-- ※ uuid_v7_bin() 必須
DELIMITER $$

/* 1) 診断書 */
DROP TABLE IF EXISTS v_docsnap_medical_certificate;
CREATE TABLE v_docsnap_medical_certificate (
  uuid                           BINARY(16) PRIMARY KEY,
  issued_at                      DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  issued_by_vet_user_uuid        BINARY(16) NULL,
  row_version                    BIGINT UNSIGNED NOT NULL DEFAULT 1,
  created_at                     DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at                     DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),

  -- ビュー列に対応（prefix = 'checkups'）
  checkups_uuid                  BINARY(16) NOT NULL,
  checkups_clinic_uuid           BINARY(16) NOT NULL,
  checkups_farm_uuid             BINARY(16) NOT NULL,
  checkups_individual_uuid       BINARY(16) NOT NULL,
  checkups_individual_name       VARCHAR(255) NOT NULL,
  checkups_ear_tag               VARCHAR(64) NULL,
  checkups_performed_at          DATETIME(6) NOT NULL,
  checkups_title                 VARCHAR(255) NOT NULL,
  checkups_diagnosis_summary     TEXT NULL,
  checkups_checkup_note          TEXT NULL,
  checkups_updated_at            DATETIME(6) NOT NULL,

  KEY idx_src    (checkups_uuid),
  KEY idx_tenant (checkups_clinic_uuid, issued_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP TRIGGER IF EXISTS tr_docsnap_mc_bi_uuid $$
CREATE TRIGGER tr_docsnap_mc_bi_uuid
BEFORE INSERT ON v_docsnap_medical_certificate
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid=UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$

DROP TRIGGER IF EXISTS tr_docsnap_mc_bu_rowver $$
CREATE TRIGGER tr_docsnap_mc_bu_rowver
BEFORE UPDATE ON v_docsnap_medical_certificate
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END $$


/* 2) ワクチン証明書 */
DROP TABLE IF EXISTS v_docsnap_vaccination_certificate;
CREATE TABLE v_docsnap_vaccination_certificate (
  uuid                           BINARY(16) PRIMARY KEY,
  issued_at                      DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  issued_by_vet_user_uuid        BINARY(16) NULL,
  row_version                    BIGINT UNSIGNED NOT NULL DEFAULT 1,
  created_at                     DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at                     DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),

  checkups_uuid                  BINARY(16) NOT NULL,
  checkups_clinic_uuid           BINARY(16) NOT NULL,
  checkups_farm_uuid             BINARY(16) NOT NULL,
  checkups_individual_uuid       BINARY(16) NOT NULL,
  checkups_individual_name       VARCHAR(255) NOT NULL,
  checkups_ear_tag               VARCHAR(64) NULL,
  checkups_performed_at          DATETIME(6) NOT NULL,
  checkups_title                 VARCHAR(255) NOT NULL,
  checkups_history_text          MEDIUMTEXT NULL,
  checkups_updated_at            DATETIME(6) NOT NULL,

  KEY idx_src    (checkups_uuid),
  KEY idx_tenant (checkups_clinic_uuid, issued_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP TRIGGER IF EXISTS tr_docsnap_vc_bi_uuid $$
CREATE TRIGGER tr_docsnap_vc_bi_uuid
BEFORE INSERT ON v_docsnap_vaccination_certificate
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid=UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$

DROP TRIGGER IF EXISTS tr_docsnap_vc_bu_rowver $$
CREATE TRIGGER tr_docsnap_vc_bu_rowver
BEFORE UPDATE ON v_docsnap_vaccination_certificate
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END $$


/* 3) 休薬期間通知書 */
DROP TABLE IF EXISTS v_docsnap_withdrawal_notice;
CREATE TABLE v_docsnap_withdrawal_notice (
  uuid                           BINARY(16) PRIMARY KEY,
  issued_at                      DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  issued_by_vet_user_uuid        BINARY(16) NULL,
  row_version                    BIGINT UNSIGNED NOT NULL DEFAULT 1,
  created_at                     DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at                     DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),

  checkups_uuid                  BINARY(16) NOT NULL,
  checkups_clinic_uuid           BINARY(16) NOT NULL,
  checkups_farm_uuid             BINARY(16) NOT NULL,
  checkups_individual_uuid       BINARY(16) NOT NULL,
  checkups_individual_name       VARCHAR(255) NOT NULL,
  checkups_ear_tag               VARCHAR(64) NULL,
  checkups_performed_at          DATETIME(6) NOT NULL,
  checkups_title                 VARCHAR(255) NOT NULL,
  checkups_max_withdrawal_days   INT NOT NULL,
  checkups_withdrawal_until      DATE NULL,
  checkups_withdrawal_details_text MEDIUMTEXT NULL,
  checkups_updated_at            DATETIME(6) NOT NULL,

  KEY idx_src    (checkups_uuid),
  KEY idx_tenant (checkups_clinic_uuid, issued_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP TRIGGER IF EXISTS tr_docsnap_wn_bi_uuid $$
CREATE TRIGGER tr_docsnap_wn_bi_uuid
BEFORE INSERT ON v_docsnap_withdrawal_notice
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid=UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$

DROP TRIGGER IF EXISTS tr_docsnap_wn_bu_rowver $$
CREATE TRIGGER tr_docsnap_wn_bu_rowver
BEFORE UPDATE ON v_docsnap_withdrawal_notice
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END $$


/* 4) 妊娠鑑定書 */
DROP TABLE IF EXISTS v_docsnap_pregnancy_certificate;
CREATE TABLE v_docsnap_pregnancy_certificate (
  uuid                           BINARY(16) PRIMARY KEY,
  issued_at                      DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  issued_by_vet_user_uuid        BINARY(16) NULL,
  row_version                    BIGINT UNSIGNED NOT NULL DEFAULT 1,
  created_at                     DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at                     DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),

  checkups_uuid                  BINARY(16) NOT NULL,
  checkups_clinic_uuid           BINARY(16) NOT NULL,
  checkups_farm_uuid             BINARY(16) NOT NULL,
  checkups_individual_uuid       BINARY(16) NOT NULL,
  checkups_individual_name       VARCHAR(255) NOT NULL,
  checkups_ear_tag               VARCHAR(64) NULL,
  checkups_performed_at          DATETIME(6) NOT NULL,
  checkups_title                 VARCHAR(255) NOT NULL,
  checkups_result_text           VARCHAR(255) NULL,
  checkups_methods_text          TEXT NULL,
  checkups_updated_at            DATETIME(6) NOT NULL,

  KEY idx_src    (checkups_uuid),
  KEY idx_tenant (checkups_clinic_uuid, issued_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP TRIGGER IF EXISTS tr_docsnap_pc_bi_uuid $$
CREATE TRIGGER tr_docsnap_pc_bi_uuid
BEFORE INSERT ON v_docsnap_pregnancy_certificate
FOR EACH ROW
BEGIN
  IF NEW.uuid IS NULL OR NEW.uuid=UNHEX(REPEAT('0',32)) THEN
    SET NEW.uuid = uuid_v7_bin();
  END IF;
END $$

DROP TRIGGER IF EXISTS tr_docsnap_pc_bu_rowver $$
CREATE TRIGGER tr_docsnap_pc_bu_rowver
BEFORE UPDATE ON v_docsnap_pregnancy_certificate
FOR EACH ROW
BEGIN
  SET NEW.row_version = OLD.row_version + 1;
END $$

DELIMITER ;



/* =======================================================================
   7) ミラーテーブル（ME v1 用）
   • スナップ列は同名でコピー、updated_at → updated_at_source に改名
   ======================================================================= */

-- 1) 診断書
DROP TABLE IF EXISTS v_docsnap_medical_certificate_mirror;
CREATE TABLE v_docsnap_medical_certificate_mirror (
  uuid                           BINARY(16) PRIMARY KEY,
  issued_at                      DATETIME(6) NOT NULL,
  issued_by_vet_user_uuid        BINARY(16) NULL,
  row_version                    BIGINT UNSIGNED NOT NULL,
  created_at                     DATETIME(6) NOT NULL,
  updated_at_source              DATETIME(6) NOT NULL,

  checkups_uuid                  BINARY(16) NOT NULL,
  checkups_clinic_uuid           BINARY(16) NOT NULL,
  checkups_farm_uuid             BINARY(16) NOT NULL,
  checkups_individual_uuid       BINARY(16) NOT NULL,
  checkups_individual_name       VARCHAR(255) NOT NULL,
  checkups_ear_tag               VARCHAR(64) NULL,
  checkups_performed_at          DATETIME(6) NOT NULL,
  checkups_title                 VARCHAR(255) NOT NULL,
  checkups_diagnosis_summary     TEXT NULL,
  checkups_checkup_note          TEXT NULL,
  checkups_updated_at            DATETIME(6) NOT NULL,

  KEY idx_src    (checkups_uuid),
  KEY idx_tenant (checkups_clinic_uuid, issued_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2) ワクチン証明書
DROP TABLE IF EXISTS v_docsnap_vaccination_certificate_mirror;
CREATE TABLE v_docsnap_vaccination_certificate_mirror (
  uuid                           BINARY(16) PRIMARY KEY,
  issued_at                      DATETIME(6) NOT NULL,
  issued_by_vet_user_uuid        BINARY(16) NULL,
  row_version                    BIGINT UNSIGNED NOT NULL,
  created_at                     DATETIME(6) NOT NULL,
  updated_at_source              DATETIME(6) NOT NULL,

  checkups_uuid                  BINARY(16) NOT NULL,
  checkups_clinic_uuid           BINARY(16) NOT NULL,
  checkups_farm_uuid             BINARY(16) NOT NULL,
  checkups_individual_uuid       BINARY(16) NOT NULL,
  checkups_individual_name       VARCHAR(255) NOT NULL,
  checkups_ear_tag               VARCHAR(64) NULL,
  checkups_performed_at          DATETIME(6) NOT NULL,
  checkups_title                 VARCHAR(255) NOT NULL,
  checkups_history_text          MEDIUMTEXT NULL,
  checkups_updated_at            DATETIME(6) NOT NULL,

  KEY idx_src    (checkups_uuid),
  KEY idx_tenant (checkups_clinic_uuid, issued_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3) 休薬期間通知書
DROP TABLE IF EXISTS v_docsnap_withdrawal_notice_mirror;
CREATE TABLE v_docsnap_withdrawal_notice_mirror (
  uuid                           BINARY(16) PRIMARY KEY,
  issued_at                      DATETIME(6) NOT NULL,
  issued_by_vet_user_uuid        BINARY(16) NULL,
  row_version                    BIGINT UNSIGNED NOT NULL,
  created_at                     DATETIME(6) NOT NULL,
  updated_at_source              DATETIME(6) NOT NULL,

  checkups_uuid                  BINARY(16) NOT NULL,
  checkups_clinic_uuid           BINARY(16) NOT NULL,
  checkups_farm_uuid             BINARY(16) NOT NULL,
  checkups_individual_uuid       BINARY(16) NOT NULL,
  checkups_individual_name       VARCHAR(255) NOT NULL,
  checkups_ear_tag               VARCHAR(64) NULL,
  checkups_performed_at          DATETIME(6) NOT NULL,
  checkups_title                 VARCHAR(255) NOT NULL,
  checkups_max_withdrawal_days   INT NOT NULL,
  checkups_withdrawal_until      DATE NULL,
  checkups_withdrawal_details_text MEDIUMTEXT NULL,
  checkups_updated_at            DATETIME(6) NOT NULL,

  KEY idx_src    (checkups_uuid),
  KEY idx_tenant (checkups_clinic_uuid, issued_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4) 妊娠鑑定書
DROP TABLE IF EXISTS v_docsnap_pregnancy_certificate_mirror;
CREATE TABLE v_docsnap_pregnancy_certificate_mirror (
  uuid                           BINARY(16) PRIMARY KEY,
  issued_at                      DATETIME(6) NOT NULL,
  issued_by_vet_user_uuid        BINARY(16) NULL,
  row_version                    BIGINT UNSIGNED NOT NULL,
  created_at                     DATETIME(6) NOT NULL,
  updated_at_source              DATETIME(6) NOT NULL,

  checkups_uuid                  BINARY(16) NOT NULL,
  checkups_clinic_uuid           BINARY(16) NOT NULL,
  checkups_farm_uuid             BINARY(16) NOT NULL,
  checkups_individual_uuid       BINARY(16) NOT NULL,
  checkups_individual_name       VARCHAR(255) NOT NULL,
  checkups_ear_tag               VARCHAR(64) NULL,
  checkups_performed_at          DATETIME(6) NOT NULL,
  checkups_title                 VARCHAR(255) NOT NULL,
  checkups_result_text           VARCHAR(255) NULL,
  checkups_methods_text          TEXT NULL,
  checkups_updated_at            DATETIME(6) NOT NULL,

  KEY idx_src    (checkups_uuid),
  KEY idx_tenant (checkups_clinic_uuid, issued_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;



/* =======================================================================
   8) ME v1 への登録（mirror_targets）
   ======================================================================= */
INSERT IGNORE INTO mirror_targets
  (source_table,                           mirror_table,                                  pk_col, updated_col, mirror_updated_col, batch_size, is_enabled)
VALUES
  ('v_docsnap_medical_certificate',        'v_docsnap_medical_certificate_mirror',        'uuid', 'updated_at', 'updated_at_source', 1000, 1),
  ('v_docsnap_vaccination_certificate',    'v_docsnap_vaccination_certificate_mirror',    'uuid', 'updated_at', 'updated_at_source', 1000, 1),
  ('v_docsnap_withdrawal_notice',          'v_docsnap_withdrawal_notice_mirror',          'uuid', 'updated_at', 'updated_at_source', 1000, 1),
  ('v_docsnap_pregnancy_certificate',      'v_docsnap_pregnancy_certificate_mirror',      'uuid', 'updated_at', 'updated_at_source', 1000, 1);



/* =======================================================================
   9) docsnap v1 ターゲット登録（doc_kind → view/snap/prefix）
   ======================================================================= */
INSERT IGNORE INTO docsnap_targets
  (doc_kind,                 src_view,                        dest_table,                           dest_prefix, where_col, is_enabled)
VALUES
  ('medical_certificate',    'v_doc_medical_certificate',     'v_docsnap_medical_certificate',      'checkups',  'uuid',    1),
  ('vaccination_certificate','v_doc_vaccination_certificate', 'v_docsnap_vaccination_certificate',  'checkups',  'uuid',    1),
  ('withdrawal_notice',      'v_doc_withdrawal_notice',       'v_docsnap_withdrawal_notice',        'checkups',  'uuid',    1),
  ('pregnancy_certificate',  'v_doc_pregnancy_certificate',   'v_docsnap_pregnancy_certificate',    'checkups',  'uuid',    1);

/* 以上：docsnap v1 組み込み完了 */
