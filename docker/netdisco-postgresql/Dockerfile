# vim: ft=Dockerfile
FROM docker.io/postgres:9.6.6-alpine

ARG TAG
ENV TAG ${TAG:-master}

RUN apk add --no-cache \
  curl \
  jq \
  tar

WORKDIR /var/lib/postgresql/netdisco-sql
RUN curl -sL "https://api.github.com/repos/netdisco/netdisco/tarball/${TAG}" | \
  tar --wildcards -zt '*App-Netdisco-DB-*' | xargs -n1 basename | sort -n -t '-' -k4 | \
  while read file; \
    do curl -sLO "https://raw.githubusercontent.com/netdisco/netdisco/${TAG}/share/schema_versions/$file"; \
  done && \
  curl -sLO "https://raw.githubusercontent.com/netdisco/upstream-sources/master/ieee/oui.sql" && \
  curl -sLO "https://raw.githubusercontent.com/netdisco/netdisco/master/lib/App/Netdisco/DB.pm"

RUN PGDATA=/var/lib/postgresql/netdisco-pgdata /usr/local/bin/docker-entrypoint.sh postgres --version

COPY netdisco-db-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/netdisco-db-entrypoint.sh

WORKDIR /
VOLUME /var/lib/postgresql/data
ENTRYPOINT ["/usr/local/bin/netdisco-db-entrypoint.sh"]
CMD ["postgres"]
