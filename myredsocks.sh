#!/bin/bash
LINE="==============================================="
OSTYPE=$(cat /etc/os-release | grep -E "^NAME=.*" | awk -F\" '{print $2}')
sock_server="127.0.0.1"    #socket5代理服务器
sock_port="7070"      #socket5代理端口
proxy_port="12345"  #redsock的监听端口



redsocks_pid="/tmp/redsocks.pid"
function start_redsocks()
{
  echo "start the redsocks........................"
  if [[ -f ${redsocks_pid} ]];then
    echo "the redsocks is stared..................."
    return 0
  fi
  rm -rf redsocks.conf
  cp redsocks.conf.example redsocks.conf 
  read -p "please tell me you sock_server:" sock_server
  read -p "please tell me you sock_port:" sock_port
  sed -i '18s/daemon.*/daemon = on;/g'  redsocks.conf
  sed -i '44s/local_port.*/local_port = '${proxy_port}';/g'  redsocks.conf
  sed -i '61s/ip.*/ip = '${sock_server}';/g'  redsocks.conf
  sed -i '62s/port.*/port = '${sock_port}';/g'  redsocks.conf
  ./redsocks -c redsocks.conf -p ${redsocks_pid}
}
function stop_redsocks()
{
  echo "stop the redsocks........................"
  if [[ ! -f ${redsocks_pid} ]];then
    echo "the redsocks is not run...please start......"
    return 0
  fi
  pid=$(cat ${redsocks_pid})
  rm -rf ${redsocks_pid}
  kill -9 ${pid}
}
function restart_redsocks()
{
  stop_redsocks
  start_redsocks 
}
until [ $# -eq 0 ]
do
  case $1 in
    start)
    start_redsocks
    shift
    ;;
    stop)
    stop_redsocks
    shift
    ;;
    restart)
    restart_redsocks
    shift
    ;;
    clean)
    iptables -t nat -F 
    shift
    ;;
    proxy)
    #proxy the fwlist.txt
    iptables -t nat -F
    read -p "please tell me you network:" mynetwork
    iptables -t nat -A OUTPUT -p tcp -d ${mynetwork} -j RETURN
    iptables -t nat -A OUTPUT -p tcp -d ${sock_server} -j RETURN
    iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 -j RETURN
    while read line
    do
     echo -e "\033[32m this ip[${line}] will use proxy connected .... \033[0m"
     iptables -t nat -A OUTPUT -p tcp -d ${line} -j REDIRECT --to-ports ${proxy_port}
    done < GFlist.txt
    echo -e "\033[32m your iptabls OUTPUT chain like this.... \033[0m"
    iptables -t nat -nvL --line-numbers
    shift
    ;;
    proxyall)
    #proxy all connection
    iptables -t nat -F
    read -p "please tell me you network:" mynetwork
    iptables -t nat -A OUTPUT -p tcp -d ${mynetwork} -j RETURN
    iptables -t nat -A OUTPUT -p tcp -d ${sock_server} -j RETURN
    iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 -j RETURN
    iptables -t nat -A OUTPUT -p tcp -j REDIRECT --to-ports ${proxy_port}
    echo -e "\033[32m your iptabls OUTPUT chain like this.... \033[0m"
    iptables -t nat -nvL --line-numbers
    shift
    ;;
    stop)
    #clean all iptables
    shift
    ;;
    install)
    echo "install the redsocket"
    install_redsocks
    shift
    ;;
    *)
    shift
    ;;
  esac
done

