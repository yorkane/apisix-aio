#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Build Apache APISIX
#FROM apache/apisix:latest
FROM apache/apisix:3.11.0-debian

ARG ENABLE_PROXY=false
ARG ETCD_VERSION="v3.5.4"


WORKDIR /tmp
LABEL etcd_version="${ETCD_VERSION}"
USER root
COPY ./klib/ /usr/local/apisix/klib
# https://github.com/etcd-io/etcd/releases/download/v3.5.17/etcd-v3.5.17-linux-amd64.tar.gz

RUN echo https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz \
    && echo 'ls -lta "$@"' > /usr/bin/ll && chmod 755 /usr/bin/ll\
    && apt update && apt install -y curl \
    && curl -sL https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz -o etcd.tar.gz \
    && tar -zxvf etcd.tar.gz \
    && mv etcd-*/* /usr/bin/ \
    && rm -rf etcd* \
    && rm -rf /usr/local/openresty/openssl3/share/ /usr/local/openresty/openssl3/include/ /usr/local/openresty/pod/ \
    && chown apisix:apisix -R /usr/local/apisix/ \
    && echo Finished


WORKDIR /usr/local/apisix

ENV PATH=$PATH:/usr/local/openresty/luajit/bin:/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin

EXPOSE 9180 9080 9443 2379 2380

CMD ["sh", "-c", "(nohup etcd >/tmp/etcd.log 2>&1 &) && sleep 3  && rm -f /usr/local/apisix/logs/stream_worker_events.sock /usr/local/apisix/logs/worker_events.sock && /usr/bin/apisix init && /usr/bin/apisix init_etcd && /usr/local/openresty/bin/openresty -p /usr/local/apisix -g 'daemon off;'"]

STOPSIGNAL SIGQUIT


# docker run -it --rm --user 0  apache/apisix:3.11.0-debian bash
# docker run -it --rm --user 0  yorkane/apisix-aio:latest bash
# docker run -it --rm --user 0  yorkane/apisix-dashboard:latest  bash

# docker build  -t yorkane/apisix-aio:latest ./ -f Dockerfile --progress=plain

# docker run -d -p 19080:9080 -p 19091:9091 -p 12379:2379 -p 19000:9000  -v ./apisix_config.yaml:/usr/local/apisix/conf/config.yaml -v ./dashboard_conf.yaml:/usr/local/apisix-dashboard/conf/conf.yaml apisix-aio:1