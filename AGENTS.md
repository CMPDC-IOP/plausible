# Plausible Analytics 本地维护指南

## 仓库结构

- 当前目录是唯一的 Git 仓库，也是源码和部署配置的项目根目录。
- `origin` 指向 CMPDC-IOP 组织 fork，`upstream` 指向官方 `plausible/analytics`。

## 合并上游

在项目根目录中操作：

```bash
git fetch upstream
git rebase upstream/master
```

本地定制提交应保持在 `upstream/master` 之上。解决冲突时重点检查 `/plausible` base-path 路由、静态资源、LiveView 跳转和 Dockerfile 的本地构建适配。

## 构建与发布

所有命令均从项目根目录执行：

```bash
./scripts/release.sh
```

- `scripts/release.sh` 从当前仓库最高的 `v*` tag 生成镜像版本，并读取当前 HEAD 作为 revision。
- 脚本构建并部署 `plausible:<version>`，构建前检查基础镜像更新但不清空构建缓存。
- `compose.yml` 的顶层项目名固定为 `plausible`，用于复用现有的 `plausible_*` 容器和数据卷，不得随目录名修改。
- Compose 的构建上下文是当前目录 `.`，Dockerfile 固定为 `Dockerfile`。
- `.env.production` 位于项目根目录，已被 `.gitignore` 和 `.dockerignore` 排除。
- 脚本不显式注入 HTTP/HTTPS/ALL_PROXY。Node 和 Alpine 通过 Docker daemon 的镜像配置拉取；Elixir 基础镜像使用 `dockerproxy.net`；Docker 构建使用 BuildKit 默认网络和 DNS。

只检查配置（脚本语法 + Compose 插值校验）而不发布时可运行：

```bash
./scripts/release.sh check
```

完整发布成功标准是镜像构建完成、数据库健康检查通过，并且 `docker compose up -d --remove-orphans` 成功。

## 本地部署定制

- 站点部署在 `/plausible` base path 下；不要新增绕过 `PlausibleWeb.URL` 或 Endpoint base-path 处理的根绝对链接。
- 浏览器只通过本地 endpoint 加载站点 favicon；后端解析页面声明的图标并缓存结果。私网主机必须显式加入 `FAVICON_TRUSTED_HOSTS`，不要在浏览器端重试外部路径，也不要重新引入手工 `?v=N` 缓存版本。
- 用户头像在本地生成，不依赖 Gravatar 或外部代理。
