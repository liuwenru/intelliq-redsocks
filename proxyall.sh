#!/bin/bash
set -euo pipefail

SOCK_SERVER="${SOCK_SERVER:-SED_SOCK_SERVER}"
PROXY_PORT="${PROXY_PORT:-SED_PROXY_PORT}"
SUDO="${SUDO:-}"
NO_PROXY_FILE="/etc/redsocks/NoProxy.txt"
PROXY_CHAIN="REDSOCKS_OUTPUT"

prepare_proxy_chain() {
    if ! ${SUDO} iptables -t nat -nL "${PROXY_CHAIN}" >/dev/null 2>&1; then
        ${SUDO} iptables -t nat -N "${PROXY_CHAIN}"
    fi
    ${SUDO} iptables -t nat -F "${PROXY_CHAIN}"

    if ! ${SUDO} iptables -t nat -C OUTPUT -p tcp -j "${PROXY_CHAIN}" >/dev/null 2>&1; then
        ${SUDO} iptables -t nat -A OUTPUT -p tcp -j "${PROXY_CHAIN}"
    fi
}

load_no_proxy() {
    if [[ ! -f "${NO_PROXY_FILE}" ]]; then
        echo "warn: ${NO_PROXY_FILE} not found"
        return 0
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
        echo -e "\033[32m no-proxy: ${line}\033[0m"
        ${SUDO} iptables -t nat -A "${PROXY_CHAIN}" -p tcp -d "${line}" -j RETURN
    done < "${NO_PROXY_FILE}"
}

load_local_routes() {
    while IFS= read -r subroute; do
        [[ -z "${subroute}" ]] && continue
        ${SUDO} iptables -t nat -A "${PROXY_CHAIN}" -p tcp -d "${subroute}" -j RETURN
    done < <(ip -o route show | awk '{print $1}' | grep -v '^default$')
}

prepare_proxy_chain
load_no_proxy
load_local_routes
${SUDO} iptables -t nat -A "${PROXY_CHAIN}" -p tcp -j REDIRECT --to-ports "${PROXY_PORT}"

echo -e "\033[32m iptables OUTPUT chain:\033[0m"
${SUDO} iptables -t nat -nvL OUTPUT --line-numbers
echo -e "\033[32m iptables ${PROXY_CHAIN} chain:\033[0m"
${SUDO} iptables -t nat -nvL "${PROXY_CHAIN}" --line-numbers
