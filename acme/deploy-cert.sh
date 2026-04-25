#!/bin/sh
# deploy-cert.sh - Deploy certificates to APISIX Admin API and copy to shared certs directory
# Called by acme.sh --reloadcmd / --renew-hook on certificate issue/renewal
#
# Usage: deploy-cert.sh <domain> <cert_file> <key_file> <fullchain_file> [sni1 sni2 ...]
# If no SNIs are provided, they are derived from the domain and ACME_DOMAINS env var.

DOMAIN="$1"
CERT_FILE="$2"
KEY_FILE="$3"
FULLCHAIN_FILE="$4"
shift 4

ADMIN_KEY="${APISIX_ADMIN_KEY:-ffffc9f034335f136f87ad84b625dddd}"
CERTS_DIR="/acme.sh/certs"

echo "[deploy-cert] Deploying certificate for domain: ${DOMAIN}"

# --- Copy cert files to shared certs directory ---
if [ -n "$FULLCHAIN_FILE" ] && [ -f "$FULLCHAIN_FILE" ]; then
  cp "$FULLCHAIN_FILE" "${CERTS_DIR}/fullchain_${DOMAIN}.cer"
  echo "[deploy-cert] Copied fullchain to ${CERTS_DIR}/fullchain_${DOMAIN}.cer"
fi
if [ -f "$CERT_FILE" ]; then
  cp "$CERT_FILE" "${CERTS_DIR}/${DOMAIN}.cer"
fi
if [ -f "$KEY_FILE" ]; then
  cp "$KEY_FILE" "${CERTS_DIR}/${DOMAIN}.key"
  chmod 644 "${CERTS_DIR}/${DOMAIN}.key"
fi

# --- Build SNIs list ---
# If extra arguments are provided, use them as SNIs
# Otherwise, build from ACME_DOMAINS env var matching this domain group
if [ $# -gt 0 ]; then
  SNIS="$*"
else
  # Extract SNIs: use the primary domain and its wildcard
  SNIS="${DOMAIN} *.${DOMAIN}"
fi

# Build JSON array of SNIs
snis_json="["
for sni in $SNIS; do
  snis_json="${snis_json}\"${sni}\","
done
snis_json=$(echo "$snis_json" | sed 's/,$/]/')
if [ "$snis_json" = "[" ]; then snis_json="[]"; fi

# --- Read certificate content ---
CERT_CONTENT=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' "$FULLCHAIN_FILE" 2>/dev/null || awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' "$CERT_FILE")
KEY_CONTENT=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' "$KEY_FILE")

# --- Generate a stable SSL ID from the domain name ---
SSL_ID=$(echo "$DOMAIN" | sed 's/[^a-zA-Z0-9]/-/g')

# --- Deploy to APISIX Admin API ---
echo "[deploy-cert] Deploying SSL '${SSL_ID}' to APISIX with SNIs: ${snis_json}"
RESULT=$(curl -s -w "\n%{http_code}" http://apisix:9180/apisix/admin/ssls/${SSL_ID} \
  -H "X-API-KEY: ${ADMIN_KEY}" \
  -H 'Content-Type: application/json' \
  -X PUT -d "
{
  \"snis\": $snis_json,
  \"cert\": \"$CERT_CONTENT\",
  \"key\": \"$KEY_CONTENT\"
}")

HTTP_CODE=$(echo "$RESULT" | tail -1)
BODY=$(echo "$RESULT" | sed '$d')

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo "[deploy-cert] Certificate deployed successfully (HTTP ${HTTP_CODE})"
else
  echo "[deploy-cert] WARNING: Deploy returned HTTP ${HTTP_CODE}"
  echo "[deploy-cert] Response: ${BODY}"
fi
