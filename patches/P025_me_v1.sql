/* ============================================================
   1) 対象一覧（どの表をミラーするか）
   ------------------------------------------------------------
   - source_table      : 元テーブル名
   - mirror_table      : ミラー先テーブル名（列は元と同じ、updated_atのみ updated_at_source）
   - pk_col            : 主キー列（BINARY(16)想定、既定 'uuid'）
   - updated_col       : 変更検出列（既定 'updated_at'）
   - mirror_updated_col: ミラー側の updated_at の改名先（既定 'updated_at_source'）
   - where_clause      : 任意の追加フィルタ（文字列SQL）
   - batch_size        : 1バッチ件数（既定 1000）
   - is_enabled        : 有効/無効フラグ
   ============================================================ */
DROP TABLE IF EXISTS mirror_targets;
CREATE TABLE mirror_targets (
  id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  source_table        VARCHAR(64)  NOT NULL,
  mirror_table        VARCHAR(64)  NOT NULL,
  pk_col              VARCHAR(64)  NOT NULL DEFAULT 'uuid',
  updated_col         VARCHAR(64)  NOT NULL DEFAULT 'updated_at',
  mirror_updated_col  VARCHAR(64)  NOT NULL DEFAULT 'updated_at_source',
  where_clause        TEXT NULL,
  batch_size          INT          NOT NULL DEFAULT 1000,
  is_enabled          TINYINT(1)   NOT NULL DEFAULT 1,
  UNIQUE KEY uq_mirror_table (mirror_table)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

/* 例: farms → farmdb_farms_mirror / individuals → farmdb_individuals_mirror
INSERT INTO mirror_targets (source_table, mirror_table) VALUES
 ('farms',        'farmdb_farms_mirror'),
 ('individuals',  'farmdb_individuals_mirror'),
 ('farm_users',   'farmdb_farm_users_mirror');
*/


/* ============================================================
   2) カーソル（水位）保存表（テーブルごとに last_ts / last_pk を保持）
   ------------------------------------------------------------
   - last_ts : 最後に処理した updated_at（ミラー側は updated_at_source に格納）
   - last_pk : 同一時刻でのタイブレーク用（uuid: BINARY(16)）
   ============================================================ */
DROP TABLE IF EXISTS mirror_cursors;
CREATE TABLE mirror_cursors (
  target_id     INT UNSIGNED PRIMARY KEY,
  last_ts       DATETIME(6) NOT NULL DEFAULT '1970-01-01 00:00:00.000000',
  last_pk       BINARY(16)  NOT NULL DEFAULT UNHEX(REPEAT('0',32)),
  last_run_at   DATETIME(6) NULL,
  last_rows     INT         NOT NULL DEFAULT 0,
  CONSTRAINT fk_cursor_target
    FOREIGN KEY (target_id) REFERENCES mirror_targets(id)
    ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


/* ============================================================
   3) 1ターゲットを1バッチだけ同期するSP
   ------------------------------------------------------------
   ポイント:
     - INFORMATION_SCHEMA から列リストを動的生成
     - updated_at → updated_at_source の別名付け
     - タイブレーク: (updated_at, uuid)
     - 一時表 tmp_mirror_batch に対象uuid/updated_atを先に落としてからUPSERT
   ============================================================ */
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_mirror_one $$
CREATE PROCEDURE sp_mirror_one(IN p_target_id INT UNSIGNED)
proc: BEGIN
  DECLARE v_source        VARCHAR(64);
  DECLARE v_mirror        VARCHAR(64);
  DECLARE v_pk            VARCHAR(64) DEFAULT 'uuid';
  DECLARE v_upd           VARCHAR(64) DEFAULT 'updated_at';
  DECLARE v_upd_mirror    VARCHAR(64) DEFAULT 'updated_at_source';
  DECLARE v_where         TEXT;
  DECLARE v_batch         INT DEFAULT 1000;

  DECLARE v_last_ts       DATETIME(6);
  DECLARE v_last_pk       BINARY(16);

  DECLARE v_select_cols   LONGTEXT;
  DECLARE v_insert_cols   LONGTEXT;
  DECLARE v_update_list   LONGTEXT;

  DECLARE v_sql           LONGTEXT;
  DECLARE v_cnt           INT;
  DECLARE v_new_ts        DATETIME(6);
  DECLARE v_new_pk        BINARY(16);

  /* 1) 設定を取得 */
  SELECT source_table, mirror_table, pk_col, updated_col, mirror_updated_col, where_clause, batch_size
    INTO v_source, v_mirror, v_pk, v_upd, v_upd_mirror, v_where, v_batch
  FROM mirror_targets
  WHERE id = p_target_id AND is_enabled = 1
  LIMIT 1;

  IF v_source IS NULL THEN LEAVE proc; END IF;

  /* 2) 水位を取得（無ければ作成） */
  SELECT last_ts, last_pk INTO v_last_ts, v_last_pk
  FROM mirror_cursors WHERE target_id = p_target_id;
  IF v_last_ts IS NULL THEN
    SET v_last_ts = TIMESTAMP('1970-01-01');
    SET v_last_pk = UNHEX(REPEAT('0',32));
    INSERT IGNORE INTO mirror_cursors(target_id) VALUES (p_target_id);
  END IF;

  /* 3) 列リスト生成（updated_at → updated_at_source に付け替え） */
  SET @db := DATABASE();
  /* SELECT 句（元 → 別名） */
  SET SESSION group_concat_max_len = 1024*1024;

  SELECT GROUP_CONCAT(
           CASE
             WHEN COLUMN_NAME = v_upd
               THEN CONCAT('s.`', COLUMN_NAME, '` AS `', v_upd_mirror, '`')
             ELSE CONCAT('s.`', COLUMN_NAME, '`')
           END
           ORDER BY ORDINAL_POSITION SEPARATOR ', '
         ) INTO v_select_cols
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = @db AND TABLE_NAME = v_source;

  /* INSERT列（ミラー側の列名） */
  SELECT GROUP_CONCAT(
           CASE
             WHEN COLUMN_NAME = v_upd
               THEN CONCAT('`', v_upd_mirror, '`')
             ELSE CONCAT('`', COLUMN_NAME, '`')
           END
           ORDER BY ORDINAL_POSITION SEPARATOR ', '
         ) INTO v_insert_cols
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = @db AND TABLE_NAME = v_source;

  /* UPDATE句（PK以外、VALUES()で上書き） */
  SELECT GROUP_CONCAT(
           CASE
             WHEN COLUMN_NAME = v_pk THEN NULL
             WHEN COLUMN_NAME = v_upd
               THEN CONCAT('`', v_upd_mirror, '`=VALUES(`', v_upd_mirror, '`)')
             ELSE CONCAT('`', COLUMN_NAME, '`=VALUES(`', COLUMN_NAME, '`)')
           END
           ORDER BY ORDINAL_POSITION SEPARATOR ', '
         ) INTO v_update_list
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = @db AND TABLE_NAME = v_source;

  /* 4) 対象uuidを一時表に抽出（同一Tx内のバッチ） */
  DROP TEMPORARY TABLE IF EXISTS tmp_mirror_batch;
  CREATE TEMPORARY TABLE tmp_mirror_batch (
    uuid       BINARY(16) NOT NULL PRIMARY KEY,
    updated_at DATETIME(6) NOT NULL
  ) ENGINE=MEMORY;

  SET @p_ts1 := v_last_ts;
  SET @p_ts2 := v_last_ts;
  SET @p_pk  := v_last_pk;
  SET @p_lim := v_batch;

  SET v_sql = CONCAT(
    'INSERT INTO tmp_mirror_batch(uuid, updated_at) ',
    'SELECT s.`', v_pk, '`, s.`', v_upd, '` ',
    'FROM `', v_source, '` s ',
    'WHERE (s.`', v_upd, '` > ? OR (s.`', v_upd, '` = ? AND s.`', v_pk, '` > ?)) ',
    IF(v_where IS NULL OR v_where='', '', CONCAT(' AND (', v_where, ') ')),
    'ORDER BY s.`', v_upd, '`, s.`', v_pk, '` ',
    'LIMIT ?'
  );
  PREPARE s0 FROM v_sql; EXECUTE s0 USING @p_ts1, @p_ts2, @p_pk, @p_lim; DEALLOCATE PREPARE s0;

  SELECT COUNT(*) INTO v_cnt FROM tmp_mirror_batch;
  IF v_cnt = 0 THEN
    UPDATE mirror_cursors
       SET last_run_at = UTC_TIMESTAMP(6), last_rows = 0
     WHERE target_id = p_target_id;
    LEAVE proc;
  END IF;

  /* 5) UPSERT（ミラーへ投入） */
  SET v_sql = CONCAT(
    'INSERT INTO `', v_mirror, '` (', v_insert_cols, ') ',
    'SELECT ', v_select_cols, ' ',
    'FROM `', v_source, '` s JOIN tmp_mirror_batch b ON s.`', v_pk, '`=b.uuid ',
    'ON DUPLICATE KEY UPDATE ', v_update_list
  );
  PREPARE s1 FROM v_sql; EXECUTE s1; DEALLOCATE PREPARE s1;

  /* 6) 新しい水位（max(updated_at), その時刻内のmax(uuid)）を更新 */
  SELECT MAX(updated_at) INTO v_new_ts FROM tmp_mirror_batch;
  SELECT MAX(uuid) INTO v_new_pk FROM tmp_mirror_batch WHERE updated_at = v_new_ts;

  UPDATE mirror_cursors
     SET last_ts   = v_new_ts,
         last_pk   = v_new_pk,
         last_run_at = UTC_TIMESTAMP(6),
         last_rows = v_cnt
   WHERE target_id = p_target_id;

  DROP TEMPORARY TABLE IF EXISTS tmp_mirror_batch;
END $$

DELIMITER ;


/* ============================================================
   4) すべての対象を順に1バッチずつ回すSP
   ------------------------------------------------------------
   - 定期実行（cron/イベントスケジューラ）で sp_mirror_all() を呼ぶ想定
   ============================================================ */
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_mirror_all $$
CREATE PROCEDURE sp_mirror_all()
BEGIN
  DECLARE v_id INT UNSIGNED;
  DECLARE done INT DEFAULT 0;

  DECLARE cur CURSOR FOR
    SELECT id FROM mirror_targets WHERE is_enabled = 1 ORDER BY id;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

  OPEN cur;
  readloop: LOOP
    FETCH cur INTO v_id;
    IF done = 1 THEN LEAVE readloop; END IF;
    CALL sp_mirror_one(v_id);
  END LOOP;
  CLOSE cur;
END $$

DELIMITER ;
