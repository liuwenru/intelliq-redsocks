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
 Chain REDSOCKS_OUTPUT (N references)
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
Shell> iptables -t filter -D INPUT -p tcp -j REDSOCKS_INPUT
Shell> iptables -t filter -F REDSOCKS_INPUT
Shell> iptables -t filter -X REDSOCKS_INPUT
Shell> service redsocks stop            #关闭 redsocks 进程


```

# 关于代理范围

`proxyall` 会在 iptables nat 表中创建 `REDSOCKS_OUTPUT` 链，并由 `OUTPUT` 链引用。代理规则按以下顺序写入 `REDSOCKS_OUTPUT`：

1. `/etc/redsocks/NoProxy.txt` 中列出的 IP/CIDR（由 `install.sh` 自动写入，第一行为 SOCK_SERVER）
2. 本机直连路由表中的子网
3. 兜底：所有 TCP 流量 `REDIRECT` 到 redsocks 监听端口

如需新增直连条目，编辑 `/etc/redsocks/NoProxy.txt` 后重新执行 `proxyall` 即可。默认文件已经包含本机、私网、链路本地、组播和保留地址。

脚本还会通过 Docker API 动态读取所有 `bridge` 驱动网络的 IPv4 子网，包括默认 `docker0` 和自定义 bridge。来自这些子网的 TCP 流量通过 nat 表的 `REDSOCKS_PREROUTING` 链进入 `REDSOCKS_OUTPUT`，filter 表的 `REDSOCKS_INPUT` 链负责放行重定向到 redsocks 监听端口的流量。`REDSOCKS_PREROUTING` 的引用会追加到现有 `PREROUTING` 规则之后，让 Docker published ports 等已有 DNAT 规则优先处理。Docker 未安装或 daemon 不可用时会跳过这部分规则，不影响宿主机代理。

重复执行时只会清空并重建三个 `REDSOCKS_*` 自定义链，不会清空系统内置链或重复添加引用。升级前由旧版脚本直接写入 `OUTPUT` 的规则不会被自动删除，需要手动清理一次。

# 运行时文件分布

```
/etc/redsocks/
├── redsocks.conf          # redsocks 配置文件
├── NoProxy.txt            # 直连 IP/CIDR 列表（第一行是 SOCK_SERVER）
└── proxyserverinfo        # 上次安装时的 SOCK_SERVER:SOCK_PORT 记录

/etc/systemd/system/redsocks.service   # systemd unit 文件
/run/redsocks.pid                       # redsocks 进程 PID 文件
/usr/bin/redsocks                       # redsocks 二进制
/usr/local/bin/proxyall                 # 全局代理快捷命令
```

# 静态编译方法

```bash

apk --no-cache add busybox-extras musl-dev linux-headers libevent-static libevent-dev musl-dev gcc make vim bash

```
