# vim: ft=Dockerfile
ARG TAG=master
FROM docker.io/netdisco:${TAG}-base

VOLUME ["/home/netdisco/environments", "/home/netdisco/nd-site-local"]

USER netdisco:netdisco
WORKDIR $NETDISCO_HOME/netdisco-mibs
RUN curl -s https://api.github.com/repos/netdisco/netdisco-mibs/tags | \
  jq '.[]|.tarball_url|select(test("tarball/\\d+\\.\\d+$"))' | \
  sort -rg | head -n1 | xargs -n1 curl -L | tar --strip-components=1 -zxf -

WORKDIR $NETDISCO_HOME
ENTRYPOINT ["/home/netdisco/bin/netdisco-backend"]
CMD ["foreground"]
