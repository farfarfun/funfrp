#!/usr/bin/env bash
set -euo pipefail
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# 终端颜色
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
GREEN_BG="\033[42;37m"
RED_BG="\033[41;37m"
FONT="\033[0m"
# 终端颜色

# 变量
WORK_PATH=$(dirname "$(readlink -f "$0")")
FRP_NAME=frpc
FRP_PATH=/usr/local/frp

# 停止frpc
systemctl stop "${FRP_NAME}" 2>/dev/null || true
systemctl disable "${FRP_NAME}" 2>/dev/null || true
# 只删除本组件自己的二进制、配置与 service 文件。
# 注意：不要 `rm -rf ${FRP_PATH}` —— frpc 与 frps 共用 /usr/local/frp，
# 整目录删除会连带删掉另一个组件的程序和配置。
rm -f "${FRP_PATH}/${FRP_NAME}" "${FRP_PATH}/${FRP_NAME}.toml"
# 目录为空时才删除目录本身
if [ -d "${FRP_PATH}" ] && [ -z "$(ls -A "${FRP_PATH}" 2>/dev/null)" ]; then
    rmdir "${FRP_PATH}"
fi
# 删除 frpc.service
rm -f "/lib/systemd/system/${FRP_NAME}.service"
systemctl daemon-reload
# 删除本文件
rm -f "${WORK_PATH}/${FRP_NAME}_linux_uninstall.sh"

echo -e "${GREEN}============================${FONT}"
echo -e "${GREEN}卸载成功,相关文件已清理完毕!${FONT}"
echo -e "${GREEN}============================${FONT}"
