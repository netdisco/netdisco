# vim: ft=Dockerfile
FROM debian:stable-slim

RUN bash -c 'mkdir -p /usr/share/man/man{1..8}' && \
    apt-get -yq update && \
    apt-get install -yq --no-install-recommends \
      build-essential \
      ca-certificates \
      cpanminus \
      curl \
      daemontools-run \
      git \
      jq \
      libdbd-pg-perl \
      libio-socket-ssl-perl \
      libnet-ldap-perl \
      libsnmp-perl \
      libssl-dev \
      postgresql-client && \
    apt-get clean &&  \
    rm -rf /var/lib/apt/lists/*

ENV NETDISCO_HOME "/home/netdisco"
RUN groupadd -r netdisco -g 901 && \
    useradd -u 901 -r -p x -g netdisco -m -d $NETDISCO_HOME -s /bin/bash -c "netdisco user" netdisco
USER netdisco:netdisco

RUN curl -s https://api.github.com/repos/netdisco/netdisco/tags | \
  jq '.[]|.name|select(test("^\\d+\\.\\d+$"))|"https://github.com/netdisco/netdisco.git@"+.' | \
  sort -rg | head -n1 | \
  PERL5LIB='.' xargs -n1 cpanm --quiet --notest --local-lib $NETDISCO_HOME/perl5

RUN mkdir $NETDISCO_HOME/bin && \
  bash -c 'ln -sf $NETDISCO_HOME/perl5/bin/{localenv,netdisco-*} $NETDISCO_HOME/bin/'
ENV PATH $NETDISCO_HOME/bin:$PATH
ENV SHELL "/bin/bash"

WORKDIR $NETDISCO_HOME
CMD bash
