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
# Legacy clean-up: older releases injected an ACME location block into the
# vhost.d includes. Every generated server block now carries its own, so the
# injected copy would be a duplicate `location` and must be removed.
# ---------------------------------------------------------------------------
remove_all_location_configurations() {
    local file
    shopt -s nullglob
    for file in "${VHOST_DIR}"/*; do
        [[ -f "$file" ]] || continue
        if grep -qF -- "$START_HEADER" "$file"; then
            log "removing legacy ACME location block from ${file}"
            sed -i "/$START_HEADER/,/$END_HEADER/d" "$file"
        fi
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
# Web application firewall (ModSecurity + OWASP CRS)
# ---------------------------------------------------------------------------
: "${MODSEC_DIR:=/etc/modsecurity.d}"

# Write the CRS tuning (paranoia level, anomaly thresholds) and the include
# list from the WAF_* environment variables. Called once at start-up.
configure_waf() {
    local waf="${WAF:-detect}" pl="${WAF_PARANOIA:-1}" in="${WAF_ANOMALY_INBOUND:-5}" out="${WAF_ANOMALY_OUTBOUND:-4}"
    case "$waf" in on|detect|off) ;; *) err "WAF='$waf' is not on/detect/off; using detect"; waf=detect ;; esac
    [[ $pl =~ ^[1-4]$ ]] || { err "WAF_PARANOIA='$pl' must be 1-4; using 1"; pl=1; }
    [[ $in =~ ^[0-9]{1,3}$ ]] || { err "WAF_ANOMALY_INBOUND='$in' must be numeric; using 5"; in=5; }
    [[ $out =~ ^[0-9]{1,3}$ ]] || { err "WAF_ANOMALY_OUTBOUND='$out' must be numeric; using 4"; out=4; }
    export WAF="$waf"
    if [[ $waf == off ]]; then
        log "WAF disabled (WAF=off)"
        return 0
    fi

    {
        echo "# Generated by rancher-active-proxy from WAF_PARANOIA / WAF_ANOMALY_* at start-up. Do not edit."
        echo "SecAction \"id:900000,phase:1,pass,t:none,nolog,setvar:tx.blocking_paranoia_level=${pl}\""
        echo "SecAction \"id:900110,phase:1,pass,t:none,nolog,setvar:tx.inbound_anomaly_score_threshold=${in},setvar:tx.outbound_anomaly_score_threshold=${out}\""
    } > "${MODSEC_DIR}/rap-crs.conf"
    {
        echo "# Generated by rancher-active-proxy at start-up. Do not edit."
        echo "Include ${MODSEC_DIR}/modsecurity.conf"
        echo "Include ${MODSEC_DIR}/owasp-crs/crs-setup.conf"
        echo "Include ${MODSEC_DIR}/rap-crs.conf"
        [[ -f "${VHOST_DIR}/default_modsec_before" ]] && echo "Include ${VHOST_DIR}/default_modsec_before"
        echo "Include ${MODSEC_DIR}/owasp-crs/rules/*.conf"
        [[ -f "${VHOST_DIR}/default_modsec" ]] && echo "Include ${VHOST_DIR}/default_modsec"
        true
    } > "${MODSEC_DIR}/setup.conf"
    log "WAF mode '${waf}', OWASP CRS ${CRS_VERSION:-?} paranoia level ${pl}, anomaly thresholds in=${in}/out=${out}"
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
