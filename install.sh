#!/bin/bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "must run as root" >&2
    exit 1
fi

SOCK_SERVER="127.0.0.1"
SOCK_PORT="7070"
PROXY_PORT="12345"
UDP_PROXY_PORT="10053"

REDSDOCKS_ETC="/etc/redsocks"
PROXYSERVERINFO="${REDSDOCKS_ETC}/proxyserverinfo"
REDSDOCKS_CONF="${REDSDOCKS_ETC}/redsocks.conf"
NO_PROXY_FILE="${REDSDOCKS_ETC}/NoProxy.txt"

if ! getent group redsocks >/dev/null; then
    groupadd --system redsocks
fi
if ! getent passwd redsocks >/dev/null; then
    useradd --system --gid redsocks --no-create-home --shell /usr/sbin/nologin redsocks
fi

mkdir -p "${REDSDOCKS_ETC}"

binfile="redsocks_$(uname --machine)"
cp "${binfile}" /usr/bin/redsocks

cp redsocks.conf.example "${REDSDOCKS_CONF}"

if [[ ! -f "${PROXYSERVERINFO}" ]]; then
    read -r -p "please tell me you sock_server:" sock_server
    if [[ -n "${sock_server}" ]]; then
        SOCK_SERVER="${sock_server}"
    fi
    read -r -p "please tell me you sock_port:" sock_port
    if [[ -n "${sock_port}" ]]; then
        SOCK_PORT="${sock_port}"
    fi
    echo "${SOCK_SERVER}:${SOCK_PORT}" > "${PROXYSERVERINFO}"
else
    SOCK_SERVER=$(head -n 1 "${PROXYSERVERINFO}" | awk -F: '{print $1}')
    SOCK_PORT=$(head -n 1 "${PROXYSERVERINFO}" | awk -F: '{print $2}')
fi

sed -i -E "0,/^\s*daemon\s*=.*/{s|^\s*daemon\s*=.*|daemon = on;|}" "${REDSDOCKS_CONF}"
sed -i -E "0,/^\s*local_port\s*=.*/{s|^\s*local_port\s*=.*|local_port = ${PROXY_PORT};|}" "${REDSDOCKS_CONF}"
sed -i -E "0,/^\s*ip\s*=.*/{s|^\s*ip\s*=.*|ip = ${SOCK_SERVER};|}" "${REDSDOCKS_CONF}"
sed -i -E "0,/^\s*port\s*=.*/{s|^\s*port\s*=.*|port = ${SOCK_PORT};|}" "${REDSDOCKS_CONF}"
sed -i "s/SED_SOCK_SERVER/${SOCK_SERVER}/g" "${REDSDOCKS_CONF}"
sed -i "s/SED_SOCK_PORT/${SOCK_PORT}/g" "${REDSDOCKS_CONF}"
sed -i "s/SED_UDP_PROXY_PORT/${UDP_PROXY_PORT}/g" "${REDSDOCKS_CONF}"

cp redsocks.service /etc/systemd/system/
systemctl daemon-reload

( echo "${SOCK_SERVER}"; cat NoProxy.txt ) > "${NO_PROXY_FILE}"

/bin/cp -rf proxyall.sh /usr/local/bin/proxyall
chmod +x /usr/local/bin/proxyall
sed -i "s/SED_SOCK_SERVER/${SOCK_SERVER}/g" /usr/local/bin/proxyall
sed -i "s/SED_PROXY_PORT/${PROXY_PORT}/g" /usr/local/bin/proxyall
sed -i "s/SED_UDP_PROXY_PORT/${UDP_PROXY_PORT}/g" /usr/local/bin/proxyall
