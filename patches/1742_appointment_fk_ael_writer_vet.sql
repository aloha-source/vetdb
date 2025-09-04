/* 1742_appointment_fk_ael_writer_vet.sql */
-- @phase: fk
-- @provides: fk:fk_ael_writer_vet
-- @requires: table:appointment_event_links, table:vet_users

ALTER TABLE appointment_event_links
  ADD CONSTRAINT fk_ael_writer_vet
    FOREIGN KEY (writer_vet_user_uuid) REFERENCES vet_users(uuid)
    ON UPDATE CASCADE ON DELETE SET NULL;
