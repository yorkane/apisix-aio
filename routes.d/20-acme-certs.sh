#!/bin/sh
# =============================================================================
# 20-acme-certs.sh - ACME certificate access routes
# =============================================================================
# Provides authenticated access to certificate files:
#   /certs/*  - key-auth (for API/script access)
#   /certs/   - basic-auth (for browser directory listing)

# Certificate file access (token-based)
put_route "acme-certs" '{
  "uri": "/certs/*",
  "name": "acme-cert-files",
  "desc": "Access ACME certificate files via token (key-auth)",
  "plugins": {
    "key-auth": {}
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": { "127.0.0.1:60000": 1 }
  }
}'

# Certificate directory listing (browser-based)
put_route "acme-certs-dir" '{
  "uri": "/certs/",
  "name": "acme-cert-directory",
  "desc": "Browse ACME certificate directory via basic-auth (browser)",
  "plugins": {
    "basic-auth": {}
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": { "127.0.0.1:60000": 1 }
  }
}'
