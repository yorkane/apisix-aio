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
sleep 3

# Clean up stale sockets
rm -f /usr/local/apisix/logs/stream_worker_events.sock /usr/local/apisix/logs/worker_events.sock

# Initialize APISIX
/usr/bin/apisix init
/usr/bin/apisix init_etcd

# Initialize default routes in background
/usr/local/apisix/init-routes.sh &

# Run openresty in foreground
exec /usr/local/openresty/bin/openresty -p /usr/local/apisix -g 'daemon off;'
