# vim: ft=Dockerfile
FROM docker.io/alpine:3.7

ARG TAG
ENV TAG ${TAG:-2.000000}

RUN apk add --no-cache \
  curl

RUN curl -u "$GHTOKID:$GHTOKVAL" \
  --data '{"tag_name": "$TAG", "target_commitish": "og-import-irasnyd"}' \
  "https://api.github.com/repos/netdisco/netdisco-docker/releases"

CMD ["sh"]
