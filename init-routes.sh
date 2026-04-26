#!/bin/sh
# =============================================================================
# init-routes.sh - APISIX Route Initialization Orchestrator
# =============================================================================
# This script initializes default routes, consumers, and domain-based proxies.
# It sources all *.sh files from routes.d/ directory in alphabetical order.
#
# Usage:
#   ./init-routes.sh           # Normal mode: skip existing routes
#   ./init-routes.sh --force   # Force mode:  always create/update all routes
#
# Environment variables:
#   APISIX_ADMIN_KEY           - Admin API key (default: ffffc9f034335f136f87ad84b625dddd)
#   DASHBOARD_ADMIN_PASSWORD   - Dashboard password (default: admin)
#   APISIX_ROOT_DOMAIN         - Root domain for domain-based routing (optional)
# =============================================================================

set -e

# --- Configuration ---
ADMIN_KEY="${APISIX_ADMIN_KEY:-ffffc9f034335f136f87ad84b625dddd}"
ADMIN_PASSWORD="${DASHBOARD_ADMIN_PASSWORD:-admin}"
ADMIN_API="http://127.0.0.1:9180/apisix/admin"
ROOT_DOMAIN="${APISIX_ROOT_DOMAIN:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROUTES_DIR="${SCRIPT_DIR}/routes.d"

# --- Parse arguments ---
FORCE_MODE=false
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE_MODE=true ;;
  esac
done

# =============================================================================
# Helper Functions (available to all routes.d/*.sh scripts)
# =============================================================================

# Log with prefix
log() {
  echo "[init-routes] $*"
}

# Wait for APISIX Admin API to be ready (max 30s)
wait_admin() {
  log "Waiting for APISIX admin API..."
  for i in $(seq 1 30); do
    if curl -s -o /dev/null -w "%{http_code}" \
      "${ADMIN_API}/routes" -H "X-API-KEY: ${ADMIN_KEY}" 2>/dev/null | grep -q "200"; then
      log "APISIX admin API is ready."
      return 0
    fi
    sleep 1
  done
  log "ERROR: APISIX admin API not ready after 30s"
  return 1
}

# Check if a route exists. Returns 0 if exists, 1 if not.
route_exists() {
  local route_id="$1"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    "${ADMIN_API}/routes/${route_id}" \
    -H "X-API-KEY: ${ADMIN_KEY}" 2>/dev/null)
  [ "$code" = "200" ]
}

# PUT (upsert) a route. In normal mode, skips if route already exists.
# Usage: put_route <route_id> <json_body>
put_route() {
  local route_id="$1"
  local json="$2"

  if [ "$FORCE_MODE" = "false" ] && route_exists "$route_id"; then
    log "Route '${route_id}' already exists, skipping. (use --force to update)"
    return 0
  fi

  local action="Creating"
  route_exists "$route_id" && action="Updating"

  log "${action} route '${route_id}'..."
  local result
  result=$(curl -s -w "\n%{http_code}" \
    "${ADMIN_API}/routes/${route_id}" \
    -H "X-API-KEY: ${ADMIN_KEY}" \
    -H "Content-Type: application/json" \
    -X PUT -d "$json" 2>/dev/null)

  local http_code
  http_code=$(echo "$result" | tail -1)
  if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
    log "Route '${route_id}' OK (HTTP ${http_code})"
    # PATCH status=1 to ensure route is published (PUT ignores status field)
    curl -s -o /dev/null "${ADMIN_API}/routes/${route_id}" \
      -H "X-API-KEY: ${ADMIN_KEY}" \
      -H "Content-Type: application/json" \
      -X PATCH -d '{"status": 1}' 2>/dev/null
  else
    local body
    body=$(echo "$result" | sed '$d')
    log "WARNING: Route '${route_id}' returned HTTP ${http_code}: ${body}"
  fi
}

# PUT (upsert) a stream route. In normal mode, skips if route already exists.
# Usage: put_stream_route <route_id> <json_body>
put_stream_route() {
  local route_id="$1"
  local json="$2"

  local exists=false
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    "${ADMIN_API}/stream_routes/${route_id}" \
    -H "X-API-KEY: ${ADMIN_KEY}" 2>/dev/null)
  [ "$code" = "200" ] && exists=true

  if [ "$FORCE_MODE" = "false" ] && [ "$exists" = "true" ]; then
    log "Stream route '${route_id}' already exists, skipping. (use --force to update)"
    return 0
  fi

  local action="Creating"
  [ "$exists" = "true" ] && action="Updating"

  log "${action} stream route '${route_id}'..."
  local result
  result=$(curl -s -w "\n%{http_code}" \
    "${ADMIN_API}/stream_routes/${route_id}" \
    -H "X-API-KEY: ${ADMIN_KEY}" \
    -H "Content-Type: application/json" \
    -X PUT -d "$json" 2>/dev/null)

  local http_code
  http_code=$(echo "$result" | tail -1)
  if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
    log "Stream route '${route_id}' OK (HTTP ${http_code})"
  else
    local body
    body=$(echo "$result" | sed '$d')
    log "WARNING: Stream route '${route_id}' returned HTTP ${http_code}: ${body}"
  fi
}

# PUT (upsert) a consumer. Always upserts (consumers are idempotent).
# Usage: put_consumer <json_body>
put_consumer() {
  local json="$1"
  local username
  username=$(echo "$json" | grep -o '"username"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"username"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

  log "Upserting consumer '${username}'..."
  local result
  result=$(curl -s -w "\n%{http_code}" \
    "${ADMIN_API}/consumers" \
    -H "X-API-KEY: ${ADMIN_KEY}" \
    -H "Content-Type: application/json" \
    -X PUT -d "$json" 2>/dev/null)

  local http_code
  http_code=$(echo "$result" | tail -1)
  if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
    log "Consumer '${username}' OK (HTTP ${http_code})"
  else
    local body
    body=$(echo "$result" | sed '$d')
    log "WARNING: Consumer '${username}' returned HTTP ${http_code}: ${body}"
  fi
}

# =============================================================================
# Main
# =============================================================================

if [ "$FORCE_MODE" = "true" ]; then
  log "=== Force mode: all routes will be created/updated ==="
else
  log "=== Normal mode: existing routes will be skipped ==="
fi

# Wait for admin API
wait_admin || exit 1

# Source all route definition files in order
if [ -d "$ROUTES_DIR" ]; then
  for route_file in "${ROUTES_DIR}"/*.sh; do
    [ -f "$route_file" ] || continue
    log "--- Loading $(basename "$route_file") ---"
    . "$route_file"
  done
else
  log "WARNING: routes.d/ directory not found at ${ROUTES_DIR}"
fi

log "=== Route initialization complete ==="
