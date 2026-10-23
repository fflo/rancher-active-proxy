#!/bin/bash
# Issue (or expand) Let's Encrypt certificates for every rap.le_host listed in
# /app/letsencrypt.conf. Runs at start-up, whenever rancher-gen regenerates the
# host list, and after `certbot renew` from cron. Idempotent: certbot keeps
# certificates that are not due for renewal, so this never burns rate limits.
set -u
source /app/functions.sh

: "${LETSENCRYPT_DELAY:=10}"   # seconds to wait for nginx/Rancher routing to settle
ACME_PROD="https://acme-v02.api.letsencrypt.org/directory"
ACME_STAGING="https://acme-staging-v02.api.letsencrypt.org/directory"

[[ -s "$LE_CONF" ]] || exit 0

exec 9>"$LE_LOCK"
if ! flock -w 600 9; then
    err "another certificate job is still running, giving up"
    exit 1
fi

issue_cert() {
    local id="$1" email="$2" test="$3"; shift 3
    local -a doms=("$@") dargs=()
    local certname="${doms[0]}" server dom
    local -a extra=()

    [[ $test == true ]] && server="$ACME_STAGING" || server="$ACME_PROD"
    [[ ${DEBUG:-false} == true ]] && extra+=(-v)

    # Switching between staging and production: drop the old lineage so certbot
    # does not try to renew a staging certificate against production (or vice versa).
    local renewal_conf="${LE_DIR}/renewal/${certname}.conf"
    if [[ -f "$renewal_conf" ]]; then
        local current_server
        current_server="$(sed -n 's/^server *= *//p' "$renewal_conf" | head -n1)"
        if [[ -n "$current_server" && "$current_server" != "$server" ]]; then
            log "ACME server changed for $certname, discarding old certificate"
            certbot delete --non-interactive --cert-name "$certname" >/dev/null 2>&1 || true
            for dom in "${doms[@]}"; do rm -f "${CERT_DIR}/${dom}".{crt,key,dhparam.pem}; done
        fi
    fi

    for dom in "${doms[@]}"; do
        dargs+=(-d "$dom")
    done

    log "Creating/renewing certificate '$certname' (${doms[*]}) via $server"
    if certbot certonly --non-interactive --agree-tos --no-eff-email \
            --keep-until-expiring --expand \
            --cert-name "$certname" -m "$email" "${dargs[@]}" \
            --server "$server" --preferred-challenges http \
            --webroot -w "$WEBROOT" "${extra[@]}"; then
        for dom in "${doms[@]}"; do setup_certs "$dom" "$certname"; done
    else
        err "certbot failed for '$certname'; nginx keeps serving the previous certificate (if any)"
    fi
}

sleep "$LETSENCRYPT_DELAY"
# Make sure every vhost already serves /.well-known/acme-challenge/ before certbot runs.
reload_nginx
each_le_record issue_cert
reload_nginx
