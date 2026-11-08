#!/bin/bash
# 透明代理 iptables 规则管理。
#   ./proxyall.sh up      建立/重建全部 REDSOCKS_* 规则（可重复执行）
#   ./proxyall.sh down    清理全部规则、策略路由（可重复执行）
#   ./proxyall.sh status  打印当前规则
#   ./proxyall.sh run     up 后常驻，收到 SIGTERM/SIGINT 或退出时自动 down（供 process-compose 使用）
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/scripts/env.sh"

PROXY_CHAIN="REDSOCKS_OUTPUT"
TCP_PROXY_CHAIN="REDSOCKS_TCP"
PREROUTING_CHAIN="REDSOCKS_PREROUTING"
INPUT_CHAIN="REDSOCKS_INPUT"
UDP_OUTPUT_CHAIN="REDSOCKS_UDP_OUTPUT"
UDP_PREROUTING_CHAIN="REDSOCKS_UDP_PREROUTING"
UDP_PROXY_CHAIN="REDSOCKS_UDP_PROXY"
UDP_MARK="0x2333"
PROXY_BYPASS_MARK="6666"
UDP_ROUTE_TABLE="10053"

ensure_chain() {
    local table="$1"
    local chain="$2"

    if ! iptables -t "${table}" -nL "${chain}" >/dev/null 2>&1; then
        iptables -t "${table}" -N "${chain}"
    fi
    iptables -t "${table}" -F "${chain}"
}

prepare_proxy_chain() {
    ensure_chain nat "${PROXY_CHAIN}"
    ensure_chain nat "${TCP_PROXY_CHAIN}"
    ensure_chain nat "${PREROUTING_CHAIN}"
    ensure_chain filter "${INPUT_CHAIN}"
    ensure_chain mangle "${UDP_OUTPUT_CHAIN}"
    ensure_chain mangle "${UDP_PREROUTING_CHAIN}"
    ensure_chain mangle "${UDP_PROXY_CHAIN}"

    # 本机只放行被重定向的连接；Docker 的必要端口在 load_docker_networks 中精确授权。
    iptables -t filter -A "${INPUT_CHAIN}" -i lo -p tcp --dport "${PROXY_PORT}" \
        -m conntrack --ctstate DNAT -j ACCEPT

    if ! iptables -t nat -C OUTPUT -p tcp -j "${PROXY_CHAIN}" >/dev/null 2>&1; then
        iptables -t nat -A OUTPUT -p tcp -j "${PROXY_CHAIN}"
    fi
    while iptables -t nat -C PREROUTING -p tcp -j "${PREROUTING_CHAIN}" >/dev/null 2>&1; do
        iptables -t nat -D PREROUTING -p tcp -j "${PREROUTING_CHAIN}"
    done
    # Preserve existing destination NAT, including Docker published ports.
    iptables -t nat -A PREROUTING -p tcp -j "${PREROUTING_CHAIN}"
    if ! iptables -t filter -C INPUT -p tcp -j "${INPUT_CHAIN}" >/dev/null 2>&1; then
        iptables -t filter -I INPUT 1 -p tcp -j "${INPUT_CHAIN}"
    fi
    if ! iptables -t filter -C INPUT -p udp -j "${INPUT_CHAIN}" >/dev/null 2>&1; then
        iptables -t filter -I INPUT 1 -p udp -j "${INPUT_CHAIN}"
    fi
    if ! iptables -t mangle -C OUTPUT -p udp -j "${UDP_OUTPUT_CHAIN}" >/dev/null 2>&1; then
        iptables -t mangle -A OUTPUT -p udp -j "${UDP_OUTPUT_CHAIN}"
    fi
    while iptables -t mangle -C PREROUTING -p udp -j "${UDP_PREROUTING_CHAIN}" >/dev/null 2>&1; do
        iptables -t mangle -D PREROUTING -p udp -j "${UDP_PREROUTING_CHAIN}"
    done
    iptables -t mangle -A PREROUTING -p udp -j "${UDP_PREROUTING_CHAIN}"
}

load_no_proxy() {
    local table="$1"
    local chain="$2"
    local protocol="$3"

    if [[ ! -f "${NO_PROXY_FILE}" ]]; then
        echo "error: ${NO_PROXY_FILE} not found; run scripts/render-config.sh first" >&2
        return 1
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
        echo -e "\033[32m no-proxy: ${line}\033[0m"
        iptables -t "${table}" -A "${chain}" -p "${protocol}" -d "${line}" -j RETURN
    done < "${NO_PROXY_FILE}"
}

load_local_routes() {
    local table="$1"
    local chain="$2"
    local protocol="$3"

    while IFS= read -r subroute; do
        [[ -z "${subroute}" ]] && continue
        iptables -t "${table}" -A "${chain}" -p "${protocol}" -d "${subroute}" -j RETURN
    done < <(ip -o route show | awk '{print $1}' | grep -v '^default$')
}

load_docker_networks() {
    local network_ids
    local subnet_output
    local subnet
    local bridge_interface
    local -a network_id_list

    if ! command -v docker >/dev/null 2>&1; then
        echo "warn: docker command not found, skipping Docker bridge networks"
        return 0
    fi
    if ! network_ids=$(docker network ls --filter driver=bridge --quiet 2>/dev/null); then
        echo "warn: cannot query Docker networks, skipping Docker bridge networks"
        return 0
    fi
    [[ -z "${network_ids}" ]] && return 0
    mapfile -t network_id_list <<< "${network_ids}"
    if ! subnet_output=$(docker network inspect --format '{{range .IPAM.Config}}{{if .Subnet}}{{println .Subnet}}{{end}}{{end}}' "${network_id_list[@]}" 2>/dev/null); then
        echo "warn: cannot inspect Docker networks, skipping Docker bridge networks"
        return 0
    fi

    while IFS= read -r subnet; do
        [[ -z "${subnet}" || "${subnet}" == *:* ]] && continue
        bridge_interface=$(ip -o route show to "${subnet}" | awk '$2 == "dev" { print $3; exit }')
        if [[ -z "${bridge_interface}" || ! -d "/sys/class/net/${bridge_interface}/bridge" ]]; then
            echo "error: cannot identify Docker bridge interface for ${subnet}; refusing broad INPUT allow" >&2
            return 1
        fi
        echo -e "\033[32m docker-proxy: ${subnet}\033[0m"
        iptables -t nat -A "${PREROUTING_CHAIN}" -s "${subnet}" -p tcp -j "${TCP_PROXY_CHAIN}"
        # 仅授权网桥接口、源网段和确经 DNAT 的代理连接，不将整个网段加入 ipset。
        iptables -t filter -A "${INPUT_CHAIN}" -i "${bridge_interface}" -s "${subnet}" \
            -p tcp --dport "${PROXY_PORT}" -m conntrack --ctstate DNAT -j ACCEPT
        # Docker 客户端可能自动注入本机 HTTP/SOCKS 代理；只开放该地址的这两个端口。
        iptables -t filter -A "${INPUT_CHAIN}" -i "${bridge_interface}" -s "${subnet}" \
            -d "${SOCK_SERVER}" -p tcp -m multiport --dports 1080,7070 -j ACCEPT
        iptables -t mangle -A "${UDP_PREROUTING_CHAIN}" -s "${subnet}" -p udp -j "${UDP_PROXY_CHAIN}"
    done <<< "${subnet_output}"
}

prepare_udp_proxy() {
    load_no_proxy mangle "${UDP_OUTPUT_CHAIN}" udp
    load_local_routes mangle "${UDP_OUTPUT_CHAIN}" udp
    iptables -t mangle -A "${UDP_OUTPUT_CHAIN}" -p udp -j MARK --set-mark "${UDP_MARK}"

    load_no_proxy mangle "${UDP_PROXY_CHAIN}" udp
    load_local_routes mangle "${UDP_PROXY_CHAIN}" udp
    iptables -t mangle -A "${UDP_PROXY_CHAIN}" -p udp -j TPROXY \
        --on-ip 127.0.0.1 --on-port "${UDP_PROXY_PORT}" --tproxy-mark "${UDP_MARK}"

    iptables -t mangle -A "${UDP_PREROUTING_CHAIN}" -p udp -m mark --mark "${UDP_MARK}" -j "${UDP_PROXY_CHAIN}"
    # Leave host-bound UDP for Docker published ports and local services.
    iptables -t mangle -A "${UDP_PREROUTING_CHAIN}" -p udp -m addrtype --dst-type LOCAL -j RETURN
    # TPROXY 保留原始目标端口，不能按监听端口匹配；只放行回环送回的本机 UDP。
    iptables -t filter -A "${INPUT_CHAIN}" -i lo -p udp -m mark --mark "${UDP_MARK}" -j ACCEPT

    if ! ip -4 rule show | grep -Eq "fwmark ${UDP_MARK}(/0xffffffff)? .*lookup ${UDP_ROUTE_TABLE}([[:space:]]|$)"; then
        ip -4 rule add fwmark "${UDP_MARK}" lookup "${UDP_ROUTE_TABLE}"
    fi
    ip -4 route replace local 0.0.0.0/0 dev lo table "${UDP_ROUTE_TABLE}"
}

exclude_proxy_process() {
    # Mihomo 出站使用 routing-mark: 6666，避免上游代理再次进入 redsocks。
    iptables -t nat -A "${PROXY_CHAIN}" -p tcp -m mark --mark "${PROXY_BYPASS_MARK}" -j RETURN
    iptables -t nat -A "${PROXY_CHAIN}" -p tcp -m owner --gid-owner "${PROXY_GROUP}" -j RETURN
    iptables -t nat -A "${PROXY_CHAIN}" -p tcp -j "${TCP_PROXY_CHAIN}"
    iptables -t mangle -I "${UDP_OUTPUT_CHAIN}" 1 -p udp -m owner --gid-owner "${PROXY_GROUP}" -j RETURN
    # 必须先绕过，不能让后续 MARK 将 Mihomo 的标记覆盖为 UDP_MARK。
    iptables -t mangle -I "${UDP_OUTPUT_CHAIN}" 1 -p udp -m mark --mark "${PROXY_BYPASS_MARK}" -j RETURN
}

# 删除内置链中所有指向自定义链的引用（可能被重复添加过），再清空并删除自定义链。
delete_jump() {
    local table="$1"
    local builtin="$2"
    shift 2

    while iptables -t "${table}" -C "${builtin}" "$@" >/dev/null 2>&1; do
        iptables -t "${table}" -D "${builtin}" "$@"
    done
}

delete_chain() {
    local table="$1"
    local chain="$2"

    if iptables -t "${table}" -nL "${chain}" >/dev/null 2>&1; then
        iptables -t "${table}" -F "${chain}"
        iptables -t "${table}" -X "${chain}"
    fi
}

proxy_down() {
    # 清理要尽量做完：单条删除失败不能中断后续步骤（也会在 EXIT trap 中调用）。
    local -
    set +e

    delete_jump nat OUTPUT -p tcp -j "${PROXY_CHAIN}"
    delete_jump nat PREROUTING -p tcp -j "${PREROUTING_CHAIN}"
    delete_jump filter INPUT -p tcp -j "${INPUT_CHAIN}"
    delete_jump filter INPUT -p udp -j "${INPUT_CHAIN}"
    delete_jump mangle OUTPUT -p udp -j "${UDP_OUTPUT_CHAIN}"
    delete_jump mangle PREROUTING -p udp -j "${UDP_PREROUTING_CHAIN}"

    # REDSOCKS_OUTPUT / REDSOCKS_PREROUTING 引用 REDSOCKS_TCP，需先删除它们。
    delete_chain nat "${PROXY_CHAIN}"
    delete_chain nat "${PREROUTING_CHAIN}"
    delete_chain nat "${TCP_PROXY_CHAIN}"
    delete_chain filter "${INPUT_CHAIN}"
    delete_chain mangle "${UDP_OUTPUT_CHAIN}"
    delete_chain mangle "${UDP_PREROUTING_CHAIN}"
    delete_chain mangle "${UDP_PROXY_CHAIN}"

    while ip -4 rule del fwmark "${UDP_MARK}" lookup "${UDP_ROUTE_TABLE}" 2>/dev/null; do :; done
    ip -4 route del local 0.0.0.0/0 dev lo table "${UDP_ROUTE_TABLE}" 2>/dev/null || true
    echo "proxy rules removed"
}

proxy_up() {
    prepare_proxy_chain
    # 先建立出站绕过，再启用接管，避免启用过程短暂接管 Mihomo 和 redsocks 自身流量。
    exclude_proxy_process
    load_no_proxy nat "${TCP_PROXY_CHAIN}" tcp
    load_local_routes nat "${TCP_PROXY_CHAIN}" tcp
    iptables -t nat -A "${TCP_PROXY_CHAIN}" -p tcp -j REDIRECT --to-ports "${PROXY_PORT}"
    prepare_udp_proxy
    load_docker_networks
}

proxy_status() {
    echo -e "\033[32m iptables OUTPUT chain:\033[0m"
    iptables -t nat -nvL OUTPUT --line-numbers
    echo -e "\033[32m iptables ${PROXY_CHAIN} chain:\033[0m"
    iptables -t nat -nvL "${PROXY_CHAIN}" --line-numbers
    echo -e "\033[32m iptables ${TCP_PROXY_CHAIN} chain:\033[0m"
    iptables -t nat -nvL "${TCP_PROXY_CHAIN}" --line-numbers
    echo -e "\033[32m iptables ${PREROUTING_CHAIN} chain:\033[0m"
    iptables -t nat -nvL "${PREROUTING_CHAIN}" --line-numbers
    echo -e "\033[32m iptables ${INPUT_CHAIN} chain:\033[0m"
    iptables -t filter -nvL "${INPUT_CHAIN}" --line-numbers
    echo -e "\033[32m iptables UDP proxy chains:\033[0m"
    iptables -t mangle -nvL "${UDP_OUTPUT_CHAIN}" --line-numbers
    iptables -t mangle -nvL "${UDP_PREROUTING_CHAIN}" --line-numbers
    iptables -t mangle -nvL "${UDP_PROXY_CHAIN}" --line-numbers
}

on_run_exit() {
    set +e
    trap - EXIT
    # process-compose 停止时会向整个进程组发信号，sleep 可能已先退出，kill 失败是正常的。
    if [[ -n "${SLEEP_PID}" ]]; then
        kill "${SLEEP_PID}" 2>/dev/null
    fi
    proxy_down
}

proxy_run() {
    SLEEP_PID=""

    # 任何退出路径（包括 up 中途失败）都清理规则，避免流量被重定向到已停止的 redsocks。
    trap on_run_exit EXIT
    trap 'exit 0' TERM INT HUP

    proxy_up
    proxy_status
    echo "proxy rules active; waiting for stop signal"
    sleep infinity &
    SLEEP_PID=$!
    wait "${SLEEP_PID}"
}

require_root
case "${1:-up}" in
    up)
        require_config
        proxy_up
        proxy_status
        ;;
    down)
        proxy_down
        ;;
    status)
        proxy_status
        ;;
    run)
        require_config
        proxy_run
        ;;
    *)
        echo "usage: $0 [up|down|status|run]" >&2
        exit 2
        ;;
esac
