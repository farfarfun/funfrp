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
FRP_NAME=frps
FRP_VERSION=0.67.0
FRP_PATH=/usr/local/frp
PROXY_URL="https://ghfast.top/"

# check frps 已安装则退出（仅以二进制为准；.toml 已存在时后面不会覆盖）
if [ -f "/usr/local/frp/${FRP_NAME}" ]; then
    echo -e "${GREEN}=========================================================================${FONT}"
    echo -e "${RED_BG}当前已退出脚本.${FONT}"
    echo -e "${GREEN}检查到服务器已安装${FONT} ${RED}${FRP_NAME}${FONT}"
    echo -e "${GREEN}请先执行卸载脚本或手动删除${FONT} ${RED}/usr/local/frp/${FRP_NAME}${FONT} ${GREEN}后再次执行本脚本.${FONT}"
    echo -e "${GREEN}=========================================================================${FONT}"
    exit 0
fi

# 只清理本脚本自己托管的 frps 进程：按精确进程名匹配（pgrep -x），
# 不用 `ps -A | grep` 做子串匹配，避免误杀命令行里恰好带 frps 字样的无关进程。
for pid in $(pgrep -x "${FRP_NAME}" 2>/dev/null || true); do
    kill -9 "${pid}" 2>/dev/null || true
done

# check pkg
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

# check network
GOOGLE_HTTP_CODE=$(curl -o /dev/null --connect-timeout 5 --max-time 8 -s --head -w "%{http_code}" "https://www.google.com" || true)
PROXY_HTTP_CODE=$(curl -o /dev/null --connect-timeout 5 --max-time 8 -s --head -w "%{http_code}" "${PROXY_URL}" || true)

# check arch
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

# download
if [ "$GOOGLE_HTTP_CODE" = "200" ]; then
    wget -P "${WORK_PATH}" "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILE_NAME}.tar.gz" -O "${FILE_NAME}.tar.gz"
elif [ "$PROXY_HTTP_CODE" = "200" ]; then
    wget -P "${WORK_PATH}" "${PROXY_URL}https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILE_NAME}.tar.gz" -O "${FILE_NAME}.tar.gz"
else
    echo -e "${RED}检测 GitHub Proxy 代理失效 开始使用官方地址下载${FONT}"
    wget -P "${WORK_PATH}" "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILE_NAME}.tar.gz" -O "${FILE_NAME}.tar.gz"
fi
tar -zxvf "${FILE_NAME}.tar.gz"

mkdir -p "${FRP_PATH}"
mv "${FILE_NAME}/${FRP_NAME}" "${FRP_PATH}"

# configure frps.toml (server side)，若已存在则不覆盖
TOML_CREATED=0
if [ ! -f "${FRP_PATH}/${FRP_NAME}.toml" ]; then
    RANDOM_TOKEN=$(cat /dev/urandom | head -n 10 | md5sum | head -c 16)
    RANDOM_DASH_PASS=$(cat /dev/urandom | head -n 10 | md5sum | head -c 12)
    cat >"${FRP_PATH}/${FRP_NAME}.toml" <<EOF
bindPort = 7000
auth.method = "token"
auth.token = "${RANDOM_TOKEN}"

# 如需 HTTP/HTTPS 域名代理可取消下面注释并修改端口
# vhostHTTPPort = 80
# vhostHTTPSPort = 443

# 默认为 127.0.0.1，如果需要公网访问，需要修改为 0.0.0.0。
webServer.addr = "0.0.0.0"
webServer.port = 7500
# dashboard 用户名密码，随机生成，可按需修改
webServer.user = "admin"
webServer.password = "${RANDOM_DASH_PASS}"

EOF
    TOML_CREATED=1
fi

# configure systemd
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

# finish install
systemctl daemon-reload
systemctl start "${FRP_NAME}"
systemctl enable "${FRP_NAME}"

# clean
rm -rf "${WORK_PATH}/${FILE_NAME}.tar.gz" "${WORK_PATH}/${FILE_NAME}" "${FRP_NAME}_linux_install.sh"

echo -e "${GREEN}====================================================================${FONT}"
echo -e "${GREEN}安装成功!${FONT}"
if [ "$TOML_CREATED" = "1" ]; then
    echo -e "${GREEN}已生成 ${FRP_NAME}.toml，auth.token 与 dashboard 密码均已随机生成，不在终端回显.${FONT}"
    echo -e "${GREEN}如需查看请执行: ${RED}cat ${FRP_PATH}/${FRP_NAME}.toml${FONT}"
    echo -e "${GREEN}客户端连接时请使用相同 token.${FONT}"
fi
echo -e "${GREEN}编辑配置: ${RED}vi /usr/local/frp/${FRP_NAME}.toml${FONT}"
echo -e "${GREEN}修改后重启: ${RED}sudo systemctl restart ${FRP_NAME}${FONT}"
echo -e "${GREEN}====================================================================${FONT}"
