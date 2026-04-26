#!/bin/sh
# =============================================================================
# 10-default.sh - Default welcome route
# =============================================================================
# Serves the default welcome page at /

put_route "default" '{
  "uri": "/",
  "name": "default-welcome",
  "status": 1,
  "desc": "Default welcome route - returns APISIX welcome page",
  "upstream": {
    "type": "roundrobin",
    "nodes": { "127.0.0.1:60000": 1 }
  }
}'
