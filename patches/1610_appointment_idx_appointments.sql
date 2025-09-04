/* 1610_appointment_idx_appointments.sql */
-- @phase: idx
-- @provides: index:idx_appt_list, index:idx_appt_tenant_time, index:idx_appt_farm_time, index:idx_appt_individual, index:idx_appt_org
-- @requires: table:appointments

CREATE INDEX idx_appt_list        ON appointments (deleted_at, updated_at, id);
CREATE INDEX idx_appt_tenant_time ON appointments (clinic_uuid, start_at, end_at);
CREATE INDEX idx_appt_farm_time   ON appointments (farm_uuid, start_at, end_at);
CREATE INDEX idx_appt_individual  ON appointments (individual_uuid);
CREATE INDEX idx_appt_org         ON appointments (organizer_vet_user_uuid);
