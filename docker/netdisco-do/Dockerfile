# vim: ft=Dockerfile
ARG TAG=master
FROM docker.io/netdisco:${TAG}-base

VOLUME ["/home/netdisco/environments", "/home/netdisco/nd-site-local"]

USER netdisco:netdisco
WORKDIR $NETDISCO_HOME
ENTRYPOINT ["/home/netdisco/bin/netdisco-do"]
CMD [""]
