# xray-tunnel-reality

无面板 Xray 脚本管理器。目标是不用 3x-ui 这类 Web 面板，只通过脚本安装、查看、重启、卸载协议，减少暴露面。

支持：

1. VLESS Reality Vision，使用已验证的双层结构。
2. SOCKS5，随机端口、账号、密码。
3. Cloudflare 优选入口 VLESS-WS，可选。
4. VLESS Reality 和 SOCKS5 多协议共存。
5. 默认尝试开启 BBR + fq。

## 一键运行

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh)
```

第一次运行会进入菜单。安装后会创建快捷命令：

```bash
xrt
```

以后直接输入 `xrt` 就能管理。

## 菜单功能

```text
1) 添加 VLESS Reality
2) 添加 SOCKS5
3) 添加 Cloudflare VLESS-WS
4) 查看所有协议链接
5) 卸载指定协议
6) 重启服务
7) 查看状态
8) 查看日志
9) BBR 状态/开启
10) 完整卸载
0) 退出
```

## Reality 结构

Reality 默认结构：

```text
外层公网端口 -> tunnel inbound -> 127.0.0.1:4431 -> VLESS Reality
```

默认值：

```text
外层端口: 随机高位端口，范围 20000-59999
内层端口: 4431
SNI: www.icloud.com
节点名: 国家码+协议，例如 DE-VLESS+Reality
```

中转面板只填脚本输出的：

```text
中转填写: 落地IP:外层端口
```

不要把 `127.0.0.1:4431` 填到中转面板，`4431` 是落地机内部 Reality 端口。

## 添加 Reality

交互式：

```bash
xrt
```

然后选：

```text
1) 添加 VLESS Reality
```

非交互式，全部随机：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) \
  --mode reality \
  --yes
```

指定外层端口：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) \
  --mode reality \
  --port 56777 \
  --inner-port 4431 \
  --sni www.icloud.com
```

## 添加 SOCKS5

交互式：

```bash
xrt
```

然后选：

```text
2) 添加 SOCKS5
```

非交互式，端口、账号、密码全部随机：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) \
  --mode socks5 \
  --yes
```

手动指定：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) \
  --mode socks5 \
  --port 你的端口 \
  --user 你的用户名 \
  --pass 你的密码
```

## 多协议共存

脚本不会再用后安装的协议覆盖前一个协议。

它会把协议保存到：

```text
/etc/xray-tunnel-reality/state.json
```

然后统一生成：

```text
/etc/xray-tunnel-reality/config.json
```

所以可以这样用：

```bash
xrt
# 先添加 VLESS Reality
# 再添加 SOCKS5
# 然后选择 4 查看所有协议链接
```

## 查看协议

```bash
xrt --show
```

或进入菜单选：

```text
4) 查看所有协议链接
```

输出会包含：

```text
中转填写: 落地IP:端口
客户端链接: vless://...
SOCKS5 明文: IP:端口:用户名:密码
SOCKS 链接: socks://...
```

## Cloudflare VLESS-WS

这个模式是可选项，适合你已经在 Cloudflare 配好橙云域名和 Origin Rule 的场景。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) \
  --mode cf-ws \
  --cf-domain hostdzire.212202.xyz \
  --cf-entry cf.3666888.xyz
```

含义：

```text
--cf-domain  Cloudflare 橙云域名，也是 WS Host/SNI
--cf-entry   客户端连接入口，可以是优选 IP 或优选域名
--port       源站端口，默认随机
--path       WebSocket 路径，默认随机
```

Cloudflare 里要设置 Origin Rule，把访问 `--cf-domain` 的流量转到脚本输出的源站端口。

## BBR

安装协议时默认尝试开启：

```text
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

检查：

```bash
xrt --enable-bbr
```

或菜单选：

```text
9) BBR 状态/开启
```

说明：BBR 是系统 TCP 拥塞控制优化，不是魔法。它能改善 TCP 传输，但不能绕过中转线路、运营商、落地机本身的限速。

## 服务命令

```bash
xrt --status
xrt --restart
xrt --logs
xrt --stop
xrt --start
```

等价的 systemd 命令：

```bash
systemctl status xray-tunnel-reality --no-pager
systemctl restart xray-tunnel-reality
journalctl -u xray-tunnel-reality -f
```

## 卸载

卸载指定协议：

```bash
xrt
# 选择 5) 卸载指定协议
```

卸载整个服务和配置，但保留 Xray 和 xrt：

```bash
xrt --uninstall
```

完整卸载脚本管理器：

```bash
xrt --full-uninstall
```

完整卸载也不会删除：

```text
/usr/local/bin/xray
```

原因是避免影响其它节点或其它面板。

## 安全说明

- 脚本不安装 Web 面板。
- 不开放面板端口。
- 配置目录权限会收紧。
- Reality 私钥只写入服务端配置，不在查看协议时展示。
- 不要把 SSH 密码、Reality 私钥、GitHub token 发到公开页面。

## Xray 版本

默认固定：

```text
v26.6.27
```

指定版本：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) \
  --mode reality \
  --xray-version v26.6.27
```

使用最新版本：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh) \
  --mode reality \
  --latest-xray
```
