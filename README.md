# intelliq-redsocks
实现Linux下的全局翻墙，使用redsocks配合iptables实现请求流量的转发，详细参见[此处Github主页](https://github.com/darkk/redsocks)。

## 一、使用方法

1. 安装依赖包 

yum install libevent libevent-deve

2. 启动myredsocks 

./myredsocks.sh star

3. 选择代理模式 

./myredsocks.sh proxyall|prox


4. 清理代理  

./myredsocks.sh clean
