#!/bin/sh
# acme-init.sh - Initialize ACME certificates based on ACME_DOMAINS env var
# This script is the entrypoint for the acme container.
# It issues certificates for configured domains and sets up auto-renewal with deploy hooks.
#
# ACME_DOMAINS format: "domain1.com,*.domain1.com; domain2.com,*.domain2.com"
#   - Semicolon separates domain groups (each group = one certificate)
#   - Comma separates domains within a group (first = primary, rest = SANs)
#
# Example: ACME_DOMAINS="c.gatepro.cn,*.c.gatepro.cn,v.gatepro.cn,*.v.gatepro.cn"
#   This issues ONE certificate covering all 4 domains.
#
# Example: ACME_DOMAINS="c.gatepro.cn,*.c.gatepro.cn; v.gatepro.cn,*.v.gatepro.cn"
#   This issues TWO separate certificates.

set -e

ACME_HOME="/acmebin"
ACME_CONFIG="/acme.sh"
CERTS_DIR="${ACME_CONFIG}/certs"
DEPLOY_SCRIPT="${ACME_CONFIG}/deploy-cert.sh"
DNS_PROVIDER="${ACME_DNS_PROVIDER:-dns_ali}"

# Ensure certs directory exists
mkdir -p "$CERTS_DIR"
chmod +x "$DEPLOY_SCRIPT" 2>/dev/null || true

if [ -z "$ACME_DOMAINS" ]; then
  echo "[acme-init] ACME_DOMAINS not set, skipping certificate issuance."
  echo "[acme-init] Starting acme.sh daemon for existing certificate renewals..."
  exec "${ACME_HOME}/acme.sh" --cron --home "$ACME_HOME" --config-home "$ACME_CONFIG"
  # Keep running for cron renewals
  exec crond -f
fi

echo "[acme-init] Processing domain groups from ACME_DOMAINS..."
echo "[acme-init] DNS Provider: ${DNS_PROVIDER}"

# Process each domain group (separated by semicolons)
echo "$ACME_DOMAINS" | tr ';' '\n' | while IFS= read -r group; do
  # Trim whitespace
  group=$(echo "$group" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -z "$group" ] && continue

  # Parse domains (comma-separated)
  PRIMARY=""
  DOMAIN_ARGS=""
  ALL_DOMAINS=""

  echo "$group" | tr ',' '\n' | while IFS= read -r domain; do
    domain=$(echo "$domain" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$domain" ] && continue
    echo "$domain"
  done | {
    first=true
    while IFS= read -r domain; do
      if $first; then
        PRIMARY="$domain"
        DOMAIN_ARGS="-d ${domain}"
        ALL_DOMAINS="${domain}"
        first=false
      else
        DOMAIN_ARGS="${DOMAIN_ARGS} -d ${domain}"
        ALL_DOMAINS="${ALL_DOMAINS} ${domain}"
      fi
    done

    if [ -z "$PRIMARY" ]; then
      return
    fi

    echo "[acme-init] === Domain Group: ${PRIMARY} ==="
    echo "[acme-init] All domains: ${ALL_DOMAINS}"

    # Build the deploy/reload command
    # deploy-cert.sh <domain> <cert> <key> <fullchain> [sni1 sni2 ...]
    CERT_PATH="${ACME_CONFIG}/${PRIMARY}_ecc/${PRIMARY}.cer"
    KEY_PATH="${ACME_CONFIG}/${PRIMARY}_ecc/${PRIMARY}.key"
    FULLCHAIN_PATH="${ACME_CONFIG}/${PRIMARY}_ecc/fullchain.cer"

    RELOAD_CMD="sh ${DEPLOY_SCRIPT} ${PRIMARY} ${CERT_PATH} ${KEY_PATH} ${FULLCHAIN_PATH} ${ALL_DOMAINS}"

    # Check if certificate already exists
    if [ -f "$CERT_PATH" ]; then
      echo "[acme-init] Certificate already exists for ${PRIMARY}, installing with deploy hook..."
      "${ACME_HOME}/acme.sh" --home "$ACME_HOME" --config-home "$ACME_CONFIG" \
        --install-cert ${DOMAIN_ARGS} \
        --cert-file "${CERTS_DIR}/${PRIMARY}.cer" \
        --key-file "${CERTS_DIR}/${PRIMARY}.key" \
        --fullchain-file "${CERTS_DIR}/fullchain_${PRIMARY}.cer" \
        --reloadcmd "${RELOAD_CMD}" \
        || echo "[acme-init] install-cert failed for ${PRIMARY}, will retry on renewal"

      # Also run deploy now
      echo "[acme-init] Running initial deploy for ${PRIMARY}..."
      sh "$DEPLOY_SCRIPT" "$PRIMARY" "$CERT_PATH" "$KEY_PATH" "$FULLCHAIN_PATH" $ALL_DOMAINS \
        || echo "[acme-init] Initial deploy failed for ${PRIMARY} (APISIX may not be ready yet)"
    else
      echo "[acme-init] Issuing new certificate for ${PRIMARY}..."
      "${ACME_HOME}/acme.sh" --home "$ACME_HOME" --config-home "$ACME_CONFIG" \
        --issue ${DOMAIN_ARGS} --dns "$DNS_PROVIDER" --keylength ec-256 \
        || { echo "[acme-init] ERROR: Failed to issue certificate for ${PRIMARY}"; return; }

      echo "[acme-init] Installing certificate for ${PRIMARY}..."
      "${ACME_HOME}/acme.sh" --home "$ACME_HOME" --config-home "$ACME_CONFIG" \
        --install-cert ${DOMAIN_ARGS} \
        --cert-file "${CERTS_DIR}/${PRIMARY}.cer" \
        --key-file "${CERTS_DIR}/${PRIMARY}.key" \
        --fullchain-file "${CERTS_DIR}/fullchain_${PRIMARY}.cer" \
        --reloadcmd "${RELOAD_CMD}"

      # Fix key file permissions
      chmod 644 "${CERTS_DIR}/${PRIMARY}.key" 2>/dev/null || true

      # Deploy to APISIX
      echo "[acme-init] Deploying certificate to APISIX for ${PRIMARY}..."
      sh "$DEPLOY_SCRIPT" "$PRIMARY" "$CERT_PATH" "$KEY_PATH" "$FULLCHAIN_PATH" $ALL_DOMAINS \
        || echo "[acme-init] Deploy failed for ${PRIMARY} (APISIX may not be ready yet)"
    fi

    echo "[acme-init] === Done: ${PRIMARY} ==="
  }
done

echo "[acme-init] Certificate initialization complete."
echo "[acme-init] Starting acme.sh daemon for auto-renewal..."

# Start crond for auto-renewal (acme.sh daemon mode)
exec crond -f
