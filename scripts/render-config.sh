#!/bin/bash
# 根据 .env 生成 run/redsocks.conf 和 run/NoProxy.txt。每次启动都重新生成，不要手工修改 run/ 下的文件。
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
require_config

if [[ ! -x "${REDSOCKS_BIN}" ]]; then
    echo "error: ${REDSOCKS_BIN} not found or not executable (unsupported arch $(uname -m)?)" >&2
    exit 1
fi

mkdir -p "${RUN_DIR}"

sed -e "s|@SOCK_SERVER@|${SOCK_SERVER}|g" \
    -e "s|@SOCK_PORT@|${SOCK_PORT}|g" \
    -e "s|@PROXY_PORT@|${PROXY_PORT}|g" \
    -e "s|@UDP_PROXY_PORT@|${UDP_PROXY_PORT}|g" \
    "${REPO_DIR}/redsocks.conf.tmpl" > "${REDSOCKS_CONF}.tmp"
if grep -q '@[A-Z_]*@' "${REDSOCKS_CONF}.tmp"; then
    echo "error: unresolved placeholder in redsocks.conf.tmpl:" >&2
    grep -n '@[A-Z_]*@' "${REDSOCKS_CONF}.tmp" >&2
    exit 1
fi
mv "${REDSOCKS_CONF}.tmp" "${REDSOCKS_CONF}"

# 第一行固定为 SOCK_SERVER，避免上游连接被自己接管；NoProxy.local.txt 用于本机专属条目（不入库）。
{
    echo "${SOCK_SERVER}"
    cat "${REPO_DIR}/NoProxy.txt"
    if [[ -f "${REPO_DIR}/NoProxy.local.txt" ]]; then
        echo
        cat "${REPO_DIR}/NoProxy.local.txt"
    fi
} > "${NO_PROXY_FILE}"

echo "rendered ${REDSOCKS_CONF} (upstream ${SOCK_SERVER}:${SOCK_PORT}, tcp ${PROXY_PORT}, udp ${UDP_PROXY_PORT})"
echo "rendered ${NO_PROXY_FILE}"
