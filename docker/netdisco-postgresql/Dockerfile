# vim: ft=Dockerfile
ARG TAG=master
FROM docker.io/postgres:9.6.6-alpine

LABEL org.netdisco.maintainer="The Netdisco Project"
LABEL org.netdisco.version=${TAG}

RUN apk add --no-cache \
  curl \
  jq \
  tar

COPY netdisco-db-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/netdisco-db-entrypoint.sh

RUN PGDATA=/var/lib/postgresql/netdisco-pgdata /usr/local/bin/docker-entrypoint.sh postgres --version

WORKDIR /var/lib/postgresql/netdisco-sql
RUN curl -sL https://api.github.com/repos/netdisco/netdisco/tags | \
  jq '.[]|.name|select(test("^\\d+\\.\\d+$"))|"https://api.github.com/repos/netdisco/netdisco/tarball/"+.' | \
  sort -rg | head -n1 | xargs -n1 curl -sL | \
  tar --wildcards --strip-components=3 -zx '*App-Netdisco-DB-*' && \
  curl -sLO "https://raw.githubusercontent.com/netdisco/upstream-sources/master/ieee/oui.sql" && \
  curl -sLO "https://raw.githubusercontent.com/netdisco/netdisco/master/lib/App/Netdisco/DB.pm"

VOLUME ["/var/lib/postgresql/data"]

WORKDIR /
ENTRYPOINT ["/usr/local/bin/netdisco-db-entrypoint.sh"]
CMD ["postgres"]
