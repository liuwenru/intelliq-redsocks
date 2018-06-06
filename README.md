# 一、简介

实现Linux下的全局翻墙，使用redsocks配合iptables实现请求流量的转发




有的时候在实验环境中下载一些被`GFW`给墙掉的资源会出现下载不到的情况，好在网上有大神使用`C`写了一个库可以将将本地的流量从一个端口转向`Socket5`的端口，我们再使用一个`SSH -D`参数本地启动一个`Socket5`端口，使用`redsocks`将流量转到对应的`Socket5`上。这样就是就可以实现任何流量都可以翻墙了，由于官方的`redsocks`并没有提供`iptables`的配置方法，所以我写了一个脚本，自动的读取配置文件啥的，帮助快速使用。

感谢大神的项目，详细参见[此处Github主页](https://github.com/darkk/redsocks)。

# 一、使用方法

本人已经针对`redsocks`的一个稳定版本编译好了一个直接可以运行的二进制文件，在`Centos`上可以直接使用。如果想编译其他`Linux`版本上的请按照`redsocks`官方文档操作



1. 使用前请安装依赖包 
如果是`Centos`操作系统
```bash
Shell> yum install libevent libevent-devel
```
如果是`Ubuntu`操作系统
```bash
Shell> sudo apt-get install libevent-2.0-5 libevent-dev

```

2. 启动myredsocks 
```bash
Shell > ./myredsocks.sh start #启动服务进程
start the redsocks........................
please tell me you sock_server:127.0.0.1 #输入socket5代理服务器的地址
please tell me you sock_port:7070        #输入socket5代理服务器的端口
```

3. 选择代理模式 

**全局代理模式**


```bash
./myredsocks.sh proxyall      #启动全局代理模式，此模式下将代理所有的访问
please tell me you network:192.168.188.0/24             #输入你当前主机的网络信息，因为该网段的机器是不需要翻墙访问的
 your iptabls OUTPUT chain like this.... 
 Chain PREROUTING (policy ACCEPT 0 packets, 0 bytes)
 num   pkts bytes target     prot opt in     out     source               destination         

 Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
 num   pkts bytes target     prot opt in     out     source               destination         

 Chain OUTPUT (policy ACCEPT 0 packets, 0 bytes)
 num   pkts bytes target     prot opt in     out     source               destination         
 1        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            192.168.188.0/24    
 2        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            127.0.0.1           
 3        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            127.0.0.1           
 4        0     0 REDIRECT   tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            redir ports 12345

 Chain POSTROUTING (policy ACCEPT 0 packets, 0 bytes)
 num   pkts bytes target     prot opt in     out     source               destination  
```

**代理指定主机**

该模式下只代理`GFlist.txt`中指定的主机

```bash
Shell> ./myredsocks.sh proxy
please tell me you network:192.168.188.0/24   #输入你的网络信息，同全局代理模式一样，同网段的机器不要翻墙
this ip[216.58.194.99] will use proxy connected .... 
this ip[180.97.33.107] will use proxy connected .... 
your iptabls OUTPUT chain like this.... 
   Chain PREROUTING (policy ACCEPT 0 packets, 0 bytes)
   num   pkts bytes target     prot opt in     out     source               destination         

   Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
   num   pkts bytes target     prot opt in     out     source               destination         

   Chain OUTPUT (policy ACCEPT 0 packets, 0 bytes)
   num   pkts bytes target     prot opt in     out     source               destination         
   1        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            192.168.188.0/24    
   2        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            127.0.0.1           
   3        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            127.0.0.1           
   4        0     0 REDIRECT   tcp  --  *      *       0.0.0.0/0            216.58.194.99        redir ports 12345
   5        0     0 REDIRECT   tcp  --  *      *       0.0.0.0/0            180.97.33.107        redir ports 12345

   Chain POSTROUTING (policy ACCEPT 0 packets, 0 bytes)
   num   pkts bytes target     prot opt in     out     source               destination   

```

4. 清理代理与关闭代理 


```bash

Shell> ./myredsocks.sh clean                  #清理所有的代理模式
Shell> ./myredsocks.sh stop                   #关闭代理


```
