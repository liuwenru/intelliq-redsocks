#!/bin/bash
binfile="redsocks_$(uname --machine)"
cp ${binfile} /usr/bin/redsocks
if [[ ! -d /etc/redsocksenv ]]; then
    touch /etc/redsocksenv
fi

SOCK_SERVER="127.0.0.1" #socket5代理服务器
SOCK_PORT="7070"        #socket5代理端口
PROXY_PORT="12345"      #redsock的监听端口

rm -rf redsocks.conf
cp redsocks.conf.example /etc/redsocks.conf
if [[ ! -f proxyserverinfo ]]; then
    # 本地不存在代理服务器的配置
    read -p "please tell me you sock_server:" sock_server
    if [[ ${sock_server} != "" ]]; then
        SOCK_SERVER=$sock_server
    fi
    read -p "please tell me you sock_port:" sock_port
    if [[ ${SOCK_PORT} != "" ]]; then
        SOCK_PORT=${sock_port}
    fi
    echo "${SOCK_SERVER}:${SOCK_PORT}" >proxyserverinfo
else
    # 本地已经存在了代理服务的配置信息,直接读取就好了
    SOCK_SERVER=$(head -n 1 proxyserverinfo | awk -F: '{print $1}')
    SOCK_PORT=$(head -n 1 proxyserverinfo | awk -F: '{print $2}')

fi

cp redsocks.service /lib/systemd/system/
sed -i '18s/daemon.*/daemon = on;/g' /etc/redsocks.conf
sed -i '44s/local_port.*/local_port = '${PROXY_PORT}';/g' /etc/redsocks.conf
sed -i '61s/ip.*/ip = '${SOCK_SERVER}';/g' /etc/redsocks.conf
sed -i '62s/port.*/port = '${SOCK_PORT}';/g' /etc/redsocks.conf
sed -i 's/SOCK_SERVER/'${SOCK_SERVER}'/g' /lib/systemd/system/redsocks.service

systemctl daemon-reload

#  cpy proxy set
/bin/cp NoProxy.txt /etc/NoProxy.txt
/bin/cp NoProxyDoamin.txt /etc/NoProxyDoamin.txt
/bin/cp GFlist.txt /etc/GFlist.txt

/bin/cp -rf proxy.sh /usr/local/bin/proxy && chmod +x /usr/local/bin/proxy && sed -i 's/SED_SOCK_SERVER/'${SOCK_SERVER}'/g' /usr/local/bin/proxy && sed -i 's/SED_PROXY_PORT/'${PROXY_PORT}'/g' /usr/local/bin/proxy
/bin/cp -rf proxyall.sh /usr/local/bin/proxyall && chmod +x /usr/local/bin/proxyall && sed -i 's/SED_SOCK_SERVER/'${SOCK_SERVER}'/g' /usr/local/bin/proxyall && sed -i 's/SED_PROXY_PORT/'${PROXY_PORT}'/g' /usr/local/bin/proxyall
