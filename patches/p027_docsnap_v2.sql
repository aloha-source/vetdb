/* =========================================================
  p027 — docsnap v2 インストーラ（tmp2 / 4SP版, 詳細コメント付き）
  ---------------------------------------------------------
  機能概要:
    - docsnap（文書スナップショット）を階層的に発行する最小構成のDDL一式
    - 「親→子」の辿り方は設定テーブル docsnap_targets_v2 に宣言し、
      幅優先探索（BFS）でルートから全階層をスナップ
  構成:
    1) 親子宣言テーブル docsnap_targets_v2（BFS経路の定義）
    2) 親子宣言シード（chart / receipt / 文書4種）
    3) SP#1: sp_docsnap_ensure_table      … snap_<元表> を必要なら CREATE
    4) SP#2: sp_docsnap_ensure_columns    … snap_<元表> に prefix 列を必要なら ADD
    5) SP#3: sp_docsnap_insert_one2       … 1行スナップ（SP#1,#2 を内部呼び出し）
    6) SP#4: sp_docsnap_issue_bfs         … BFSで階層を丸ごとスナップ
  前提:
    - uuid_v7_bin() 関数が存在（新規スナップ行のUUID生成）
  注意:
    - 本DDLは最小構成です。インデックス追加や循環検出などの強化は別途検討してください。
========================================================= */


/* ================================
  1) 親子宣言テーブル（BFSの経路定義）
  - 親: parent_table / 親主キー名: parent_pk_col（既定 'uuid'）
  - 子: child_table  / 親参照列: child_fk_col（子→親のFK列名）
  - 並び: order_by_sql（子取得時の ORDER BY 断片。任意）
  - 有効: is_active（宣言のON/OFF切替）
================================ */

DROP TABLE IF EXISTS docsnap_targets_v2;
CREATE TABLE docsnap_targets_v2 (
  id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,  -- 設定行ID
  parent_table   VARCHAR(64) NOT NULL,                     -- 親テーブル名
  parent_pk_col  VARCHAR(64) NOT NULL DEFAULT 'uuid',      -- 親の主キー列名（既定 'uuid'）
  child_table    VARCHAR(64) NOT NULL,                     -- 子テーブル名
  child_fk_col   VARCHAR(64) NOT NULL,                     -- 子テーブル上の親参照列名（FK列名）
  order_by_sql   VARCHAR(255) NULL,                        -- 子列挙時の ORDER BY 断片（任意）
  is_active      TINYINT(1) NOT NULL DEFAULT 1,            -- 宣言の有効/無効
  created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                  ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci;


/* =====================================
  2) 親子宣言シード（初期データ）
  - よく使う経路を事前登録
  - 必要に応じて運用時に追加・更新・無効化が可能
===================================== */

-- chart: chart_headers → chart_checkups
INSERT INTO docsnap_targets_v2
(parent_table,   parent_pk_col, child_table,      child_fk_col,           order_by_sql,                          is_active)
VALUES
('chart_headers','uuid',        'chart_checkups', 'chart_uuid',           'seq_no ASC, id ASC',                 1);

-- chart: chart_checkups → chart_items
INSERT INTO docsnap_targets_v2
(parent_table,    parent_pk_col, child_table,   child_fk_col,         order_by_sql,                              is_active)
VALUES
('chart_checkups','uuid',        'chart_items', 'chart_checkup_uuid', 'within_checkup_line_no ASC, id ASC',     1);

-- receipt: receipt_headers → receipt_items
INSERT INTO docsnap_targets_v2
(parent_table,      parent_pk_col, child_table,     child_fk_col,            order_by_sql,  is_active)
VALUES
('receipt_headers', 'uuid',        'receipt_items', 'receipt_header_uuid',   'id ASC',      1);

-- 文書4種: headers → lines（ビュー/表名・FK名は環境に合わせて調整可）
INSERT INTO docsnap_targets_v2
(parent_table,                 parent_pk_col, child_table,                    child_fk_col,  order_by_sql,             is_active)
VALUES
('v_doc_pregnancy_headers',    'uuid',        'v_doc_pregnancy_lines',        'header_uuid', 'line_no ASC, id ASC',    1),
('v_doc_vaccine_headers',      'uuid',        'v_doc_vaccine_lines',          'header_uuid', 'line_no ASC, id ASC',    1),
('v_doc_withdrawal_headers',   'uuid',        'v_doc_withdrawal_lines',       'header_uuid', 'line_no ASC, id ASC',    1),
('v_doc_medical_headers',      'uuid',        'v_doc_medical_lines',          'header_uuid', 'line_no ASC, id ASC',    1);



/* =========================================================
  3) SP#1: sp_docsnap_ensure_table
  目的: snap_<元表> が未作成なら、その場で共通メタ列付きで CREATE
  備考: idempotent（繰り返し呼んでも安全）
========================================================= */
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_docsnap_ensure_table $$
CREATE PROCEDURE sp_docsnap_ensure_table(
  IN p_src_table VARCHAR(64)                             -- 元テーブル名
)
BEGIN
  DECLARE v_snap_table VARCHAR(128);
  DECLARE v_exists INT DEFAULT 0;

  SET v_snap_table = CONCAT('snap_', p_src_table);       -- 例: 'chart_items' → 'snap_chart_items'

  -- 既存チェック（information_schema で存在確認）
  SELECT COUNT(*) INTO v_exists
    FROM information_schema.TABLES
   WHERE TABLE_SCHEMA = DATABASE()
     AND TABLE_NAME = v_snap_table;

  -- 無ければ CREATE（共通メタ列のみ。prefix列はSP#2で追加）
  IF v_exists = 0 THEN
    SET @sql_create = CONCAT(
      'CREATE TABLE `', v_snap_table, '` (',
      '  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,',                 -- 行ID（内部主キー）
      '  uuid BINARY(16) NOT NULL UNIQUE,',                            -- スナップ行UUID（v7想定）
      '  source_table VARCHAR(64) NOT NULL,',                          -- 由来の元テーブル名
      '  source_uuid BINARY(16) NOT NULL,',                            -- 由来の元UUID
      '  parent_snap_uuid BINARY(16) NULL,',                           -- 親スナップ行UUID（階層リンク）
      '  parent_table VARCHAR(64) NULL,',                              -- 親のテーブル名
      '  parent_source_uuid BINARY(16) NULL,',                         -- 親の元UUID
      '  source_row_version BIGINT UNSIGNED NULL,',                    -- 元row_version（存在時のみ）
      '  status ENUM(''printed'',''voided'') NULL DEFAULT NULL,',      -- 印字/無効状態（未印字はNULL）
      '  printed_at DATETIME NULL,',                                   -- 印字日時
      '  printed_count INT UNSIGNED NOT NULL DEFAULT 0,',              -- 印字回数
      '  voided_at DATETIME NULL,',                                    -- 無効化日時
      '  void_reason VARCHAR(255) NULL,',                              -- 無効理由
      '  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,',     -- 作成時刻
      '  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP', -- 更新時刻
      ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
    );
    PREPARE st FROM @sql_create; EXECUTE st; DEALLOCATE PREPARE st;
  END IF;
END $$

DELIMITER ;



/* =========================================================
  4) SP#2: sp_docsnap_ensure_columns
  目的: snap_<元表> に <元表>_<元列> という prefix列を不足分だけ ADD
  方針: 型は元の COLUMN_TYPE を踏襲。NULL許容で追加（制約は持ち込まない）。
========================================================= */
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_docsnap_ensure_columns $$
CREATE PROCEDURE sp_docsnap_ensure_columns(
  IN p_src_table VARCHAR(64)                         -- 元テーブル名
)
BEGIN
  DECLARE v_snap_table VARCHAR(128);
  DECLARE v_col VARCHAR(64);
  DECLARE v_coltype TEXT;
  DECLARE done INT DEFAULT 0;

  SET v_snap_table = CONCAT('snap_', p_src_table);

  -- 元テーブルの全列を物理順に走査
  DECLARE cur CURSOR FOR
    SELECT COLUMN_NAME, COLUMN_TYPE
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = p_src_table
     ORDER BY ORDINAL_POSITION;

  -- カーソル取り切り時の終了ハンドラ
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

  OPEN cur;
  read_loop: LOOP
    FETCH cur INTO v_col, v_coltype;
    IF done = 1 THEN LEAVE read_loop; END IF;

    -- 追加対象の prefix 列名を組み立て（例: chart_items_quantity）
    SET @pref_name := CONCAT(p_src_table, '_', v_col);

    -- 既に存在するか（snap_<元表> 側）をチェック
    SELECT COUNT(*) INTO @exists_col
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = v_snap_table
       AND COLUMN_NAME = @pref_name;

    -- 無ければ ALTER TABLE で追加（型は元の COLUMN_TYPE を踏襲／NULL許容）
    IF @exists_col = 0 THEN
      SET @sql_add = CONCAT(
        'ALTER TABLE `', v_snap_table, '` ADD COLUMN `', @pref_name, '` ', v_coltype, ' NULL'
      );
      PREPARE st2 FROM @sql_add; EXECUTE st2; DEALLOCATE PREPARE st2;
    END IF;
  END LOOP;
  CLOSE cur;
END $$

DELIMITER ;



/* =========================================================
  5) SP#3: sp_docsnap_insert_one2
  目的: 元テーブルの単一行を、snap_<元表> に「メタ列＋prefix列」でコピー
  流れ:
    (1) ensure（SP#1, #2）で保存先のテーブル・列を用意
    (2) prefix/元 両側の列名CSVをメタから構築
    (3) INSERT … SELECT（CASE WHEN で row_version 有無を吸収）
    (4) 直近スナップの uuid を取得し、OUT 返却
========================================================= */
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_docsnap_insert_one2 $$
CREATE PROCEDURE sp_docsnap_insert_one2(
  IN  p_src_table           VARCHAR(64),   -- 元テーブル名
  IN  p_src_pk              VARCHAR(64),   -- 元PK列名（通常 'uuid'）
  IN  p_src_uuid            BINARY(16),    -- 対象の元UUID
  IN  p_parent_snap_uuid    BINARY(16),    -- 親スナップUUID（ルートはNULL）
  IN  p_parent_table        VARCHAR(64),   -- 親テーブル名
  IN  p_parent_source_uuid  BINARY(16),    -- 親の元UUID
  OUT p_new_snap_uuid       BINARY(16)     -- 作成したスナップのUUID
)
BEGIN
  DECLARE v_snap_table VARCHAR(128);
  DECLARE v_cols_src   TEXT;
  DECLARE v_cols_dst   TEXT;

  SET v_snap_table = CONCAT('snap_', p_src_table);

  -- (1) 保存先のテーブル・列を ensure
  CALL sp_docsnap_ensure_table(p_src_table);
  CALL sp_docsnap_ensure_columns(p_src_table);

  -- (2) INSERT側（prefix列）のCSVを構築
  SELECT GROUP_CONCAT(CONCAT('`', p_src_table, '_', COLUMN_NAME, '`')
                      ORDER BY ORDINAL_POSITION SEPARATOR ',')
    INTO v_cols_dst
    FROM information_schema.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE()
     AND TABLE_NAME = p_src_table;

  -- (2) SELECT側（元列 s.`col`）のCSVを構築
  SELECT GROUP_CONCAT(CONCAT('s.`', COLUMN_NAME, '`')
                      ORDER BY ORDINAL_POSITION SEPARATOR ',')
    INTO v_cols_src
    FROM information_schema.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE()
     AND TABLE_NAME = p_src_table;

  -- (3) INSERT … SELECT（メタ列＋全列）
  SET @sql_ins = CONCAT(
    'INSERT INTO `', v_snap_table, '` (',
    '  uuid, source_table, source_uuid, parent_snap_uuid, parent_table, parent_source_uuid, source_row_version, ',
    '  ', v_cols_dst,
    ') SELECT ',
    '  uuid_v7_bin(), ?, s.`', p_src_pk, '`, ?, ?, ?, ',
    '  (CASE WHEN EXISTS (SELECT 1 FROM information_schema.COLUMNS ',
    '                     WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=''', p_src_table, ''' AND COLUMN_NAME=''row_version'') ',
    '        THEN s.`row_version` ELSE NULL END), ',
    '  ', v_cols_src,
    ' FROM `', p_src_table, '` s WHERE s.`', p_src_pk, '` = ? LIMIT 1'
  );

  PREPARE st3 FROM @sql_ins;
  SET @st := p_src_table;               -- source_table
  SET @psu := p_parent_snap_uuid;       -- parent_snap_uuid
  SET @pt  := p_parent_table;           -- parent_table
  SET @ps  := p_parent_source_uuid;     -- parent_source_uuid
  SET @uu  := p_src_uuid;               -- WHERE 条件の元UUID
  EXECUTE st3 USING @st, @psu, @pt, @ps, @uu;
  DEALLOCATE PREPARE st3;

  -- (4) 直近のスナップUUIDを取得（同じ source_* 複数発行時にも最後尾を拾う）
  SET @sql_get := CONCAT(
    'SELECT `uuid` FROM `', v_snap_table, '` ',
    'WHERE source_table=? AND source_uuid=? ORDER BY id DESC LIMIT 1'
  );
  PREPARE st4 FROM @sql_get; EXECUTE st4 USING @st, @uu; DEALLOCATE PREPARE st4;

  SET @sql_get2 := CONCAT(
    'SELECT `uuid` INTO @__snap FROM `', v_snap_table, '` ',
    'WHERE source_table=? AND source_uuid=? ORDER BY id DESC LIMIT 1'
  );
  PREPARE st5 FROM @sql_get2; EXECUTE st5 USING @st, @uu; DEALLOCATE PREPARE st5;

  SET p_new_snap_uuid = @__snap;        -- OUT で返却
END $$

DELIMITER ;



/* =========================================================
  6) SP#4: sp_docsnap_issue_bfs
  目的: ルート（テーブル・UUID）から docsnap_targets_v2 に従って BFS で階層スナップ
  方式: 一時テーブルをキューとして使用（深さごとに処理）
  注意: 循環経路や重複投入を前提にしていません（宣言側で回避）
========================================================= */
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_docsnap_issue_bfs $$
CREATE PROCEDURE sp_docsnap_issue_bfs(
  IN p_root_table VARCHAR(64),    -- ルート表名（例: 'chart_headers'）
  IN p_root_pk    VARCHAR(64),    -- ルートPK列名（通常 'uuid'）※現行では未使用（将来拡張用）
  IN p_root_uuid  BINARY(16)      -- ルートの元UUID
)
BEGIN
  DECLARE v_have INT DEFAULT 0;         -- 現深さの未処理件数
  DECLARE v_cur_depth INT DEFAULT 0;    -- 現在の深さ

  -- キュー: 処理待ち（MEMORYテーブル）
  DROP TEMPORARY TABLE IF EXISTS tmp_docsnap_queue;
  CREATE TEMPORARY TABLE tmp_docsnap_queue (
    id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,  -- FIFO安定化用
    depth                INT NOT NULL DEFAULT 0,                   -- 深さ（層）
    table_name           VARCHAR(64) NOT NULL,                     -- 対象テーブル名
    source_uuid          BINARY(16) NOT NULL,                      -- 対象の元UUID
    parent_table         VARCHAR(64) NULL,                         -- 親テーブル名（連携メタ）
    parent_source_uuid   BINARY(16) NULL,                          -- 親の元UUID
    parent_snap_uuid     BINARY(16) NULL,                          -- 親スナップUUID
    processed            TINYINT(1) NOT NULL DEFAULT 0,            -- 0=未処理 / 1=済
    KEY idx_q (processed, depth, id)                               -- 取り出し効率
  ) ENGINE=MEMORY;

  -- 子UUIDの一時置き場
  DROP TEMPORARY TABLE IF EXISTS tmp_docsnap_children;
  CREATE TEMPORARY TABLE tmp_docsnap_children (
    child_uuid BINARY(16) NOT NULL,
    KEY idx_c (child_uuid)
  ) ENGINE=MEMORY;

  -- ルート投入（深さ0）
  INSERT INTO tmp_docsnap_queue(depth, table_name, source_uuid)
  VALUES (0, p_root_table, p_root_uuid);

  -- 深さ0,1,2... の順に処理（幅優先）
  depth_loop: LOOP
    -- 現深さの未処理が無ければ次の深さへ
    SELECT COUNT(*) INTO v_have
      FROM tmp_docsnap_queue
     WHERE processed=0 AND depth=v_cur_depth;

    IF v_have = 0 THEN
      -- さらに深い層に未処理が無ければ全処理完了
      SELECT COUNT(*) INTO v_have
        FROM tmp_docsnap_queue
       WHERE processed=0 AND depth>v_cur_depth;
      IF v_have = 0 THEN
        LEAVE depth_loop;
      END IF;
      SET v_cur_depth = v_cur_depth + 1;
      ITERATE depth_loop;
    END IF;

    -- 同じ深さから1件POP → スナップ → 子をPUSH
    BEGIN
      DECLARE v_id INT UNSIGNED;
      DECLARE v_tbl VARCHAR(64);
      DECLARE v_src_uuid BINARY(16);
      DECLARE v_parent_tbl VARCHAR(64);
      DECLARE v_parent_src_uuid BINARY(16);
      DECLARE v_parent_snap_uuid BINARY(16);
      DECLARE v_snap_uuid BINARY(16);

      -- 1件取り出し（FIFO）
      SELECT id, table_name, source_uuid, parent_table, parent_source_uuid, parent_snap_uuid
        INTO v_id, v_tbl, v_src_uuid, v_parent_tbl, v_parent_src_uuid, v_parent_snap_uuid
        FROM tmp_docsnap_queue
       WHERE processed=0 AND depth=v_cur_depth
       ORDER BY id
       LIMIT 1;

      -- 1行スナップ（保存先の ensure はSP内で実施）
      CALL sp_docsnap_insert_one2(
        v_tbl, 'uuid', v_src_uuid,
        v_parent_snap_uuid, v_parent_tbl, v_parent_src_uuid,
        v_snap_uuid
      );

      -- 子テーブル宣言に従って子UUIDを収集 → 次の深さに積む
      BEGIN
        DECLARE done INT DEFAULT 0;
        DECLARE v_child_table VARCHAR(64);
        DECLARE v_child_fk    VARCHAR(64);
        DECLARE v_order_sql   VARCHAR(255);

        DECLARE cur CURSOR FOR
          SELECT child_table, child_fk_col, IFNULL(order_by_sql,'')
            FROM docsnap_targets_v2
           WHERE is_active=1 AND parent_table=v_tbl;

        DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

        OPEN cur;
        read_children: LOOP
          FETCH cur INTO v_child_table, v_child_fk, v_order_sql;
          IF done = 1 THEN LEAVE read_children; END IF;

          TRUNCATE TABLE tmp_docsnap_children;

          -- 子UUID列挙（ORDER指定があれば適用）
          SET @sql_ins = CONCAT(
            'INSERT INTO tmp_docsnap_children(child_uuid) ',
            'SELECT `', v_child_table, '`.`uuid` FROM `', v_child_table, '` ',
            'WHERE `', v_child_fk, '` = ? ',
            CASE WHEN v_order_sql IS NULL OR v_order_sql = '' THEN '' ELSE CONCAT('ORDER BY ', v_order_sql) END
          );
          PREPARE st FROM @sql_ins; SET @p := v_src_uuid; EXECUTE st USING @p; DEALLOCATE PREPARE st;

          -- 収集した子UUIDをキューに投入（深さ+1）
          BEGIN
            DECLARE done2 INT DEFAULT 0;
            DECLARE v_child_uuid BINARY(16);
            DECLARE cur2 CURSOR FOR SELECT child_uuid FROM tmp_docsnap_children;
            DECLARE CONTINUE HANDLER FOR NOT FOUND SET done2 = 1;

            OPEN cur2;
            loop2: LOOP
              FETCH cur2 INTO v_child_uuid;
              IF done2 = 1 THEN LEAVE loop2; END IF;

              INSERT INTO tmp_docsnap_queue(
                depth, table_name, source_uuid,
                parent_table, parent_source_uuid, parent_snap_uuid
              )
              VALUES (
                v_cur_depth+1, v_child_table, v_child_uuid,
                v_tbl, v_src_uuid, v_snap_uuid
              );
            END LOOP;
            CLOSE cur2;
          END;

        END LOOP;
        CLOSE cur;
      END;

      -- 処理済みマーク
      UPDATE tmp_docsnap_queue SET processed=1 WHERE id=v_id;
    END;

    ITERATE depth_loop;  -- 同深さに未処理が続く限りループ
  END LOOP depth_loop;
END $$

DELIMITER ;
