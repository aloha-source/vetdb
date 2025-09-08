/* =========================================================
  tmp1 — docsnap v2（階層スナップ最小構成）/ “行ごと＆用語つき”詳細コメント版
  ---------------------------------------------------------
  構成:
    1) 親子宣言テーブル docsnap_targets_v2（BFSの経路定義）
    2) 親子宣言シード（chart / receipt / 文書4種）
    3) SP#1: sp_docsnap_insert_one2（1行を snap_* へ; ensure内蔵）
    4) SP#2: sp_docsnap_issue_bfs（幅優先で階層を一括スナップ）
  前提:
    - uuid_v7_bin() 関数が存在（新規snap行のUUID生成）
  注記:
    - コード本体は tmp1 と同じです。コメントのみ追加しています。
========================================================= */


/* ================================
  1) 親子宣言テーブル（経路定義）
================================ */

DROP TABLE IF EXISTS docsnap_targets_v2;                   -- DROP TABLE: 既存テーブルを削除 / IF EXISTS: 存在時のみ安全に
CREATE TABLE docsnap_targets_v2 (                          -- CREATE TABLE: 新規にテーブルを作成
  id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,  -- id: 連番 / INT: 整数 / UNSIGNED: 符号なし / AUTO_INCREMENT: 自動採番 / PRIMARY KEY: 主キー
  parent_table   VARCHAR(64) NOT NULL,                     -- parent_table: 親テーブル名 / VARCHAR(64): 文字列 / NOT NULL: 必須
  parent_pk_col  VARCHAR(64) NOT NULL DEFAULT 'uuid',      -- parent_pk_col: 親PK列名 / DEFAULT 'uuid': 既定値は 'uuid'
  child_table    VARCHAR(64) NOT NULL,                     -- child_table: 子テーブル名
  child_fk_col   VARCHAR(64) NOT NULL,                     -- child_fk_col: 子→親 を指す列名（FK列）
  order_by_sql   VARCHAR(255) NULL,                        -- order_by_sql: 子取得の並び順（SQL断片）/ NULL可
  is_active      TINYINT(1) NOT NULL DEFAULT 1,            -- is_active: 有効フラグ / TINYINT(1): 0/1 / DEFAULT 1: 既定で有効
  created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,           -- created_at: 作成時刻 / DEFAULT CURRENT_TIMESTAMP: 現在時刻
  updated_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP            -- updated_at: 更新時刻 / DEFAULT CURRENT_TIMESTAMP
                  ON UPDATE CURRENT_TIMESTAMP                           -- ON UPDATE: 更新時に現在時刻へ自動更新
) ENGINE=InnoDB                                                        -- ENGINE=InnoDB: 取引・行ロック対応
  DEFAULT CHARSET=utf8mb4                                              -- DEFAULT CHARSET: 文字集合 utf8mb4
  COLLATE=utf8mb4_unicode_ci;                                          -- COLLATE: 照合順序（大小・アクセントの扱い）



/* =====================================
  2) 親子宣言シード（初期データ投入）
===================================== */

-- chart: chart_headers → chart_checkups
INSERT INTO docsnap_targets_v2                                  -- INSERT INTO: 行追加 / 対象テーブル
(parent_table,   parent_pk_col, child_table,      child_fk_col,           order_by_sql,                              is_active)  -- 指定する列リスト
VALUES                                                                                                                   -- VALUES: 挿入する値の組
('chart_headers','uuid',        'chart_checkups', 'chart_uuid',           'seq_no ASC, id ASC',                     1); -- 1行目: 親=chart_headers / 子=chart_checkups / 子FK=chart_uuid / 並び=seq_no→id / 有効=1

-- chart: chart_checkups → chart_items
INSERT INTO docsnap_targets_v2
(parent_table,    parent_pk_col, child_table,   child_fk_col,         order_by_sql,                              is_active)
VALUES
('chart_checkups','uuid',        'chart_items', 'chart_checkup_uuid', 'within_checkup_line_no ASC, id ASC',     1); -- 親=chart_checkups / 子=chart_items / 子FK=chart_checkup_uuid / 並び=行番号→id

-- receipt: receipt_headers → receipt_items
INSERT INTO docsnap_targets_v2
(parent_table,      parent_pk_col, child_table,     child_fk_col,            order_by_sql,  is_active)
VALUES
('receipt_headers', 'uuid',        'receipt_items', 'receipt_header_uuid',   'id ASC',      1);                     -- 親=receipt_headers / 子=receipt_items / 子FK=receipt_header_uuid / 並び=id昇順

-- 文書系（妊娠鑑定 / ワクチン証明 / 休薬 / 診断書）: headers → lines
-- ※ ビュー/表名・FK名は実環境に合わせて置換可能（ここでは header_uuid を想定）
INSERT INTO docsnap_targets_v2
(parent_table,                 parent_pk_col, child_table,                    child_fk_col,  order_by_sql,             is_active)
VALUES
('v_doc_pregnancy_headers',    'uuid',        'v_doc_pregnancy_lines',        'header_uuid', 'line_no ASC, id ASC',    1), -- 妊娠鑑定
('v_doc_vaccine_headers',      'uuid',        'v_doc_vaccine_lines',          'header_uuid', 'line_no ASC, id ASC',    1), -- ワクチン証明
('v_doc_withdrawal_headers',   'uuid',        'v_doc_withdrawal_lines',       'header_uuid', 'line_no ASC, id ASC',    1), -- 休薬
('v_doc_medical_headers',      'uuid',        'v_doc_medical_lines',          'header_uuid', 'line_no ASC, id ASC',    1); -- 診断書



/* =========================================================
  3) SP#1: sp_docsnap_insert_one2（1行スナップ; ensure内蔵）
========================================================= */

DELIMITER $$                                                     -- DELIMITER: プロシージャ定義の終端記号を $$ に変更
DROP PROCEDURE IF EXISTS sp_docsnap_insert_one2 $$               -- DROP PROCEDURE: 既存SPを削除（IF EXISTS: 存在時のみ）
CREATE PROCEDURE sp_docsnap_insert_one2(                         -- CREATE PROCEDURE: 新規SP定義
  IN  p_src_table           VARCHAR(64),                         -- IN: p_src_table（元テーブル名）
  IN  p_src_pk              VARCHAR(64),                         -- IN: p_src_pk（元PK列名。通常 'uuid'）
  IN  p_src_uuid            BINARY(16),                          -- IN: p_src_uuid（対象の元UUID / BINARY(16)）
  IN  p_parent_snap_uuid    BINARY(16),                          -- IN: p_parent_snap_uuid（親スナップUUID / 最上位はNULL）
  IN  p_parent_table        VARCHAR(64),                         -- IN: p_parent_table（親テーブル名）
  IN  p_parent_source_uuid  BINARY(16),                          -- IN: p_parent_source_uuid（親の元UUID）
  OUT p_new_snap_uuid       BINARY(16)                           -- OUT: p_new_snap_uuid（新規スナップUUIDの返り値）
)
BEGIN                                                            -- BEGIN: 本体開始
  DECLARE v_snap_table VARCHAR(128);                             -- DECLARE: 変数宣言 / v_snap_table: 保存先テーブル名
  DECLARE v_cols_src   TEXT;                                     -- v_cols_src: SELECT側（元列）CSV文字列
  DECLARE v_cols_dst   TEXT;                                     -- v_cols_dst: INSERT側（prefix列）CSV文字列
  DECLARE v_exists     INT DEFAULT 0;                            -- v_exists: テーブル存在確認フラグ

  SET v_snap_table = CONCAT('snap_', p_src_table);               -- SET: 代入 / CONCAT: 文字連結 → 'snap_' + 元テーブル名

  /* ensure(1): 保存先テーブルが無ければ CREATE */
  SELECT COUNT(*) INTO v_exists                                  -- SELECT … INTO: 結果を変数へ代入
    FROM information_schema.TABLES                               -- FROM: 参照元（メタ情報テーブル）
   WHERE TABLE_SCHEMA = DATABASE()                               -- WHERE: 絞り込み（現在のDBスキーマ）
     AND TABLE_NAME = v_snap_table;                              --        対象テーブル名に一致

  IF v_exists = 0 THEN                                           -- IF: 条件分岐（存在しない時）
    SET @sql_create = CONCAT(                                    -- SET: 動的SQLの文字列を組立
      'CREATE TABLE `', v_snap_table, '` (',
      '  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,',           -- id: 連番 / 主キー
      '  uuid BINARY(16) NOT NULL UNIQUE,',                      -- uuid: スナップ自身のUUID / UNIQUE: 一意
      '  source_table VARCHAR(64) NOT NULL,',                    -- source_table: 元テーブル名
      '  source_uuid BINARY(16) NOT NULL,',                      -- source_uuid: 元UUID
      '  parent_snap_uuid BINARY(16) NULL,',                     -- parent_snap_uuid: 親スナップUUID
      '  parent_table VARCHAR(64) NULL,',                        -- parent_table: 親テーブル名
      '  parent_source_uuid BINARY(16) NULL,',                   -- parent_source_uuid: 親の元UUID
      '  source_row_version BIGINT UNSIGNED NULL,',              -- source_row_version: 元row_version（存在時）
      '  status ENUM(''printed'',''voided'') NULL DEFAULT NULL,',-- status: 印字状態（printed/voided/NULL）
      '  printed_at DATETIME NULL,',                             -- printed_at: 印字時刻
      '  printed_count INT UNSIGNED NOT NULL DEFAULT 0,',        -- printed_count: 印字回数
      '  voided_at DATETIME NULL,',                              -- voided_at: 無効化時刻
      '  void_reason VARCHAR(255) NULL,',                        -- void_reason: 無効理由
      '  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,',-- created_at: 作成時刻
      '  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP', -- updated_at: 更新時刻（自動更新）
      ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci' -- ENGINE/CHARSET/COLLATE: 表オプション
    );
    PREPARE st FROM @sql_create;                                 -- PREPARE: 動的SQLを準備
    EXECUTE st;                                                   -- EXECUTE: 実行
    DEALLOCATE PREPARE st;                                        -- DEALLOCATE: 後片付け
  END IF;

  /* ensure(2): 保存先prefix列（<元表>_<元列>）を不足分だけ追加 */
  BEGIN                                                          -- サブブロック開始
    DECLARE v_col VARCHAR(64);                                   -- v_col: 元列名
    DECLARE v_coltype TEXT;                                      -- v_coltype: 元列の型（文字列）
    DECLARE done INT DEFAULT 0;                                  -- done: カーソル終了フラグ

    DECLARE cur CURSOR FOR                                       -- DECLARE CURSOR: 行反復用カーソル
      SELECT COLUMN_NAME, COLUMN_TYPE                             -- SELECT: 列メタ（名前と型）
        FROM information_schema.COLUMNS
       WHERE TABLE_SCHEMA = DATABASE()
         AND TABLE_NAME = p_src_table
       ORDER BY ORDINAL_POSITION;                                -- ORDER BY: 列の物理順で安定化

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;         -- ハンドラ: 取り切ったら done=1 に設定

    OPEN cur;                                                    -- OPEN: カーソル開始
    read_loop: LOOP                                              -- LOOP: 反復開始
      FETCH cur INTO v_col, v_coltype;                           -- FETCH: 1行取得 → 変数へ
      IF done = 1 THEN LEAVE read_loop; END IF;                  -- LEAVE: ループ終了

      SET @pref_name := CONCAT(p_src_table, '_', v_col);         -- @pref_name: 追加すべきprefix列名（例 chart_items_quantity）

      SELECT COUNT(*) INTO @exists2
        FROM information_schema.COLUMNS
       WHERE TABLE_SCHEMA = DATABASE()
         AND TABLE_NAME = v_snap_table
         AND COLUMN_NAME = @pref_name;                           -- 既にあるかチェック

      IF @exists2 = 0 THEN                                       -- 無ければ追加
        SET @sql_add = CONCAT(
          'ALTER TABLE `', v_snap_table, '` ADD COLUMN `', @pref_name, '` ', v_coltype, ' NULL'
        );
        PREPARE st2 FROM @sql_add; EXECUTE st2; DEALLOCATE PREPARE st2;  -- ALTER TABLE 実行
      END IF;
    END LOOP;
    CLOSE cur;                                                   -- CLOSE: カーソル終了
  END;

  /* --- 列リスト構築（INSERT列=prefix側 / SELECT列=元側） --- */
  -- 用語補足: SELECT=抽出 / GROUP_CONCAT=複数行を1文字列連結 / CONCAT=結合 / ORDER BY=並び替え
  --          SEPARATOR=区切指定 / INTO=変数へ代入 / FROM=参照元 / WHERE=条件 / DATABASE()=現在DB名
  SELECT GROUP_CONCAT(CONCAT('`', p_src_table, '_', COLUMN_NAME, '`')       -- 例: `chart_items_quantity`,`chart_items_unit_price`,…
                      ORDER BY ORDINAL_POSITION SEPARATOR ',')              -- ORDER BY: 列順で安定 / SEPARATOR ',': カンマ区切り
    INTO v_cols_dst                                                         -- INTO: 結果を v_cols_dst へ代入
    FROM information_schema.COLUMNS                                         -- FROM: メタ表（列一覧）
   WHERE TABLE_SCHEMA = DATABASE()                                          -- WHERE: 現在DBスキーマ内で
     AND TABLE_NAME = p_src_table;                                          --        対象の元テーブルに一致

  SELECT GROUP_CONCAT(CONCAT('s.`', COLUMN_NAME, '`')                        -- 例: s.`quantity`,s.`unit_price`,…
                      ORDER BY ORDINAL_POSITION SEPARATOR ',')
    INTO v_cols_src
    FROM information_schema.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE()
     AND TABLE_NAME = p_src_table;

  /* --- 本体コピー: INSERT … SELECT（メタ列＋全列） --- */
  SET @sql_ins = CONCAT(                                                    -- SET: 動的INSERT文の組立開始
    'INSERT INTO `', v_snap_table, '` (',                                   -- INSERT INTO: 追加先テーブル
    '  uuid, source_table, source_uuid, parent_snap_uuid, parent_table, parent_source_uuid, source_row_version, ', -- 先頭にメタ列
    '  ', v_cols_dst,                                                       -- 続けて prefix列（全部）
    ') SELECT ',                                                            -- SELECT: 取得系
    '  uuid_v7_bin(), ?, s.`', p_src_pk, '`, ?, ?, ?, ',                    -- uuid_v7_bin(): 新UUID / 以降 ? はバインドパラメータ
    '  (CASE WHEN EXISTS (SELECT 1 FROM information_schema.COLUMNS ',       -- CASE WHEN EXISTS: 条件式（row_version列が存在するか）
    '                     WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=''', p_src_table, ''' AND COLUMN_NAME=''row_version'') ',
    '        THEN s.`row_version` ELSE NULL END), ',                        -- 存在すれば row_version を、無ければ NULL を
    '  ', v_cols_src,                                                       -- s.`<元列>` のCSV（全部）
    ' FROM `', p_src_table, '` s WHERE s.`', p_src_pk, '` = ? LIMIT 1'      -- FROM: 元テーブル（別名 s）/ WHERE: PK一致 / LIMIT 1: 1行のみ
  );

  PREPARE st3 FROM @sql_ins;                                               -- PREPARE: 動的INSERTの準備
  SET @st := p_src_table;                                                  -- @st: ?（source_table）に渡す値
  SET @psu := p_parent_snap_uuid;                                          -- @psu: ?（parent_snap_uuid）
  SET @pt  := p_parent_table;                                             -- @pt : ?（parent_table）
  SET @ps  := p_parent_source_uuid;                                       -- @ps : ?（parent_source_uuid）
  SET @uu  := p_src_uuid;                                                 -- @uu : ?（WHEREの元UUID）
  EXECUTE st3 USING @st, @psu, @pt, @ps, @uu;                              -- EXECUTE … USING: 位置パラメータに値を適用して実行
  DEALLOCATE PREPARE st3;                                                 -- DEALLOCATE: 準備の解放

  /* 直近スナップのUUIDを取得 → OUTで返す */
  SET @sql_get := CONCAT(                                                 -- 直近（id DESC）のスナップuuidを取得
    'SELECT `uuid` FROM `', v_snap_table, '` ',
    'WHERE source_table=? AND source_uuid=? ORDER BY id DESC LIMIT 1'
  );
  PREPARE st4 FROM @sql_get; EXECUTE st4 USING @st, @uu; DEALLOCATE PREPARE st4;  -- SELECT実行（結果セットとしても出る）

  SET @sql_get2 := CONCAT(                                                -- 同じ条件で @__snap に格納（INTO 変数）
    'SELECT `uuid` INTO @__snap FROM `', v_snap_table, '` ',
    'WHERE source_table=? AND source_uuid=? ORDER BY id DESC LIMIT 1'
  );
  PREPARE st5 FROM @sql_get2; EXECUTE st5 USING @st, @uu; DEALLOCATE PREPARE st5;  -- 実行 → @__snap に代入

  SET p_new_snap_uuid = @__snap;                                          -- OUT引数へ代入（呼び出し側で受け取れる）
END $$                                                                     -- END: プロシージャ終端
DELIMITER ;                                                                -- DELIMITER: 通常の ';' に戻す



/* =========================================================
  4) SP#2: sp_docsnap_issue_bfs（幅優先で階層スナップ）
========================================================= */

DELIMITER $$                                                                -- プロシージャ定義用に区切りを $$ へ
DROP PROCEDURE IF EXISTS sp_docsnap_issue_bfs $$                            -- 既存SPを削除
CREATE PROCEDURE sp_docsnap_issue_bfs(                                      -- 新規SP作成
  IN p_root_table VARCHAR(64),   -- IN: ルート表名（例 'chart_headers'）
  IN p_root_pk    VARCHAR(64),   -- IN: ルートPK列名（通常 'uuid'）※この版では未使用（将来拡張用）
  IN p_root_uuid  BINARY(16)     -- IN: ルートの元UUID（BINARY(16)）
)
BEGIN
  DECLARE v_have INT DEFAULT 0;           -- v_have: 未処理があるかの一時カウント
  DECLARE v_cur_depth INT DEFAULT 0;      -- v_cur_depth: 現在の深さ（0,1,2,…）

  /* 一時テーブル（キュー & 子UUID置き場）作成 */
  DROP TEMPORARY TABLE IF EXISTS tmp_docsnap_queue;                           -- TEMPORARY: セッション限定 / 既存があれば削除
  CREATE TEMPORARY TABLE tmp_docsnap_queue (                                  -- キュー: 処理待ち行列
    id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,             -- id: 取り出し順制御（FIFO）
    depth                INT NOT NULL DEFAULT 0,                              -- depth: 深さ（層）
    table_name           VARCHAR(64) NOT NULL,                                -- table_name: 対象テーブル名
    source_uuid          BINARY(16) NOT NULL,                                 -- source_uuid: 対象の元UUID
    parent_table         VARCHAR(64) NULL,                                    -- parent_table: 親テーブル名
    parent_source_uuid   BINARY(16) NULL,                                     -- parent_source_uuid: 親の元UUID
    parent_snap_uuid     BINARY(16) NULL,                                     -- parent_snap_uuid: 親スナップUUID
    processed            TINYINT(1) NOT NULL DEFAULT 0,                       -- processed: 0=未処理 / 1=処理済
    KEY idx_q (processed, depth, id)                                          -- KEY: 簡易インデックス（取り出し効率）
  ) ENGINE=MEMORY;                                                            -- ENGINE=MEMORY: 高速・揮発

  DROP TEMPORARY TABLE IF EXISTS tmp_docsnap_children;                        -- 既存を削除
  CREATE TEMPORARY TABLE tmp_docsnap_children (                               -- 子UUIDの一時置き場
    child_uuid BINARY(16) NOT NULL,                                           -- child_uuid: 子の元UUID
    KEY idx_c (child_uuid)                                                    -- インデックス: 単一列
  ) ENGINE=MEMORY;

  /* ルート投入（深さ0の最初の1件） */
  INSERT INTO tmp_docsnap_queue(depth, table_name, source_uuid)               -- キューに初期ノードを入れる
  VALUES (0, p_root_table, p_root_uuid);                                      -- depth=0 / ルート表 / ルートUUID

  /* BFSループ（同じ深さをまとめて → 次の深さへ） */
  depth_loop: LOOP                                                            -- LOOP: ラベル付きループ
    SELECT COUNT(*) INTO v_have                                               -- 現深さの未処理数カウント
      FROM tmp_docsnap_queue
     WHERE processed=0 AND depth=v_cur_depth;

    IF v_have = 0 THEN                                                        -- 未処理なし
      SELECT COUNT(*) INTO v_have                                             -- より深い層に未処理が残るか
        FROM tmp_docsnap_queue
       WHERE processed=0 AND depth>v_cur_depth;
      IF v_have = 0 THEN                                                      -- どの層にも無し
        LEAVE depth_loop;                                                     -- ループ終了
      END IF;
      SET v_cur_depth = v_cur_depth + 1;                                      -- 深さを1段進める
      ITERATE depth_loop;                                                     -- 次サイクルへ
    END IF;

    /* 同深さから1件取り出して処理（POP→SNAP→子PUSH） */
    BEGIN
      DECLARE v_id INT UNSIGNED;                                              -- v_id: キュー行ID
      DECLARE v_tbl VARCHAR(64);                                              -- v_tbl: テーブル名
      DECLARE v_src_uuid BINARY(16);                                          -- v_src_uuid: 元UUID
      DECLARE v_parent_tbl VARCHAR(64);                                       -- v_parent_tbl: 親テーブル名
      DECLARE v_parent_src_uuid BINARY(16);                                   -- v_parent_src_uuid: 親の元UUID
      DECLARE v_parent_snap_uuid BINARY(16);                                  -- v_parent_snap_uuid: 親スナップUUID
      DECLARE v_snap_uuid BINARY(16);                                         -- v_snap_uuid: 生成されたスナップUUID（OUT受け）

      SELECT id, table_name, source_uuid, parent_table, parent_source_uuid, parent_snap_uuid -- 先頭の未処理1件を取得
        INTO v_id, v_tbl, v_src_uuid, v_parent_tbl, v_parent_src_uuid, v_parent_snap_uuid
        FROM tmp_docsnap_queue
       WHERE processed=0 AND depth=v_cur_depth
       ORDER BY id                                                            -- ORDER BY id: FIFO順で安定
       LIMIT 1;

      CALL sp_docsnap_insert_one2(                                            -- 1行スナップ（SP#1を呼ぶ）
        v_tbl, 'uuid', v_src_uuid,                                            -- 元テーブル / PK列名 / 元UUID
        v_parent_snap_uuid, v_parent_tbl, v_parent_src_uuid,                  -- 親リンク情報
        v_snap_uuid                                                           -- OUT: 生成されたスナップUUID
      );

      /* 子を列挙 → 子UUIDを収集 → 次の深さにキュー投入 */
      BEGIN
        DECLARE done INT DEFAULT 0;                                           -- done: 子列挙カーソル終了フラグ
        DECLARE v_child_table VARCHAR(64);                                    -- v_child_table: 子テーブル名
        DECLARE v_child_fk    VARCHAR(64);                                    -- v_child_fk: 子のFK列名（親UUIDを指す）
        DECLARE v_order_sql   VARCHAR(255);                                   -- v_order_sql: 並び順SQL（空なら順不同）

        DECLARE cur CURSOR FOR
          SELECT child_table, child_fk_col, IFNULL(order_by_sql,'')           -- IFNULL: NULLなら空文字
            FROM docsnap_targets_v2
           WHERE is_active=1 AND parent_table=v_tbl;                          -- 現在の親テーブル v_tbl の子宣言だけ

        DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;                  -- 取り切り時の終了ハンドラ

        OPEN cur;                                                             -- 子宣言カーソル開始
        read_children: LOOP                                                   -- 反復
          FETCH cur INTO v_child_table, v_child_fk, v_order_sql;              -- 1宣言取得
          IF done = 1 THEN LEAVE read_children; END IF;                       -- 終了判定

          TRUNCATE TABLE tmp_docsnap_children;                                -- 前回の子UUID一時表を空にする

          SET @sql_ins = CONCAT(                                              -- 子UUIDを一時表へ入れるINSERT … SELECT を組立
            'INSERT INTO tmp_docsnap_children(child_uuid) ',
            'SELECT `', v_child_table, '`.`uuid` FROM `', v_child_table, '` ',
            'WHERE `', v_child_fk, '` = ? ',                                   -- 子.FK = 親の “元UUID”
            CASE WHEN v_order_sql IS NULL OR v_order_sql = ''                  -- 並び指定がある場合だけ ORDER BY を付ける
                 THEN '' ELSE CONCAT('ORDER BY ', v_order_sql) END
          );
          PREPARE st FROM @sql_ins;                                           -- 準備
          SET @p := v_src_uuid;                                               -- @p: バインド用 “親の元UUID”
          EXECUTE st USING @p;                                                -- 実行（? に @p を渡す）
          DEALLOCATE PREPARE st;                                              -- 解放

          BEGIN
            DECLARE done2 INT DEFAULT 0;                                      -- 子UUID列挙の終了フラグ
            DECLARE v_child_uuid BINARY(16);                                  -- v_child_uuid: 子の元UUID
            DECLARE cur2 CURSOR FOR SELECT child_uuid FROM tmp_docsnap_children; -- 子UUIDを順に読むカーソル
            DECLARE CONTINUE HANDLER FOR NOT FOUND SET done2 = 1;             -- 取り切ったら終了

            OPEN cur2;                                                        -- 開始
            loop2: LOOP                                                       -- 反復
              FETCH cur2 INTO v_child_uuid;                                   -- 1つ子UUID取得
              IF done2 = 1 THEN LEAVE loop2; END IF;                          -- 終了

              INSERT INTO tmp_docsnap_queue(                                  -- 次の深さのキューに子を積む
                depth, table_name, source_uuid,
                parent_table, parent_source_uuid, parent_snap_uuid
              )
              VALUES (
                v_cur_depth+1, v_child_table, v_child_uuid,                   -- depth: 現在+1 / 子テーブル / 子元UUID
                v_tbl, v_src_uuid, v_snap_uuid                                -- 親情報: 親テーブル / 親元UUID / 親スナップUUID
              );
            END LOOP;
            CLOSE cur2;                                                       -- 終了
          END;

        END LOOP;
        CLOSE cur;                                                            -- 子宣言カーソル終了
      END;

      UPDATE tmp_docsnap_queue SET processed=1 WHERE id=v_id;                 -- このキュー行を処理済みに更新
    END;

    ITERATE depth_loop;                                                       -- 同じ深さに未処理がまだあればループ継続
  END LOOP depth_loop;                                                        -- 全層処理完了で抜ける
END $$                                                                         -- SP終端
DELIMITER ;                                                                    -- DELIMITER: ';' に復帰
