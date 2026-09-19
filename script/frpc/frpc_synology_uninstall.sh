#!/bin/sh
set -eu

# fonts color
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
GREEN_BG="\033[42;37m"
RED_BG="\033[41;37m"
FONT="\033[0m"
# fonts color

FRP_NAME=frpc
WORK_PATH=$(dirname "$(readlink -f "$0")")

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

# 删除frp
rm -rf /usr/local/frp
# 删除本文件
rm -rf "${WORK_PATH}/${FRP_NAME}_synology_uninstall.sh"

echo -e "${GREEN}============================${FONT}"
echo -e "${GREEN}卸载成功,相关文件已清理完毕!${FONT}"
echo -e "${GREEN}============================${FONT}"
