# xray-tunnel-reality

One-command Xray installer with three modes:

1. VLESS Reality Vision using a 3x-ui style tunnel structure.
2. SOCKS5 inbound with username/password authentication.
3. Cloudflare preferred entry VLESS + WebSocket.

## 简体中文快速操作

### 直接安装

在落地机 root 里执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh)
```

然后按菜单选择：

```text
1) VLESS Reality Vision，推荐，中转端口用这个
2) SOCKS5
3) Cloudflare 优选 VLESS-WS
```

### Reality 推荐用法

默认直接选 `1` 就行：

```text
外层公网端口：自动随机高位端口，范围 20000-59999
内层 Reality 端口：默认 4431，建议不要改
SNI：默认 www.icloud.com，可自己填
节点名：自动生成 国家码+协议，例如 DE-VLESS+Reality
```

安装完成后脚本会打印客户端链接。中转面板里填脚本输出的：

```text
Relay target / Public listen: 落地IP:外层端口
```

例如脚本输出：

```text
Public listen: 107.173.237.81:34567
Relay target:  107.173.237.81:34567
```

中转面板就填：

```text
107.173.237.81:34567
```

客户端链接里的 IP/端口改成中转机 IP 和中转端口。

### 指定外层端口

默认外层端口是随机的。如果你想固定外层端口，例如 `56777`：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) \
  --mode reality \
  --port 56777 \
  --inner-port 4431
```

规则很简单：

```text
--port       外层公网端口，可以变
--inner-port 内层 Reality 端口，默认 4431，建议固定
```

### SOCKS5 安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) \
  --mode socks5 \
  --port 21109 \
  --user nt \
  --pass nt888888
```

### Cloudflare 优选 VLESS-WS

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) \
  --mode cf-ws \
  --port 31520 \
  --cf-domain hostdzire.212202.xyz \
  --cf-entry cf.3666888.xyz \
  --path /ws233
```

含义：

```text
--cf-domain  你的 Cloudflare 橙云域名，也是 WS Host/SNI
--cf-entry   客户端连接入口，可以是优选 IP、优选域名或你自己的优选入口域名
--path       WebSocket 路径
```

Cloudflare 里还要设置 Origin Rule，把访问 `--cf-domain` 的流量重写到你的源站端口，例如 `31520`。

### 常用检查命令

```bash
systemctl status xray-tunnel-reality --no-pager
systemctl restart xray-tunnel-reality
journalctl -u xray-tunnel-reality -f
ss -lntup | grep -E ':4431|xray'
```

### 注意事项

- Reality 中转优先用模式 `1`。
- `4431` 是本机内层端口，不需要填到中转面板。
- 中转面板只填外层公网端口。
- 重新运行脚本会覆盖 `/etc/xray-tunnel-reality/config.json`。
- 不要把 SSH 密码、Reality 私钥、GitHub token 发到公开页面。

## Why this Reality layout

Reality mode intentionally uses a two-layer 3x-ui style layout:

```text
public port -> tunnel inbound -> 127.0.0.1 local VLESS Reality Vision inbound
```

This is different from a single public Reality inbound:

```text
public port -> VLESS Reality
```

The two-layer layout is the default because it is easier to reproduce from a working 3x-ui node and is friendlier to relay panels that forward a public port to the landing server.

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh)
```

Interactive menu:

```text
1) VLESS Reality Vision (3x-ui tunnel structure)
2) SOCKS5
3) Cloudflare preferred entry VLESS-WS
```

## Reality examples

Install with defaults:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) --mode reality --yes
```

Install with custom SNI and a random public high port:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) \
  --mode reality \
  --inner-port 4431 \
  --sni www.icloud.com
```

The default Reality SNI is `www.icloud.com`. Override it with `--sni` only after testing that the target performs well on your relay path.

Port rule:

- Public tunnel port is random by default in the `20000-59999` range.
- Use `--port` when you want to specify the public tunnel port yourself.
- Local Reality port should normally stay `4431`. Change `--inner-port` only when `4431` is already in use.

Default node name is detected from the server country plus protocol, for example:

```text
DE-VLESS+Reality
US-SOCKS5
DE-VLESS+WS
```

Use `--name` to override the generated name.

Specify public port manually:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) \
  --mode reality \
  --port 56777 \
  --inner-port 4431
```

Do not paste SSH keys, passwords, panel secrets, or GitHub tokens into public issues, README files, or screenshots.

## Xray version

The script pins Xray to `v26.6.27` by default for repeatable installs:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) \
  --mode reality \
  --xray-version v26.6.27
```

Use the latest Xray release explicitly:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) \
  --mode reality \
  --latest-xray
```

Force reinstall the selected Xray version:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) \
  --mode reality \
  --force-xray-install
```

## SOCKS5 example

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) \
  --mode socks5 \
  --port 21109 \
  --user nt \
  --pass nt888888
```

## Cloudflare preferred entry VLESS-WS

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) \
  --mode cf-ws \
  --port 31520 \
  --cf-domain hostdzire.212202.xyz \
  --cf-entry cf.3666888.xyz \
  --path /ws233
```

`--cf-entry` is the client address. It can be a preferred IP, preferred domain, or your own domain pointed to a preferred Cloudflare IP.

`--cf-domain` is the Cloudflare proxied/orange-cloud domain used as WebSocket Host and SNI.

Cloudflare DNS:

```text
cf-domain.example.com  A  origin-server-ip  Proxied/orange-cloud
```

Cloudflare Origin Rule:

```text
If incoming request matches:
  http.host eq "cf-domain.example.com"

Then:
  Rewrite destination/origin port to your source port, for example 31520
```

Generated client URL:

```text
vless://UUID@CF_ENTRY:443?encryption=none&security=tls&type=ws&host=CF_DOMAIN&sni=CF_DOMAIN&path=%2Fws233#NAME
```

## Relay panel target

For Reality and SOCKS5, use the printed relay target:

```text
landing-ip:port
```

For Cloudflare VLESS-WS, clients connect through Cloudflare. Configure Cloudflare DNS and Origin Rule instead of a normal relay target.

## Manage service

```bash
systemctl status xray-tunnel-reality --no-pager
systemctl restart xray-tunnel-reality
journalctl -u xray-tunnel-reality -f
```

## Notes

- Re-running the script overwrites `/etc/xray-tunnel-reality/config.json`.
- If a port is already in use, stop the old service or use another `--port`.
- Use `--force` only when you are sure the old listener can be replaced.
- CF VLESS-WS origin is plain WS; TLS is provided at the Cloudflare edge.
