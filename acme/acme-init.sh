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
#
# Required environment variables (checked at startup):
#   - ACME_DOMAINS: domains to issue certificates for
#   - DNS provider API keys (varies by provider, e.g. Ali_Key/Ali_Secret for dns_ali)
# If any required config is missing, the container exits gracefully without starting ACME.

set -e

ACME_HOME="/acmebin"
ACME_CONFIG="/acme.sh"
CERTS_DIR="${ACME_CONFIG}/certs"
DEPLOY_SCRIPT="${ACME_CONFIG}/deploy-cert.sh"
DNS_PROVIDER="${ACME_DNS_PROVIDER:-dns_ali}"
ACME_CA="${ACME_CA_SERVER:-letsencrypt}"

# ============================================================================
# Pre-flight check: validate required environment variables before starting
# ============================================================================

# Check ACME_DOMAINS
if [ -z "$ACME_DOMAINS" ]; then
  echo "[acme-init] ACME_DOMAINS is not set. ACME service will not start."
  echo "[acme-init] To enable ACME, set ACME_DOMAINS in your .env file."
  echo "[acme-init] Example: ACME_DOMAINS=example.com,*.example.com"
  exit 0
fi

# Check DNS provider API keys based on provider type
check_dns_keys() {
  MISSING=""
  case "$DNS_PROVIDER" in
    dns_ali)
      [ -z "$Ali_Key" ] && MISSING="${MISSING} Ali_Key"
      [ -z "$Ali_Secret" ] && MISSING="${MISSING} Ali_Secret"
      ;;
    dns_cf)
      # Cloudflare: either CF_Key+CF_Email or CF_Token
      if [ -z "$CF_Token" ]; then
        [ -z "$CF_Key" ] && MISSING="${MISSING} CF_Key(or CF_Token)"
        [ -z "$CF_Email" ] && MISSING="${MISSING} CF_Email(or CF_Token)"
      fi
      ;;
    dns_dp)
      # DNSPod
      [ -z "$DP_Id" ] && MISSING="${MISSING} DP_Id"
      [ -z "$DP_Key" ] && MISSING="${MISSING} DP_Key"
      ;;
    dns_he)
      # Hurricane Electric
      [ -z "$HE_Username" ] && MISSING="${MISSING} HE_Username"
      [ -z "$HE_Password" ] && MISSING="${MISSING} HE_Password"
      ;;
    dns_gd)
      # GoDaddy
      [ -z "$GD_Key" ] && MISSING="${MISSING} GD_Key"
      [ -z "$GD_Secret" ] && MISSING="${MISSING} GD_Secret"
      ;;
    dns_aws)
      # AWS Route53
      [ -z "$AWS_ACCESS_KEY_ID" ] && MISSING="${MISSING} AWS_ACCESS_KEY_ID"
      [ -z "$AWS_SECRET_ACCESS_KEY" ] && MISSING="${MISSING} AWS_SECRET_ACCESS_KEY"
      ;;
    dns_tencent)
      # Tencent Cloud
      [ -z "$Tencent_SecretId" ] && MISSING="${MISSING} Tencent_SecretId"
      [ -z "$Tencent_SecretKey" ] && MISSING="${MISSING} Tencent_SecretKey"
      ;;
    *)
      echo "[acme-init] WARNING: Unknown DNS provider '${DNS_PROVIDER}', skipping key validation."
      echo "[acme-init] If certificate issuance fails, please check your DNS API keys."
      return 0
      ;;
  esac

  if [ -n "$MISSING" ]; then
    echo "[acme-init] ERROR: Missing required DNS API keys for provider '${DNS_PROVIDER}':${MISSING}"
    echo "[acme-init] ACME service will not start. Please configure the keys in your .env file."
    exit 0
  fi

  echo "[acme-init] DNS provider '${DNS_PROVIDER}' API keys validated OK."
  return 0
}

check_dns_keys

# ============================================================================
# Initialization: setup CA, register account
# ============================================================================

# Ensure certs directory exists
mkdir -p "$CERTS_DIR"
chmod +x "$DEPLOY_SCRIPT" 2>/dev/null || true

# Set default CA server (avoid ZeroSSL registration requirement in clean environments)
echo "[acme-init] Setting default CA to: ${ACME_CA}"
"${ACME_HOME}/acme.sh" --home "$ACME_HOME" --config-home "$ACME_CONFIG" \
  --set-default-ca --server "$ACME_CA" 2>/dev/null || true

# Register account with email if provided (speeds up first-time issuance)
if [ -n "${ACME_EMAIL}" ]; then
  if ! grep -q "ACCOUNT_EMAIL" "${ACME_CONFIG}/account.conf" 2>/dev/null; then
    echo "[acme-init] Registering account with email: ${ACME_EMAIL}"
    "${ACME_HOME}/acme.sh" --home "$ACME_HOME" --config-home "$ACME_CONFIG" \
      --register-account -m "${ACME_EMAIL}" 2>/dev/null || true
  else
    echo "[acme-init] Account already registered."
  fi
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
      # Check certificate age (seconds since creation)
      CERT_AGE_DAYS=999
      CERT_CONF="${ACME_CONFIG}/${PRIMARY}_ecc/${PRIMARY}.conf"
      if [ -f "$CERT_CONF" ]; then
        CREATE_TIME=$(grep "Le_CertCreateTime=" "$CERT_CONF" | cut -d= -f2 | tr -d "'")
        if [ -n "$CREATE_TIME" ]; then
          NOW=$(date +%s)
          CERT_AGE_DAYS=$(( (NOW - CREATE_TIME) / 86400 ))
        fi
      fi

      echo "[acme-init] Certificate exists for ${PRIMARY} (age: ${CERT_AGE_DAYS} days)"

      if [ "$CERT_AGE_DAYS" -lt 60 ]; then
        # Cert is fresh (< 60 days), just deploy directly to APISIX
        echo "[acme-init] Certificate is still valid, deploying directly to APISIX..."
        # Copy cert files to shared directory
        cp "$CERT_PATH" "${CERTS_DIR}/${PRIMARY}.cer" 2>/dev/null || true
        cp "$KEY_PATH" "${CERTS_DIR}/${PRIMARY}.key" 2>/dev/null || true
        cp "$FULLCHAIN_PATH" "${CERTS_DIR}/fullchain_${PRIMARY}.cer" 2>/dev/null || true
        chmod 644 "${CERTS_DIR}/${PRIMARY}.key" 2>/dev/null || true
        # Deploy to APISIX
        sh "$DEPLOY_SCRIPT" "$PRIMARY" "$CERT_PATH" "$KEY_PATH" "$FULLCHAIN_PATH" $ALL_DOMAINS \
          || echo "[acme-init] Deploy failed for ${PRIMARY} (APISIX may not be ready yet)"
      else
        # Cert is old (>= 60 days), run install-cert to set up renewal hook
        echo "[acme-init] Certificate is aging, running install-cert with renewal hook..."
        "${ACME_HOME}/acme.sh" --home "$ACME_HOME" --config-home "$ACME_CONFIG" \
          --install-cert ${DOMAIN_ARGS} \
          --cert-file "${CERTS_DIR}/${PRIMARY}.cer" \
          --key-file "${CERTS_DIR}/${PRIMARY}.key" \
          --fullchain-file "${CERTS_DIR}/fullchain_${PRIMARY}.cer" \
          --reloadcmd "${RELOAD_CMD}" \
          || echo "[acme-init] install-cert failed for ${PRIMARY}, will retry on renewal"
        # Deploy to APISIX
        sh "$DEPLOY_SCRIPT" "$PRIMARY" "$CERT_PATH" "$KEY_PATH" "$FULLCHAIN_PATH" $ALL_DOMAINS \
          || echo "[acme-init] Deploy failed for ${PRIMARY} (APISIX may not be ready yet)"
      fi
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
