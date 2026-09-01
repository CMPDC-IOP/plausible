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
- `scripts/release.sh` 构建并部署 `plausible:<version>`，默认使用本地基础镜像和依赖镜像；`--pull` 才检查并拉取更新，但不清空构建缓存。
- `scripts/release.sh restart [service ...]` 只重启服务，不构建、不拉取；不指定服务名时重启全部。
- `compose.yml` 的顶层项目名固定为 `plausible`，用于复用现有的 `plausible_*` 容器和数据卷，不得随目录名修改。
- Compose 的构建上下文是当前目录 `.`，Dockerfile 固定为 `Dockerfile`。
- `.env.production` 位于项目根目录，已被 `.gitignore` 和 `.dockerignore` 排除。
- 脚本不显式注入 HTTP/HTTPS/ALL_PROXY。Node 和 Alpine 通过 Docker daemon 的镜像配置拉取；Elixir 基础镜像使用 `dockerproxy.net`；Docker 构建使用 BuildKit 默认网络和 DNS。
- Tailwind 文件在主机下载到 `build-assets/tailwind-linux-x64-musl`（Git 忽略），可使用主机已有代理。Dockerfile 只复制本地文件并校验 SHA256；升级 Tailwind 时同时更新文件与校验值，不向 Docker 传递代理认证。
- 原生库下载使用 Docker 的 `/root/.cache` 构建缓存，依赖编译失败最多尝试三次。GitHub Release 文件仍走 HTTPS；缓存缺失或依赖版本变化时仍需直连下载，SSH 不能替代 Release 下载。
- 构建复用 `priv/geodb/dbip-country.mmdb.gz`（Git 忽略），不再自动下载地理数据库。首次构建前从已有部署恢复或放入可信数据文件；缺失或 gzip 校验失败时停止发布。更新地理数据时替换此文件再构建。

只检查配置（脚本语法 + Compose 插值校验）而不发布时可运行：

```bash
./scripts/release.sh check
```

完整发布成功标准是镜像构建完成、数据库健康检查通过，并且 `docker compose up -d --remove-orphans` 成功。

## 本地部署定制

- 站点部署在 `/plausible` base path 下；不要新增绕过 `PlausibleWeb.URL` 或 Endpoint base-path 处理的根绝对链接。
- 浏览器只通过本地 endpoint 加载站点 favicon；后端解析页面声明的图标并缓存结果。私网主机必须显式加入 `FAVICON_TRUSTED_HOSTS`，不要在浏览器端重试外部路径，也不要重新引入手工 `?v=N` 缓存版本。
- 用户头像在本地生成，不依赖 Gravatar 或外部代理。
