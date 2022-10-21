#!/bin/bash

function set_no_proxy() {
    # set no need proxy
    while read line; do
        echo -e "\033[32m this ip[${line}] will no connected .... \033[0m"
        ${SUDO} iptables -t nat -A OUTPUT -p tcp -d ${line} -j RETURN
    done </etc/NoProxy.txt
}

#proxy all connection
for i in $(ip route show | awk '{print $1}' | grep -v default); do
    ${SUDO} iptables -t nat -A OUTPUT -p tcp -d ${i} -j RETURN
done
set_no_proxy
# ${SUDO} iptables -t nat -A OUTPUT -p tcp -d ${SOCK_SERVER} -j RETURN
${SUDO} iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 -j RETURN
${SUDO} iptables -t nat -A OUTPUT -p tcp -j REDIRECT --to-ports ${PROXY_PORT}
echo -e "\033[32m your iptabls OUTPUT chain like this.... \033[0m"
${SUDO} iptables -t nat -nvL --line-numbers
