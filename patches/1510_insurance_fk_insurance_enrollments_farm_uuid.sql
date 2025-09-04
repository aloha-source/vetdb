/* 1510_insurance_fk_insurance_enrollments_farm_uuid.sql */
-- @phase: fk
-- @provides: fk:fk_ins_enro_farm
-- @requires: table:insurance_enrollments, table:farms
-- 役割: farm_uuid → farms.uuid（ON UPDATE CASCADE / ON DELETE RESTRICT）

ALTER TABLE `insurance_enrollments`
  ADD CONSTRAINT `fk_ins_enro_farm`
    FOREIGN KEY (`farm_uuid`) REFERENCES `farms`(`uuid`)
    ON UPDATE CASCADE ON DELETE RESTRICT;
