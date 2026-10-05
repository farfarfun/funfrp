#!/bin/sh
# frpc 群晖（DSM 无 systemd）场景下的生命周期管理脚本。
#
# 用法：
#   ./frpc_service.sh start     后台启动（写 PID 与日志到 .run/）
#   ./frpc_service.sh run       前台运行（exec 接管当前进程，便于排查）
#   ./frpc_service.sh stop      停止
#   ./frpc_service.sh restart   重启
#   ./frpc_service.sh status    非交互查询状态，运行中退出码 0，未运行 1
#   ./frpc_service.sh log       跟踪后台日志
#
# 说明：Linux 服务器用 systemd 托管，不需要本脚本；本脚本只服务于
# 没有 systemd 的群晖 DSM 环境。按 SPEC §6 的安装器例外，仅实现
# start/run/stop/restart/status 语义与 .run/ 运行时约定，不带 dev/prod
# 参数——被安装的系统服务只有一套运行环境。
set -eu

# ---- 配置块（集中定义，全脚本复用）----
FRP_NAME=frpc
# 路径基于脚本自身位置解析，不依赖当前工作目录
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
FRP_PATH="${SCRIPT_DIR}"
FRP_BIN="${FRP_PATH}/${FRP_NAME}"
FRP_CONF="${FRP_PATH}/${FRP_NAME}.toml"
RUN_DIR="${FRP_PATH}/.run"
PID_FILE="${RUN_DIR}/${FRP_NAME}.pid"
LOG_FILE="${RUN_DIR}/${FRP_NAME}.log"
# frpc 本身不监听对外端口，端口全部在 frpc.toml 的 [[proxies]] 里配置

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
FONT="\033[0m"

say() {
    printf '%b\n' "$1"
}

die() {
    say "${RED}$1${FONT}" >&2
    exit 1
}

check_installed() {
    [ -x "${FRP_BIN}" ] || die "未找到可执行文件 ${FRP_BIN}，请先执行安装脚本."
    [ -f "${FRP_CONF}" ] || die "未找到配置文件 ${FRP_CONF}."
    if grep -q "CHANGE_ME_" "${FRP_CONF}"; then
        die "配置 ${FRP_CONF} 中仍有 CHANGE_ME_ 占位符，请先填入 serverAddr 与 auth.token."
    fi
}

# 读取 PID 文件并确认那个进程真的还活着，且确实是本脚本托管的 frpc。
# 返回 0 并在 stdout 打印 PID；进程已死（陈旧 PID 文件）返回 1。
running_pid() {
    [ -f "${PID_FILE}" ] || return 1
    pid=$(cat "${PID_FILE}" 2>/dev/null || true)
    case "${pid}" in
        '' | *[!0-9]*) return 1 ;;
    esac
    kill -0 "${pid}" 2>/dev/null || return 1
    # 端口探测只能当旁证，这里改为核对进程名，确认 PID 没有被别的进程复用
    if command -v ps >/dev/null 2>&1; then
        cmd=$(ps -p "${pid}" -o comm= 2>/dev/null || true)
        if [ -n "${cmd}" ]; then
            case "${cmd}" in
                *"${FRP_NAME}"*) ;;
                *) return 1 ;;
            esac
        fi
    fi
    echo "${pid}"
    return 0
}

do_start() {
    if pid=$(running_pid); then
        say "${YELLOW}${FRP_NAME} 已在运行 (PID ${pid})，拒绝重复启动.${FONT}"
        return 0
    fi
    if [ -f "${PID_FILE}" ]; then
        say "${YELLOW}发现陈旧 PID 文件，进程已不存在，清理后继续启动.${FONT}"
        rm -f "${PID_FILE}"
    fi
    check_installed
    mkdir -p "${RUN_DIR}"
    "${FRP_BIN}" -c "${FRP_CONF}" >>"${LOG_FILE}" 2>&1 &
    echo $! >"${PID_FILE}"
    say "${GREEN}${FRP_NAME} 已后台启动 (PID $(cat "${PID_FILE}")).${FONT}"
    say "${GREEN}日志: ${LOG_FILE}${FONT}"
}

do_run() {
    if pid=$(running_pid); then
        die "${FRP_NAME} 已在后台运行 (PID ${pid})，请先 stop 再前台运行."
    fi
    check_installed
    # 前台路径用 exec 接管当前进程，便于被上层进程管理器直接监督
    exec "${FRP_BIN}" -c "${FRP_CONF}"
}

do_stop() {
    if ! pid=$(running_pid); then
        rm -f "${PID_FILE}"
        say "${YELLOW}${FRP_NAME} 未在运行.${FONT}"
        return 0
    fi
    kill "${pid}" 2>/dev/null || true
    i=0
    while [ "${i}" -lt 20 ]; do
        kill -0 "${pid}" 2>/dev/null || break
        sleep 1
        i=$((i + 1))
    done
    if kill -0 "${pid}" 2>/dev/null; then
        say "${YELLOW}优雅停止超时，强制结束 PID ${pid}.${FONT}"
        kill -9 "${pid}" 2>/dev/null || true
    fi
    rm -f "${PID_FILE}"
    say "${GREEN}${FRP_NAME} 已停止.${FONT}"
}

do_status() {
    if pid=$(running_pid); then
        say "${GREEN}${FRP_NAME}: running (PID ${pid})${FONT}"
        say "  配置: ${FRP_CONF}"
        say "  日志: ${LOG_FILE}"
        return 0
    fi
    if [ -f "${PID_FILE}" ]; then
        say "${YELLOW}${FRP_NAME}: stopped (存在陈旧 PID 文件 ${PID_FILE})${FONT}"
    else
        say "${YELLOW}${FRP_NAME}: stopped${FONT}"
    fi
    return 1
}

case "${1:-}" in
    start) do_start ;;
    run) do_run ;;
    stop) do_stop ;;
    restart)
        do_stop
        do_start
        ;;
    status) do_status ;;
    log)
        [ -f "${LOG_FILE}" ] || die "日志文件不存在: ${LOG_FILE}"
        tail -f "${LOG_FILE}"
        ;;
    *)
        say "用法: $0 {start|run|stop|restart|status|log}"
        exit 1
        ;;
esac
