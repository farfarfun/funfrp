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
FRP_VERSION=0.67.0
FRP_PATH=/usr/local/frp
PROXY_URL="https://ghfast.top/"

# ---- 连接参数（优先级：环境变量 > 占位符）----
# 绝不内置可用的真实 token：未显式提供时写入 CHANGE_ME_* 占位符，
# 并在占位符未被替换前拒绝自动启动服务。
PLACEHOLDER_ADDR="CHANGE_ME_FRPS_SERVER_ADDR"
PLACEHOLDER_TOKEN="CHANGE_ME_FRPS_TOKEN"
SERVER_ADDR="${FRPC_SERVER_ADDR:-$PLACEHOLDER_ADDR}"
SERVER_PORT="${FRPC_SERVER_PORT:-7000}"
AUTH_TOKEN="${FRPC_AUTH_TOKEN:-$PLACEHOLDER_TOKEN}"

# 检查 frpc 是否已安装，已安装则退出（仅以二进制为准；.toml 已存在时后面不会覆盖）
if [ -f "/usr/local/frp/${FRP_NAME}" ]; then
    echo -e "${GREEN}=========================================================================${FONT}"
    echo -e "${RED_BG}当前已退出脚本.${FONT}"
    echo -e "${GREEN}检查到服务器已安装${FONT} ${RED}${FRP_NAME}${FONT}"
    echo -e "${GREEN}请先执行卸载脚本或手动删除${FONT} ${RED}/usr/local/frp/${FRP_NAME}${FONT} ${GREEN}后再次执行本脚本.${FONT}"
    echo -e "${GREEN}=========================================================================${FONT}"
    exit 0
fi

# 只清理本脚本自己托管的 frpc 进程：按精确进程名匹配（pgrep -x），
# 不用 `ps -A | grep` 做子串匹配，避免误杀命令行里恰好带 frpc 字样的无关进程。
for pid in $(pgrep -x "${FRP_NAME}" 2>/dev/null || true); do
    kill -9 "${pid}" 2>/dev/null || true
done

# 检查依赖包
if type apt-get >/dev/null 2>&1; then
    if ! type wget >/dev/null 2>&1; then
        apt-get install wget -y
    fi
    if ! type curl >/dev/null 2>&1; then
        apt-get install curl -y
    fi
fi

if type yum >/dev/null 2>&1; then
    if ! type wget >/dev/null 2>&1; then
        yum install wget -y
    fi
    if ! type curl >/dev/null 2>&1; then
        yum install curl -y
    fi
fi

# 检查网络连通性
GOOGLE_HTTP_CODE=$(curl -o /dev/null --connect-timeout 5 --max-time 8 -s --head -w "%{http_code}" "https://www.google.com" || true)
PROXY_HTTP_CODE=$(curl -o /dev/null --connect-timeout 5 --max-time 8 -s --head -w "%{http_code}" "${PROXY_URL}" || true)

# 检查架构
PLATFORM=""
case "$(uname -m)" in
    x86_64) PLATFORM=amd64 ;;
    aarch64) PLATFORM=arm64 ;;
    armv7|armv7l|armhf) PLATFORM=arm ;;
esac
if [ -z "$PLATFORM" ]; then
    echo -e "${RED}不支持的架构: $(uname -m)${FONT}"
    exit 1
fi

FILE_NAME="frp_${FRP_VERSION}_linux_${PLATFORM}"

# 下载
if [ "$GOOGLE_HTTP_CODE" = "200" ]; then
    wget -P "${WORK_PATH}" "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILE_NAME}.tar.gz" -O "${WORK_PATH}/${FILE_NAME}.tar.gz"
elif [ "$PROXY_HTTP_CODE" = "200" ]; then
    wget -P "${WORK_PATH}" "${PROXY_URL}https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILE_NAME}.tar.gz" -O "${WORK_PATH}/${FILE_NAME}.tar.gz"
else
    echo -e "${RED}检测 GitHub Proxy 代理失效 开始使用官方地址下载${FONT}"
    wget -P "${WORK_PATH}" "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILE_NAME}.tar.gz" -O "${WORK_PATH}/${FILE_NAME}.tar.gz"
fi
tar -zxf "${WORK_PATH}/${FILE_NAME}.tar.gz" -C "${WORK_PATH}"

mkdir -p "${FRP_PATH}"
mv "${WORK_PATH}/${FILE_NAME}/${FRP_NAME}" "${FRP_PATH}/"

# 生成 frpc.toml 配置，若已存在则不覆盖
TOML_CREATED=0
if [ ! -f "${FRP_PATH}/${FRP_NAME}.toml" ]; then
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
    TOML_CREATED=1
fi

# 配置 systemd 服务
cat >"/lib/systemd/system/${FRP_NAME}.service" <<EOF
[Unit]
Description=Frp Server Service
After=network.target syslog.target
Wants=network.target

[Service]
Type=simple
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/frp/${FRP_NAME} -c /usr/local/frp/${FRP_NAME}.toml

[Install]
WantedBy=multi-user.target
EOF

# 完成安装
systemctl daemon-reload
systemctl enable "${FRP_NAME}"

# 配置里还留着占位符就不要启动：否则 frpc 会拿着无效 token 不停重连，
# 更重要的是避免「装完即连上某个默认服务端」这种用户没预期的行为。
NEEDS_CONFIG=0
if grep -q "CHANGE_ME_" "${FRP_PATH}/${FRP_NAME}.toml"; then
    NEEDS_CONFIG=1
else
    systemctl start "${FRP_NAME}"
fi

# 清理临时文件
rm -rf "${WORK_PATH:?}/${FILE_NAME:?}.tar.gz" "${WORK_PATH:?}/${FILE_NAME:?}"
rm -f "${WORK_PATH}/${FRP_NAME}_linux_install.sh"

echo -e "${GREEN}====================================================================${FONT}"
echo -e "${GREEN}安装成功!${FONT}"
if [ "$TOML_CREATED" = "1" ]; then
    echo -e "${GREEN}已生成 ${FRP_NAME}.toml.${FONT}"
fi
if [ "$NEEDS_CONFIG" = "1" ]; then
    echo -e "${YELLOW}配置中仍有 CHANGE_ME_ 占位符，服务已注册但${FONT} ${RED}未启动${FONT}${YELLOW}.${FONT}"
    echo -e "${YELLOW}请先填好 serverAddr / auth.token 及代理配置，再手动启动.${FONT}"
    echo -e "${GREEN}也可在安装时直接指定: ${RED}FRPC_SERVER_ADDR=... FRPC_AUTH_TOKEN=... ./${FRP_NAME}_linux_install.sh${FONT}"
fi
echo -e "${GREEN}编辑配置: ${RED}vi /usr/local/frp/${FRP_NAME}.toml${FONT}"
echo -e "${GREEN}启动/重启: ${RED}sudo systemctl restart ${FRP_NAME}${FONT}"
echo -e "${GREEN}查看状态: ${RED}sudo systemctl status ${FRP_NAME}${FONT}"
echo -e "${GREEN}====================================================================${FONT}"
