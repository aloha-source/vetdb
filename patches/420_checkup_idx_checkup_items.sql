/* 420_checkup_idx_checkup_items.sql */
-- @phase: idx
-- @provides: index:idx_checkup_items_parent, index:idx_checkup_items_list, index:idx_checkup_items_clinic
-- @requires: table:checkup_items

CREATE INDEX idx_checkup_items_parent ON checkup_items(checkup_uuid, pay_type);
CREATE INDEX idx_checkup_items_list   ON checkup_items(deleted_at, updated_at, id);
CREATE INDEX idx_checkup_items_clinic ON checkup_items(clinic_uuid, id);
