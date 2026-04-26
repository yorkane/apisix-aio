# apisix-aio

Apache APISIX All-in-One 部署方案，集成 etcd、ACME 证书管理和 Dashboard。

## 快速开始

```bash
# 1. 复制环境变量文件并修改
cp .env.example .env
# 编辑 .env 设置你的密钥

# 2. 启动服务
docker compose up -d
```

## 环境变量配置 (.env)

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `APISIX_ADMIN_KEY` | APISIX Admin API 密钥 | `ffffc9f034335f136f87ad84b625dddd` |
| `APISIX_ROOT_DOMAIN` | 根域名（启用 Dashboard/Admin API 域名路由） | - |
| `DASHBOARD_ADMIN_PASSWORD` | Dashboard 登录密码 | `admin@890.COM` |
| `ACME_DOMAINS` | ACME 证书域名（见下方说明） | - |
| `ACME_EMAIL` | ACME 账户邮箱（预注册加速 + 到期提醒） | - |
| `ACME_DNS_PROVIDER` | DNS 验证提供商 | `dns_ali` |
| `ACME_CA_SERVER` | CA 服务器 | `letsencrypt` |
| `Ali_Key` | 阿里云 DNS API Key | - |
| `Ali_Secret` | 阿里云 DNS API Secret | - |
| `REDIS_PASSWORD` | Redis 密码 | `apisix_redis` |
| `REDIS_EXTERNAL_HOST` | 外部 Redis 地址（设置后跳过内置 Redis） | - |

> **重要**：所有密钥都通过 `.env` 文件管理，容器启动时自动注入到配置文件中。

### ACME 证书自动管理

通过 `ACME_DOMAINS` 环境变量配置需要签发的域名。ACME 容器启动时会**自动检查必要的环境变量**：

- 如果 `ACME_DOMAINS` 未设置，容器会输出提示后**直接退出**（不启动 ACME 服务）
- 如果 DNS provider 对应的 API 密钥缺失（如 `Ali_Key`/`Ali_Secret`），容器同样**直接退出**
- 所有必要配置就绪后，才会签发证书并启动自动续期

> **提示**：这意味着在没有配置 ACME 相关密钥的环境中（如开发/测试），ACME 容器会自动跳过，不影响其他服务正常运行。

**支持的 DNS Provider 及其所需环境变量**：

| Provider | `ACME_DNS_PROVIDER` | 所需环境变量 |
|----------|---------------------|-------------|
| 阿里云 DNS | `dns_ali`（默认） | `Ali_Key`, `Ali_Secret` |
| Cloudflare | `dns_cf` | `CF_Token` 或 `CF_Key`+`CF_Email` |
| DNSPod | `dns_dp` | `DP_Id`, `DP_Key` |
| GoDaddy | `dns_gd` | `GD_Key`, `GD_Secret` |
| AWS Route53 | `dns_aws` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |
| 腾讯云 DNS | `dns_tencent` | `Tencent_SecretId`, `Tencent_SecretKey` |
| Hurricane Electric | `dns_he` | `HE_Username`, `HE_Password` |

**域名格式**：
- 逗号分隔同一证书的域名
- 分号分隔不同证书组

```bash
# 单证书覆盖所有域名
ACME_DOMAINS=c.gatepro.cn,*.c.gatepro.cn,v.gatepro.cn,*.v.gatepro.cn

# 两个独立证书
ACME_DOMAINS=c.gatepro.cn,*.c.gatepro.cn; v.gatepro.cn,*.v.gatepro.cn
```

### Redis

AIO 容器内置 Redis（127.0.0.1:6379，最大内存 64MB），不对外暴露端口。APISIX 插件使用示例：

```json
{
  "limit-count": {
    "count": 100,
    "time_window": 60,
    "policy": "redis",
    "redis_host": "127.0.0.1",
    "redis_port": 6379,
    "redis_password": "<REDIS_PASSWORD>"
  }
}
```

如需使用外部 Redis，在 `.env` 中设置 `REDIS_EXTERNAL_HOST`，内置 Redis 将自动跳过启动：

```bash
REDIS_EXTERNAL_HOST=your-redis-host
REDIS_EXTERNAL_PORT=6379
```

## 服务端口

| 端口 | 服务 | 说明 |
|------|------|------|
| 80 | APISIX HTTP 代理 | 必需 |
| 443 | APISIX HTTPS 代理 | 必需 |
| 9000 | APISIX Dashboard | 设置 `APISIX_ROOT_DOMAIN` 后可移除 |
| 9180 | APISIX Admin API | 设置 `APISIX_ROOT_DOMAIN` 后可移除 |
| 60000 | 内置静态文件服务 | 内部使用 |

> **提示**：配置 `APISIX_ROOT_DOMAIN` 后，Dashboard 和 Admin API 通过域名路由访问，无需暴露 9000/9180 端口。

## 默认路由

APISIX 首次启动时自动创建以下路由和 Consumer：

| 路由 | 认证方式 | 说明 |
|------|----------|------|
| `/` | 无 | 默认欢迎页面 |
| `/certs/*` | key-auth (Token) | 获取证书/密钥文件 |
| `/certs/` | basic-auth | 浏览器浏览证书目录 |

### 域名路由（需设置 `APISIX_ROOT_DOMAIN`）

当配置了 `APISIX_ROOT_DOMAIN`（如 `v.gatepro.cn`）时，自动创建以下域名路由：

| 域名 | 后端服务 | 认证方式 | 说明 |
|------|----------|----------|------|
| `admin1.{ROOT_DOMAIN}` | `apisix-dashboard:9000` | Dashboard 自身认证 | APISIX Dashboard 管理界面 |
| `admin-api.{ROOT_DOMAIN}` | `127.0.0.1:9180` | basic-auth | APISIX Admin API |

### Consumer

| Consumer | 认证插件 | 凭证 |
|----------|----------|------|
| `cert-token` | key-auth | apikey = `APISIX_ADMIN_KEY` |
| `cert-browser` | basic-auth | admin / `DASHBOARD_ADMIN_PASSWORD` |

### 访问 ACME 证书

**Token 方式**（适用于 API 调用、脚本）：

```bash
curl -H "apikey: <your_admin_key>" http://localhost/certs/v.gatepro.cn.cer
curl -H "apikey: <your_admin_key>" http://localhost/certs/v.gatepro.cn.key
```

**Basic Auth 方式**（适用于浏览器访问目录列表）：

```bash
# 浏览器访问 http://localhost/certs/ 会弹出认证对话框
# 用户名: admin  密码: <DASHBOARD_ADMIN_PASSWORD>
curl -u admin:<password> http://localhost/certs/
```

也可以通过端口 60000 直接访问静态文件（需要暴露该端口）：

```bash
curl http://localhost:60000/certs/v.gatepro.cn.cer
```

## 路由管理

路由定义采用模块化架构，所有路由定义文件存放在 `routes.d/` 目录下，按文件名顺序自动加载。

### 文件结构

```
routes.d/
  00-consumers.sh       # Consumer 定义（cert-token, cert-browser）
  10-default.sh         # 默认欢迎页面路由 /
  20-acme-certs.sh      # ACME 证书访问路由 /certs/*
  30-domain-proxy.sh    # 域名代理路由（Dashboard, Admin API）
```

### 运行模式

```bash
# 容器内手动执行（一般模式：跳过已存在的路由）
docker exec apisix /usr/local/apisix/init-routes.sh

# 容器内手动执行（强制模式：创建或更新所有路由）
docker exec apisix /usr/local/apisix/init-routes.sh --force
```

> **提示**：APISIX 每次启动时自动以 `--force` 模式执行，确保路由与当前环境变量保持同步。

### 添加自定义路由

在 `routes.d/` 目录下创建新的 `.sh` 文件，使用 `put_route` 函数即可：

```bash
#!/bin/sh
# routes.d/40-my-service.sh - 自定义服务路由

put_route "my-service" '{
  "uri": "/api/*",
  "name": "my-service",
  "host": "api.example.com",
  "upstream": {
    "type": "roundrobin",
    "nodes": { "my-backend:8080": 1 }
  }
}'
```

可用的 helper 函数：
- `put_route <route_id> <json>` - 创建/更新路由
- `put_consumer <json>` - 创建/更新 Consumer
- `route_exists <route_id>` - 检查路由是否存在
- `log <message>` - 带前缀日志输出

## 架构说明

```
.env                    # 密钥配置（git 忽略）
apisix_config.yml       # APISIX 配置模板（容器内通过 entrypoint.sh 替换密钥）
dashboard_conf.yml      # Dashboard 配置模板（docker-compose 启动时 sed 替换）
entrypoint.sh           # APISIX 容器入口脚本
init-routes.sh          # 路由初始化编排器（提供 helper 函数）
routes.d/               # 路由定义文件（按文件名顺序加载）
acme/
  acme-init.sh          # ACME 证书初始化脚本
  deploy-cert.sh        # 证书部署脚本（调用 Admin API）
  certs/                # ACME 生成的证书文件（挂载到 APISIX /html/certs）
```
