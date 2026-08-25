BEGIN;

-- Three rules constrain how this file may be written, and they come from
-- DBIx::Class::Schema::Versioned::_read_sql_file, not from Postgres. It drops
-- lines starting with -- or BEGIN or COMMIT, joins what is left with NO
-- separator, then splits on ";". So: every continuation line starts with
-- whitespace, or its first token fuses to the previous line's last one;
-- and no -- comment anywhere but at the start of a line.

-- migrate from IP list inside the users table, to a managed ACL
-- by building ACLs dynamically and then relating them to the user entry

-- add temporary username column to the acl table
ALTER TABLE access_control_list ADD COLUMN username text;
-- add temporary acl ID columns to users table
ALTER TABLE users ADD COLUMN acl_id integer;
ALTER TABLE users ADD COLUMN empty_acl_id integer;

-- create an ACL from the IPs in the username entry
WITH inserted_rows AS (
    INSERT INTO access_control_list (rules, username)
    SELECT token_allowed_ips, username 
    FROM users
    WHERE token_allowed_ips IS NOT NULL
    RETURNING id, username
  )
  UPDATE users
  SET acl_id = ir.id
  FROM inserted_rows ir
  WHERE users.username = ir.username;

-- insert and store one empty acl for each acl map
WITH inserted_rows AS (
    INSERT INTO access_control_list (rules, username)
    SELECT '{}', username 
    FROM users
    WHERE token_allowed_ips IS NOT NULL
    RETURNING id, username
  )
  UPDATE users
  SET empty_acl_id = ir.id
  FROM inserted_rows ir
  WHERE users.username = ir.username;

-- delete temporary username column from the acl
ALTER TABLE access_control_list DROP COLUMN username;

-- delete the legacy allowed IPs array from users
ALTER TABLE users DROP COLUMN token_allowed_ips;
-- create the new acl name column in users
ALTER TABLE users ADD COLUMN token_allowed_acl text;

-- synthesize the acl name column in users
UPDATE users
  SET token_allowed_acl = concat(username, '_acl') WHERE acl_id IS NOT NULL;

-- insert into aclname by selecting synthesized acl name from users
INSERT INTO access_control_list_name (acl_name, acl_type)
  SELECT token_allowed_acl, 'host' FROM users WHERE acl_id IS NOT NULL;

-- insert into aclmap by selecting the two acl id fields from users
INSERT INTO access_control_list_map (acl_name, left_acl_id, right_acl_id)
  SELECT token_allowed_acl, acl_id, empty_acl_id FROM users WHERE acl_id IS NOT NULL;

-- delete temporary acl ID fields from users
ALTER TABLE users DROP COLUMN acl_id;
ALTER TABLE users DROP COLUMN empty_acl_id;

COMMIT;
