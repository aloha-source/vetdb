SET NAMES utf8mb4;

-- =====================================================================
-- vetDB v1p9 — Outbox / Inbox 新設（BINARY(16) 版・既存関数利用）
-- 依存関数（既存）:
--   • uuid_hex_to_bin(s VARCHAR(36)) RETURNS BINARY(16)
--   • uuid_bin_to_hex(b BINARY(16)) RETURNS CHAR(32)
--   • uuid_v7_bin() RETURNS BINARY(16)
-- 方針:
--   • APIは文字UUID、DBはBINARY(16)。DB-API間の変換はアプリ層で実施。
--   • 時刻はUTC保存（表示でTZ変換）。
--   • ENGINE=InnoDB / utf8mb4 / ROW_FORMAT=DYNAMIC（MariaDB 10.5）
-- =====================================================================


/* ---------------------------------------------------------------------
   Outbox（配信キュー）
   役割:
     - 本体Tx内でイベント行をINSERT（確定と同時に記録）
     - ワーカーが pending を取り出して配信（at-least-once）
   カラム要点:
     - event_uuid   : イベントID（BINARY(16), UNIQUE）
     - aggregate    : 集約名（'visit','checkup','appointment'など）
     - aggregate_id : 対象UUID（BINARY(16)）
     - event_type   : 'created' | 'updated' | 'deleted' など
     - payload_json : スナップショット or 差分（まずはスナップショット推奨）
     - attempts     : 送信試行回数
     - available_at : 次回試行時刻（指数バックオフで再設定）
     - status       : 'pending' | 'sent' | 'failed'
   インデックス:
     - (status, available_at, id): 配信対象スキャンの最適化
     - (aggregate, aggregate_id) : 対象別の監査/再送用
   --------------------------------------------------------------------- */
DROP TRIGGER IF EXISTS tr_outbox_messages_bi_uuid_v7;

CREATE TABLE IF NOT EXISTS outbox_messages (
  id             BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,          -- 配信順の近似
  event_uuid     BINARY(16)  NOT NULL UNIQUE,                         -- イベントUUID（BINARY16）
  aggregate      VARCHAR(64) NOT NULL,                                -- 集約名
  aggregate_id   BINARY(16)  NOT NULL,                                -- 対象UUID（BINARY16）
  event_type     VARCHAR(64) NOT NULL,                                -- created/updated/deleted 等
  payload_json   JSON        NOT NULL,                                -- MariaDB 10.5: 実体はLONGTEXT
  attempts       INT UNSIGNED NOT NULL DEFAULT 0,                     -- 試行回数
  available_at   DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,      -- 次回試行（UTC）
  status         ENUM('pending','sent','failed') NOT NULL DEFAULT 'pending',
  created_at     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_outbox_status_available (status, available_at, id),
  INDEX idx_outbox_aggregate (aggregate, aggregate_id)
) ENGINE=InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  ROW_FORMAT = DYNAMIC;

-- 既存の uuid_v7_bin() を利用して event_uuid を自動付与
DELIMITER //
CREATE TRIGGER tr_outbox_messages_bi_uuid_v7
BEFORE INSERT ON outbox_messages
FOR EACH ROW
BEGIN
  IF NEW.event_uuid IS NULL THEN
    SET NEW.event_uuid = uuid_v7_bin();           -- 既存: 擬似v7のBINARY(16)
    -- v7でなくてよければ下記でも可（どちらか片方のみ利用）
    -- SET NEW.event_uuid = uuid_hex_to_bin(uuid());
  END IF;
END//
DELIMITER ;


-- ---------------------------------------------------------------------
-- Inbox（Idempotency-Key 重複排除）
-- 役割:
--   - 同一Idempotency-Keyの多重適用を防止（Tx内で挿入して確定）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS inbox_processed (
  idempotency_key VARCHAR(128) PRIMARY KEY,                            -- クライアント送信ユニークキー
  processed_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP          -- 初回処理時刻（UTC）
) ENGINE=InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  ROW_FORMAT = DYNAMIC;


-- =====================================================================
-- 参考: ワーカー/APIでの利用例（DDL外、実装時のSQLイメージ）
-- 1) 取得（最大100件、pending & 期限到来）
--    UUIDを「32桁HEX（ダッシュ無し）」で返したい場合は uuid_bin_to_hex() を使用。
--    「36桁ダッシュ形式」が必要なら下段の式例を利用（既存関数のみで実現可）。
-- =====================================================================

/*
-- 32桁HEXで返す例（既存: uuid_bin_to_hex）
SELECT id,
       uuid_bin_to_hex(event_uuid)   AS event_uuid_hex,
       aggregate,
       uuid_bin_to_hex(aggregate_id) AS aggregate_id_hex,
       event_type, payload_json, attempts
FROM outbox_messages
WHERE status='pending'
  AND available_at <= UTC_TIMESTAMP()
ORDER BY id
LIMIT 100;

-- 36桁ダッシュ形式で返す場合（関数追加せず式で対応）
SELECT id,
       LOWER(CONCAT(
         SUBSTR(HEX(event_uuid),1,8),'-',
         SUBSTR(HEX(event_uuid),9,4),'-',
         SUBSTR(HEX(event_uuid),13,4),'-',
         SUBSTR(HEX(event_uuid),17,4),'-',
         SUBSTR(HEX(event_uuid),21,12)
       )) AS event_uuid_str,
       aggregate,
       LOWER(CONCAT(
         SUBSTR(HEX(aggregate_id),1,8),'-',
         SUBSTR(HEX(aggregate_id),9,4),'-',
         SUBSTR(HEX(aggregate_id),13,4),'-',
         SUBSTR(HEX(aggregate_id),17,4),'-',
         SUBSTR(HEX(aggregate_id),21,12)
       )) AS aggregate_id_str,
       event_type, payload_json, attempts
FROM outbox_messages
WHERE status='pending'
  AND available_at <= UTC_TIMESTAMP()
ORDER BY id
LIMIT 100;

-- 成功時の更新
UPDATE outbox_messages
   SET status='sent', updated_at=UTC_TIMESTAMP()
 WHERE id IN (...);

-- 失敗時の指数バックオフ（例：2^attempts 秒、上限はアプリ側で制御）
UPDATE outbox_messages
   SET attempts = attempts + 1,
       available_at = DATE_ADD(UTC_TIMESTAMP(), INTERVAL LEAST(3600, POW(2, attempts)) SECOND),
       status = IF(attempts+1 >= 10, 'failed', 'pending'),
       updated_at = UTC_TIMESTAMP()
 WHERE id = ?;
*/
