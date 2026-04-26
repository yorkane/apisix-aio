#!/bin/sh
set -e

ADMIN_KEY="${APISIX_ADMIN_KEY:-ffffc9f034335f136f87ad84b625dddd}"
DEFAULT_KEY="ffffc9f034335f136f87ad84b625dddd"

# Copy config template to writable path and replace admin key
cp /usr/local/apisix/conf/config.yaml.tpl /usr/local/apisix/conf/config.yaml
if [ "$ADMIN_KEY" != "$DEFAULT_KEY" ]; then
  sed -i "s/${DEFAULT_KEY}/${ADMIN_KEY}/g" /usr/local/apisix/conf/config.yaml
fi

# Start etcd in background
nohup etcd >/tmp/etcd.log 2>&1 &

# Start built-in Redis (skip if external Redis is configured)
REDIS_PASS="${REDIS_PASSWORD:-apisix_redis}"
if [ -z "${REDIS_EXTERNAL_HOST}" ]; then
  echo "[entrypoint] Starting built-in Redis (127.0.0.1:6379, maxmemory 64mb)..."
  nohup redis-server \
    --bind 127.0.0.1 \
    --port 6379 \
    --requirepass "${REDIS_PASS}" \
    --maxmemory 64mb \
    --maxmemory-policy allkeys-lru \
    --save "" \
    --appendonly no \
    --loglevel warning \
    >/tmp/redis.log 2>&1 &
else
  echo "[entrypoint] External Redis configured (${REDIS_EXTERNAL_HOST}), skipping built-in Redis."
fi

sleep 3

# Clean up stale sockets
rm -f /usr/local/apisix/logs/stream_worker_events.sock /usr/local/apisix/logs/worker_events.sock

# Initialize APISIX
/usr/bin/apisix init
/usr/bin/apisix init_etcd

# Initialize default routes in background (force mode to sync with current env)
/usr/local/apisix/init-routes.sh --force &

# Run openresty in foreground
exec /usr/local/openresty/bin/openresty -p /usr/local/apisix -g 'daemon off;'
