# 一、简介

实现 Linux 下的全局翻墙，使用 redsocks 配合 iptables 实现请求流量的转发

有的时候在实验环境中下载一些被`GFW`给墙掉的资源会出现下载不到的情况，好在网上有大神使用`C`写了一个库可以将将本地的流量从一个端口转向`Socket5`的端口，我们再使用一个`SSH -D`参数本地启动一个`Socket5`端口，使用`redsocks`将流量转到对应的`Socket5`上。这样就是就可以实现任何流量都可以翻墙了，由于官方的`redsocks`并没有提供`iptables`的配置方法，所以我写了一个脚本，自动的读取配置文件啥的，帮助快速使用。

感谢大神的项目，详细参见[此处 Github 主页](https://github.com/darkk/redsocks)。

# 一、使用方法

本人已经针对`redsocks`的一个稳定版本编译好了一个直接可以运行的二进制文件，使用`alpine musl gilbc`编译，因此可以不需要安装依赖直接使用，提供了`x86`和`aarch64`两个版本，使用方法如下

1. 安装

```bash
Shell> git clone 本仓库
Shell> ./install.sh
please tell me you sock_server:127.0.0.1 #输入socket5代理服务器的地址
please tell me you sock_port:7070        #输入socket5代理服务器的端口
```

2. 启动 redsocks

```bash
Shell > service redsocks start

```

3. 启动全局代理

```bash
Shell> proxyall      #启动全局代理模式，此模式下将代理所有的访问

 iptables OUTPUT chain:
 Chain OUTPUT (policy ACCEPT 0 packets, 0 bytes)
 num   pkts bytes target     prot opt in     out     source               destination
 1        0     0 REDSOCKS_OUTPUT tcp -- *    *       0.0.0.0/0            0.0.0.0/0

 iptables REDSOCKS_OUTPUT chain:
 Chain REDSOCKS_OUTPUT (1 references)
 num   pkts bytes target     prot opt in     out     source               destination
 1        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            owner UID match redsocks
 2        0     0 REDSOCKS_TCP tcp --  *      *       0.0.0.0/0            0.0.0.0/0

 iptables REDSOCKS_TCP chain:
 Chain REDSOCKS_TCP (N references)
 num   pkts bytes target     prot opt in     out     source               destination
 1        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            192.168.188.8
 2        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            127.0.0.1
 3        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            192.168.0.0/16
 4        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            172.16.0.0/16
 5        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            192.168.188.0/24
 6        0     0 REDIRECT   tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            redir ports 12345
```

4. 清理代理与关闭代理

```bash

Shell> iptables -t nat -D OUTPUT -p tcp -j REDSOCKS_OUTPUT
Shell> iptables -t nat -D PREROUTING -p tcp -j REDSOCKS_PREROUTING
Shell> iptables -t nat -F REDSOCKS_PREROUTING
Shell> iptables -t nat -X REDSOCKS_PREROUTING
Shell> iptables -t nat -F REDSOCKS_OUTPUT
Shell> iptables -t nat -X REDSOCKS_OUTPUT
Shell> iptables -t nat -F REDSOCKS_TCP
Shell> iptables -t nat -X REDSOCKS_TCP
Shell> iptables -t filter -D INPUT -p tcp -j REDSOCKS_INPUT
Shell> iptables -t filter -D INPUT -p udp -j REDSOCKS_INPUT
Shell> iptables -t filter -F REDSOCKS_INPUT
Shell> iptables -t filter -X REDSOCKS_INPUT
Shell> iptables -t mangle -D OUTPUT -p udp -j REDSOCKS_UDP_OUTPUT
Shell> iptables -t mangle -D PREROUTING -p udp -j REDSOCKS_UDP_PREROUTING
Shell> iptables -t mangle -F REDSOCKS_UDP_OUTPUT
Shell> iptables -t mangle -X REDSOCKS_UDP_OUTPUT
Shell> iptables -t mangle -F REDSOCKS_UDP_PREROUTING
Shell> iptables -t mangle -X REDSOCKS_UDP_PREROUTING
Shell> iptables -t mangle -F REDSOCKS_UDP_PROXY
Shell> iptables -t mangle -X REDSOCKS_UDP_PROXY
Shell> ip -4 rule del fwmark 0x2333 lookup 10053
Shell> ip -4 route del local 0.0.0.0/0 dev lo table 10053
Shell> service redsocks stop            #关闭 redsocks 进程


```

# 关于代理范围

`proxyall` 会在 iptables nat 表中创建 OUTPUT 专用链 `REDSOCKS_OUTPUT` 和通用链 `REDSOCKS_TCP`。`REDSOCKS_OUTPUT` 先排除 redsocks 进程自身流量，再进入 `REDSOCKS_TCP`。代理规则按以下顺序写入 `REDSOCKS_TCP`：

1. `/etc/redsocks/NoProxy.txt` 中列出的 IP/CIDR（由 `install.sh` 自动写入，第一行为 SOCK_SERVER）
2. 本机直连路由表中的子网
3. 兜底：所有 TCP 流量 `REDIRECT` 到 redsocks 监听端口

如需新增直连条目，编辑 `/etc/redsocks/NoProxy.txt` 后重新执行 `proxyall` 即可。默认文件已经包含本机、私网、链路本地、组播和保留地址。

脚本还会通过 Docker API 动态读取所有 `bridge` 驱动网络的 IPv4 子网，包括默认 `docker0` 和自定义 bridge，不会写死 Docker 地址池。来自这些子网的 TCP 流量通过 nat 表的 `REDSOCKS_PREROUTING` 链进入 `REDSOCKS_TCP`。filter 表的 `REDSOCKS_INPUT` 链放行回环接口上的本机透明代理流量，并对 Docker 仅精确授权：匹配实际网桥入接口和源网段后，允许确经 DNAT 到 redsocks 端口的 TCP，以及访问 `SOCK_SERVER` 地址 TCP 1080/7070 的显式代理连接。不会将整个 Docker 网段加入 ipset，其他服务仍按原有 INPUT/ipset 策略判断；无法确定网桥接口时明确报错，不退化为宽泛放行。OUTPUT 专用的 owner 规则不会出现在 PREROUTING 路径中，兼容 iptables 的 nf_tables 后端。`REDSOCKS_PREROUTING` 的引用会追加到现有 `PREROUTING` 规则之后，让 Docker published ports 等已有 DNAT 规则优先处理。Docker 未安装或 daemon 不可用时会跳过这部分规则，不影响宿主机代理。

重复执行时只会清空并重建相关 `REDSOCKS_*` 自定义链，不会清空系统内置链或重复添加引用。升级前由旧版脚本直接写入 `OUTPUT` 的规则不会被自动删除，需要手动清理一次。

## 在 SOCKS 服务所在机器上使用

`192.168.188.150` 和 `192.168.188.8` 可以共用上游地址 `192.168.188.8:7070`，无需将后者改成 `127.0.0.1`。但在 `188.8` 上启用透明代理前，必须先让两个 Mihomo 实例的出站绕过接管，否则节点连接、DIRECT 和 DNS 流量可能再次进入 redsocks，形成循环。

在两个 Mihomo 配置的顶层设置 `routing-mark: 6666`。若通过 Docker 运行，为对应服务增加 `cap_add: [NET_ADMIN]` 并重建容器，使权限生效；无需启用 privileged。脚本会在 TCP 重定向和 UDP 标记前放过 `6666`（十六进制 `0x1a0a`），同时保留 redsocks 用户绕过规则。该标记需专用于代理出站，不要用于其他需要透明代理的程序。

先验证 Mihomo 标记设置没有权限错误、HTTP/SOCKS 及 DNS 服务正常，再安装和启用 redsocks 规则。宿主机 INPUT 若有 DROP 规则，还需确认回环接口上的本机代理连接被允许。不要排除整个 root 用户，也不要只依赖代理节点 IP 白名单。

修改仓库中的 `proxyall.sh` 不会自动更新已安装的 `/usr/local/bin/proxyall`；应用时需同步脚本并替换 `SED_*` 占位符。重新运行 `install.sh` 会覆盖 redsocks 配置及直连列表，已有安装不要为更新脚本直接重跑安装。

**统一 DNS 与直连约定：** 三台主机的唯一默认上游均为 `192.168.188.8:53`（Mihomo），不将公网 DNS 混入系统备用解析器。`223.5.5.5`、`114.114.114.114` 同时保留在仓库和运行时 `NoProxy.txt`，保持这两个 IP 的所有 TCP/UDP 流量直连，保护显式查询及引导解析。保留统一的 `proxyall` 入口，不增加 TCP-only 参数。188.8 本机的 redudp 若代理其他外部 UDP DNS，回包绑定 `IP:53` 仍会与 Mihomo 通配监听冲突。

主机配置按实际管理方式持久化，不能只临时改生成文件：

- 188.8：NetworkManager 的 `ens192`、`ens256` 设置 DNS 为 `192.168.188.8`，忽略自动 DNS。
- 188.150：NetworkManager 使用 `dns=none`，手工 `/etc/resolv.conf` 仅保留 `192.168.188.8`，网卡配置也同步为该地址。
- 182.150：保留 systemd-resolved 的 `127.0.0.53` stub，其全局及网卡上游均为 `192.168.188.8`，清空公网 fallback 并忽略自动 DNS。

未显式覆盖 DNS 的新 Docker 容器继承主机配置；自定义网络可显示 `127.0.0.11`，其外部查询再转发到主机上游。存量容器需经授权重启后核对，不手工修改 Docker 生成的 resolv.conf，不为此重启整个 Docker daemon。本次已同步 188.8 的两个 Mihomo、SmartDNS 和 188.150 的 mysql57，未启动原本停止的容器。

Mihomo 的 `default-nameserver` 保留独立公网 IP，不能改为指向自身的 `192.168.188.8` 或依赖系统 DNS，否则有引导循环风险。SmartDNS 的显式公网 UDP 上游仍为 `223.5.5.5`，走 NoProxy 直连；“默认 DNS 统一”不等于覆盖这些服务内明确配置的上游。本轮未修改开机策略：188.8 两个 Mihomo 容器目前为 `restart: no`，重启主机后必须确认代理/DNS已启动，否则三台主机的默认解析均受影响。

此约定不覆盖硬编码的其他外部 UDP DNS（例如 `8.8.8.8:53`），也不解决其他端口的通配监听冲突。不要误认为“本机启动了 Mihomo DNS，所有 DNS 请求就会自动进入 Mihomo”。修改 DNS 地址前先同步评估直连列表，且不要清空现有 ipset/iptables。

## 验证案例

宿主机测试需明确禁用显式代理，确认走透明代理而不是环境变量：

```bash
curl --noproxy '*' --connect-timeout 10 --max-time 30 https://www.google.com -o /dev/null
```

用户原始 Docker 命令如下，默认 bridge 网络不变，但要注意 Docker 客户端可能自动注入显式代理变量：

```bash
docker run --rm -it alpine wget -O- https://www.google.com
# 自动化测试不分配终端，并限制等待时间：
docker run --rm alpine wget -T 20 -O- https://www.google.com
```

188.8 当前 Docker 客户端会自动注入 HTTP 代理，上述原始命令在现有 Alpine 镜像中存在独立的 502 问题：BusyBox wget 发完请求即半关闭发送方向（FIN）。对同一 `GET https://...` 请求进行对照，保持发送方向打开返回 200，立即半关闭则返回 502；Google 和 example.com 均可复现。不能仅凭 GET 与 CONNECT 的不同认定协议不兼容，也不能将该 502 归因于默认 DNS。此问题与透明代理连通性分开处理。

以下默认 bridge 测试已在三台机器通过：只清空显式代理变量，不传 `--dns`，由新容器继承主机的 Mihomo DNS，验证默认 DNS 与真正的透明代理路径。182.150 使用本机已有的 ARM 镜像 `alpine:3.22`。

```bash
docker run --rm \
  -e http_proxy= -e https_proxy= -e HTTP_PROXY= -e HTTPS_PROXY= \
  -e all_proxy= -e ALL_PROXY= \
  alpine wget -T 20 -O- https://www.google.com
```

容器测试若超时，分别检查 DNS 查询、nat 重定向命中以及 INPUT 最终 DROP，不能通过清空防火墙或扩大 ipset 白名单掩盖问题。容器的 `wget` 是否支持指定的 TLS 功能也需根据镜像实际版本确认。

三机还通过了系统默认 DNS 的 Google 解析、公司域名解析、两个公网 DNS 直连以及经 redudp 的 UDP NTP 测试；ipset 成员保持不变。188.8 的 INPUT 仅按授权开放指定网桥、源网段和代理端口，不放行整个 Docker 网段。直连公网 DNS 仍可能返回被污染的 Google IP，将 DNS 加入 NoProxy 不能替代系统默认 DNS 切换。

# UDP 代理

`proxyall` 使用 redsocks `redudp`、iptables `TPROXY` 和策略路由代理宿主机及所有 Docker bridge 网络的 IPv4 UDP 流量。UDP 监听地址为 `127.0.0.1:10053`，SOCKS5 服务必须支持 UDP ASSOCIATE；OpenSSH `ssh -D` 不支持这种 UDP 转发。

安装时会创建专用系统用户 `redsocks`，systemd 向进程授予透明 UDP 所需的 `CAP_NET_ADMIN`，以及回送 DNS 等低源端口 UDP 响应所需的 `CAP_NET_BIND_SERVICE`；否则回包绑定原始源端口时会报 Permission denied。OUTPUT 规则会按进程 owner 排除 redsocks 自己发出的 TCP 和 UDP，避免 SOCKS5 UDP relay 地址与控制连接地址不同时形成代理循环。

脚本使用 fwmark `0x2333` 和路由表 `10053`，并维护以下 mangle 链：

1. `REDSOCKS_UDP_OUTPUT`：排除 `NoProxy.txt` 和本地路由后，标记宿主机 UDP。
2. `REDSOCKS_UDP_PREROUTING`：接收策略路由回送的宿主机流量及 Docker bridge UDP。
3. `REDSOCKS_UDP_PROXY`：保留原始目标地址并通过 TPROXY 交给 `redudp`。

本机目标 UDP 会被排除，以免影响 Docker published UDP ports 和其他本地服务。filter `INPUT` 只额外放行回环接口上带 `0x2333` 标记的透明代理 UDP，不修改已有的 ipset 集合、白名单规则或最终 DROP。

当前 UDP 实现只支持 IPv4。SOCKS5 UDP 分片不受支持，原版 redsocks 0.5 对同一个客户端 UDP socket 同时访问多个目标也存在限制。

通配监听冲突不限于 DNS 53：188.150 的 Avahi 监听 UDP 5353，实测 redudp 绑定 `208.67.222.222:5353` 回包也报 `EADDRINUSE`。这不影响默认 Mihomo DNS 或已通过的 UDP NTP，但不能宣称所有 UDP 目标端口均可代理；不要为了测试停止现有服务或擅自放宽规则。

# 运行时文件分布

```
/etc/redsocks/
├── redsocks.conf          # redsocks 配置文件
├── NoProxy.txt            # 直连 IP/CIDR 列表（第一行是 SOCK_SERVER）
└── proxyserverinfo        # 上次安装时的 SOCK_SERVER:SOCK_PORT 记录

/etc/systemd/system/redsocks.service   # systemd unit 文件
/run/redsocks/redsocks.pid              # redsocks 进程 PID 文件
/usr/bin/redsocks                       # redsocks 二进制
/usr/local/bin/proxyall                 # 全局代理快捷命令
```

# 静态编译方法

```bash

apk --no-cache add busybox-extras musl-dev linux-headers libevent-static libevent-dev musl-dev gcc make vim bash

```
