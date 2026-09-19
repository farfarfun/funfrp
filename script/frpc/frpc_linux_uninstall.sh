#!/usr/bin/env bash
set -euo pipefail
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# fonts color
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
GREEN_BG="\033[42;37m"
RED_BG="\033[41;37m"
FONT="\033[0m"
# fonts color

# variable
WORK_PATH=$(dirname "$(readlink -f "$0")")
FRP_NAME=frpc
FRP_PATH=/usr/local/frp

# 停止frpc
systemctl stop "${FRP_NAME}" 2>/dev/null || true
systemctl disable "${FRP_NAME}" 2>/dev/null || true
# 删除frpc
rm -rf "${FRP_PATH}"
# 删除frpc.service
rm -rf "/lib/systemd/system/${FRP_NAME}.service"
systemctl daemon-reload
# 删除本文件
rm -rf "${WORK_PATH}/${FRP_NAME}_linux_uninstall.sh"

echo -e "${GREEN}============================${FONT}"
echo -e "${GREEN}卸载成功,相关文件已清理完毕!${FONT}"
echo -e "${GREEN}============================${FONT}"
