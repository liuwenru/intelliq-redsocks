#!/bin/bash
# 初始化本地运行环境：不向系统目录复制任何文件，只做以下事情
#   1. 创建 redsocks 系统组（iptables 据此排除 redsocks 自身流量）
#   2. 检查运行依赖
#   3. 生成仓库根目录的 .env（已存在则保留）
# 之后在仓库根目录执行 process-compose up 启动。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REPO_DIR}/.env"
PROXY_GROUP="redsocks"

if [[ ${EUID} -ne 0 ]]; then
    echo "must run as root" >&2
    exit 1
fi

if ! getent group "${PROXY_GROUP}" >/dev/null; then
    groupadd --system "${PROXY_GROUP}"
    echo "created group ${PROXY_GROUP}"
fi

missing=0
for cmd in iptables ip ss setpriv process-compose; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "missing dependency: ${cmd}" >&2
        missing=1
    fi
done
if [[ ${missing} -ne 0 ]]; then
    echo "process-compose: https://github.com/F1bonacc1/process-compose/releases" >&2
fi

binfile="${REPO_DIR}/redsocks_$(uname -m)"
if [[ ! -f "${binfile}" ]]; then
    echo "error: no prebuilt redsocks for $(uname -m)" >&2
    exit 1
fi
chmod +x "${binfile}" "${REPO_DIR}"/proxyall.sh "${REPO_DIR}"/scripts/*.sh

if [[ ! -f "${ENV_FILE}" ]]; then
    sock_server=""
    sock_port=""
    # 兼容旧版安装记录的上游地址。
    for info in "${REPO_DIR}/proxyserverinfo" /etc/redsocks/proxyserverinfo; do
        if [[ -f "${info}" ]]; then
            sock_server=$(head -n 1 "${info}" | awk -F: '{print $1}')
            sock_port=$(head -n 1 "${info}" | awk -F: '{print $2}')
            echo "found previous upstream ${sock_server}:${sock_port} in ${info}"
            break
        fi
    done
    read -r -p "socks5 server [${sock_server:-127.0.0.1}]: " input
    sock_server="${input:-${sock_server:-127.0.0.1}}"
    read -r -p "socks5 port [${sock_port:-7070}]: " input
    sock_port="${input:-${sock_port:-7070}}"

    sed -e "s|^SOCK_SERVER=.*|SOCK_SERVER=${sock_server}|" \
        -e "s|^SOCK_PORT=.*|SOCK_PORT=${sock_port}|" \
        "${REPO_DIR}/.env.example" > "${ENV_FILE}"
    echo "wrote ${ENV_FILE}"
else
    echo "keeping existing ${ENV_FILE}"
fi

if [[ -f /etc/systemd/system/redsocks.service || -f /usr/local/bin/proxyall ]]; then
    cat <<'EOF'

检测到旧版系统安装。新旧版本不能同时运行，迁移前请手动执行：
  systemctl disable --now redsocks       # 停止旧服务（ExecStopPost 会清理旧规则）
  rm -f /etc/systemd/system/redsocks.service /usr/local/bin/proxyall /usr/bin/redsocks
  systemctl daemon-reload
  rm -rf /etc/redsocks                    # 如有自定义 NoProxy 条目，先移到仓库的 NoProxy.local.txt
EOF
fi

echo
echo "done. start with: cd ${REPO_DIR} && process-compose up"
