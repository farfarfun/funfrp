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

# 变量
WORK_PATH=$(dirname "$(readlink -f "$0")")
FRP_NAME=frpc
FRP_VERSION=0.67.0
FRP_PATH=/usr/local/frp
RUN_DIR="${FRP_PATH}/.run"
SERVICE_SCRIPT="${FRP_PATH}/${FRP_NAME}_service.sh"
PROXY_URL="https://ghfast.top/"
RAW_BASE="https://raw.githubusercontent.com/farfarfun/funfrp/master"

# ---- 连接参数（优先级：环境变量 > 占位符）----
# 绝不内置可用的真实 token：未显式提供时写入 CHANGE_ME_* 占位符，
# 必须手工改完才能启动。
PLACEHOLDER_ADDR="CHANGE_ME_FRPS_SERVER_ADDR"
PLACEHOLDER_TOKEN="CHANGE_ME_FRPS_TOKEN"
SERVER_ADDR="${FRPC_SERVER_ADDR:-$PLACEHOLDER_ADDR}"
SERVER_PORT="${FRPC_SERVER_PORT:-7000}"
AUTH_TOKEN="${FRPC_AUTH_TOKEN:-$PLACEHOLDER_TOKEN}"

# 检查 frpc 是否已安装，已安装则退出
if [ -f "/usr/local/frp/${FRP_NAME}" ] || [ -f "/usr/local/frp/${FRP_NAME}.toml" ] || [ -f "/lib/systemd/system/${FRP_NAME}.service" ]; then
    printf '%b\n' "${GREEN}=========================================================================${FONT}"
    printf '%b\n' "${RED_BG}当前已退出脚本.${FONT}"
    printf '%b\n' "${GREEN}检查到服务器已安装${FONT} ${RED}${FRP_NAME}${FONT}"
    printf '%b\n' "${GREEN}请手动确认和删除${FONT} ${RED}/usr/local/frp/${FONT} ${GREEN}目录下的${FONT} ${RED}${FRP_NAME}${FONT} ${GREEN}和${FONT} ${RED}/${FRP_NAME}.toml${FONT} ${GREEN}文件以及${FONT} ${RED}/lib/systemd/system/${FRP_NAME}.service${FONT} ${GREEN}文件,再次执行本脚本.${FONT}"
    printf '%b\n' "${GREEN}参考命令如下:${FONT}"
    printf '%b\n' "${RED}rm -rf /usr/local/frp/${FRP_NAME}${FONT}"
    printf '%b\n' "${RED}rm -rf /usr/local/frp/${FRP_NAME}.toml${FONT}"
    printf '%b\n' "${RED}rm -rf /lib/systemd/system/${FRP_NAME}.service${FONT}"
    printf '%b\n' "${GREEN}=========================================================================${FONT}"
    exit 0
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

# 检查网络连通性
GOOGLE_HTTP_CODE=$(curl -o /dev/null --connect-timeout 5 --max-time 8 -s --head -w "%{http_code}" "https://www.google.com" || true)
PROXY_HTTP_CODE=$(curl -o /dev/null --connect-timeout 5 --max-time 8 -s --head -w "%{http_code}" "${PROXY_URL}" || true)

# 检查架构
if [ "$(uname -m)" = "x86_64" ]; then
    PLATFORM=amd64
elif [ "$(uname -m)" = "aarch64" ]; then
    PLATFORM=arm64
else
    PLATFORM=arm
fi

FILE_NAME="frp_${FRP_VERSION}_linux_${PLATFORM}"

# 下载
if [ "$GOOGLE_HTTP_CODE" = "200" ]; then
    wget -P "${WORK_PATH}" "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILE_NAME}.tar.gz" -O "${WORK_PATH}/${FILE_NAME}.tar.gz"
else
    if [ "$PROXY_HTTP_CODE" = "200" ]; then
        wget -P "${WORK_PATH}" "${PROXY_URL}https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILE_NAME}.tar.gz" -O "${WORK_PATH}/${FILE_NAME}.tar.gz"
    else
        printf '%b\n' "${RED}检测 GitHub Proxy 代理失效 开始使用官方下载地址下载${FONT}"
        wget -P "${WORK_PATH}" "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILE_NAME}.tar.gz" -O "${WORK_PATH}/${FILE_NAME}.tar.gz"
    fi
fi
tar -zxf "${WORK_PATH}/${FILE_NAME}.tar.gz" -C "${WORK_PATH}"
mkdir -p "${FRP_PATH}"
mv "${WORK_PATH}/${FILE_NAME}/${FRP_NAME}" "${FRP_PATH}/"

# 生成 frpc.toml 配置
RANDOM_NAME=$(head -n 10 /dev/urandom | md5sum | head -c 8)
cat >"${FRP_PATH}/${FRP_NAME}.toml" <<EOF
# serverAddr / serverPort / auth.token 必须与你的 frps 服务端完全一致。
# 安装时可通过环境变量 FRPC_SERVER_ADDR / FRPC_SERVER_PORT / FRPC_AUTH_TOKEN
# 直接写入；未提供时这里留的是占位符，必须手工改完才能启动。
serverAddr = "${SERVER_ADDR}"
serverPort = ${SERVER_PORT}
auth.method = "token"
auth.token = "${AUTH_TOKEN}"

[[proxies]]
name = "web1_${RANDOM_NAME}"
type = "http"
localIP = "192.168.1.2"
localPort = 5000
customDomains = ["nas.yourdomain.com"]

[[proxies]]
name = "web2_${RANDOM_NAME}"
type = "https"
localIP = "192.168.1.2"
localPort = 5001
customDomains = ["nas.yourdomain.com"]

[[proxies]]
name = "tcp1_${RANDOM_NAME}"
type = "tcp"
localIP = "192.168.1.3"
localPort = 22
remotePort = 22222

EOF

# 安装生命周期管理脚本（群晖 DSM 没有 systemd，用它提供 start/run/stop/restart/status）
mkdir -p "${RUN_DIR}"
if [ -f "${WORK_PATH}/${FRP_NAME}_synology_service.sh" ]; then
    cp "${WORK_PATH}/${FRP_NAME}_synology_service.sh" "${SERVICE_SCRIPT}"
elif [ "$GOOGLE_HTTP_CODE" = "200" ]; then
    wget "${RAW_BASE}/script/frpc/${FRP_NAME}_synology_service.sh" -O "${SERVICE_SCRIPT}"
else
    wget "${PROXY_URL}${RAW_BASE}/script/frpc/${FRP_NAME}_synology_service.sh" -O "${SERVICE_SCRIPT}"
fi
chmod +x "${SERVICE_SCRIPT}"

# 清理临时文件
rm -rf "${WORK_PATH:?}/${FILE_NAME:?}.tar.gz" "${WORK_PATH:?}/${FILE_NAME:?}"
rm -f "${WORK_PATH}/${FRP_NAME}_synology_install.sh"

# 完成安装,手动修改frpc.toml并启动服务.
printf '%b\n' "${GREEN}=======================================================================${FONT}"
printf '%b\n' "${GREEN}安装成功. 配置中的 CHANGE_ME_ 占位符必须先改掉才能启动:${FONT}"
printf '%b\n' "${RED}vi ${FRP_PATH}/${FRP_NAME}.toml${FONT}"
printf '%b\n' "${GREEN}改完后用服务脚本管理（PID 与日志在 ${RUN_DIR}/）:${FONT}"
printf '%b\n' "${RED}${SERVICE_SCRIPT} start${FONT}    ${GREEN}# 后台启动${FONT}"
printf '%b\n' "${RED}${SERVICE_SCRIPT} run${FONT}      ${GREEN}# 前台运行，便于排查${FONT}"
printf '%b\n' "${RED}${SERVICE_SCRIPT} status${FONT}   ${GREEN}# 查看状态${FONT}"
printf '%b\n' "${RED}${SERVICE_SCRIPT} restart${FONT}  ${GREEN}# 重启${FONT}"
printf '%b\n' "${RED}${SERVICE_SCRIPT} stop${FONT}     ${GREEN}# 停止${FONT}"
printf '%b\n' "${GREEN}安装时也可直接指定: FRPC_SERVER_ADDR=... FRPC_AUTH_TOKEN=... ./${FRP_NAME}_synology_install.sh${FONT}"
printf '%b\n' "${GREEN}=======================================================================${FONT}"
