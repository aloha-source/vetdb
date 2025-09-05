-- ============================================================
-- p022.1 : SAL v1（新規インストール統合版）＋ Receiptsヘッダ連携
-- 依存: p017.3（receipt_headers 等が既に存在）, p012系UUIDユーティリティが事前導入
-- ポリシー:
--  - ヘッダ1枚 = 請求1行（farm向け）
--  - 発行後にSPで作成/更新（未配分のみ上書き）/0円・voidedは未配分なら削除
--  - 会計の事実は自動で壊さない（配分済は凍結）
--  - 手修正は差分Onlyログ（sp_save_row_ultralite）
-- ============================================================

SET NAMES utf8mb4;

-- =========================================
-- 1) SAL コア（テーブル & ビュー）
-- =========================================

-- 再実行安全化
DROP VIEW  IF EXISTS v_receivable_open;
DROP TABLE IF EXISTS manual_corrections;
DROP TABLE IF EXISTS receivable_allocations;
DROP TABLE IF EXISTS receivable_credits;
DROP TABLE IF EXISTS receivable_charges;

-- 1-1) 請求（charge）：Receiptsヘッダ由来列を内包
CREATE TABLE receivable_charges (
  uuid                BINARY(16) PRIMARY KEY,
  counterparty_type   ENUM('farm','insurer') NOT NULL,
  counterparty_uuid   BINARY(16) NOT NULL,
  amount_yen          INT NOT NULL CHECK (amount_yen >= 0),
  occurred_at         DATETIME NOT NULL,

  -- Receiptsヘッダとの1:1リンク（支払い体験＝ヘッダ単位）
  source_receipt_header_uuid BINARY(16) NULL,

  row_version         BIGINT NOT NULL DEFAULT 0,
  created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  UNIQUE KEY uq_rc_source_receipt (source_receipt_header_uuid),
  KEY idx_rcp_ctp_ctu (counterparty_type, counterparty_uuid),
  KEY idx_rcp_occurred (occurred_at),

  CONSTRAINT fk_rc_source_receipt
    FOREIGN KEY (source_receipt_header_uuid) REFERENCES receipt_headers(uuid)
    ON UPDATE RESTRICT
    ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 1-2) クレジット（入金/調整/相殺は正数で統一）
CREATE TABLE receivable_credits (
  uuid                BINARY(16) PRIMARY KEY,
  counterparty_type   ENUM('farm','insurer') NOT NULL,
  counterparty_uuid   BINARY(16) NOT NULL,

  credit_type         ENUM('cash','direct_debit','insurer_payment','adjustment','void','rounding','discount') NOT NULL,
  amount_yen          INT NOT NULL CHECK (amount_yen >= 0),
  occurred_at         DATETIME NOT NULL,

  created_by_user_uuid  BINARY(16) NULL,
  created_via           ENUM('ui','import','system','api') NOT NULL DEFAULT 'ui',
  op_reason             VARCHAR(255) NULL,

  row_version         BIGINT NOT NULL DEFAULT 0,
  created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  KEY idx_ccp_ctp_ctu (counterparty_type, counterparty_uuid),
  KEY idx_credit_type (credit_type),
  KEY idx_credit_occurred (occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 1-3) 配分（どのクレジットをどの請求に何円充当したか）
CREATE TABLE receivable_allocations (
  id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  charge_uuid         BINARY(16) NOT NULL,
  credit_uuid         BINARY(16) NOT NULL,
  amount_yen          INT NOT NULL CHECK (amount_yen >= 0),

  created_by_user_uuid  BINARY(16) NULL,
  created_via           ENUM('ui','import','system','api') NOT NULL DEFAULT 'ui',
  note                  VARCHAR(255) NULL,

  row_version         BIGINT NOT NULL DEFAULT 0,
  created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

  KEY idx_alloc_charge (charge_uuid),
  KEY idx_alloc_credit (credit_uuid),

  CONSTRAINT fk_alloc_charge FOREIGN KEY (charge_uuid)  REFERENCES receivable_charges(uuid)
    ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT fk_alloc_credit FOREIGN KEY (credit_uuid)  REFERENCES receivable_credits(uuid)
    ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 1-4) 未収ビュー（open = 請求 − 配分合計）
CREATE VIEW v_receivable_open AS
SELECT
  c.uuid               AS charge_uuid,
  c.counterparty_type,
  c.counterparty_uuid,
  c.amount_yen,
  c.occurred_at,
  (c.amount_yen - IFNULL((SELECT SUM(a.amount_yen)
                            FROM receivable_allocations a
                           WHERE a.charge_uuid = c.uuid), 0)
  ) AS open_amount_yen
FROM receivable_charges c;

-- 1-5) 手修正ログ（手動UPDATEのみ差分JSONを記録）
CREATE TABLE manual_corrections (
  id               BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  occurred_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  actor_user_uuid  BINARY(16) NOT NULL,
  actor_name       VARCHAR(128) NULL,

  entity           VARCHAR(64) NOT NULL,
  charge_uuid      BINARY(16) NULL,
  credit_uuid      BINARY(16) NULL,
  alloc_id         BIGINT NULL,

  action           ENUM('update') NOT NULL DEFAULT 'update',
  reason           VARCHAR(255) NOT NULL,
  delta_json       LONGTEXT NOT NULL,

  KEY idx_mcl_charge (charge_uuid),
  KEY idx_mcl_credit (credit_uuid),
  KEY idx_mcl_alloc  (alloc_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =========================================
-- 2) 汎用：1行保存（差分Onlyログ）
-- =========================================
DELIMITER //

DROP PROCEDURE IF EXISTS sp_save_row_ultralite //
CREATE PROCEDURE sp_save_row_ultralite (
  IN  p_table            VARCHAR(64),
  IN  p_pk_col           VARCHAR(64),
  IN  p_pk_kind          ENUM('uuid','bigint'),
  IN  p_pk_bin           BINARY(16),
  IN  p_pk_bigint        BIGINT,
  IN  p_row_version      BIGINT,
  IN  p_after_json       LONGTEXT,
  IN  p_actor_uuid_bin   BINARY(16),
  IN  p_actor_name       VARCHAR(128),
  IN  p_reason           VARCHAR(255),
  IN  p_entity           VARCHAR(64),
  IN  p_log_key_column   VARCHAR(64)
)
proc: BEGIN
  DECLARE v_pk BLOB;
  DECLARE v_db_ver BIGINT;
  DECLARE v_delta LONGTEXT DEFAULT JSON_OBJECT();
  DECLARE v_changes INT DEFAULT 0;
  DECLARE v_set_csv LONGTEXT DEFAULT '';

  SET v_pk = IF(p_pk_kind='uuid', p_pk_bin, p_pk_bigint);

  START TRANSACTION;

  -- ① row_version ロック取得
  SET @sql_lock := CONCAT(
    'SELECT row_version INTO @dbver FROM `', p_table, '` ',
    'WHERE `', p_pk_col, '`=? FOR UPDATE'
  );
  PREPARE s0 FROM @sql_lock; EXECUTE s0 USING v_pk; DEALLOCATE PREPARE s0;
  SET v_db_ver = @dbver;
  IF v_db_ver IS NULL THEN
    ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='404_NOT_FOUND';
  END IF;

  -- ② 楽観ロック
  IF v_db_ver <> p_row_version THEN
    ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='409_CONFLICT';
  END IF;

  -- ③ 差分作成
  SET @keys  := JSON_KEYS(p_after_json);
  SET @n     := IFNULL(JSON_LENGTH(@keys), 0);
  SET @i     := 0;
  SET @after := p_after_json;

  WHILE @i < @n DO
    SET @k := JSON_UNQUOTE(JSON_EXTRACT(@keys, CONCAT('$[', @i, ']')));

    SET @sql_col := CONCAT(
      'SELECT `', @k, '` INTO @b FROM `', p_table, '` WHERE `', p_pk_col, '`=?'
    );
    PREPARE s1 FROM @sql_col; EXECUTE s1 USING v_pk; DEALLOCATE PREPARE s1;

    SET @a := JSON_UNQUOTE(JSON_EXTRACT(@after, CONCAT('$.', @k)));

    IF NOT ((@b IS NULL AND @a IS NULL) OR (@b = @a)) THEN
      SET v_delta = JSON_SET(v_delta, CONCAT('$.', @k), JSON_OBJECT('before', @b, 'after', @a));
      SET v_changes = v_changes + 1;

      SET v_set_csv = IF(
        v_set_csv='',
        CONCAT('`', @k, '` = JSON_UNQUOTE(JSON_EXTRACT(@after, ''$.', @k, '''))'),
        CONCAT(v_set_csv, ', `', @k, '` = JSON_UNQUOTE(JSON_EXTRACT(@after, ''$.', @k, '''))')
      );
    END IF;

    SET @i := @i + 1;
  END WHILE;

  -- ④ 差分なし
  IF v_changes = 0 THEN
    COMMIT; SELECT 'NO_CHANGE' AS status; LEAVE proc;
  END IF;

  -- ⑤ 差分UPDATE + row_version +1
  SET @upd := CONCAT(
    'UPDATE `', p_table, '` SET ', v_set_csv, ', `row_version`=`row_version`+1 ',
    'WHERE `', p_pk_col, '`=?'
  );
  PREPARE s2 FROM @upd; EXECUTE s2 USING v_pk; DEALLOCATE PREPARE s2;

  -- ⑥ ログ1行
  SET @ins := CONCAT(
    'INSERT INTO manual_corrections(',
    'occurred_at,actor_user_uuid,actor_name,entity,', p_log_key_column, ',action,reason,delta_json',
    ') VALUES (NOW(), ?, ?, ?, ?, ''update'', ?, ?)'
  );
  PREPARE s3 FROM @ins;
  EXECUTE s3 USING
    p_actor_uuid_bin,
    p_actor_name,
    p_entity,
    v_pk,
    p_reason,
    v_delta;
  DEALLOCATE PREPARE s3;

  COMMIT;
  SELECT 'OK' AS status;
END//

DELIMITER ;

-- =========================================
-- 3) Receiptsヘッダ ↔ SAL 連携SP（発行後に1回CALL）
-- =========================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_upsert_charge_for_receipt_header $$
CREATE PROCEDURE sp_upsert_charge_for_receipt_header(
  IN p_header_uuid BINARY(16)
)
proc: BEGIN
  DECLARE v_farm_uuid BINARY(16);
  DECLARE v_issued_at DATETIME;
  DECLARE v_status VARCHAR(10);         -- 'printed' / 'voided' / NULL
  DECLARE v_patient_copay INT UNSIGNED;
  DECLARE v_charge_uuid BINARY(16);
  DECLARE v_alloc_cnt INT DEFAULT 0;

  -- 1) ヘッダ本体（p017.3）
  SELECT h.farm_uuid, h.issued_at, h.status, h.patient_copay_yen
    INTO v_farm_uuid, v_issued_at, v_status, v_patient_copay
  FROM receipt_headers h
  WHERE h.uuid = p_header_uuid
  LIMIT 1;

  IF v_issued_at IS NULL OR v_farm_uuid IS NULL THEN
    LEAVE proc; -- 相手不明や未発行はスキップ
  END IF;

  -- 2) 既存請求（このヘッダ由来）と配分数
  SELECT r.uuid INTO v_charge_uuid
    FROM receivable_charges r
   WHERE r.source_receipt_header_uuid = p_header_uuid
   LIMIT 1;

  IF v_charge_uuid IS NOT NULL THEN
    SELECT COUNT(*) INTO v_alloc_cnt
      FROM receivable_allocations a
     WHERE a.charge_uuid = v_charge_uuid;
  END IF;

  -- 3) 同期ロジック
  IF (v_status IS NULL OR v_status='printed') AND v_patient_copay > 0 THEN
    -- 新規
    IF v_charge_uuid IS NULL THEN
      SET v_charge_uuid = uuid_v7_bin();  -- ← p012のユーティリティを使用
      INSERT INTO receivable_charges(
        uuid, counterparty_type, counterparty_uuid,
        amount_yen, occurred_at, source_receipt_header_uuid
      ) VALUES (
        v_charge_uuid, 'farm', v_farm_uuid,
        v_patient_copay, v_issued_at, p_header_uuid
      );
    -- 更新（未配分のみ）
    ELSEIF v_alloc_cnt = 0 THEN
      UPDATE receivable_charges
         SET counterparty_type = 'farm',
             counterparty_uuid = v_farm_uuid,
             amount_yen        = v_patient_copay,
             occurred_at       = v_issued_at,
             row_version       = row_version + 1
       WHERE uuid = v_charge_uuid;
    END IF;
  ELSE
    -- voided or 0円 → 未配分なら削除
    IF v_charge_uuid IS NOT NULL AND v_alloc_cnt = 0 THEN
      DELETE FROM receivable_charges WHERE uuid = v_charge_uuid;
    END IF;
  END IF;
END $$

-- 3-任意) ヘッダ取消前クリーンアップ（配分有無で削除/リンク切り）
DROP PROCEDURE IF EXISTS sp_cleanup_charge_before_receipt_void $$
CREATE PROCEDURE sp_cleanup_charge_before_receipt_void(
  IN p_header_uuid BINARY(16)
)
proc: BEGIN
  DECLARE v_charge_uuid BINARY(16);
  DECLARE v_alloc_cnt INT DEFAULT 0;

  SELECT r.uuid INTO v_charge_uuid
    FROM receivable_charges r
   WHERE r.source_receipt_header_uuid = p_header_uuid
   LIMIT 1;

  IF v_charge_uuid IS NULL THEN LEAVE proc; END IF;

  SELECT COUNT(*) INTO v_alloc_cnt
    FROM receivable_allocations a
   WHERE a.charge_uuid = v_charge_uuid;

  IF v_alloc_cnt = 0 THEN
    DELETE FROM receivable_charges WHERE uuid = v_charge_uuid;
  ELSE
    UPDATE receivable_charges
       SET source_receipt_header_uuid = NULL,
           row_version = row_version + 1
     WHERE uuid = v_charge_uuid;
  END IF;
END $$

DELIMITER ;

-- ============================================================
-- 使用手順（要点）
--  - 発行後に:  CALL sp_upsert_charge_for_receipt_header(:receipt_header_uuid);
--  - 取消前に:  CALL sp_cleanup_charge_before_receipt_void(:receipt_header_uuid); → その後 status='voided'
--  - 手修正:    CALL sp_save_row_ultralite(...)
-- ============================================================
