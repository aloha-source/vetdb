/* 1996_farmmirror_create_entity_links.sql */
-- @phase: create
-- @provides: table:entity_links
-- @requires: table:farms, table:farm_users, table:farmdb_*_mirror, table:individuals (individual分岐を使う場合)

DROP TABLE IF EXISTS entity_links;
CREATE TABLE entity_links (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

  clinic_uuid   BINARY(16) NOT NULL,                  -- ← local 由来（トリガで確定）
  entity_type   ENUM('farm','individual','farm_user') NOT NULL,
  source_system ENUM('farmdb') NOT NULL DEFAULT 'farmdb',

  local_uuid    BINARY(16) NOT NULL,                  -- VetDB SoT 側 UUID
  remote_uuid   BINARY(16) NOT NULL,                  -- farmDB mirror 側 UUID

  is_primary    TINYINT(1) NOT NULL DEFAULT 1,        -- 将来: 多対1許容時の“主”印
  note          VARCHAR(255) NULL,

  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
