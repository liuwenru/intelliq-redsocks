#!/bin/bash
set -euo pipefail

SOCK_SERVER="${SOCK_SERVER:-SED_SOCK_SERVER}"
PROXY_PORT="${PROXY_PORT:-SED_PROXY_PORT}"
UDP_PROXY_PORT="${UDP_PROXY_PORT:-SED_UDP_PROXY_PORT}"
SUDO="${SUDO:-}"
NO_PROXY_FILE="/etc/redsocks/NoProxy.txt"
PROXY_CHAIN="REDSOCKS_OUTPUT"
TCP_PROXY_CHAIN="REDSOCKS_TCP"
PREROUTING_CHAIN="REDSOCKS_PREROUTING"
INPUT_CHAIN="REDSOCKS_INPUT"
UDP_OUTPUT_CHAIN="REDSOCKS_UDP_OUTPUT"
UDP_PREROUTING_CHAIN="REDSOCKS_UDP_PREROUTING"
UDP_PROXY_CHAIN="REDSOCKS_UDP_PROXY"
UDP_MARK="0x2333"
UDP_ROUTE_TABLE="10053"
PROXY_USER="redsocks"

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
    ensure_chain nat "${TCP_PROXY_CHAIN}"
    ensure_chain nat "${PREROUTING_CHAIN}"
    ensure_chain filter "${INPUT_CHAIN}"
    ensure_chain mangle "${UDP_OUTPUT_CHAIN}"
    ensure_chain mangle "${UDP_PREROUTING_CHAIN}"
    ensure_chain mangle "${UDP_PROXY_CHAIN}"

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
    if ! ${SUDO} iptables -t filter -C INPUT -p udp -j "${INPUT_CHAIN}" >/dev/null 2>&1; then
        ${SUDO} iptables -t filter -I INPUT 1 -p udp -j "${INPUT_CHAIN}"
    fi
    if ! ${SUDO} iptables -t mangle -C OUTPUT -p udp -j "${UDP_OUTPUT_CHAIN}" >/dev/null 2>&1; then
        ${SUDO} iptables -t mangle -A OUTPUT -p udp -j "${UDP_OUTPUT_CHAIN}"
    fi
    while ${SUDO} iptables -t mangle -C PREROUTING -p udp -j "${UDP_PREROUTING_CHAIN}" >/dev/null 2>&1; do
        ${SUDO} iptables -t mangle -D PREROUTING -p udp -j "${UDP_PREROUTING_CHAIN}"
    done
    ${SUDO} iptables -t mangle -A PREROUTING -p udp -j "${UDP_PREROUTING_CHAIN}"
}

load_no_proxy() {
    local table="$1"
    local chain="$2"
    local protocol="$3"

    if [[ ! -f "${NO_PROXY_FILE}" ]]; then
        echo "warn: ${NO_PROXY_FILE} not found"
        return 0
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
        echo -e "\033[32m no-proxy: ${line}\033[0m"
        ${SUDO} iptables -t "${table}" -A "${chain}" -p "${protocol}" -d "${line}" -j RETURN
    done < "${NO_PROXY_FILE}"
}

load_local_routes() {
    local table="$1"
    local chain="$2"
    local protocol="$3"

    while IFS= read -r subroute; do
        [[ -z "${subroute}" ]] && continue
        ${SUDO} iptables -t "${table}" -A "${chain}" -p "${protocol}" -d "${subroute}" -j RETURN
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
        ${SUDO} iptables -t nat -A "${PREROUTING_CHAIN}" -s "${subnet}" -p tcp -j "${TCP_PROXY_CHAIN}"
        ${SUDO} iptables -t filter -A "${INPUT_CHAIN}" -s "${subnet}" -p tcp --dport "${PROXY_PORT}" -j ACCEPT
        ${SUDO} iptables -t mangle -A "${UDP_PREROUTING_CHAIN}" -s "${subnet}" -p udp -j "${UDP_PROXY_CHAIN}"
    done <<< "${subnet_output}"
}

prepare_udp_proxy() {
    load_no_proxy mangle "${UDP_OUTPUT_CHAIN}" udp
    load_local_routes mangle "${UDP_OUTPUT_CHAIN}" udp
    ${SUDO} iptables -t mangle -A "${UDP_OUTPUT_CHAIN}" -p udp -j MARK --set-mark "${UDP_MARK}"

    load_no_proxy mangle "${UDP_PROXY_CHAIN}" udp
    load_local_routes mangle "${UDP_PROXY_CHAIN}" udp
    ${SUDO} iptables -t mangle -A "${UDP_PROXY_CHAIN}" -p udp -j TPROXY \
        --on-ip 127.0.0.1 --on-port "${UDP_PROXY_PORT}" --tproxy-mark "${UDP_MARK}"

    ${SUDO} iptables -t mangle -A "${UDP_PREROUTING_CHAIN}" -p udp -m mark --mark "${UDP_MARK}" -j "${UDP_PROXY_CHAIN}"
    # Leave host-bound UDP for Docker published ports and local services.
    ${SUDO} iptables -t mangle -A "${UDP_PREROUTING_CHAIN}" -p udp -m addrtype --dst-type LOCAL -j RETURN
    ${SUDO} iptables -t filter -A "${INPUT_CHAIN}" -p udp -m mark --mark "${UDP_MARK}" -j ACCEPT

    if ! ${SUDO} ip -4 rule show | grep -Eq "fwmark ${UDP_MARK}(/0xffffffff)? .*lookup ${UDP_ROUTE_TABLE}([[:space:]]|$)"; then
        ${SUDO} ip -4 rule add fwmark "${UDP_MARK}" lookup "${UDP_ROUTE_TABLE}"
    fi
    ${SUDO} ip -4 route replace local 0.0.0.0/0 dev lo table "${UDP_ROUTE_TABLE}"
}

exclude_proxy_process() {
    ${SUDO} iptables -t nat -A "${PROXY_CHAIN}" -p tcp -m owner --uid-owner "${PROXY_USER}" -j RETURN
    ${SUDO} iptables -t nat -A "${PROXY_CHAIN}" -p tcp -j "${TCP_PROXY_CHAIN}"
    ${SUDO} iptables -t mangle -I "${UDP_OUTPUT_CHAIN}" 1 -p udp -m owner --uid-owner "${PROXY_USER}" -j RETURN
}

if ! id -u "${PROXY_USER}" >/dev/null 2>&1; then
    echo "error: ${PROXY_USER} user not found; run install.sh first" >&2
    exit 1
fi

prepare_proxy_chain
load_no_proxy nat "${TCP_PROXY_CHAIN}" tcp
load_local_routes nat "${TCP_PROXY_CHAIN}" tcp
${SUDO} iptables -t nat -A "${TCP_PROXY_CHAIN}" -p tcp -j REDIRECT --to-ports "${PROXY_PORT}"
prepare_udp_proxy
exclude_proxy_process
load_docker_networks

echo -e "\033[32m iptables OUTPUT chain:\033[0m"
${SUDO} iptables -t nat -nvL OUTPUT --line-numbers
echo -e "\033[32m iptables ${PROXY_CHAIN} chain:\033[0m"
${SUDO} iptables -t nat -nvL "${PROXY_CHAIN}" --line-numbers
echo -e "\033[32m iptables ${TCP_PROXY_CHAIN} chain:\033[0m"
${SUDO} iptables -t nat -nvL "${TCP_PROXY_CHAIN}" --line-numbers
echo -e "\033[32m iptables ${PREROUTING_CHAIN} chain:\033[0m"
${SUDO} iptables -t nat -nvL "${PREROUTING_CHAIN}" --line-numbers
echo -e "\033[32m iptables ${INPUT_CHAIN} chain:\033[0m"
${SUDO} iptables -t filter -nvL "${INPUT_CHAIN}" --line-numbers
echo -e "\033[32m iptables UDP proxy chains:\033[0m"
${SUDO} iptables -t mangle -nvL "${UDP_OUTPUT_CHAIN}" --line-numbers
${SUDO} iptables -t mangle -nvL "${UDP_PREROUTING_CHAIN}" --line-numbers
${SUDO} iptables -t mangle -nvL "${UDP_PROXY_CHAIN}" --line-numbers
