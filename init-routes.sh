#!/bin/sh
# Initialize default routes for APISIX
# This script runs in the background after APISIX starts

ADMIN_KEY="${APISIX_ADMIN_KEY:-ffffc9f034335f136f87ad84b625dddd}"
ADMIN_API="http://127.0.0.1:9180/apisix/admin"

# Wait for APISIX admin API to be ready
echo "[init-routes] Waiting for APISIX admin API..."
for i in $(seq 1 30); do
  if curl -s -o /dev/null -w "%{http_code}" "${ADMIN_API}/routes" -H "X-API-KEY: ${ADMIN_KEY}" | grep -q "200"; then
    echo "[init-routes] APISIX admin API is ready."
    break
  fi
  sleep 1
done

# --- Default welcome route ---
ROUTE_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
  "${ADMIN_API}/routes/default" \
  -H "X-API-KEY: ${ADMIN_KEY}")

if [ "$ROUTE_CHECK" != "200" ]; then
  echo "[init-routes] Creating default welcome route..."
  curl -s "${ADMIN_API}/routes/default" \
    -H "X-API-KEY: ${ADMIN_KEY}" \
    -H "Content-Type: application/json" \
    -X PUT -d '{
      "uri": "/",
      "name": "default-welcome",
      "desc": "Default welcome route - returns APISIX welcome page",
      "upstream": {
        "type": "roundrobin",
        "nodes": { "127.0.0.1:60000": 1 }
      }
    }'
  echo ""
  echo "[init-routes] Default welcome route created."
else
  echo "[init-routes] Default welcome route already exists, skipping."
fi

# --- ACME certificates route (protected by key-auth) ---
CERT_ROUTE_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
  "${ADMIN_API}/routes/acme-certs" \
  -H "X-API-KEY: ${ADMIN_KEY}")

if [ "$CERT_ROUTE_CHECK" != "200" ]; then
  echo "[init-routes] Creating ACME certificates route..."

  # First ensure key-auth consumer exists
  curl -s "${ADMIN_API}/consumers" \
    -H "X-API-KEY: ${ADMIN_KEY}" \
    -H "Content-Type: application/json" \
    -X PUT -d "{
      \"username\": \"cert-reader\",
      \"plugins\": {
        \"key-auth\": {
          \"key\": \"${ADMIN_KEY}\"
        }
      }
    }"
  echo ""

  # Create the certificate route with key-auth protection
  curl -s "${ADMIN_API}/routes/acme-certs" \
    -H "X-API-KEY: ${ADMIN_KEY}" \
    -H "Content-Type: application/json" \
    -X PUT -d '{
      "uri": "/certs/*",
      "name": "acme-certificates",
      "desc": "Expose ACME certificates and keys (protected by key-auth)",
      "plugins": {
        "key-auth": {}
      },
      "upstream": {
        "type": "roundrobin",
        "nodes": { "127.0.0.1:60000": 1 }
      }
    }'
  echo ""
  echo "[init-routes] ACME certificates route created."
else
  echo "[init-routes] ACME certificates route already exists, skipping."
fi

echo "[init-routes] Route initialization complete."
