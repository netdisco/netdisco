#!/usr/bin/env bash

su=( su-exec "${PGUSER:-postgres}" )
psql=( psql -X -v ON_ERROR_STOP=0 -v ON_ERROR_ROLLBACK=on )
psql+=( --username netdisco --dbname netdisco )

if [ "$1" = 'postgres' ]; then
  if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo >&2 "netdisco-db-entrypoint: copying initial database files"
    chmod 700 /var/lib/postgresql/data
    chown postgres /var/lib/postgresql/data
    cp -a /var/lib/postgresql/netdisco-pgdata/* /var/lib/postgresql/data/
  fi

  echo >&2 "netdisco-db-entrypoint: starting pg privately to container"
  "${su[@]}" pg_ctl -D "$PGDATA" -o "-c listen_addresses='localhost'" -w start

  echo >&2 "netdisco-db-entrypoint: configuring Netdisco db user"
  echo "*:*:netdisco:netdisco:netdisco" > ~/.pgpass
  chmod 0600 ~/.pgpass
  "${su[@]}" createuser -DRSw netdisco
  "${su[@]}" createdb -O netdisco netdisco

  echo >&2 "netdisco-db-entrypoint: bringing schema up-to-date"
  ls -1 /var/lib/postgresql/netdisco-sql/App-Netdisco-DB-* | \
  xargs -n1 basename | sort -n -t '-' -k4 | \
  while read file; do
    "${psql[@]}" -f "/var/lib/postgresql/netdisco-sql/$file"
  done

  echo >&2 "netdisco-db-entrypoint: importing OUI"
  NUMOUI=$("${psql[@]}" -A -t -c "SELECT count(oui) FROM oui")
  if [ "$NUMOUI" -eq 0 ]; then
    "${psql[@]}" -f /var/lib/postgresql/netdisco-sql/oui.sql
  fi

  echo >&2 "netdisco-db-entrypoint: marking schema as up-to-date"
  MAXSCHEMA=$(grep VERSION /var/lib/postgresql/netdisco-sql/DB.pm | sed 's/[^0-9]//g')
  STAMP=$(date '+v%Y%m%d_%H%M%S.000')
  "${psql[@]}" -c "CREATE TABLE dbix_class_schema_versions (version varchar(10) PRIMARY KEY, installed varchar(20) NOT NULL)"
  "${psql[@]}" -c "INSERT INTO dbix_class_schema_versions VALUES ('${MAXSCHEMA}', '${STAMP}')"

  echo >&2 "netdisco-db-entrypoint: shutting down pg (will restart listening for clients)"
  "${su[@]}" pg_ctl -D "$PGDATA" -m fast -w stop
fi

exec /usr/local/bin/docker-entrypoint.sh "$@"
