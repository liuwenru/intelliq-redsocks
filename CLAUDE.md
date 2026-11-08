# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

基于 [redsocks](https://github.com/darkk/redsocks) 0.5 的 Linux 全局透明代理。宿主机和所有 Docker bridge 网络的流量都转发到上游 SOCKS5 服务器：TCP 走 nat 表 `REDIRECT`，IPv4 UDP 走 mangle 表 `TPROXY` 加策略路由。

全部文件留在仓库目录内运行，不安装到系统目录。进程编排由 [process-compose](https://github.com/F1bonacc1/process-compose) 负责。仓库只包含 Bash 脚本、配置模板和预编译的静态二进制（`redsocks_x86_64`、`redsocks_aarch64`，由 `redsocks-release-0.5.tar.gz` 在 Alpine/musl 下编译），没有构建系统和测试套件。README 和代码注释使用中文，新增内容保持中文。

## 常用命令

全部需要 root，并且要在仓库根目录执行：process-compose 从当前目录加载 `.env`，进程的工作目录也是当前目录。

```bash
./install.sh                            # 创建 redsocks 组、检查依赖、交互生成 .env（不覆盖已有 .env）
process-compose up                      # 启动（-D 后台运行）
process-compose down                    # 停止，先清理规则再停止 redsocks
process-compose up --dry-run -t=false   # 校验 process-compose.yaml
./proxyall.sh status|up|down|run        # 单独管理 iptables 规则，up 和 down 可重复执行
bash -n proxyall.sh install.sh scripts/*.sh   # 语法检查
```

以下命令用来验证流量确实走透明代理，而不是环境变量里的显式代理：

```bash
curl --noproxy '*' --connect-timeout 10 --max-time 30 https://www.google.com -o /dev/null
docker run --rm -e http_proxy= -e https_proxy= -e HTTP_PROXY= -e HTTPS_PROXY= -e all_proxy= -e ALL_PROXY= \
  alpine wget -T 20 -O- https://www.google.com
```

在已经启用代理的主机上，可以在独立网络命名空间里测试规则逻辑，不影响宿主机。加一个返回失败的 `docker` shim，让脚本跳过 Docker 网段：

```bash
SOCK_SERVER=1.2.3.4 SOCK_PORT=1080 unshare -n bash -c 'ip link set lo up; ./proxyall.sh up; iptables-save | grep REDSOCKS; ./proxyall.sh down'
```

`pushfdoc.sh` 会把仓库打包后经 ssh 传到内网主机。这属于对外发布，没有明确要求时不要执行。

## 架构

**配置流向。** `.env` 由 `scripts/env.sh` 加载，它也负责默认值和校验，被所有脚本 source，所以脚本可以脱离 process-compose 单独运行。`scripts/render-config.sh` 用 `.env` 替换 `redsocks.conf.tmpl` 中的 `@VAR@` 占位符，生成 `run/redsocks.conf`。它同时生成 `run/NoProxy.txt`，内容依次是 SOCK_SERVER、`NoProxy.txt`、可选的 `NoProxy.local.txt`。`run/` 是生成目录，不要手工修改。新增可配置项时，要同时改 `.env.example`、`env.sh`（默认值和校验）和模板。

**进程编排（`process-compose.yaml`）。**
- 启动顺序：`render-config`（一次性）→ `redsocks`（`scripts/check-redsocks.sh` 确认 TCP 和 UDP 端口都在监听后才算就绪）→ `proxy-rules`（`./proxyall.sh run`）。
- `proxy-rules` 是常驻进程：建立规则后 `sleep`，收到 SIGTERM 或从任何路径退出时都会执行 `proxy_down`，包括 `up` 中途失败。所以不依赖 process-compose 对一次性进程的 shutdown 行为。
- `ordered_shutdown: true` 保证先清理规则，再停止 redsocks。
- `process-compose down` 会向整个进程组发 SIGTERM，`sleep` 可能比脚本先退出。清理路径（`on_run_exit`、`proxy_down`）必须关闭 errexit，否则某条命令失败（例如 `kill` 已经退出的 sleep）会让脚本提前退出，规则残留。
- 各进程的输出在 `run/<进程名>.log`。
- 规则清理只在 `proxyall.sh` 的 `proxy_down` 里实现，新增链、跳转引用、fwmark、路由时要同步修改它。README 的迁移章节提到的旧版 `redsocks.service` 已删除。

**权限模型。** `scripts/run-redsocks.sh` 用 `setpriv` 启动 redsocks：保持 uid 0，因为仓库可能在 `/root` 下，其他用户无法读取；gid 切换为 `redsocks`；能力集只保留 `net_admin` 和 `net_bind_service`。iptables 用 `-m owner --gid-owner redsocks` 排除 redsocks 自身流量。不要改回按 uid 匹配，除非同时改变运行用户。redsocks 必须保持 `daemon = off`。

**iptables 链结构（`proxyall.sh`）。** 只清空并重建自己的 `REDSOCKS_*` 链；内置链里的跳转引用只在缺失时添加。从不清空内置链，也不动 ipset。

- **nat `OUTPUT` → `REDSOCKS_OUTPUT`**：先放过 fwmark `6666`（Mihomo 的 `routing-mark`）和 redsocks 组的流量，再跳到 `REDSOCKS_TCP`。
- **nat `PREROUTING` → `REDSOCKS_PREROUTING`**：这条引用故意追加在末尾，让 Docker published ports 的 DNAT 先处理。Docker bridge 源网段的流量从这里跳到 `REDSOCKS_TCP`。
- **`REDSOCKS_TCP`**：NoProxy 条目和本机路由子网直接 `RETURN`，其余 `REDIRECT` 到 `PROXY_PORT`。这条链同时被 OUTPUT 和 PREROUTING 引用，不能放 `-m owner` 匹配，否则在 nf_tables 后端下 PREROUTING 路径会报错。
- **UDP 路径**：
  1. mangle `REDSOCKS_UDP_OUTPUT` 给宿主机 UDP 打上 `0x2333` 标记。
  2. 策略路由（`ip rule fwmark 0x2333 lookup 10053`，加上 `local 0.0.0.0/0 dev lo`）把带标记的包送回本机，进入 `REDSOCKS_UDP_PREROUTING`。
  3. `REDSOCKS_UDP_PROXY` 用 `TPROXY` 把包交给 `127.0.0.1:UDP_PROXY_PORT`。
- **filter `INPUT` → `REDSOCKS_INPUT`**（插在第 1 位）：只做以下精确放行。
  - `lo` 上经过 DNAT 的 TCP
  - 各 Docker 网桥接口加对应网段：经过 DNAT 的代理端口连接，以及访问 SOCK_SERVER 1080/7070 的连接
  - `lo` 上带 `0x2333` 标记的 UDP

**规则顺序很关键。** `exclude_proxy_process` 必须在 REDIRECT/MARK 兜底规则之前执行，否则代理自身的出站流量会被接管，形成循环。UDP OUTPUT 链里 `6666` 的 RETURN 必须排在 MARK 之前，否则 Mihomo 的标记会被覆盖成 `0x2333`。

**Docker 网段发现。** 通过 Docker API 读取所有 `bridge` 驱动网络的 IPv4 子网，不写死地址。Docker 不可用时只打印警告并跳过。某个子网找不到网桥接口时报错退出，这时 `proxy-rules` 会让整个 process-compose 退出。

## README 中的约束

- 连通性有问题时，不要靠清空 iptables、扩大 ipset 白名单或放行整个 Docker 网段来"修复"。应分别排查 DNS 解析、nat 重定向是否命中、INPUT 最终 DROP。
- UDP 代理要求 SOCKS5 支持 UDP ASSOCIATE，`ssh -D` 不支持。UDP 只支持 IPv4。
- redudp 回包时会绑定原始目标 `IP:端口`，与本机的通配监听冲突（Mihomo DNS 53、Avahi 5353）。这就是公网 DNS IP 放在 NoProxy 里直连的原因。
- README 里有各主机的运维约定（192.168.188.8、188.150、182.150，Mihomo，统一 DNS）。修改 DNS 或 NoProxy 行为前先读这部分。
