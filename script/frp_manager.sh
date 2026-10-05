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

# 变量
WORK_PATH=$(dirname "$(readlink -f "$0")")
FRP_VERSION=0.67.0
FRP_PATH=/usr/local/frp
PROXY_URL="https://ghfast.top/"

# ---- frpc 连接参数（优先级：环境变量 > 占位符）----
# 绝不内置可用的真实 token：未显式提供时写入 CHANGE_ME_* 占位符，
# 并在占位符未被替换前拒绝自动启动服务。
PLACEHOLDER_ADDR="CHANGE_ME_FRPS_SERVER_ADDR"
PLACEHOLDER_TOKEN="CHANGE_ME_FRPS_TOKEN"
SERVER_ADDR="${FRPC_SERVER_ADDR:-$PLACEHOLDER_ADDR}"
SERVER_PORT="${FRPC_SERVER_PORT:-7000}"
AUTH_TOKEN="${FRPC_AUTH_TOKEN:-$PLACEHOLDER_TOKEN}"

# ---- frps 端口与监听地址（集中配置，全脚本复用）----
FRPS_BIND_PORT=7000
FRPS_DASHBOARD_PORT=7500
# dashboard 默认只监听回环，需要公网访问时显式设成 0.0.0.0
FRPS_DASHBOARD_ADDR="${FRPS_DASHBOARD_ADDR:-127.0.0.1}"

# 选择组件
echo -e "${GREEN}========================================${FONT}"
echo -e "${GREEN}  frp 一键管理脚本${FONT}"
echo -e "${GREEN}========================================${FONT}"
echo "请选择组件:"
echo "  1) frpc (客户端)"
echo "  2) frps (服务端)"
read -r -p "请输入 [1-2]: " COMPONENT
case "$COMPONENT" in
    1) FRP_NAME=frpc ;;
    2) FRP_NAME=frps ;;
    *)
        echo -e "${RED}无效选择，退出.${FONT}"
        exit 1
        ;;
esac

# 选择操作
echo ""
echo "请选择操作:"
echo "  1) 安装 (覆盖配置)"
echo "  2) 更新 (仅更新程序，不覆盖配置)"
echo "  3) 卸载"
read -r -p "请输入 [1-3]: " ACTION
case "$ACTION" in
    1) ACTION=install ;;
    2) ACTION=update ;;
    3) ACTION=uninstall ;;
    *)
        echo -e "${RED}无效选择，退出.${FONT}"
        exit 1
        ;;
esac

# 确保依赖
ensure_deps() {
    if type apt-get >/dev/null 2>&1; then
        for cmd in wget curl; do type "$cmd" >/dev/null 2>&1 || apt-get install "$cmd" -y; done
    fi
    if type yum >/dev/null 2>&1; then
        for cmd in wget curl; do type "$cmd" >/dev/null 2>&1 || yum install "$cmd" -y; done
    fi
}

# 检测架构
get_platform() {
    case "$(uname -m)" in
        x86_64)  echo amd64 ;;
        aarch64) echo arm64 ;;
        armv7|armv7l|armhf) echo arm ;;
        *) echo "" ;;
    esac
}

# 选择下载源并下载
download_frp() {
    local file_name="$1"
    local google_http_code proxy_http_code
    google_http_code=$(curl -o /dev/null --connect-timeout 5 --max-time 8 -s --head -w "%{http_code}" "https://www.google.com" || true)
    proxy_http_code=$(curl -o /dev/null --connect-timeout 5 --max-time 8 -s --head -w "%{http_code}" "${PROXY_URL}" || true)
    if [ "$google_http_code" = "200" ]; then
        wget -P "${WORK_PATH}" "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${file_name}.tar.gz" -O "${WORK_PATH}/${file_name}.tar.gz"
    elif [ "$proxy_http_code" = "200" ]; then
        wget -P "${WORK_PATH}" "${PROXY_URL}https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${file_name}.tar.gz" -O "${WORK_PATH}/${file_name}.tar.gz"
    else
        echo -e "${RED}代理不可用，使用官方地址下载${FONT}"
        wget -P "${WORK_PATH}" "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${file_name}.tar.gz" -O "${WORK_PATH}/${file_name}.tar.gz"
    fi
}

# 只停止/清理本脚本管理的 frpc/frps 进程：优先走 systemd 名称匹配，
# 再用 pgrep -x 按精确进程名兜底，避免 `ps -A | grep` 误杀命令行里
# 恰好含有 frpc/frps 字样的无关进程。
kill_process() {
    if systemctl list-unit-files "${FRP_NAME}.service" 2>/dev/null | grep -q "${FRP_NAME}.service"; then
        systemctl stop "${FRP_NAME}" 2>/dev/null || true
    fi
    local pid
    for pid in $(pgrep -x "${FRP_NAME}" 2>/dev/null || true); do
        kill -9 "${pid}" 2>/dev/null || true
    done
}

# 写 systemd 服务
write_systemd_service() {
    cat >"/lib/systemd/system/${FRP_NAME}.service" <<EOF
[Unit]
Description=Frp ${FRP_NAME} Service
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
}

# ---------- 安装 (覆盖配置) ----------
do_install() {
    ensure_deps
    local platform
    platform=$(get_platform)
    if [ -z "$platform" ]; then
        echo -e "${RED}不支持的架构: $(uname -m)${FONT}"
        exit 1
    fi
    local file_name="frp_${FRP_VERSION}_linux_${platform}"
    kill_process
    download_frp "$file_name"
    tar -zxf "${WORK_PATH}/${file_name}.tar.gz" -C "${WORK_PATH}"
    mkdir -p "${FRP_PATH}"
    mv "${WORK_PATH}/${file_name}/${FRP_NAME}" "${FRP_PATH}/"

    # 始终覆盖 toml
    if [ "$FRP_NAME" = "frpc" ]; then
        local random_name
        random_name=$(head -n 10 /dev/urandom | md5sum | head -c 8)
        cat >"${FRP_PATH}/${FRP_NAME}.toml" <<EOF
# serverAddr / serverPort / auth.token 必须与你的 frps 服务端完全一致。
# 安装时可通过环境变量 FRPC_SERVER_ADDR / FRPC_SERVER_PORT / FRPC_AUTH_TOKEN
# 直接写入；未提供时这里留的是占位符，必须手工改完才能启动。
serverAddr = "${SERVER_ADDR}"
serverPort = ${SERVER_PORT}
auth.method = "token"
auth.token = "${AUTH_TOKEN}"

[[proxies]]
name = "web1_${random_name}"
type = "http"
localIP = "192.168.1.2"
localPort = 5000
customDomains = ["nas.yourdomain.com"]

[[proxies]]
name = "web2_${random_name}"
type = "https"
localIP = "192.168.1.2"
localPort = 5001
customDomains = ["nas.yourdomain.com"]

[[proxies]]
name = "tcp1_${random_name}"
type = "tcp"
localIP = "192.168.1.3"
localPort = 22
remotePort = 22222

EOF
    else
        local random_token random_dash_pass
        random_token=$(head -n 10 /dev/urandom | md5sum | head -c 16)
        random_dash_pass=$(head -n 10 /dev/urandom | md5sum | head -c 12)
        cat >"${FRP_PATH}/${FRP_NAME}.toml" <<EOF
bindPort = ${FRPS_BIND_PORT}
auth.method = "token"
auth.token = "${random_token}"

# 如需 HTTP/HTTPS 域名代理可取消下面注释并修改端口
# vhostHTTPPort = 80
# vhostHTTPSPort = 443

# dashboard 默认只监听回环，避免把管理界面直接暴露到公网；
# 确需公网访问时改成 0.0.0.0 并务必配好防火墙。
webServer.addr = "${FRPS_DASHBOARD_ADDR}"
webServer.port = ${FRPS_DASHBOARD_PORT}
webServer.user = "admin"
webServer.password = "${random_dash_pass}"

EOF
        echo -e "${GREEN}frps auth.token 与 dashboard 密码已随机生成，不在终端回显.${FONT}"
        echo -e "${GREEN}如需查看请执行: ${RED}cat ${FRP_PATH}/${FRP_NAME}.toml${FONT}"
    fi

    write_systemd_service
    systemctl daemon-reload
    systemctl enable "${FRP_NAME}"
    # 配置里还留着占位符就不要启动：既避免 frpc 拿着无效 token 不停重连，
    # 也避免「装完即连上某个默认服务端」这种用户没预期的行为。
    if grep -q "CHANGE_ME_" "${FRP_PATH}/${FRP_NAME}.toml"; then
        echo -e "${YELLOW}配置中仍有 CHANGE_ME_ 占位符，服务已注册但${FONT} ${RED}未启动${FONT}${YELLOW}.${FONT}"
        echo -e "${YELLOW}请先填好 serverAddr / auth.token，或安装时指定:${FONT}"
        echo -e "${RED}FRPC_SERVER_ADDR=... FRPC_AUTH_TOKEN=... ./frp_manager.sh${FONT}"
    else
        systemctl start "${FRP_NAME}"
    fi
    rm -rf "${WORK_PATH:?}/${file_name:?}.tar.gz" "${WORK_PATH:?}/${file_name:?}"
    echo -e "${GREEN}安装完成 (已覆盖配置). 编辑: vi ${FRP_PATH}/${FRP_NAME}.toml  重启: systemctl restart ${FRP_NAME}${FONT}"
}

# ---------- 更新 (仅程序，不覆盖配置) ----------
do_update() {
    if [ ! -f "${FRP_PATH}/${FRP_NAME}" ]; then
        echo -e "${RED}未检测到 ${FRP_NAME}，请先执行安装.${FONT}"
        exit 1
    fi
    ensure_deps
    local platform
    platform=$(get_platform)
    if [ -z "$platform" ]; then
        echo -e "${RED}不支持的架构: $(uname -m)${FONT}"
        exit 1
    fi
    local file_name="frp_${FRP_VERSION}_linux_${platform}"
    download_frp "$file_name"
    tar -zxf "${WORK_PATH}/${file_name}.tar.gz" -C "${WORK_PATH}"
    mv "${WORK_PATH}/${file_name}/${FRP_NAME}" "${FRP_PATH}/"
    rm -rf "${WORK_PATH:?}/${file_name:?}.tar.gz" "${WORK_PATH:?}/${file_name:?}"
    systemctl restart "${FRP_NAME}"
    echo -e "${GREEN}更新完成，配置未改动. 已重启 ${FRP_NAME}.${FONT}"
}

# ---------- 卸载 ----------
do_uninstall() {
    if [ ! -f "${FRP_PATH}/${FRP_NAME}" ] && [ ! -f "/lib/systemd/system/${FRP_NAME}.service" ]; then
        echo -e "${YELLOW}未检测到 ${FRP_NAME} 安装.${FONT}"
        exit 0
    fi
    systemctl stop "${FRP_NAME}" 2>/dev/null || true
    systemctl disable "${FRP_NAME}" 2>/dev/null || true
    rm -f "${FRP_PATH}/${FRP_NAME}" "${FRP_PATH}/${FRP_NAME}.toml"
    if [ -z "$(ls -A "${FRP_PATH}" 2>/dev/null)" ]; then
        rm -rf "${FRP_PATH}"
    fi
    rm -f "/lib/systemd/system/${FRP_NAME}.service"
    systemctl daemon-reload
    echo -e "${GREEN}卸载完成.${FONT}"
}

# 执行
case "$ACTION" in
    install)   do_install ;;
    update)    do_update ;;
    uninstall) do_uninstall ;;
esac
