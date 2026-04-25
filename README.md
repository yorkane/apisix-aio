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
| `Ali_Key` | 阿里云 DNS API Key（ACME 证书） | - |
| `Ali_Secret` | 阿里云 DNS API Secret（ACME 证书） | - |

> **重要**：所有密钥都通过 `.env` 文件管理，容器启动时自动注入到配置文件中。

## 服务端口

| 端口 | 服务 |
|------|------|
| 80 | APISIX HTTP 代理 |
| 443 | APISIX HTTPS 代理 |
| 9000 | APISIX Dashboard |
| 60000 | 内置静态文件服务 |

## 默认路由

APISIX 首次启动时自动创建以下路由：

- **`/`** — 默认欢迎页面（指向内置静态文件服务）
- **`/certs/*`** — ACME 证书文件（key-auth 保护）

### 访问 ACME 证书

证书路由受 `key-auth` 插件保护，需携带认证头：

```bash
curl -H "apikey: <your_admin_key>" http://localhost/certs/v.gatepro.cn.cer
curl -H "apikey: <your_admin_key>" http://localhost/certs/v.gatepro.cn.key
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
