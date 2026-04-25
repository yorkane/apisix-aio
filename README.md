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
| `DASHBOARD_ADMIN_PASSWORD` | Dashboard 登录密码 | `admin@890.COM` |
| `REDIS_PASSWORD` | Redis 密码 | `apisix_redis` |
| `REDIS_EXTERNAL_HOST` | 外部 Redis 地址（设置后跳过内置 Redis） | - |
| `REDIS_EXTERNAL_PORT` | 外部 Redis 端口 | `6379` |
| `Ali_Key` | 阿里云 DNS API Key（ACME 证书） | - |
| `Ali_Secret` | 阿里云 DNS API Secret（ACME 证书） | - |

> **重要**：所有密钥都通过 `.env` 文件管理，容器启动时自动注入到配置文件中。

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

| 端口 | 服务 |
|------|------|
| 80 | APISIX HTTP 代理 |
| 443 | APISIX HTTPS 代理 |
| 9000 | APISIX Dashboard |
| 60000 | 内置静态文件服务 |

## 默认路由

APISIX 首次启动时自动创建以下路由和 Consumer：

| 路由 | 认证方式 | 说明 |
|------|----------|------|
| `/` | 无 | 默认欢迎页面 |
| `/certs/*` | key-auth (Token) | 获取证书/密钥文件 |
| `/certs/` | basic-auth | 浏览器浏览证书目录 |

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

## 架构说明

```
.env                    # 密钥配置（git 忽略）
apisix_config.yml       # APISIX 配置模板（容器内通过 entrypoint.sh 替换密钥）
dashboard_conf.yml      # Dashboard 配置模板（docker-compose 启动时 sed 替换）
entrypoint.sh           # APISIX 容器入口脚本
init-routes.sh          # 默认路由初始化脚本
acme/
  deploy-cert.sh        # 证书部署脚本（调用 Admin API）
  certs/                # ACME 生成的证书文件（挂载到 APISIX /html/certs）
```
