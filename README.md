# intelliq-redsocks

实现Linux下的全局翻墙，使用`redsocks`配合`iptables`实现请求流量的转发，详细参见此处[Github主页](https://github.com/darkk/redsocks)。


# 一、使用方法

**1.安装依赖包 yum install  libevent libevent-devel

**2.启动myredsocks ./myredsocks.sh start

**3.选择代理模式 ./myredsocks.sh proxyall|proxy

**4.清理代理 ./myredsocks.sh clean
