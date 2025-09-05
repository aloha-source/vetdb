-- ============================================
-- SAL v1 （コメント付き完全版・スキーマ＋監査＋保存SP）
-- ※ “コードに変更なし”。コメントのみ追加。
-- ============================================

-- ------------------------------
-- 1) 請求（charges）：売上（正数）。未収は alloc（配分）で相殺していく。
-- ------------------------------
CREATE TABLE receivable_charges (
  uuid                BINARY(16) PRIMARY KEY,                          -- 行ID（UUID: BINARY(16)）
  counterparty_type   ENUM('farm','insurer') NOT NULL,                 -- 相手先の種別：農家 or 保険会社
  counterparty_uuid   BINARY(16) NOT NULL,                             -- 相手先UUID
  amount_yen          INT NOT NULL CHECK (amount_yen >= 0),            -- 請求金額（正数）
  occurred_at         DATETIME NOT NULL,                               -- 発生日（請求日/締め日など）
  row_version         BIGINT NOT NULL DEFAULT 0,                       -- 楽観ロック用バージョン番号

  created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,     -- 生成時刻（DBサーバ）
  updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, -- 最終更新時刻

  KEY idx_rcp_ctp_ctu (counterparty_type, counterparty_uuid),          -- 相手先での検索用複合キー
  KEY idx_occurred    (occurred_at)                                    -- 期間検索用
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------
-- 2) クレジット（credits）：入金/調整/相殺も“正数”で統一して保存
-- ----------------------------------------
CREATE TABLE receivable_credits (
  uuid                BINARY(16) PRIMARY KEY,                          -- 行ID（UUID）
  counterparty_type   ENUM('farm','insurer') NOT NULL,                 -- 相手先の種別
  counterparty_uuid   BINARY(16) NOT NULL,                             -- 相手先UUID

  credit_type         ENUM(                                            -- 種別（入金/相殺/調整など）
    'cash','direct_debit','insurer_payment','adjustment','void','rounding','discount'
  ) NOT NULL,
  amount_yen          INT NOT NULL CHECK (amount_yen >= 0),            -- 金額（常に正）
  occurred_at         DATETIME NOT NULL,                               -- 発生日（入金日/相殺日など）

  -- INSERTはログ不要運用のため、誰がどう作ったかの最小痕跡をここに保存
  created_by_user_uuid  BINARY(16) NULL,                               -- 作成者UUID
  created_via           ENUM('ui','import','system','api') NOT NULL DEFAULT 'ui', -- 生成経路
  op_reason             VARCHAR(255) NULL,                              -- 事由メモ（任意）

  row_version         BIGINT NOT NULL DEFAULT 0,                       -- 手修正を許す場合のために付与

  created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,     -- 生成時刻
  updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, -- 更新時刻

  KEY idx_ccp_ctp_ctu (counterparty_type, counterparty_uuid),          -- 相手先での検索用
  KEY idx_credit_type (credit_type),                                   -- 種別での分析用
  KEY idx_occurred    (occurred_at)                                    -- 期間分析用
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------
-- 3) 配分（allocations）：あるクレジットをどの請求に何円充当したか
-- ----------------------------------------------------------
CREATE TABLE receivable_allocations (
  id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,      -- 行ID（数値）
  charge_uuid         BINARY(16) NOT NULL,                             -- 紐づく請求
  credit_uuid         BINARY(16) NOT NULL,                             -- 紐づくクレジット
  amount_yen          INT NOT NULL CHECK (amount_yen >= 0),            -- 充当金額（正数）

  created_by_user_uuid  BINARY(16) NULL,                               -- 生成者（追跡）
  created_via           ENUM('ui','import','system','api') NOT NULL DEFAULT 'ui', -- 生成経路
  note                  VARCHAR(255) NULL,                              -- 任意メモ

  row_version         BIGINT NOT NULL DEFAULT 0,                       -- 手修正（編集）許可時に使用
  created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,     -- 生成時刻

  KEY idx_charge (charge_uuid),                                        -- 請求別合計の高速化
  KEY idx_credit (credit_uuid),                                        -- クレジット別合計の高速化
  CONSTRAINT fk_alloc_charge FOREIGN KEY (charge_uuid) REFERENCES receivable_charges(uuid)
    ON DELETE CASCADE ON UPDATE RESTRICT,                              -- 親が消えたら配分も消す
  CONSTRAINT fk_alloc_credit FOREIGN KEY (credit_uuid) REFERENCES receivable_credits(uuid)
    ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------
-- 4) ビュー：請求ごとの未収金額（open_amount_yen）を即時計算
--    ※ open = 請求金額 - その請求に対する配分合計
-- ------------------------------------------------------
CREATE OR REPLACE VIEW v_receivable_open AS
SELECT
  c.uuid               AS charge_uuid,                                  -- 請求ID
  c.counterparty_type,                                                  -- 相手種別
  c.counterparty_uuid,                                                  -- 相手UUID
  c.amount_yen,                                                         -- 請求金額
  c.occurred_at,                                                        -- 請求日
  (c.amount_yen - IFNULL((
     SELECT SUM(a.amount_yen) FROM receivable_allocations a WHERE a.charge_uuid = c.uuid
   ), 0)
  ) AS open_amount_yen                                                  -- 未収金額
FROM receivable_charges c;

-- --------------------------------------------
-- 監査ログ（手修正のみ：UPDATE/DELETE を対象）
-- 差分は delta_json に { col: {before, after}, ... } で保存
-- --------------------------------------------
CREATE TABLE manual_corrections (
  id               BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,          -- 行ID
  occurred_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,         -- 記録時刻
  actor_user_uuid  BINARY(16) NOT NULL,                                 -- 操作者UUID
  actor_name       VARCHAR(128) NULL,                                   -- 操作者名（表示用）

  entity           VARCHAR(64) NOT NULL,                                -- 対象テーブル論理名（例: 'receivable_charges'）
  charge_uuid      BINARY(16) NULL,                                     -- 対象キー（請求）
  credit_uuid      BINARY(16) NULL,                                     -- 対象キー（クレジット）
  alloc_id         BIGINT NULL,                                         -- 対象キー（配分）

  action           ENUM('update') NOT NULL DEFAULT 'update',            -- 操作種別（最小：updateのみ）
  reason           VARCHAR(255) NOT NULL,                               -- 手修正の理由（UIで必須入力）
  delta_json       LONGTEXT NOT NULL,                                   -- 差分JSON

  KEY idx_charge (charge_uuid),                                         -- 検索用
  KEY idx_credit (credit_uuid),
  KEY idx_alloc  (alloc_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =========================================================
-- 汎用 保存＋差分ログ ストアド（UNHEX不要：BINARY(16)直バインド）
-- 1行更新のたびに呼び出し（編集モードで「保存」されたとき）
-- 手順：
-- ① SELECT ... FOR UPDATE で row_version 取得＆行ロック
-- ② 楽観ロック（画面の row_version と一致検証）
-- ③ p_after_json のキーだけ before/after を比較し差分作成
-- ④ 差分ゼロなら NO_CHANGE で終了（row_versionもログも増やさない）
-- ⑤ 差分カラムだけ UPDATE（row_versionを+1）
-- ⑥ manual_corrections に差分JSONを1行INSERT
-- ⑦ COMMIT
-- =========================================================
DELIMITER // 

CREATE PROCEDURE sp_save_row_ultralite (
  IN  p_table            VARCHAR(64),         -- 物理テーブル名（例: 'receivable_charges'）
  IN  p_pk_col           VARCHAR(64),         -- 主キー列名（例: 'uuid' / 'id'）
  IN  p_pk_kind          ENUM('uuid','bigint'), -- 主キー型（uuid/bigint）
  IN  p_pk_bin           BINARY(16),          -- UUID主キーの実値（BINARY(16)）
  IN  p_pk_bigint        BIGINT,              -- BIGINT主キーの実値
  IN  p_row_version      BIGINT,              -- 楽観ロック用 row_version（画面の値）
  IN  p_after_json       LONGTEXT,            -- 変更候補 {列:値,...}（変更した列だけ送る）
  IN  p_actor_uuid_bin   BINARY(16),          -- 操作者UUID（BINARY(16)）
  IN  p_actor_name       VARCHAR(128),        -- 操作者名
  IN  p_reason           VARCHAR(255),        -- 修正理由（必須）
  IN  p_entity           VARCHAR(64),         -- ログ表示用の論理名
  IN  p_log_key_column   VARCHAR(64)          -- manual_corrections側の対象キー列名
)
BEGIN
  DECLARE v_pk BLOB;                 -- WHEREに使う主キー（uuid/bigint を両方受けられる器）
  DECLARE v_db_ver BIGINT;           -- DB上の現行 row_version
  DECLARE v_delta LONGTEXT DEFAULT JSON_OBJECT();  -- 差分JSON（{col:{before,after},...}）
  DECLARE v_changes INT DEFAULT 0;   -- 変更カラム数
  DECLARE v_set_csv LONGTEXT DEFAULT '';           -- UPDATE SET句のCSV

  SET v_pk = IF(p_pk_kind='uuid', p_pk_bin, p_pk_bigint);  -- 主キー実値を決定

  START TRANSACTION;  -- 原子性確保

  -- ① row_version をロック付きで取得（存在しなければ404）
  SET @sql_lock := CONCAT(
    'SELECT row_version INTO @dbver FROM `', p_table, '` ',
    'WHERE `', p_pk_col, '`=? FOR UPDATE'
  );
  PREPARE s0 FROM @sql_lock; EXECUTE s0 USING v_pk; DEALLOCATE PREPARE s0;
  SET v_db_ver = @dbver;
  IF v_db_ver IS NULL THEN
    ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='404_NOT_FOUND';
  END IF;

  -- ② 楽観ロック：画面の row_version と一致しなければ競合
  IF v_db_ver <> p_row_version THEN
    ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='409_CONFLICT';
  END IF;

  -- ③ 送信されたキーだけ比較して差分作成（カラム定義の事前取得は不要）
  SET @keys  := JSON_KEYS(p_after_json);              -- 変更候補のキー配列
  SET @n     := IFNULL(JSON_LENGTH(@keys), 0);        -- キー数
  SET @i     := 0;
  SET @after := p_after_json;                          -- 可読性のため別名

  WHILE @i < @n DO
    SET @k := JSON_UNQUOTE(JSON_EXTRACT(@keys, CONCAT('$[', @i, ']')));  -- i番目の列名

    -- before を1カラムだけ取得（行はFOR UPDATE済）
    SET @sql_col := CONCAT(
      'SELECT `', @k, '` INTO @b FROM `', p_table, '` WHERE `', p_pk_col, '`=?'
    );
    PREPARE s1 FROM @sql_col; EXECUTE s1 USING v_pk; DEALLOCATE PREPARE s1;

    -- after は JSON から取得（文字として比較：厳密化したければCASTを追加）
    SET @a := JSON_UNQUOTE(JSON_EXTRACT(@after, CONCAT('$.', @k)));

    IF NOT ((@b IS NULL AND @a IS NULL) OR (@b = @a)) THEN
      -- 差分JSONに {before, after} を記録
      SET v_delta = JSON_SET(v_delta, CONCAT('$.', @k), JSON_OBJECT('before', @b, 'after', @a));
      SET v_changes = v_changes + 1;

      -- UPDATEのSET句に積む（差分カラムだけ）
      SET v_set_csv = IF(
        v_set_csv='',
        CONCAT('`', @k, '` = JSON_UNQUOTE(JSON_EXTRACT(@after, ''$.', @k, '''))'),
        CONCAT(v_set_csv, ', `', @k, '` = JSON_UNQUOTE(JSON_EXTRACT(@after, ''$.', @k, '''))')
      );
    END IF;

    SET @i := @i + 1;
  END WHILE;

  -- ④ 差分なし：row_versionもログも触らず終了
  IF v_changes = 0 THEN
    COMMIT; SELECT 'NO_CHANGE' AS status; LEAVE proc;
  END IF;

  -- ⑤ 差分カラムだけ UPDATE ＋ row_version を +1
  SET @upd := CONCAT(
    'UPDATE `', p_table, '` SET ', v_set_csv, ', `row_version`=`row_version`+1 ',
    'WHERE `', p_pk_col, '`=?'
  );
  PREPARE s2 FROM @upd; EXECUTE s2 USING v_pk; DEALLOCATE PREPARE s2;

  -- ⑥ 差分ログ1行（manual_corrections）
  SET @ins := CONCAT(
    'INSERT INTO manual_corrections(',
    'occurred_at,actor_user_uuid,actor_name,entity,', p_log_key_column, ',action,reason,delta_json',
    ') VALUES (NOW(), ?, ?, ?, ?, ''update'', ?, ?)'
  );
  PREPARE s3 FROM @ins;
  EXECUTE s3 USING
    p_actor_uuid_bin,       -- 操作者UUID（BINARY(16)）
    p_actor_name,           -- 操作者名
    p_entity,               -- 表示用エンティティ名
    v_pk,                   -- 対象キー（uuid: BINARY(16) / bigint: 数値）
    p_reason,               -- 修正理由
    v_delta;                -- 差分JSON
  DEALLOCATE PREPARE s3;

  COMMIT;                      -- 変更とログを同時確定（オールorナッシング）
  SELECT 'OK' AS status;       -- 呼び出し側が見やすいステータス

proc: END//

DELIMITER ;
