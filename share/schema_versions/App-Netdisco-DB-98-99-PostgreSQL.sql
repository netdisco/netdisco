BEGIN;

-- port_sortkey turns a port name into a text key that sorts the way
-- share/public/javascripts/portsort.js orders the Ports tab, so the order can
-- come from ORDER BY instead of from re-sorting in the browser. Compare the
-- result COLLATE "C", and break ties on the raw port name.
--
-- Three rules constrain how this file may be written, and they come from
-- DBIx::Class::Schema::Versioned::_read_sql_file, not from Postgres. It drops
-- lines starting with -- or BEGIN or COMMIT, joins what is left with NO
-- separator, then splits on ";". So: no semicolon anywhere inside the
-- statement, including inside the $$ body, which is why this function is a
-- single SELECT; every continuation line starts with whitespace, or its first
-- token fuses to the previous line's last one; and no -- comment anywhere but
-- at the start of a line. A failure here is silent: netdisco's
-- App::Netdisco::DB::SchemaVersioned swallows the error and stamps the version
-- anyway, so the first sign would be every Ports tab request failing with
-- "function port_sortkey(text) does not exist".

CREATE OR REPLACE FUNCTION port_sortkey(raw text)
  RETURNS text LANGUAGE sql IMMUTABLE STRICT AS $$
    WITH norm AS (
      SELECT regexp_replace(btrim(raw, ' '), '^10(GigabitEthernet)', '\1') AS s
    ), chunks AS (
      SELECT m[1] AS chunk, ord
        FROM norm, LATERAL regexp_matches(norm.s, '([0-9]+|[^0-9]+)', 'g')
               WITH ORDINALITY AS t(m, ord)
       WHERE norm.s !~* '^0x[0-9a-f]+$'
    ), tokens AS (
      SELECT string_agg(
               CASE
                 WHEN chunk ~ '^[[:space:]]+$' THEN 'A' || chunk
                 WHEN chunk ~ '^0'             THEN 'A' || chunk
                 WHEN chunk ~ '^[0-9]'         THEN 'B' || lpad(length(chunk)::text, 3, '0') || chunk
                 ELSE                               'C' || chunk
               END || E'\x01', '' ORDER BY ord) AS body
        FROM chunks
    )
    SELECT CASE WHEN norm.s ~* '^0x[0-9a-f]+$'
                THEN 'A' || norm.s || E'\x01'
                ELSE COALESCE(tokens.body, '')
           END || E'A0\x01'
      FROM norm, tokens
  $$;

COMMIT;
