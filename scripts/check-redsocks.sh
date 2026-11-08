#!/bin/bash
# process-compose 就绪探针：redsocks 的 TCP 和 UDP 端口都已监听才算就绪。
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

[[ -n "$(ss -Hltn "sport = :${PROXY_PORT}")" ]] || { echo "tcp ${PROXY_PORT} not listening" >&2; exit 1; }
[[ -n "$(ss -Hlun "sport = :${UDP_PROXY_PORT}")" ]] || { echo "udp ${UDP_PROXY_PORT} not listening" >&2; exit 1; }
