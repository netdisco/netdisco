# vim: ft=Dockerfile
ARG TAG=master
FROM docker.io/netdisco/netdisco:${TAG}-base

LABEL org.netdisco.maintainer="The Netdisco Project"
LABEL org.netdisco.version=${TAG}

EXPOSE 5000
VOLUME ["/home/netdisco/environments", "/home/netdisco/nd-site-local"]

USER netdisco:netdisco
WORKDIR $NETDISCO_HOME
ENTRYPOINT ["/home/netdisco/bin/netdisco-web"]
CMD ["foreground"]
