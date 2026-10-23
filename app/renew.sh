#!/bin/bash
# Cron entry point: renew certificates that are due, then issue anything new.
set -u
source /app/functions.sh

log "Running scheduled certificate renewal"
certbot renew --non-interactive --quiet \
    --webroot -w "$WEBROOT" \
    --deploy-hook "nginx -s reload" \
    || err "certbot renew reported errors (see /var/log/letsencrypt/letsencrypt.log)"

# Picks up newly labelled hosts and re-creates nginx symlinks; safe to run often.
/app/letsencrypt.sh
