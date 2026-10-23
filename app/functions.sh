#!/bin/bash
# Shared helpers for the rancher-active-proxy scripts. Sourced, not executed.

: "${VHOST_DIR:=/etc/nginx/vhost.d}"
: "${CERT_DIR:=/etc/nginx/certs}"
: "${LE_DIR:=/etc/letsencrypt}"
: "${WEBROOT:=/usr/share/nginx/html}"
: "${LE_CONF:=/app/letsencrypt.conf}"
: "${LE_LOCK:=/run/rap-letsencrypt.lock}"
START_HEADER='## Start of configuration add by letsencrypt container'
END_HEADER='## End of configuration add by letsencrypt container'

log() { printf '%s rap: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
err() { log "ERROR: $*" >&2; }

# ---------------------------------------------------------------------------
# Input validation. Everything in letsencrypt.conf originates from container
# labels, so treat it as untrusted even though rancher-gen validates too.
# ---------------------------------------------------------------------------
is_hostname() {
    local h="$1"
    [[ ${#h} -le 253 ]] || return 1
    [[ $h =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]]
}

is_email() {
    local e="$1"
    [[ ${#e} -le 254 ]] || return 1
    [[ $e =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

# A safe file-name component: no slashes, no dot-dot, no shell metacharacters.
is_safe_name() {
    [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$ && $1 != *..* ]]
}

lc() { printf '%s' "${*,,}"; }

# ---------------------------------------------------------------------------
# ACME challenge location inside a vhost.d include (kept for compatibility
# with existing vhost.d files; the generated redirect server block carries
# its own copy).
# ---------------------------------------------------------------------------
add_location_configuration() {
    local domain="${1:-}"
    [[ -z "$domain" || ! -f "${VHOST_DIR}/${domain}" ]] && domain=default
    if [[ -f "${VHOST_DIR}/${domain}" ]] && grep -qF -- "$START_HEADER" "${VHOST_DIR}/${domain}"; then
        return 0
    fi
    {
        echo "$START_HEADER"
        cat /app/nginx_location.conf
        echo "$END_HEADER"
        [[ -f "${VHOST_DIR}/${domain}" ]] && cat "${VHOST_DIR}/${domain}"
    } > "${VHOST_DIR}/${domain}.new"
    mv -f "${VHOST_DIR}/${domain}.new" "${VHOST_DIR}/${domain}"
    return 1
}

remove_all_location_configurations() {
    local file
    shopt -s nullglob
    for file in "${VHOST_DIR}"/*; do
        grep -qF -- "$START_HEADER" "$file" && sed -i "/$START_HEADER/,/$END_HEADER/d" "$file"
    done
    shopt -u nullglob
}

# ---------------------------------------------------------------------------
# Certificates
# ---------------------------------------------------------------------------

# setup_certs DOMAIN CERTNAME: point nginx at the certbot lineage CERTNAME for DOMAIN.
setup_certs() {
    local dom="${1:-}" certname="${2:-}"
    if ! is_safe_name "$dom" || ! is_safe_name "$certname"; then
        err "setup_certs: refusing unsafe name '$dom'/'$certname'"
        return 1
    fi
    if [[ -e "${LE_DIR}/live/${certname}/privkey.pem" && -e "${LE_DIR}/live/${certname}/fullchain.pem" ]]; then
        ln -sf "${LE_DIR}/live/${certname}/privkey.pem"   "${CERT_DIR}/${dom}.key"
        ln -sf "${LE_DIR}/live/${certname}/fullchain.pem" "${CERT_DIR}/${dom}.crt"
        ln -sf "${LE_DIR}/dhparam.pem"                    "${CERT_DIR}/${dom}.dhparam.pem"
    fi
}

# Install RFC 7919 ffdhe2048 parameters unless the operator already provides a file.
ensure_dhparam() {
    if [[ ! -s "${LE_DIR}/dhparam.pem" ]]; then
        log "Installing RFC 7919 ffdhe2048 Diffie-Hellman parameters"
        cp /app/ffdhe2048.pem "${LE_DIR}/dhparam.pem"
    fi
}

# A self-signed certificate for the catch-all server, so a request for an
# unknown host (or a plain IP) never gets answered with a tenant's certificate.
ensure_default_cert() {
    local d="${LE_DIR}/rap-default"
    # An operator-provided default.crt/default.key in /etc/nginx/certs always wins.
    if [[ -e "${CERT_DIR}/default.crt" && ! -L "${CERT_DIR}/default.crt" ]]; then
        return 0
    fi
    if [[ ! -s "$d/default.crt" || ! -s "$d/default.key" ]]; then
        log "Generating self-signed certificate for the catch-all server"
        mkdir -p "$d"
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
            -days 3650 -subj "/CN=rancher-active-proxy default" \
            -keyout "$d/default.key" -out "$d/default.crt" >/dev/null 2>&1 \
            || { err "could not generate default certificate"; rm -f "$d/default.crt" "$d/default.key"; return 1; }
        chmod 0600 "$d/default.key"
    fi
    ln -sf "$d/default.crt" "${CERT_DIR}/default.crt"
    ln -sf "$d/default.key" "${CERT_DIR}/default.key"
    ln -sf "${LE_DIR}/dhparam.pem" "${CERT_DIR}/default.dhparam.pem"
}

# Read letsencrypt.conf and call: CALLBACK id email test dom1 [dom2 ...]
# for every valid record. Invalid records are logged and skipped.
each_le_record() {
    local callback="$1" id hosts email test dom
    [[ -s "$LE_CONF" ]] || return 0
    while IFS=$'\t' read -r id hosts email test _; do
        [[ -z "$id" || "$id" == \#* ]] && continue
        local -a doms=()
        local raw
        IFS=';' read -ra raw <<< "$hosts"
        for dom in "${raw[@]}"; do
            dom="$(lc "${dom//[[:space:]]/}")"
            [[ -z "$dom" ]] && continue
            if is_hostname "$dom"; then
                doms+=("$dom")
            else
                err "ignoring invalid rap.le_host entry '$dom' (record $id)"
            fi
        done
        [[ ${#doms[@]} -eq 0 ]] && continue
        if ! is_email "$email"; then
            err "no valid e-mail for ${doms[0]}: set rap.le_email on the service or DEFAULT_EMAIL on the proxy"
            continue
        fi
        "$callback" "$id" "$email" "$(lc "$test")" "${doms[@]}"
    done < "$LE_CONF"
}

# Re-create the nginx symlinks for every certbot lineage already present in the
# /etc/letsencrypt volume, one link per subjectAltName, so existing certificates
# are served immediately after a restart (before the metadata has been polled).
relink_existing_lineages() {
    local conf certname crt dom
    shopt -s nullglob
    for conf in "${LE_DIR}"/renewal/*.conf; do
        certname="$(basename "$conf" .conf)"
        is_safe_name "$certname" || continue
        crt="${LE_DIR}/live/${certname}/fullchain.pem"
        [[ -r "$crt" ]] || continue
        while read -r dom; do
            [[ -n "$dom" && $dom != \** ]] && is_hostname "$dom" && setup_certs "$dom" "$certname"
        done < <(openssl x509 -in "$crt" -noout -ext subjectAltName 2>/dev/null | grep -o 'DNS:[^,[:space:]]*' | cut -d: -f2)
    done
    shopt -u nullglob
}

# ---------------------------------------------------------------------------
# nginx
# ---------------------------------------------------------------------------
reload_nginx() {
    # Delete file to avoid looping problem, then regenerate it and reload nginx if it validates.
    rm -f /etc/nginx/conf.d/default.conf
    rancher-gen --onetime --log-level "${RAP_DEBUG:-info}" \
        --check-cmd="nginx -t" --notify-cmd="nginx -s reload" \
        /app/nginx.tmpl /etc/nginx/conf.d/default.conf
}
