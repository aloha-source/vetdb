/* 000_checkup_create_uuid_functions.sql */
-- @phase: create
-- @provides: function:uuid_bin_to_hex, function:uuid_hex_to_bin, function:uuid_v7_str, function:uuid_v7_bin
-- @requires:

SET NAMES utf8mb4;

DELIMITER $$

DROP FUNCTION IF EXISTS uuid_bin_to_hex $$
CREATE FUNCTION uuid_bin_to_hex(b BINARY(16)) RETURNS CHAR(32) DETERMINISTIC
BEGIN
  RETURN LOWER(HEX(b));
END$$

DROP FUNCTION IF EXISTS uuid_hex_to_bin $$
CREATE FUNCTION uuid_hex_to_bin(s VARCHAR(36)) RETURNS BINARY(16) DETERMINISTIC
BEGIN
  RETURN UNHEX(REPLACE(LOWER(s), '-', ''));
END$$

DROP FUNCTION IF EXISTS uuid_v7_str $$
CREATE FUNCTION uuid_v7_str() RETURNS CHAR(36) NOT DETERMINISTIC
BEGIN
  /* 擬似 UUIDv7: ミリ秒エポック + 乱数（検証用） */
  DECLARE ts_ms BIGINT UNSIGNED;
  DECLARE ts_hex CHAR(12);
  DECLARE r12 INT UNSIGNED;
  DECLARE ver_hi CHAR(4);
  DECLARE var_hi CHAR(4);
  DECLARE tail CHAR(12);
  DECLARE t_hi CHAR(8);
  DECLARE t_mid CHAR(4);

  SET ts_ms = CAST(ROUND(UNIX_TIMESTAMP(CURRENT_TIMESTAMP(3))*1000) AS UNSIGNED);
  SET ts_hex = LPAD(HEX(ts_ms),12,'0');
  SET r12 = FLOOR(RAND()*POW(2,12));
  SET ver_hi = CONCAT('7', LPAD(HEX(r12),3,'0'));
  SET var_hi = CONCAT(ELT(FLOOR(RAND()*4)+1,'8','9','a','b'), LPAD(HEX(FLOOR(RAND()*POW(2,12))),3,'0'));
  SET tail = LPAD(HEX(FLOOR(RAND()*POW(2,48))),12,'0');

  SET t_hi = LEFT(ts_hex,8);
  SET t_mid = SUBSTRING(ts_hex,9,4);
  RETURN LOWER(CONCAT(t_hi,'-',t_mid,'-',ver_hi,'-',var_hi,'-',tail));
END$$

DROP FUNCTION IF EXISTS uuid_v7_bin $$
CREATE FUNCTION uuid_v7_bin() RETURNS BINARY(16) NOT DETERMINISTIC
BEGIN
  RETURN uuid_hex_to_bin(uuid_v7_str());
END$$

DELIMITER ;
