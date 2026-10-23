# syntax=docker/dockerfile:1

ARG GO_IMAGE=golang:1.25-alpine
ARG NGINX_IMAGE=nginx:1.30-alpine
ARG FOREGO_VERSION=v0.18.8
# Web application firewall: libmodsecurity v3, its nginx connector and the OWASP Core Rule Set.
ARG MODSEC_VERSION=3.0.17
ARG MODSEC_NGINX_VERSION=1.0.4
ARG CRS_VERSION=4.30.0

# ---------------------------------------------------------------------------
# Stage 1: rancher-gen (in-tree, see ./rancher-gen) and forego
# ---------------------------------------------------------------------------
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
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    GOBIN=/out go install -trimpath -ldflags "-s -w" github.com/nginx-proxy/forego@${FOREGO_VERSION}

# ---------------------------------------------------------------------------
# Stage 2: ModSecurity v3 + nginx connector, compiled against the exact nginx
# version of the runtime image (same recipe as the OWASP CRS container image).
# ---------------------------------------------------------------------------
FROM ${NGINX_IMAGE} AS waf
ARG MODSEC_VERSION
ARG MODSEC_NGINX_VERSION
ARG CRS_VERSION

RUN apk add --no-cache \
        autoconf automake ca-certificates coreutils curl curl-dev g++ gcc git gnupg \
        libc-dev libfuzzy2-dev libmaxminddb-dev libstdc++ libtool libxml2-dev \
        linux-headers lmdb-dev make openssl openssl-dev pkgconfig pcre2-dev yajl-dev zlib-dev

WORKDIR /sources

# libmodsecurity
RUN set -eux; \
    git clone https://github.com/owasp-modsecurity/ModSecurity --branch "v${MODSEC_VERSION}" --depth 1 --recursive; \
    cd ModSecurity; \
    ARCH=$(gcc -print-multiarch); \
    sed -ie "s/i386-linux-gnu/${ARCH}/g" build/msc_find_lib.m4; \
    ./build.sh; \
    ./configure --with-yajl --with-ssdeep --with-lmdb --with-pcre2 --with-maxmind --enable-silent-rules; \
    make -j"$(nproc)" install; \
    strip /usr/local/modsecurity/lib/lib*.so*; \
    cp unicode.mapping /sources/unicode.mapping

# nginx connector as a dynamic module. --with-compat makes it binary compatible
# with the nginx.org build used by the runtime image. The sed is the known
# GCC 14 workaround for the connector's configure test.
RUN set -eux; \
    git clone -b "v${MODSEC_NGINX_VERSION}" --depth 1 https://github.com/owasp-modsecurity/ModSecurity-nginx.git; \
    sed -iE "s/ngx_feature_test='printf(\"hello\");'/ngx_feature_test='msc_init();'/" ModSecurity-nginx/config; \
    curl -sSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -o nginx.tar.gz; \
    tar -xzf nginx.tar.gz; \
    cd "nginx-${NGINX_VERSION}"; \
    ./configure --with-compat --add-dynamic-module=../ModSecurity-nginx; \
    make -j"$(nproc)" modules; \
    strip objs/ngx_http_modsecurity_module.so; \
    cp objs/ngx_http_modsecurity_module.so /sources/

# OWASP Core Rule Set, signature-verified release tarball
RUN set -eux; \
    mkdir -p /sources/owasp-crs; \
    curl -sSL "https://github.com/coreruleset/coreruleset/releases/download/v${CRS_VERSION}/coreruleset-${CRS_VERSION}-minimal.tar.gz" -o crs.tar.gz; \
    curl -sSL "https://github.com/coreruleset/coreruleset/releases/download/v${CRS_VERSION}/coreruleset-${CRS_VERSION}-minimal.tar.gz.asc" -o crs.tar.gz.asc; \
    gpg --fetch-key https://coreruleset.org/security.asc; \
    gpg --verify crs.tar.gz.asc crs.tar.gz; \
    tar -zxf crs.tar.gz --strip-components=1 -C /sources/owasp-crs; \
    mv /sources/owasp-crs/crs-setup.conf.example /sources/owasp-crs/crs-setup.conf

# ---------------------------------------------------------------------------
# Stage 3: runtime
# ---------------------------------------------------------------------------
FROM ${NGINX_IMAGE}
ARG VERSION=dev
ARG GIT_SHA=unknown
ARG MODSEC_VERSION
ARG CRS_VERSION

LABEL org.opencontainers.image.title="rancher-active-proxy" \
      org.opencontainers.image.description="nginx reverse proxy with Let's Encrypt, rate limiting and ModSecurity/OWASP CRS for Rancher v1" \
      org.opencontainers.image.source="https://github.com/fflo/rancher-active-proxy" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.licenses="MIT"

ENV DEBUG=false \
    RAP_DEBUG=info \
    CRON="0 2 * * *" \
    DEFAULT_PORT=80 \
    RATE_LIMIT=30r/s \
    RATE_BURST=60 \
    CONN_LIMIT=100 \
    WAF=detect \
    WAF_PARANOIA=1 \
    WAF_ANOMALY_INBOUND=5 \
    WAF_ANOMALY_OUTBOUND=4 \
    SECURITY_HEADERS=on \
    CRS_VERSION=${CRS_VERSION}

# bash: scripts; certbot: ACME client; openssl: default cert; flock: job lock;
# tzdata: honour TZ; the rest are libmodsecurity's runtime libraries.
RUN apk upgrade --no-cache \
    && apk add --no-cache bash certbot openssl ca-certificates tzdata flock \
        libcurl libfuzzy2 libmaxminddb libstdc++ libxml2 lmdb pcre2 yajl

COPY --from=build /out/rancher-gen /out/forego /usr/local/bin/
COPY --from=waf /usr/local/modsecurity/lib/libmodsecurity.so.${MODSEC_VERSION} /usr/local/lib/
COPY --from=waf /sources/ngx_http_modsecurity_module.so /etc/nginx/modules/
COPY --from=waf /sources/unicode.mapping /etc/modsecurity.d/unicode.mapping
COPY --from=waf /sources/owasp-crs /etc/modsecurity.d/owasp-crs
COPY app/ /app/
WORKDIR /app

RUN set -eux; \
    chmod 0755 /app/entrypoint.sh /app/letsencrypt.sh /app/renew.sh /app/remove; \
    mkdir -p /etc/nginx/certs /etc/nginx/vhost.d /etc/nginx/conf.d /etc/nginx/htpasswd \
             /usr/share/nginx/html /etc/letsencrypt /tmp/modsecurity/tmp /tmp/modsecurity/data /tmp/modsecurity/upload; \
    chown -R nginx:nginx /tmp/modsecurity; \
    rm -f /etc/nginx/conf.d/default.conf; \
    cp /app/modsec/modsecurity.conf /etc/modsecurity.d/modsecurity.conf; \
    cp /app/nginx_security.conf /etc/nginx/conf.d/00-security.conf; \
    # musl searches /usr/local/lib by default, so no LD_LIBRARY_PATH is needed
    ln -s libmodsecurity.so.${MODSEC_VERSION} /usr/local/lib/libmodsecurity.so.3; \
    ln -s libmodsecurity.so.${MODSEC_VERSION} /usr/local/lib/libmodsecurity.so; \
    # RFC 7919 named group instead of a slow, home-grown DH group
    openssl genpkey -genparam -algorithm DH -pkeyopt group:ffdhe2048 -out /app/ffdhe2048.pem; \
    sed -i '1i load_module modules/ngx_http_modsecurity_module.so;' /etc/nginx/nginx.conf; \
    sed -i 's/worker_connections  1024;/worker_connections  4096;/' /etc/nginx/nginx.conf; \
    sed -i 's/^http {/&\n    server_names_hash_bucket_size 128;\n    server_tokens off;/' /etc/nginx/nginx.conf; \
    echo "daemon off;" >> /etc/nginx/nginx.conf; \
    nginx -t

VOLUME ["/etc/letsencrypt", "/etc/nginx/vhost.d", "/etc/nginx/htpasswd"]
EXPOSE 80 443

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD pgrep -x nginx >/dev/null && pgrep -x rancher-gen >/dev/null || exit 1

ENTRYPOINT ["/bin/bash", "/app/entrypoint.sh"]
CMD ["forego", "start", "-r"]
