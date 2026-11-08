#!/bin/bash
# 以前台方式运行 redsocks，供 process-compose 管理。
#
# 权限模型：保持 uid 0（仓库可能位于 /root 下，其他用户无法读取），但切换到 PROXY_GROUP 组，
# 并把能力集收缩为 CAP_NET_ADMIN（透明代理 / IP_TRANSPARENT）和 CAP_NET_BIND_SERVICE（UDP 以 53 等低端口回包）。
# proxyall.sh 按 --gid-owner PROXY_GROUP 排除 redsocks 自身流量，避免代理循环。
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
require_root
require_config

if [[ ! -f "${REDSOCKS_CONF}" ]]; then
    echo "error: ${REDSOCKS_CONF} missing; run scripts/render-config.sh first" >&2
    exit 1
fi

exec setpriv \
    --regid="${PROXY_GROUP}" --clear-groups \
    --bounding-set=-all,+net_admin,+net_bind_service \
    --inh-caps=-all \
    --no-new-privs \
    -- "${REDSOCKS_BIN}" -c "${REDSOCKS_CONF}"
