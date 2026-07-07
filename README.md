# xray-tunnel-reality

One-command Xray VLESS Reality installer using a 3x-ui style structure:

```text
public port -> tunnel inbound -> 127.0.0.1 local VLESS Reality Vision inbound
```

This is different from directly exposing VLESS Reality on the public port.

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh)
```

Default SNI is `www.tesla.com`. Use a custom SNI:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) --sni www.icloud.com
```

Use a custom public port:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) --port 56777 --sni www.icloud.com
```

Use a fixed UUID:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) --uuid YOUR-UUID --sni www.icloud.com
```

## Defaults

- Public tunnel port: `56777`
- Local Reality port: `4431`
- UUID: random
- Short ID: random
- SNI: `www.tesla.com` unless `--sni` is provided
- Service: `xray-tunnel-reality`
- Config: `/etc/xray-tunnel-reality/config.json`

## Relay Panel

After install, use the printed relay target in your panel:

```text
landing-ip:56777
```

The script prints a VLESS client link and the exact target after installation.

## Manage

```bash
systemctl status xray-tunnel-reality --no-pager
systemctl restart xray-tunnel-reality
journalctl -u xray-tunnel-reality -f
```

## Notes

- Do not commit passwords, SSH keys, panel secrets, or GitHub tokens.
- Re-running the script regenerates UUID/key/shortId unless you pass fixed values.
- If a port is already in use, stop the old service or use a different `--port`.