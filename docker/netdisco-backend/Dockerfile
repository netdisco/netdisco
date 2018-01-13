# vim: ft=Dockerfile
ARG TAG=master
FROM docker.io/netdisco/netdisco-base:${TAG}-base

LABEL org.netdisco.maintainer="The Netdisco Project"
LABEL org.netdisco.version=${TAG}

WORKDIR /home/netdisco/netdisco-mibs
RUN curl -sL https://api.github.com/repos/netdisco/netdisco-mibs/tags | \
  jq '.[]|.tarball_url|select(test("tarball/\\d+\\.\\d+$"))' | \
  sort -rg | head -n1 | xargs -n1 curl -sL | tar --strip-components=1 -zxf -

WORKDIR /home/netdisco
ENTRYPOINT ["/home/netdisco/bin/netdisco-backend"]
CMD ["foreground"]
