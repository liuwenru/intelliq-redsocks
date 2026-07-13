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

脚本还会通过 Docker API 动态读取所有 `bridge` 驱动网络的 IPv4 子网，包括默认 `docker0` 和自定义 bridge，不会写死 Docker 地址池。来自这些子网的 TCP 流量通过 nat 表的 `REDSOCKS_PREROUTING` 链进入 `REDSOCKS_TCP`，filter 表的 `REDSOCKS_INPUT` 链负责放行重定向到 redsocks 监听端口的流量。OUTPUT 专用的 owner 规则不会出现在 PREROUTING 路径中，兼容 iptables 的 nf_tables 后端。`REDSOCKS_PREROUTING` 的引用会追加到现有 `PREROUTING` 规则之后，让 Docker published ports 等已有 DNAT 规则优先处理。Docker 未安装或 daemon 不可用时会跳过这部分规则，不影响宿主机代理。

重复执行时只会清空并重建相关 `REDSOCKS_*` 自定义链，不会清空系统内置链或重复添加引用。升级前由旧版脚本直接写入 `OUTPUT` 的规则不会被自动删除，需要手动清理一次。

# UDP 代理

`proxyall` 使用 redsocks `redudp`、iptables `TPROXY` 和策略路由代理宿主机及所有 Docker bridge 网络的 IPv4 UDP 流量。UDP 监听地址为 `127.0.0.1:10053`，SOCKS5 服务必须支持 UDP ASSOCIATE；OpenSSH `ssh -D` 不支持这种 UDP 转发。

安装时会创建专用系统用户 `redsocks`，systemd 仅向进程授予透明 UDP 所需的 `CAP_NET_ADMIN`。OUTPUT 规则会按进程 owner 排除 redsocks 自己发出的 TCP 和 UDP，避免 SOCKS5 UDP relay 地址与控制连接地址不同时形成代理循环。

脚本使用 fwmark `0x2333` 和路由表 `10053`，并维护以下 mangle 链：

1. `REDSOCKS_UDP_OUTPUT`：排除 `NoProxy.txt` 和本地路由后，标记宿主机 UDP。
2. `REDSOCKS_UDP_PREROUTING`：接收策略路由回送的宿主机流量及 Docker bridge UDP。
3. `REDSOCKS_UDP_PROXY`：保留原始目标地址并通过 TPROXY 交给 `redudp`。

本机目标 UDP 会被排除，以免影响 Docker published UDP ports 和其他本地服务。filter `INPUT` 只放行带 `0x2333` 标记的透明代理流量。

当前 UDP 实现只支持 IPv4。SOCKS5 UDP 分片不受支持，原版 redsocks 0.5 对同一个客户端 UDP socket 同时访问多个目标也存在限制。

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
