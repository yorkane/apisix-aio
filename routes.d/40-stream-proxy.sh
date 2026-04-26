#!/bin/sh
# =============================================================================
# 40-stream-proxy.sh - Dynamic Stream (TCP/UDP) routes
# =============================================================================
# Manage stream routes via Admin API.
# Ports 60001-60009 are pre-allocated in apisix_config.yml for this purpose.

# TCP Proxy: Local 60001 -> 144.168.59.25:27777
put_stream_route "tcp-60001" '{
  "server_port": 60001,
  "upstream": {
    "type": "roundrobin",
    "nodes": { "144.168.59.25:27777": 1 }
  }
}'
