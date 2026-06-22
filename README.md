# Codex macOS Proxy Launcher

[English](README.md) | [Simplified Chinese](README.zh-CN.md)

`codex-proxy` is a small macOS launcher for Codex. It stops the currently
running Codex app, relaunches `/Applications/Codex.app` with local V2Ray/Xray
proxy settings, and then exits.

The launcher is useful when system proxy settings do not cover every Codex
background process, such as remote connections, `codex app-server`, Node child
processes, or Chromium NetworkService.

## Features

- Relaunches Codex with proxy environment variables injected at startup.
- Does not stay resident after Codex has been opened successfully.
- Covers both Codex Node background services and the Electron/Chromium network
  layer.
- Uses the local `/Applications/Codex.app` icon and installs as
  `codex-proxy.app`.
- Defaults to the local V2Ray/Xray mixed inbound at `127.0.0.1:10808`.

## Proxy Port

The default proxy endpoint is `127.0.0.1:10808`. This is commonly used by
V2Ray/Xray clients as a mixed inbound that accepts both HTTP CONNECT and SOCKS5
traffic on the same port.

The launcher sets HTTP(S) and SOCKS variables:

- `HTTP_PROXY`
- `HTTPS_PROXY`
- `ALL_PROXY`
- `SOCKS_PROXY`
- lowercase variants
- `npm_config_proxy`
- `npm_config_https_proxy`

`HTTPS_PROXY` is set to `http://127.0.0.1:10808` intentionally. The `http://`
scheme describes how the client talks to the local proxy; HTTPS traffic still
uses an HTTP CONNECT tunnel through that proxy.

`ALL_PROXY` and `SOCKS_PROXY` are set to `socks5://127.0.0.1:10808` for
services that prefer SOCKS5 proxy variables.

The launcher also passes Chromium proxy arguments to Codex:

```text
--proxy-server=http=127.0.0.1:10808;https=127.0.0.1:10808;socks=socks5://127.0.0.1:10808
--proxy-bypass-list=localhost;127.0.0.1;::1
```

`localhost`, `127.0.0.1`, and `::1` are bypassed so Codex local services are not
sent through the proxy.

## Usage

Open the installed launcher:

```text
/Applications/codex-proxy.app
```

It immediately restarts Codex. This is intentional because proxy environment
variables and Chromium launch arguments must be inherited by the new Codex
process.

## Build

```bash
./script/build_and_run.sh --build-only
```

The app is created at:

```text
dist/codex-proxy.app
```

## Install

```bash
./script/build_and_run.sh --install
```

Install location:

```text
/Applications/codex-proxy.app
```

Opening the app restarts Codex and then exits.

## Verify

Check that Codex was launched with the proxy argument:

```bash
ps ax -o pid=,args= | rg '/Applications/Codex.app/Contents/MacOS/Codex'
```

The output should include `--proxy-server=...10808...`.

You can also check whether Codex child processes are connected to V2Ray/Xray:

```bash
lsof -nP -iTCP@127.0.0.1:10808
```

## License

MIT License. See [LICENSE](LICENSE).
