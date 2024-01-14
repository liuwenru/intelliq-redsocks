#!/bin/bash

while (true); do
  cat /etc/NoProxyDoamin.txt | while read noproxydomain; do
    for ip in $(nslookup ${noproxydomain} | grep "Address" | grep -v "#" | awk '{print $2}'); do
      isexsit=$(iptables -t nat -L OUTPUT -nv --line 2>&1 | grep ${ip} | wc -l)
      if [[ ${isexsit} -eq 0 ]]; then
        iptables -t nat -I OUTPUT 1 -p tcp -d ${ip} -j RETURN   -m  comment  --comment  ${noproxydomain}
      fi
    done
  done
  sleep 300
done
