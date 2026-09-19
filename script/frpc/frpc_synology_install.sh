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

# variable
WORK_PATH=$(dirname "$(readlink -f "$0")")
FRP_NAME=frpc
FRP_VERSION=0.61.2
FRP_PATH=/usr/local/frp
PROXY_URL="https://ghp.ci/"

# check frpc
if [ -f "/usr/local/frp/${FRP_NAME}" ] || [ -f "/usr/local/frp/${FRP_NAME}.toml" ] || [ -f "/lib/systemd/system/${FRP_NAME}.service" ]; then
    echo -e "${GREEN}=========================================================================${FONT}"
    echo -e "${RED_BG}当前已退出脚本.${FONT}"
    echo -e "${GREEN}检查到服务器已安装${FONT} ${RED}${FRP_NAME}${FONT}"
    echo -e "${GREEN}请手动确认和删除${FONT} ${RED}/usr/local/frp/${FONT} ${GREEN}目录下的${FONT} ${RED}${FRP_NAME}${FONT} ${GREEN}和${FONT} ${RED}/${FRP_NAME}.toml${FONT} ${GREEN}文件以及${FONT} ${RED}/lib/systemd/system/${FRP_NAME}.service${FONT} ${GREEN}文件,再次执行本脚本.${FONT}"
    echo -e "${GREEN}参考命令如下:${FONT}"
    echo -e "${RED}rm -rf /usr/local/frp/${FRP_NAME}${FONT}"
    echo -e "${RED}rm -rf /usr/local/frp/${FRP_NAME}.toml${FONT}"
    echo -e "${RED}rm -rf /lib/systemd/system/${FRP_NAME}.service${FONT}"
    echo -e "${GREEN}=========================================================================${FONT}"
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

# check network
GOOGLE_HTTP_CODE=$(curl -o /dev/null --connect-timeout 5 --max-time 8 -s --head -w "%{http_code}" "https://www.google.com" || true)
PROXY_HTTP_CODE=$(curl -o /dev/null --connect-timeout 5 --max-time 8 -s --head -w "%{http_code}" "${PROXY_URL}" || true)

# check arch
if [ "$(uname -m)" = "x86_64" ]; then
    PLATFORM=amd64
elif [ "$(uname -m)" = "aarch64" ]; then
    PLATFORM=arm64
else
    PLATFORM=arm
fi

FILE_NAME="frp_${FRP_VERSION}_linux_${PLATFORM}"

# download
if [ "$GOOGLE_HTTP_CODE" = "200" ]; then
    wget -P "${WORK_PATH}" "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILE_NAME}.tar.gz" -O "${FILE_NAME}.tar.gz"
else
    if [ "$PROXY_HTTP_CODE" = "200" ]; then
        wget -P "${WORK_PATH}" "${PROXY_URL}https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILE_NAME}.tar.gz" -O "${FILE_NAME}.tar.gz"
    else
        echo -e "${RED}检测 GitHub Proxy 代理失效 开始使用官方下载地址下载${FONT}"
        wget -P "${WORK_PATH}" "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILE_NAME}.tar.gz" -O "${FILE_NAME}.tar.gz"
    fi
fi
tar -zxvf "${FILE_NAME}.tar.gz"
mkdir -p "${FRP_PATH}"
mv "${FILE_NAME}/${FRP_NAME}" "${FRP_PATH}"

# configure frpc.toml
RANDOM_NAME=$(cat /dev/urandom | head -n 10 | md5sum | head -c 8)
cat >"${FRP_PATH}/${FRP_NAME}.toml" <<EOF
# 默认 serverAddr/auth.token 指向 freefrp.net 公开发布的免费测试中转服务
# （公开体验 token，见 https://freefrp.net/docs），仅用于快速验证连通性，
# 生产环境请替换为你自己的 frps 地址与随机 token。
serverAddr = "frp.freefrp.net"
serverPort = 7000
auth.method = "token"
auth.token = "freefrp.net"

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

# clean
rm -rf "${WORK_PATH}/${FILE_NAME}.tar.gz" "${WORK_PATH}/${FILE_NAME}" "${WORK_PATH}/${FRP_NAME}_synology_install.sh"

# 完成安装,手动修改frpc.toml并启动服务.
echo -e "${GREEN}=======================================================================${FONT}"
echo -e "${GREEN}安装成功,请先修改 frpc.toml 文件,确保格式及配置正确无误!${FONT}"
echo -e "${RED}vi /usr/local/frp/frpc.toml${FONT}"
echo -e "${GREEN}修改完毕后执行以下命令启动服务并保持后台运行:${FONT}"
echo -e "${RED}nohup /usr/local/frp/frpc -c /usr/local/frp/frpc.toml >/dev/null 2>&1 &${FONT}"
echo -e "${GREEN}=======================================================================${FONT}"
