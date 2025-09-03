/* 672_chart_fk_chd_insenroll.sql */
-- @phase: fk
-- @provides: fk:fk_chd_insenroll
-- @requires: table:chart_header_drafts, table:insurance_enrollments

ALTER TABLE chart_header_drafts
  ADD CONSTRAINT fk_chd_insenroll
    FOREIGN KEY (insurance_enrollment_id) REFERENCES insurance_enrollments(id)
    ON UPDATE CASCADE ON DELETE SET NULL;
