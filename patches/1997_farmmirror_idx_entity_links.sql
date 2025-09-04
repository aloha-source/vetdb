/* 1997_farmmirror_idx_entity_links.sql */
-- @phase: idx
-- @provides: index:uq_entity_links_remote, index:idx_entity_links_local, index:idx_entity_links_clinic
-- @requires: table:entity_links

CREATE UNIQUE INDEX uq_entity_links_remote ON entity_links (entity_type, source_system, remote_uuid);
CREATE INDEX        idx_entity_links_local  ON entity_links (entity_type, local_uuid);
CREATE INDEX        idx_entity_links_clinic ON entity_links (clinic_uuid, entity_type, updated_at, id);
