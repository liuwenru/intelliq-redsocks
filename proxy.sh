#!/bin/bash

#proxy the fwlist.txt
iptables -t nat -F

# always set no proxy setting
function set_no_proxy() {
    # set no need proxy
    while read line; do
        echo -e "\033[32m this ip[${line}] will no connected .... \033[0m"
        ${SUDO} iptables -t nat -A OUTPUT -p tcp -d ${line} -j RETURN
    done </etc/NoProxy.txt
}
set_no_proxy

for subroute in $(ip route show | grep "/" | awk '{print $1}'); do
    iptables -t nat -A OUTPUT -p tcp -d ${subroute} -j RETURN
done
iptables -t nat -A OUTPUT -p tcp -d ${mynetwork} -j RETURN
iptables -t nat -A OUTPUT -p tcp -d SED_SOCK_SERVER -j RETURN
iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 -j RETURN
while read line; do
    echo -e "\033[32m this ip[${line}] will use proxy connected .... \033[0m"
    iptables -t nat -A OUTPUT -p tcp -d ${line} -j REDIRECT --to-ports SED_PROXY_PORT
done </etc/GFlist.txt
echo -e "\033[32m your iptabls OUTPUT chain like this.... \033[0m"
iptables -t nat -nvL --line-numbers
