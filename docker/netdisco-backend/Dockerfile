# vim: ft=Dockerfile
FROM netdisco-base:latest

RUN mkdir $NETDISCO_HOME/netdisco-mibs && cd $NETDISCO_HOME/netdisco-mibs && \
  curl -s https://api.github.com/repos/netdisco/netdisco-mibs/tags | \
  jq '.[]|.tarball_url|select(test("tarball/\\d+\\.\\d+$"))' | \
  sort -rg | head -n1 | xargs -n1 curl -L | tar --strip-components=1 -zxf -

CMD bash
