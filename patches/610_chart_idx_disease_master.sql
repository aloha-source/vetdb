/* 610_chart_idx_disease_master.sql */
-- @phase: idx
-- @provides: index:idx_dm_name, index:idx_dm_list
-- @requires: table:disease_master

CREATE INDEX idx_dm_name ON disease_master(major_name, middle_name, minor_name);
CREATE INDEX idx_dm_list ON disease_master(deleted_at, updated_at, id);
