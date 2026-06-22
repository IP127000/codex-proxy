# Codex macOS 代理启动器

[English](README.md) | [简体中文](README.zh-CN.md)

`codex-proxy` 是一个很小的 macOS 启动器。它启动后会停止当前 Codex，并用本机 V2Ray/Xray 代理重新打开 `/Applications/Codex.app`，设置完成后自动退出。

它主要解决 Codex 在只开启系统代理时仍可能有部分后台服务不走代理的问题，例如远程连接、`codex app-server`、Node 子进程、Chromium NetworkService 等。

## 特点

- 一键重启 Codex，并在启动时注入代理环境。
- 启动器本身不会常驻；成功打开 Codex 后自动退出。
- 同时覆盖 Codex 的 Node 后台服务和 Electron/Chromium 网络层。
- 使用本机 `/Applications/Codex.app` 的图标，安装后显示为 `codex-proxy.app`。
- 默认面向 V2Ray/Xray 的本机 mixed inbound 端口 `127.0.0.1:10808`。

## 端口说明

默认端口是 `127.0.0.1:10808`。这个端口通常是 V2Ray/Xray 客户端的 mixed 入口，可以在同一个端口上同时接受 HTTP CONNECT 和 SOCKS5。

因此启动器会同时设置 HTTP(S) 和 SOCKS5：

- `HTTP_PROXY`
- `HTTPS_PROXY`
- `ALL_PROXY`
- `SOCKS_PROXY`
- 对应的小写变量
- `npm_config_proxy`
- `npm_config_https_proxy`

注意：`HTTPS_PROXY` 的值是 `http://127.0.0.1:10808`，这是正常的。这里的 `http://` 表示“连接到本地代理所使用的协议”，不是目标网站的协议；HTTPS 请求会通过 HTTP CONNECT 隧道走这个 mixed 端口。

`ALL_PROXY` 和 `SOCKS_PROXY` 使用 `socks5://127.0.0.1:10808`，用于支持优先读取 SOCKS5 代理变量的后台服务。

启动器也会给 Codex 传入 Chromium 参数：

```text
--proxy-server=http=127.0.0.1:10808;https=127.0.0.1:10808;socks=socks5://127.0.0.1:10808
--proxy-bypass-list=localhost;127.0.0.1;::1
```

`localhost`、`127.0.0.1` 和 `::1` 会被绕过，避免 Codex 内部本地服务被错误送进代理。

## 使用

安装后直接打开：

```text
/Applications/codex-proxy.app
```

它会立刻重启 Codex。这个行为是设计如此，因为只有重新启动 Codex，代理环境变量和 Chromium 启动参数才会被新进程继承。

## 构建

```bash
./script/build_and_run.sh --build-only
```

构建完成后，应用会在：

```text
dist/codex-proxy.app
```

## 安装

```bash
./script/build_and_run.sh --install
```

安装位置：

```text
/Applications/codex-proxy.app
```

直接打开这个 app 会重启 Codex，然后自动退出。

## 验证

可以用下面的命令确认 Codex 是否带着代理启动：

```bash
ps ax -o pid=,args= | rg '/Applications/Codex.app/Contents/MacOS/Codex'
```

应能看到 `--proxy-server=...10808...`。

也可以检查 Codex 子进程是否连接到了 V2Ray/Xray：

```bash
lsof -nP -iTCP@127.0.0.1:10808
```

## 许可证

本项目使用 MIT License，见 [LICENSE](LICENSE)。
