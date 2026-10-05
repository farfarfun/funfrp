#!/bin/sh
set -eu

# 终端颜色
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
GREEN_BG="\033[42;37m"
RED_BG="\033[41;37m"
FONT="\033[0m"
# 终端颜色

FRP_NAME=frpc
FRP_PATH=/usr/local/frp
RUN_DIR="${FRP_PATH}/.run"
WORK_PATH=$(dirname "$(readlink -f "$0")")

# 优先走本仓库安装的服务脚本停服（它会按 .run/ 下的 PID 文件精确停止）
if [ -x "${FRP_PATH}/${FRP_NAME}_service.sh" ]; then
    "${FRP_PATH}/${FRP_NAME}_service.sh" stop || true
fi

# 只清理本脚本自己托管的 frpc 进程：优先用 pgrep 按精确进程名匹配；
# 环境没有 pgrep 时，退化为对 ps 输出末字段做整字段匹配（而不是 grep -w
# 的子串匹配），避免误杀命令行里恰好带 frpc 字样的无关进程。
if command -v pgrep >/dev/null 2>&1; then
    for pid in $(pgrep -x "${FRP_NAME}" 2>/dev/null || true); do
        kill -9 "${pid}" 2>/dev/null || true
    done
else
    for pid in $(ps -A | awk -v n="${FRP_NAME}" '$NF == n {print $1}'); do
        kill -9 "${pid}" 2>/dev/null || true
    done
fi

# 只删除本组件自己的二进制、配置、服务脚本与运行时文件。
# 注意：不要 `rm -rf /usr/local/frp` —— frpc 与 frps 共用该目录，
# 整目录删除会连带删掉另一个组件的程序和配置。
rm -f "${FRP_PATH}/${FRP_NAME}" "${FRP_PATH}/${FRP_NAME}.toml" "${FRP_PATH}/${FRP_NAME}_service.sh"
rm -f "${RUN_DIR}/${FRP_NAME}.pid" "${RUN_DIR}/${FRP_NAME}.log"
# 运行时目录与安装目录都只在为空时才删除
if [ -d "${RUN_DIR}" ] && [ -z "$(ls -A "${RUN_DIR}" 2>/dev/null)" ]; then
    rmdir "${RUN_DIR}"
fi
if [ -d "${FRP_PATH}" ] && [ -z "$(ls -A "${FRP_PATH}" 2>/dev/null)" ]; then
    rmdir "${FRP_PATH}"
fi
# 删除本文件
rm -f "${WORK_PATH}/${FRP_NAME}_synology_uninstall.sh"

printf '%b\n' "${GREEN}============================${FONT}"
printf '%b\n' "${GREEN}卸载成功,相关文件已清理完毕!${FONT}"
printf '%b\n' "${GREEN}============================${FONT}"
