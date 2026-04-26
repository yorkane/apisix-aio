#!/bin/sh
# =============================================================================
# 30-domain-proxy.sh - Domain-based proxy routes for Dashboard & Admin API
# =============================================================================
# Requires: APISIX_ROOT_DOMAIN (set in .env)
#
# Creates routes:
#   admin1.{ROOT_DOMAIN}     -> apisix-dashboard:9000 (Dashboard UI)
#   admin-api.{ROOT_DOMAIN}  -> 127.0.0.1:9180        (Admin API, basic-auth)
#
# This allows accessing Dashboard and Admin API through standard 80/443 ports
# without exposing 9000/9180 directly.

if [ -z "$ROOT_DOMAIN" ]; then
  log "APISIX_ROOT_DOMAIN not set, skipping domain-based proxy routes."
  return 0 2>/dev/null || true
fi

DASHBOARD_HOST="admin1.${ROOT_DOMAIN}"
ADMIN_API_HOST="admin-api.${ROOT_DOMAIN}"

log "Root domain: ${ROOT_DOMAIN}"
log "  Dashboard:  ${DASHBOARD_HOST}"
log "  Admin API:  ${ADMIN_API_HOST}"

# Dashboard UI proxy
put_route "dashboard-proxy" "{
  \"uri\": \"/*\",
  \"name\": \"dashboard-proxy\",
  \"desc\": \"Proxy APISIX Dashboard via domain ${DASHBOARD_HOST}\",
  \"host\": \"${DASHBOARD_HOST}\",
  \"plugins\": {
    \"proxy-rewrite\": {
      \"host\": \"apisix-dashboard:9000\"
    }
  },
  \"upstream\": {
    \"type\": \"roundrobin\",
    \"nodes\": { \"apisix-dashboard:9000\": 1 }
  }
}"

# Admin API proxy (protected by basic-auth, auto-injects X-API-KEY)
put_route "admin-api-proxy" "{
  \"uri\": \"/*\",
  \"name\": \"admin-api-proxy\",
  \"desc\": \"Proxy APISIX Admin API via domain ${ADMIN_API_HOST}\",
  \"host\": \"${ADMIN_API_HOST}\",
  \"plugins\": {
    \"basic-auth\": {},
    \"proxy-rewrite\": {
      \"headers\": {
        \"set\": {
          \"X-API-KEY\": \"${ADMIN_KEY}\"
        }
      }
    }
  },
  \"upstream\": {
    \"type\": \"roundrobin\",
    \"nodes\": { \"127.0.0.1:9180\": 1 }
  }
}"
