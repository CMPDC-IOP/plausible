# 本地站点路径与网关配置

站点标识在数据库、埋点数据、查询参数和请求体中保留原值，例如
`example.com/docs`。作为 URL 路径参数时，使用 `example.com~docs`。
现有站点校验不允许 `~`，因此该替换可逆。

- 后端 `~p` 路径插值使用 `PlausibleWeb.SitePath.encode/1`；
  `PlausibleWeb.VerifiedRoutes` 的 `stats_path` 等辅助函数在内部完成该编码。
- 手工拼接路径片段使用 `PlausibleWeb.SitePath.encode_segment/1`。
- 前端使用 `encodeSiteDomain` 或已有的 `sitePath`、`apiPath` 等封装。
- HTTP 请求匹配路由后，只解码路径中的 `domain`、`site_id` 参数。
  LiveView 的路由参数和 favicon 入口分别解码；外部网站链接不使用此编码。

网关仍负责剥离 `/plausible`，无需额外的 URI map：

```nginx
location /plausible/ {
    proxy_pass http://plausible/;
}
```

上线时先构建并发布支持新路径的应用，再检查和重载网关。新应用也能使用
旧网关配置，所以可以分两步切换。

旧 `%2F` 链接只有在代理保留其编码时才能继续解析。网关改为上述写法后，
请从站点列表重新获取链接，并更新保存的分享链接和调用路径。查询参数、
请求体中的站点标识以及分享链接的授权令牌不需要修改。
