# Release Notes

## v1.0.0

`codex-proxy` 初始版本。

### 主要解决的问题

- 解决 Codex 只依赖 macOS 系统代理时，部分后台服务仍可能不走代理的问题。
- 覆盖 Codex 远程连接、`codex app-server`、Node 子进程、Electron/Chromium NetworkService 等场景。
- 通过重启 Codex，在进程启动阶段注入代理环境变量和 Chromium 启动参数。

### 代理行为

- 使用本机 mixed 代理端口 `127.0.0.1:10808`。
- 将 `HTTP_PROXY` 和 `HTTPS_PROXY` 设置为 `http://127.0.0.1:10808`。
- 将 `ALL_PROXY` 和 `SOCKS_PROXY` 设置为 `socks5://127.0.0.1:10808`。
- 同时设置小写代理变量和 npm 代理变量，照顾 Node 后台服务。
- 给 Chromium 传入：

```text
--proxy-server=http=127.0.0.1:10808;https=127.0.0.1:10808;socks=socks5://127.0.0.1:10808
--proxy-bypass-list=localhost;127.0.0.1;::1
```

### 端口特殊性

`10808` 端口预期是 V2Ray/Xray 的 mixed inbound，因此同一个端口可以同时支持 HTTP CONNECT 和 SOCKS5。启动器会同时配置 HTTP(S) 和 SOCKS5。

`HTTPS_PROXY=http://127.0.0.1:10808` 是有意这样写的：这里的 `http://` 指本机代理入口协议，HTTPS 流量会通过 HTTP CONNECT 隧道转发。

### 应用行为

- 应用名：`codex-proxy`。
- 打包时使用本机 Codex 图标。
- 成功启动 Codex 后自动退出，不常驻。
- 只有找不到 Codex 或启动失败时才弹窗提示。
