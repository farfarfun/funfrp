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
# fonts color

# variable
WORK_PATH=$(dirname $(readlink -f $0))
FRP_NAME=frpc
FRP_VERSION=0.67.0
FRP_PATH=/usr/local/frp
PROXY_URL="https://ghfast.top/"

# check frpc 已安装则退出（仅以二进制为准；.toml 已存在时后面不会覆盖）
if [ -f "/usr/local/frp/${FRP_NAME}" ]; then
    echo -e "${Green}=========================================================================${Font}"
    echo -e "${RedBG}当前已退出脚本.${Font}"
    echo -e "${Green}检查到服务器已安装${Font} ${Red}${FRP_NAME}${Font}"
    echo -e "${Green}请先执行卸载脚本或手动删除${Font} ${Red}/usr/local/frp/${FRP_NAME}${Font} ${Green}后再次执行本脚本.${Font}"
    echo -e "${Green}=========================================================================${Font}"
    exit 0
fi

while ! test -z "$(ps -A | grep -w ${FRP_NAME})"; do
    FRPCPID=$(ps -A | grep -w ${FRP_NAME} | awk 'NR==1 {print $1}')
    kill -9 $FRPCPID
done

# check pkg
if type apt-get >/dev/null 2>&1 ; then
    if ! type wget >/dev/null 2>&1 ; then
        apt-get install wget -y
    fi
    if ! type curl >/dev/null 2>&1 ; then
        apt-get install curl -y
    fi
fi

if type yum >/dev/null 2>&1 ; then
    if ! type wget >/dev/null 2>&1 ; then
        yum install wget -y
    fi
    if ! type curl >/dev/null 2>&1 ; then
        yum install curl -y
    fi
fi

# check network
GOOGLE_HTTP_CODE=$(curl -o /dev/null --connect-timeout 5 --max-time 8 -s --head -w "%{http_code}" "https://www.google.com")
PROXY_HTTP_CODE=$(curl -o /dev/null --connect-timeout 5 --max-time 8 -s --head -w "%{http_code}" "${PROXY_URL}")

# check arch
if [ $(uname -m) = "x86_64" ]; then
    PLATFORM=amd64
elif [ $(uname -m) = "aarch64" ]; then
    PLATFORM=arm64
elif [ $(uname -m) = "armv7" ]; then
    PLATFORM=arm
elif [ $(uname -m) = "armv7l" ]; then
    PLATFORM=arm
elif [ $(uname -m) = "armhf" ]; then
    PLATFORM=arm
fi

FILE_NAME=frp_${FRP_VERSION}_linux_${PLATFORM}

# download
if [ $GOOGLE_HTTP_CODE == "200" ]; then
    wget -P ${WORK_PATH} https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILE_NAME}.tar.gz -O ${FILE_NAME}.tar.gz
else
    if [ $PROXY_HTTP_CODE == "200" ]; then
        wget -P ${WORK_PATH} ${PROXY_URL}https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILE_NAME}.tar.gz -O ${FILE_NAME}.tar.gz
    else
        echo -e "${Red}检测 GitHub Proxy 代理失效 开始使用官方地址下载${Font}"
        wget -P ${WORK_PATH} https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILE_NAME}.tar.gz -O ${FILE_NAME}.tar.gz
    fi
fi
tar -zxvf ${FILE_NAME}.tar.gz

mkdir -p ${FRP_PATH}
mv ${FILE_NAME}/${FRP_NAME} ${FRP_PATH}

# configure frpc.toml，若已存在则不覆盖
TOML_CREATED=0
if [ ! -f "${FRP_PATH}/${FRP_NAME}.toml" ]; then
    RADOM_NAME=$(cat /dev/urandom | head -n 10 | md5sum | head -c 8)
    cat >${FRP_PATH}/${FRP_NAME}.toml<<EOF
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
    TOML_CREATED=1
fi

# configure systemd
cat >/lib/systemd/system/${FRP_NAME}.service <<EOF
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
sudo systemctl start ${FRP_NAME}
sudo systemctl enable ${FRP_NAME}

# clean
rm -rf ${WORK_PATH}/${FILE_NAME}.tar.gz ${WORK_PATH}/${FILE_NAME} ${FRP_NAME}_linux_install.sh

echo -e "${Green}====================================================================${Font}"
echo -e "${Green}安装成功!${Font}"
if [ "$TOML_CREATED" = "1" ]; then
    echo -e "${Green}已生成 ${FRP_NAME}.toml，请按需修改 serverAddr、auth.token 及代理配置.${Font}"
fi
echo -e "${Green}编辑配置: ${Red}vi /usr/local/frp/${FRP_NAME}.toml${Font}"
echo -e "${Green}修改后重启: ${Red}sudo systemctl restart ${FRP_NAME}${Font}"
echo -e "${Green}====================================================================${Font}"