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

# variable
WORK_PATH=$(dirname "$(readlink -f "$0")")
FRP_VERSION=0.67.0
FRP_PATH=/usr/local/frp
PROXY_URL="https://ghfast.top/"

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
# 默认 serverAddr/auth.token 指向 freefrp.net 公开发布的免费测试中转服务
# （公开体验 token，见 https://freefrp.net/docs），仅用于快速验证连通性，
# 生产环境请替换为你自己的 frps 地址与随机 token。
serverAddr = "frp.freefrp.net"
serverPort = 7000
auth.method = "token"
auth.token = "freefrp.net"

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
bindPort = 7000
auth.method = "token"
auth.token = "${random_token}"

# vhostHTTPPort = 80
# vhostHTTPSPort = 443
webServer.addr = "0.0.0.0"
webServer.port = 7500
webServer.user = "admin"
webServer.password = "${random_dash_pass}"

EOF
        echo -e "${GREEN}frps auth.token 与 dashboard 密码已随机生成，不在终端回显.${FONT}"
        echo -e "${GREEN}如需查看请执行: ${RED}cat ${FRP_PATH}/${FRP_NAME}.toml${FONT}"
    fi

    write_systemd_service
    systemctl daemon-reload
    systemctl enable "${FRP_NAME}"
    systemctl start "${FRP_NAME}"
    rm -rf "${WORK_PATH}/${file_name}.tar.gz" "${WORK_PATH}/${file_name}"
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
    rm -rf "${WORK_PATH}/${file_name}.tar.gz" "${WORK_PATH}/${file_name}"
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
