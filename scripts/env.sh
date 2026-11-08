# shellcheck shell=bash
# 公共环境：被其他脚本 source。加载仓库根目录的 .env，补默认值并校验。
# process-compose 已经把 .env 注入环境，这里再加载一次是为了让脚本也能单独执行（例如手动 ./proxyall.sh down）。

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="${REPO_DIR}/run"

if [[ -f "${REPO_DIR}/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${REPO_DIR}/.env"
    set +a
fi

SOCK_SERVER="${SOCK_SERVER:-}"
SOCK_PORT="${SOCK_PORT:-}"
PROXY_PORT="${PROXY_PORT:-12345}"
UDP_PROXY_PORT="${UDP_PROXY_PORT:-10053}"
PROXY_GROUP="${PROXY_GROUP:-redsocks}"

REDSOCKS_BIN="${REPO_DIR}/redsocks_$(uname -m)"
REDSOCKS_CONF="${RUN_DIR}/redsocks.conf"
NO_PROXY_FILE="${RUN_DIR}/NoProxy.txt"

require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        echo "error: must run as root" >&2
        exit 1
    fi
}

require_config() {
    local name
    for name in SOCK_SERVER SOCK_PORT PROXY_PORT UDP_PROXY_PORT PROXY_GROUP; do
        if [[ -z "${!name}" ]]; then
            echo "error: ${name} is empty; edit ${REPO_DIR}/.env (see .env.example)" >&2
            exit 1
        fi
    done
    for name in SOCK_PORT PROXY_PORT UDP_PROXY_PORT; do
        if [[ ! "${!name}" =~ ^[0-9]+$ ]]; then
            echo "error: ${name}=${!name} is not a port number" >&2
            exit 1
        fi
    done
    if ! getent group "${PROXY_GROUP}" >/dev/null; then
        echo "error: group ${PROXY_GROUP} not found; run ./install.sh first" >&2
        exit 1
    fi
}
