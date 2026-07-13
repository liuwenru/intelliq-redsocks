#!/bin/bash
set -euo pipefail

SOCK_SERVER="${SOCK_SERVER:-SED_SOCK_SERVER}"
PROXY_PORT="${PROXY_PORT:-SED_PROXY_PORT}"
SUDO="${SUDO:-}"
NO_PROXY_FILE="/etc/redsocks/NoProxy.txt"
PROXY_CHAIN="REDSOCKS_OUTPUT"
PREROUTING_CHAIN="REDSOCKS_PREROUTING"
INPUT_CHAIN="REDSOCKS_INPUT"

ensure_chain() {
    local table="$1"
    local chain="$2"

    if ! ${SUDO} iptables -t "${table}" -nL "${chain}" >/dev/null 2>&1; then
        ${SUDO} iptables -t "${table}" -N "${chain}"
    fi
    ${SUDO} iptables -t "${table}" -F "${chain}"
}

prepare_proxy_chain() {
    ensure_chain nat "${PROXY_CHAIN}"
    ensure_chain nat "${PREROUTING_CHAIN}"
    ensure_chain filter "${INPUT_CHAIN}"

    if ! ${SUDO} iptables -t nat -C OUTPUT -p tcp -j "${PROXY_CHAIN}" >/dev/null 2>&1; then
        ${SUDO} iptables -t nat -A OUTPUT -p tcp -j "${PROXY_CHAIN}"
    fi
    while ${SUDO} iptables -t nat -C PREROUTING -p tcp -j "${PREROUTING_CHAIN}" >/dev/null 2>&1; do
        ${SUDO} iptables -t nat -D PREROUTING -p tcp -j "${PREROUTING_CHAIN}"
    done
    # Preserve existing destination NAT, including Docker published ports.
    ${SUDO} iptables -t nat -A PREROUTING -p tcp -j "${PREROUTING_CHAIN}"
    if ! ${SUDO} iptables -t filter -C INPUT -p tcp -j "${INPUT_CHAIN}" >/dev/null 2>&1; then
        ${SUDO} iptables -t filter -I INPUT 1 -p tcp -j "${INPUT_CHAIN}"
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

load_docker_networks() {
    local network_ids
    local subnet_output
    local subnet
    local -a network_id_list

    if ! command -v docker >/dev/null 2>&1; then
        echo "warn: docker command not found, skipping Docker bridge networks"
        return 0
    fi
    if ! network_ids=$(${SUDO} docker network ls --filter driver=bridge --quiet 2>/dev/null); then
        echo "warn: cannot query Docker networks, skipping Docker bridge networks"
        return 0
    fi
    [[ -z "${network_ids}" ]] && return 0
    mapfile -t network_id_list <<< "${network_ids}"
    if ! subnet_output=$(${SUDO} docker network inspect --format '{{range .IPAM.Config}}{{if .Subnet}}{{println .Subnet}}{{end}}{{end}}' "${network_id_list[@]}" 2>/dev/null); then
        echo "warn: cannot inspect Docker networks, skipping Docker bridge networks"
        return 0
    fi

    while IFS= read -r subnet; do
        [[ -z "${subnet}" || "${subnet}" == *:* ]] && continue
        echo -e "\033[32m docker-proxy: ${subnet}\033[0m"
        ${SUDO} iptables -t nat -A "${PREROUTING_CHAIN}" -s "${subnet}" -p tcp -j "${PROXY_CHAIN}"
        ${SUDO} iptables -t filter -A "${INPUT_CHAIN}" -s "${subnet}" -p tcp --dport "${PROXY_PORT}" -j ACCEPT
    done <<< "${subnet_output}"
}

prepare_proxy_chain
load_no_proxy
load_local_routes
${SUDO} iptables -t nat -A "${PROXY_CHAIN}" -p tcp -j REDIRECT --to-ports "${PROXY_PORT}"
load_docker_networks

echo -e "\033[32m iptables OUTPUT chain:\033[0m"
${SUDO} iptables -t nat -nvL OUTPUT --line-numbers
echo -e "\033[32m iptables ${PROXY_CHAIN} chain:\033[0m"
${SUDO} iptables -t nat -nvL "${PROXY_CHAIN}" --line-numbers
echo -e "\033[32m iptables ${PREROUTING_CHAIN} chain:\033[0m"
${SUDO} iptables -t nat -nvL "${PREROUTING_CHAIN}" --line-numbers
echo -e "\033[32m iptables ${INPUT_CHAIN} chain:\033[0m"
${SUDO} iptables -t filter -nvL "${INPUT_CHAIN}" --line-numbers
