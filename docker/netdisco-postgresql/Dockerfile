# vim: ft=Dockerfile
FROM docker.io/postgres:9.6.6-alpine

RUN apk add --no-cache \
  curl \
  jq \
  tar

WORKDIR /var/lib/postgresql/netdisco-sql
RUN curl -s https://api.github.com/repos/netdisco/netdisco/tags | \
  jq '.[]|.name|select(test("^\\d+\\.\\d+$"))|"https://api.github.com/repos/netdisco/netdisco/tarball/"+.' | \
  sort -rg | head -n1 | xargs -n1 curl -sL | \
  tar --wildcards --strip-components=3 -zx '*App-Netdisco-DB-*' && \
  curl -sLO "https://raw.githubusercontent.com/netdisco/upstream-sources/master/ieee/oui.sql" && \
  curl -sLO "https://raw.githubusercontent.com/netdisco/netdisco/master/lib/App/Netdisco/DB.pm"

RUN PGDATA=/var/lib/postgresql/netdisco-pgdata /usr/local/bin/docker-entrypoint.sh postgres --version

COPY netdisco-db-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/netdisco-db-entrypoint.sh

WORKDIR /
VOLUME /var/lib/postgresql/data
ENTRYPOINT ["/usr/local/bin/netdisco-db-entrypoint.sh"]
CMD ["postgres"]
