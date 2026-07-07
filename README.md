# xray-tunnel-reality

Interactive one-command Xray installer with two modes:

1. VLESS Reality Vision using a 3x-ui style structure:

```text
public port -> tunnel inbound -> 127.0.0.1 local VLESS Reality Vision inbound
```

2. SOCKS5 inbound with username/password authentication.

## Interactive install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh)
```

The script will ask you to choose:

```text
1) VLESS Reality Vision
2) SOCKS5
```

## Non-interactive examples

Reality with defaults:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) --mode reality --yes
```

Reality with custom port and SNI:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) --mode reality --port 56778 --inner-port 4432 --sni www.tesla.com
```

SOCKS5:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) --mode socks5 --port 21109 --user nt --pass nt888888
```

## Defaults

Reality mode:

- Public tunnel port: `56777`
- Local Reality port: `4431`
- SNI: `www.tesla.com` unless `--sni` is provided
- UUID: random
- Short ID: random

SOCKS5 mode:

- Public port: `21109`
- Username/password: prompted or random with `--yes`
- UDP: `false`

Common:

- Service: `xray-tunnel-reality`
- Config: `/etc/xray-tunnel-reality/config.json`

## Relay Panel

After install, use the printed relay target in your panel:

```text
landing-ip:port
```

## Manage

```bash
systemctl status xray-tunnel-reality --no-pager
systemctl restart xray-tunnel-reality
journalctl -u xray-tunnel-reality -f
```

## Notes

- Do not commit passwords, SSH keys, panel secrets, or GitHub tokens.
- Re-running the script overwrites `/etc/xray-tunnel-reality/config.json`.
- If a port is already in use, stop the old service or use another `--port`.