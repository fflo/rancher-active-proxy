# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Build stage: rancher-gen (in-tree, see ./rancher-gen) and forego
# ---------------------------------------------------------------------------
ARG GO_IMAGE=golang:1.25-alpine
ARG NGINX_IMAGE=nginx:1.30-alpine
ARG FOREGO_VERSION=v0.18.8

FROM ${GO_IMAGE} AS build
ARG FOREGO_VERSION
ARG VERSION=dev
ARG GIT_SHA=unknown
ENV CGO_ENABLED=0 GOFLAGS=-mod=readonly

WORKDIR /src/rancher-gen
COPY rancher-gen/go.mod rancher-gen/go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY rancher-gen/ ./
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go build -trimpath \
      -ldflags "-s -w -X 'main.Version=RAP Edition ${VERSION}' -X 'main.GitSHA=${GIT_SHA}'" \
      -o /out/rancher-gen . \
    && /out/rancher-gen --version

# forego is the tiny Procfile runner that supervises nginx, rancher-gen and crond.
# Built from a pinned, checksum-verified module instead of a loose GitHub download.
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    GOBIN=/out go install -trimpath -ldflags "-s -w" github.com/nginx-proxy/forego@${FOREGO_VERSION}

# ---------------------------------------------------------------------------
# Runtime stage
# ---------------------------------------------------------------------------
FROM ${NGINX_IMAGE}
ARG VERSION=dev
ARG GIT_SHA=unknown

LABEL org.opencontainers.image.title="rancher-active-proxy" \
      org.opencontainers.image.description="nginx reverse proxy with automatic Let's Encrypt certificates for Rancher v1" \
      org.opencontainers.image.source="https://github.com/fflo/rancher-active-proxy" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.licenses="MIT"

ENV DEBUG=false \
    RAP_DEBUG=info \
    CRON="0 2 * * *" \
    DEFAULT_PORT=80

# bash: scripts; certbot: ACME client; openssl: default cert / DH params; flock: job lock;
# ca-certificates: TLS to the ACME server; tzdata: honour TZ in cron and logs.
RUN apk add --no-cache bash certbot openssl ca-certificates tzdata flock

COPY --from=build /out/rancher-gen /out/forego /usr/local/bin/
COPY app/ /app/
WORKDIR /app

RUN chmod 0755 /app/entrypoint.sh /app/letsencrypt.sh /app/renew.sh /app/remove \
    && mkdir -p /etc/nginx/certs /etc/nginx/vhost.d /etc/nginx/conf.d /etc/nginx/htpasswd \
                /usr/share/nginx/html /etc/letsencrypt \
    && rm -f /etc/nginx/conf.d/default.conf \
    # RFC 7919 named group instead of a slow, home-grown DSA-param DH group
    && openssl genpkey -genparam -algorithm DH -pkeyopt group:ffdhe2048 -out /app/ffdhe2048.pem \
    && echo "daemon off;" >> /etc/nginx/nginx.conf \
    && sed -i 's/^http {/&\n    server_names_hash_bucket_size 128;\n    server_tokens off;/' /etc/nginx/nginx.conf \
    && nginx -t

VOLUME ["/etc/letsencrypt", "/etc/nginx/vhost.d", "/etc/nginx/htpasswd"]
EXPOSE 80 443

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD nginx -t >/dev/null 2>&1 && pgrep -x rancher-gen >/dev/null || exit 1

ENTRYPOINT ["/bin/bash", "/app/entrypoint.sh"]
CMD ["forego", "start", "-r"]
