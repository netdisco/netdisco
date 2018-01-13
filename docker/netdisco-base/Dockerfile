# vim: ft=Dockerfile
ARG TAG=master
FROM debian:stable-slim as netdisco-build-image

RUN bash -c 'mkdir -p /usr/share/man/man{1..8}' && \
    apt-get -yq update && \
    apt-get install -yq --no-install-recommends \
      build-essential \
      ca-certificates \
      cpanminus \
      curl \
      git \
      jq \
      libdbd-pg-perl \
      libio-socket-ssl-perl \
      libnet-ldap-perl \
      libsnmp-perl \
      libssl-dev \
      postgresql-client

ENV HOME "/home/netdisco"
RUN groupadd -r netdisco -g 901 && \
    useradd -u 901 -r -p x -g netdisco -m -d $HOME -s /bin/bash -c "netdisco user" netdisco

USER netdisco:netdisco
RUN curl -sL https://api.github.com/repos/netdisco/netdisco/tags | \
  jq '.[]|.name|select(test("^\\d+\\.\\d+$"))|"https://github.com/netdisco/netdisco.git@"+.' | \
  sort -rg | head -n1 | \
  PERL5LIB='.' xargs -n1 cpanm --quiet --notest --local-lib "${HOME}/perl5"

RUN bash -c 'mkdir ${HOME}/{bin,environments,nd-site-local}'
RUN bash -c 'ln -sf ${HOME}/perl5/bin/{localenv,netdisco-*} ${HOME}/bin'

COPY deployment.yml "${HOME}/environments/"
COPY wait_to_start.sh "${HOME}/bin/"

FROM debian:stable-slim

LABEL org.netdisco.maintainer="The Netdisco Project"
LABEL org.netdisco.version=${TAG}

RUN bash -c 'mkdir -p /usr/share/man/man{1..8}' && \
    apt-get -yq update && \
    apt-get install -yq --no-install-recommends \
      ca-certificates \
      cpanminus \
      curl \
      jq \
      libdbd-pg-perl \
      libio-socket-ssl-perl \
      libnet-ldap-perl \
      libsnmp-perl \
      libssl-dev \
      postgresql-client && \
    apt-get clean &&  \
    rm -rf /var/lib/apt/lists/*

COPY --from=netdisco-build-image /etc/passwd /etc/group /etc/shadow /etc/
COPY --from=netdisco-build-image /home/netdisco /home/netdisco/
RUN chown -R netdisco:netdisco /home/netdisco

VOLUME ["/home/netdisco/environments", "/home/netdisco/nd-site-local"]

USER netdisco:netdisco
WORKDIR /home/netdisco
ENV PATH "/home/netdisco/bin:$PATH"
ENV SHELL /bin/bash

CMD ["bash"]
