#!/bin/bash
set -euo pipefail

SOCK_SERVER="${SOCK_SERVER:-SED_SOCK_SERVER}"
PROXY_PORT="${PROXY_PORT:-SED_PROXY_PORT}"
SUDO="${SUDO:-}"
NO_PROXY_FILE="/etc/redsocks/NoProxy.txt"

flush_output() {
    ${SUDO} iptables -t nat -F OUTPUT
}

load_no_proxy() {
    if [[ ! -f "${NO_PROXY_FILE}" ]]; then
        echo "warn: ${NO_PROXY_FILE} not found"
        return 0
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
        echo -e "\033[32m no-proxy: ${line}\033[0m"
        ${SUDO} iptables -t nat -A OUTPUT -p tcp -d "${line}" -j RETURN
    done < "${NO_PROXY_FILE}"
}

load_local_routes() {
    while IFS= read -r subroute; do
        [[ -z "${subroute}" ]] && continue
        ${SUDO} iptables -t nat -A OUTPUT -p tcp -d "${subroute}" -j RETURN
    done < <(ip -o route show | awk '{print $1}' | grep -v '^default$')
}

flush_output
load_no_proxy
load_local_routes
${SUDO} iptables -t nat -A OUTPUT -p tcp -j REDIRECT --to-ports "${PROXY_PORT}"

echo -e "\033[32m iptables OUTPUT chain:\033[0m"
${SUDO} iptables -t nat -nvL OUTPUT --line-numbers