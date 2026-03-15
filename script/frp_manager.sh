#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# fonts color
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"

# variable
WORK_PATH=$(dirname $(readlink -f $0))
FRP_VERSION=0.67.0
FRP_PATH=/usr/local/frp
PROXY_URL="https://ghfast.top/"

# 选择组件
echo -e "${Green}========================================${Font}"
echo -e "${Green}  frp 一键管理脚本${Font}"
echo -e "${Green}========================================${Font}"
echo "请选择组件:"
echo "  1) frpc (客户端)"
echo "  2) frps (服务端)"
read -p "请输入 [1-2]: " COMPONENT
case "$COMPONENT" in
    1) FRP_NAME=frpc ;;
    2) FRP_NAME=frps ;;
    *)
        echo -e "${Red}无效选择，退出.${Font}"
        exit 1
        ;;
esac

# 选择操作
echo ""
echo "请选择操作:"
echo "  1) 安装 (覆盖配置)"
echo "  2) 更新 (仅更新程序，不覆盖配置)"
echo "  3) 卸载"
read -p "请输入 [1-3]: " ACTION
case "$ACTION" in
    1) ACTION=install ;;
    2) ACTION=update ;;
    3) ACTION=uninstall ;;
    *)
        echo -e "${Red}无效选择，退出.${Font}"
        exit 1
        ;;
esac

# 确保依赖
ensure_deps() {
    if type apt-get >/dev/null 2>&1; then
        for cmd in wget curl; do type $cmd >/dev/null 2>&1 || apt-get install $cmd -y; done
    fi
    if type yum >/dev/null 2>&1; then
        for cmd in wget curl; do type $cmd >/dev/null 2>&1 || yum install $cmd -y; done
    fi
}

# 检测架构
get_platform() {
    case $(uname -m) in
        x86_64)  echo amd64 ;;
        aarch64) echo arm64 ;;
        armv7|armv7l|armhf) echo arm ;;
        *) echo "" ;;
    esac
}

# 选择下载源并下载
download_frp() {
    local file_name=$1
    GOOGLE_HTTP_CODE=$(curl -o /dev/null --connect-timeout 5 --max-time 8 -s --head -w "%{http_code}" "https://www.google.com")
    PROXY_HTTP_CODE=$(curl -o /dev/null --connect-timeout 5 --max-time 8 -s --head -w "%{http_code}" "${PROXY_URL}")
    if [ "$GOOGLE_HTTP_CODE" = "200" ]; then
        wget -P "${WORK_PATH}" "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${file_name}.tar.gz" -O "${WORK_PATH}/${file_name}.tar.gz"
    else
        if [ "$PROXY_HTTP_CODE" = "200" ]; then
            wget -P "${WORK_PATH}" "${PROXY_URL}https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${file_name}.tar.gz" -O "${WORK_PATH}/${file_name}.tar.gz"
        else
            echo -e "${Red}代理不可用，使用官方地址下载${Font}"
            wget -P "${WORK_PATH}" "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${file_name}.tar.gz" -O "${WORK_PATH}/${file_name}.tar.gz"
        fi
    fi
}

# 清理已存在的进程
kill_process() {
    while ! test -z "$(ps -A | grep -w ${FRP_NAME})"; do
        local pid=$(ps -A | grep -w ${FRP_NAME} | awk 'NR==1 {print $1}')
        kill -9 $pid 2>/dev/null
    done
}

# 写 systemd 服务
write_systemd_service() {
    cat >/lib/systemd/system/${FRP_NAME}.service <<EOF
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
    PLATFORM=$(get_platform)
    if [ -z "$PLATFORM" ]; then
        echo -e "${Red}不支持的架构: $(uname -m)${Font}"
        exit 1
    fi
    FILE_NAME="frp_${FRP_VERSION}_linux_${PLATFORM}"
    kill_process
    download_frp "$FILE_NAME"
    tar -zxf "${WORK_PATH}/${FILE_NAME}.tar.gz" -C "${WORK_PATH}"
    mkdir -p "${FRP_PATH}"
    mv "${WORK_PATH}/${FILE_NAME}/${FRP_NAME}" "${FRP_PATH}/"

    # 始终覆盖 toml
    if [ "$FRP_NAME" = "frpc" ]; then
        RADOM_NAME=$(cat /dev/urandom | head -n 10 | md5sum | head -c 8)
        cat >"${FRP_PATH}/${FRP_NAME}.toml" <<EOF
serverAddr = "frp.freefrp.net"
serverPort = 7000
auth.method = "token"
auth.token = "freefrp.net"

[[proxies]]
name = "web1_${RADOM_NAME}"
type = "http"
localIP = "192.168.1.2"
localPort = 5000
customDomains = ["nas.yourdomain.com"]

[[proxies]]
name = "web2_${RADOM_NAME}"
type = "https"
localIP = "192.168.1.2"
localPort = 5001
customDomains = ["nas.yourdomain.com"]

[[proxies]]
name = "tcp1_${RADOM_NAME}"
type = "tcp"
localIP = "192.168.1.3"
localPort = 22
remotePort = 22222

EOF
    else
        RADOM_TOKEN=$(cat /dev/urandom | head -n 10 | md5sum | head -c 16)
        cat >"${FRP_PATH}/${FRP_NAME}.toml" <<EOF
bindPort = 7000
auth.method = "token"
auth.token = "${RADOM_TOKEN}"

# vhostHTTPPort = 80
# vhostHTTPSPort = 443
webServer.addr = "0.0.0.0"
webServer.port = 7500
webServer.user = "admin"
webServer.password = "admin"

EOF
        echo -e "${Green}frps auth.token: ${Red}${RADOM_TOKEN}${Font}"
    fi

    write_systemd_service
    systemctl daemon-reload
    systemctl enable "${FRP_NAME}"
    systemctl start "${FRP_NAME}"
    rm -rf "${WORK_PATH}/${FILE_NAME}.tar.gz" "${WORK_PATH}/${FILE_NAME}"
    echo -e "${Green}安装完成 (已覆盖配置). 编辑: vi ${FRP_PATH}/${FRP_NAME}.toml  重启: systemctl restart ${FRP_NAME}${Font}"
}

# ---------- 更新 (仅程序，不覆盖配置) ----------
do_update() {
    if [ ! -f "${FRP_PATH}/${FRP_NAME}" ]; then
        echo -e "${Red}未检测到 ${FRP_NAME}，请先执行安装.${Font}"
        exit 1
    fi
    ensure_deps
    PLATFORM=$(get_platform)
    if [ -z "$PLATFORM" ]; then
        echo -e "${Red}不支持的架构: $(uname -m)${Font}"
        exit 1
    fi
    FILE_NAME="frp_${FRP_VERSION}_linux_${PLATFORM}"
    download_frp "$FILE_NAME"
    tar -zxf "${WORK_PATH}/${FILE_NAME}.tar.gz" -C "${WORK_PATH}"
    mv "${WORK_PATH}/${FILE_NAME}/${FRP_NAME}" "${FRP_PATH}/"
    rm -rf "${WORK_PATH}/${FILE_NAME}.tar.gz" "${WORK_PATH}/${FILE_NAME}"
    systemctl restart "${FRP_NAME}"
    echo -e "${Green}更新完成，配置未改动. 已重启 ${FRP_NAME}.${Font}"
}

# ---------- 卸载 ----------
do_uninstall() {
    if [ ! -f "${FRP_PATH}/${FRP_NAME}" ] && [ ! -f "/lib/systemd/system/${FRP_NAME}.service" ]; then
        echo -e "${Yellow}未检测到 ${FRP_NAME} 安装.${Font}"
        exit 0
    fi
    systemctl stop "${FRP_NAME}" 2>/dev/null
    systemctl disable "${FRP_NAME}" 2>/dev/null
    rm -f "${FRP_PATH}/${FRP_NAME}" "${FRP_PATH}/${FRP_NAME}.toml"
    [ -z "$(ls -A ${FRP_PATH} 2>/dev/null)" ] && rm -rf "${FRP_PATH}"
    rm -f "/lib/systemd/system/${FRP_NAME}.service"
    systemctl daemon-reload
    echo -e "${Green}卸载完成.${Font}"
}

# 执行
case "$ACTION" in
    install)   do_install ;;
    update)    do_update ;;
    uninstall) do_uninstall ;;
esac
