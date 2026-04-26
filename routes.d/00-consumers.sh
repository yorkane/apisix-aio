#!/bin/sh
# =============================================================================
# 00-consumers.sh - Consumer definitions
# =============================================================================
# Creates consumers used by other routes for authentication.
# Consumers are always upserted (idempotent).

# Consumer: cert-token (key-auth for API/token access to cert files)
put_consumer "{
  \"username\": \"cert-token\",
  \"desc\": \"Token-based access for certificate files\",
  \"plugins\": {
    \"key-auth\": {
      \"key\": \"${ADMIN_KEY}\"
    }
  }
}"

# Consumer: cert-browser (basic-auth for browser access)
put_consumer "{
  \"username\": \"cert-browser\",
  \"desc\": \"Basic-auth access for certificate and admin browsing\",
  \"plugins\": {
    \"basic-auth\": {
      \"username\": \"admin\",
      \"password\": \"${ADMIN_PASSWORD}\"
    }
  }
}"
