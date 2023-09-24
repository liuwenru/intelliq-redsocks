#!/bin/bash
set -e

# 获取脚本所在目录
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# 从dnsserverinfo文件中读取$PROXY_DNS_PORT和DEFAULT_NAMESERVER，如果文件不存在则使用默认值
if [[ -f dnsserverinfo ]]; then
    source dnsserverinfo
else
    # 用户输入PROXY_DNS_PORT和DEFAULT_NAMESERVER
    read -p "Please enter PROXY_DNS_PORT (default: 5300): " PROXY_DNS_PORT
    PROXY_DNS_PORT=${PROXY_DNS_PORT:-5300}
    DEFAULT_NAMESERVER=$(awk '/nameserver/ && !/^#/{print $2; exit}' /etc/resolv.conf)
    read -p "Please enter DEFAULT_NAMESERVER (default: $DEFAULT_NAMESERVER): " custom_nameserver
    DEFAULT_NAMESERVER=${custom_nameserver:-$DEFAULT_NAMESERVER}
    # 保存输入值到dnsserverinfo文件
    echo "PROXY_DNS_PORT=$PROXY_DNS_PORT" > dnsserverinfo
    echo "DEFAULT_NAMESERVER=$DEFAULT_NAMESERVER" >> dnsserverinfo
fi

# 检查pdnsd服务是否已经存在
if systemctl is-active --quiet pdnsd; then
    # 如果服务已存在，只更新配置文件
    echo "pdnsd service already exists, updating configuration..."
    # 这里添加更新pdnsd配置文件的命令
    sed -i "s|\${$PROXY_DNS_PORT}|$PROXY_DNS_PORT|g" /etc/pdnsd.conf
    systemctl restart pdnsd
else
    # 如果服务不存在，执行安装和配置
    echo "pdnsd service does not exist, installing and configuring..."
    # 安装pdnsd
    arch=$(dpkg --print-architecture)
    package_name="pdnsd_1.2.9a-par-3"

    if [ "$arch" == "amd64" ]; then
        deb_file="${package_name}_amd64.deb"
    elif [ "$arch" == "i386" ]; then
        deb_file="${package_name}_i386.deb"
    else
        echo "Unsupported architecture: $arch"
        exit 1
    fi

    echo "Installing $deb_file"
    dpkg -i "$deb_file"

    cat default_pdnsd.example > /etc/default/pdnsd
    cat pdnsd.conf.example > /etc/pdnsd.conf
    sed -i "s|\${$PROXY_DNS_PORT}|$PROXY_DNS_PORT|g" /etc/pdnsd.conf
    systemctl restart pdnsd
fi

# 检查dnsmasq服务是否已经存在
if systemctl is-active --quiet dnsmasq; then
    # 如果服务已存在，只更新配置文件
    echo "dnsmasq service already exists, updating configuration..."
    # 这里添加更新dnsmasq配置文件的命令
    systemctl restart dnsmasq
else
    # 如果服务不存在，执行安装和配置
    echo "dnsmasq service does not exist, installing and configuring..."
    # 安装dnsmasq
    if [ -f /etc/redhat-release ]; then
        yum update -y
        yum install -y dnsmasq
    elif [ -f /etc/lsb-release ]; then
        apt-get update
        apt-get install -y dnsmasq
    else
        echo "Unsupported Linux distribution"
        exit 1
    fi

    # 启用或禁用相应的服务
    if systemctl is-active --quiet systemd-resolved; then
        systemctl disable systemd-resolved
        systemctl stop systemd-resolved
    fi

    # 定义函数来处理DNS规则配置
    configure_dns_rules() {
        # 初始化SERVER_RULES变量为空字符串
        SERVER_RULES=""

        # 读取proxy_dns.txt文件的每一行
        while IFS= read -r line; do
            # 去除前后的空白
            trimmed_line="$(echo -e "${line}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

            # 如果行不为空，则添加server规则到SERVER_RULES变量
            if [ -n "$trimmed_line" ]; then
                SERVER_RULES+="server=/$trimmed_line/127.0.0.1#$PROXY_DNS_PORT\n"
            fi
        done < "proxy_dns.txt"

        # 拷贝dnsmasq.conf.example文件到/etc/dnsmasq.conf
        cp "${SCRIPT_DIR}/dnsmasq.conf.example" /etc/dnsmasq.conf

        # 替换文件中的${SERVER_RULES}和${DEFAULT_NAMESERVER}
        sed -i "s|\${SERVER_RULES}|$SERVER_RULES|g" /etc/dnsmasq.conf
        sed -i "s|\${DEFAULT_NAMESERVER}|$DEFAULT_NAMESERVER|g" /etc/dnsmasq.conf
    }
    # 调用函数来配置DNS规则
    configure_dns_rules

    # 重启dnsmasq服务
    systemctl restart dnsmasq

    # 配置/etc/resolv.conf文件
    echo "nameserver 127.0.0.1" > /etc/resolv.conf
    # 锁定/etc/resolv.conf文件
    chattr +i /etc/resolv.conf
fi



