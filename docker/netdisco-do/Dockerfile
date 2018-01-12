# vim: ft=Dockerfile
FROM netdisco-base:latest

USER netdisco:netdisco
WORKDIR $NETDISCO_HOME
VOLUME ["/home/netdisco/environments", "/home/netdisco/nd-site-local"]
ENTRYPOINT ["/home/netdisco/bin/netdisco-do"]
CMD [""]
