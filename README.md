# funfrp

## 项目简介

基于 [fatedier/frp](https://github.com/fatedier/frp) 原版 frp 的一键安装卸载脚本，支持 **frpc（客户端）** 与 **frps（服务端）**。支持群晖 NAS、Linux 服务器等多种环境安装部署。

- GitHub [farfarfun/funfrp](https://github.com/farfarfun/funfrp)

## 目录结构

```
script/
├── frp_manager.sh    # 一键管理脚本：选择 frpc/frps → 安装(覆盖配置)/更新/卸载，按机器架构自动下载
├── frpc/             # frp 客户端
│   ├── frpc.toml                   # 示例配置（所有 CHANGE_ME_* 占位符都要替换）
│   ├── frpc_linux_install.sh
│   ├── frpc_linux_uninstall.sh
│   ├── frpc_synology_install.sh
│   ├── frpc_synology_service.sh    # 群晖下的 start/run/stop/restart/status 管理脚本
│   └── frpc_synology_uninstall.sh
└── frps/             # frp 服务端
    ├── frps_linux_install.sh
    └── frps_linux_uninstall.sh
```

## 一键管理脚本 (推荐)

运行后按提示选择 **组件**（frpc / frps）和 **操作**（安装/更新/卸载），脚本会按当前机器架构自动下载对应版本。

```shell
wget https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frp_manager.sh -O frp_manager.sh && chmod +x frp_manager.sh && ./frp_manager.sh
# 国内镜像
wget https://ghfast.top/https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frp_manager.sh -O frp_manager.sh && chmod +x frp_manager.sh && ./frp_manager.sh
```

- **安装 (覆盖配置)**：安装并写入配置，若已有配置会被覆盖。
- **更新**：仅替换程序文件，不修改现有 toml 配置。
- **卸载**：停止服务，只删除该组件自己的二进制、`.toml` 与 service 文件；`/usr/local/frp` 被清空后才会删除目录，因此同时装了 frpc 与 frps 时卸载任一个都不会影响另一个。

## 配置与凭据

脚本**不会内置任何可用的 frp token**。生成的 `frpc.toml` 里 `serverAddr` 与 `auth.token` 是 `CHANGE_ME_*` 占位符，占位符没改掉之前安装脚本**不会自动启动服务**。

两种填法：

```shell
# 1) 安装时用环境变量直接写入
FRPC_SERVER_ADDR=frps.example.com FRPC_SERVER_PORT=7000 FRPC_AUTH_TOKEN=你的token ./frp_manager.sh

# 2) 装完后手工编辑，再启动
vi /usr/local/frp/frpc.toml
sudo systemctl start frpc
```

frps 端的 `auth.token` 与 dashboard 密码由安装脚本随机生成，不在终端回显，查看方式：

```shell
sudo cat /usr/local/frp/frps.toml
```

> 只想先验证连通性，可以临时把 `serverAddr` 改成 `frp.freefrp.net`、`auth.token` 改成 `freefrp.net`
> （[freefrp.net](https://freefrp.net/docs) 公开发布的免费测试中转）。那是所有人共用的公开 token，
> 流量会经过第三方服务器，不要用于生产或涉及隐私的场景。

## 兼容性

- 安装的 frp 版本：**v0.67.0**，配置格式为 `toml`
- 支持架构：x86_64(amd64)、aarch64(arm64)、armv7(arm)
- X86 群晖 DSM 7.0 可直接用 Linux 版脚本（有 systemd）；ARM 机型请用群晖版脚本
- 历史变更见 [CHANGELOG.md](CHANGELOG.md)

---

## frpc（客户端）使用

内网机器安装，用于连接公网 frps。以下分为四种部署方法，请根据实际情况选择：

1. 群晖 NAS docker 安装 **[支持 docker 的群晖机型首选]**
2. 群晖 NAS 一键脚本安装 **[不支持 docker 的群晖机型]**
3. Linux 服务器一键脚本安装 **[内网 Linux 服务器或虚拟机]**
4. Linux 服务器 docker 安装 **[内网 Linux 服务器或虚拟机]**

### 1. 群晖 NAS docker 安装

[详情点击查看教程](https://www.ioiox.com/archives/26.html)

### 2. 群晖 NAS 一键脚本安装

适用于不支持 docker 的群晖机型。DSM 没有 systemd，安装脚本会额外装一份
`frpc_service.sh` 负责启停，PID 与日志放在 `/usr/local/frp/.run/` 下。

安装（需 root / `sudo -i`）

```shell
wget https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frpc/frpc_synology_install.sh -O frpc_synology_install.sh && chmod +x frpc_synology_install.sh && ./frpc_synology_install.sh
# 国内镜像
wget https://ghfast.top/https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frpc/frpc_synology_install.sh -O frpc_synology_install.sh && chmod +x frpc_synology_install.sh && ./frpc_synology_install.sh
```

安装后的路径：

| 文件 | 路径 |
| --- | --- |
| 程序 | `/usr/local/frp/frpc` |
| 配置 | `/usr/local/frp/frpc.toml` |
| 管理脚本 | `/usr/local/frp/frpc_service.sh` |
| PID | `/usr/local/frp/.run/frpc.pid` |
| 日志 | `/usr/local/frp/.run/frpc.log` |

使用

```shell
vi /usr/local/frp/frpc.toml           # 先把 CHANGE_ME_* 占位符改成你自己的值
/usr/local/frp/frpc_service.sh start     # 后台启动
/usr/local/frp/frpc_service.sh run       # 前台运行，便于排查启动失败
/usr/local/frp/frpc_service.sh status    # 查看状态（运行中退出码 0，未运行 1）
/usr/local/frp/frpc_service.sh restart   # 重启
/usr/local/frp/frpc_service.sh stop      # 停止
/usr/local/frp/frpc_service.sh log       # 跟踪日志
```

> 配置里还留着 `CHANGE_ME_` 时 `start` / `run` 会直接报错退出，这是有意为之，避免拿着无效 token 反复重连。
> DSM 重启后不会自动拉起，需要开机自启请在「控制面板 → 任务计划 → 触发的任务（开机）」里加一条
> `/usr/local/frp/frpc_service.sh start`。

卸载

```shell
wget https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frpc/frpc_synology_uninstall.sh -O frpc_synology_uninstall.sh && chmod +x frpc_synology_uninstall.sh && ./frpc_synology_uninstall.sh
# 国内镜像
wget https://ghfast.top/https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frpc/frpc_synology_uninstall.sh -O frpc_synology_uninstall.sh && chmod +x frpc_synology_uninstall.sh && ./frpc_synology_uninstall.sh
```

卸载只会删除 frpc 自己的程序、配置、管理脚本与 `.run/` 下的运行时文件，`/usr/local/frp` 为空时才删除目录。

[群晖图文教程（第三方，仅供参考，命令以上文为准）](https://www.ioiox.com/archives/6.html)

### 3. frpc Linux 服务器一键脚本安装

> *本脚本同时支持 Linux X86 和 ARM 架构*

安装

```shell
wget https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frpc/frpc_linux_install.sh -O frpc_linux_install.sh && chmod +x frpc_linux_install.sh && ./frpc_linux_install.sh
# 国内镜像
wget https://ghfast.top/https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frpc/frpc_linux_install.sh -O frpc_linux_install.sh && chmod +x frpc_linux_install.sh && ./frpc_linux_install.sh
```

安装脚本会注册并 `enable` systemd 服务 **frpc**，但**配置里还留着 `CHANGE_ME_` 占位符时不会自动 start**，
避免拿着无效 token 反复重连。

使用

```shell
vi /usr/local/frp/frpc.toml
# 填好 serverAddr / auth.token 及 [[proxies]] 配置
sudo systemctl start frpc      # 首次启动
sudo systemctl restart frpc    # 改完配置后重启生效
sudo systemctl status frpc     # 查看状态
sudo journalctl -u frpc -f     # 跟踪日志
```

也可以在安装时直接把连接参数写进去，装完即启动：

```shell
FRPC_SERVER_ADDR=frps.example.com FRPC_AUTH_TOKEN=你的token ./frpc_linux_install.sh
```

卸载

```shell
wget https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frpc/frpc_linux_uninstall.sh -O frpc_linux_uninstall.sh && chmod +x frpc_linux_uninstall.sh && ./frpc_linux_uninstall.sh
# 国内镜像
wget https://ghfast.top/https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frpc/frpc_linux_uninstall.sh -O frpc_linux_uninstall.sh && chmod +x frpc_linux_uninstall.sh && ./frpc_linux_uninstall.sh
```

### 4. frpc Linux 服务器 docker 安装

请先配置好 **frpc.toml** 后再运行启动，避免挂载或配置错误导致容器循环重启。

```shell
git clone https://github.com/farfarfun/funfrp
# 国内镜像
git clone https://ghfast.top/https://github.com/farfarfun/funfrp
# 配置 frpc.toml（可复制 script/frpc/frpc.toml 到指定目录，把 CHANGE_ME_* 占位符改掉）
vi /root/frpc/frpc.toml
```

启动服务

```shell
docker run -d --name=frpc --restart=always -v /root/frpc/frpc.toml:/frp/frpc.toml stilleshan/frpc
```

> -v 挂载路径可改为你本地的 frpc.toml 路径。

修改配置后重启

```shell
vi /root/frpc/frpc.toml
docker restart frpc
```

---

## frps（服务端）使用

公网机器安装，用于接收 frpc 连接。仅支持 Linux 服务器一键脚本。

### frps Linux 服务器一键脚本安装

> *本脚本同时支持 Linux X86 和 ARM 架构*

安装

```shell
wget https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frps/frps_linux_install.sh -O frps_linux_install.sh && chmod +x frps_linux_install.sh && sudo ./frps_linux_install.sh
# 国内镜像
wget https://ghfast.top/https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frps/frps_linux_install.sh -O frps_linux_install.sh && chmod +x frps_linux_install.sh && sudo ./frps_linux_install.sh
```

安装完成后会生成 `frps.toml` 并注册 systemd 服务 **frps**：

- `bindPort = 7000`，客户端连接端口
- `auth.token` 随机生成，不在终端回显
- dashboard 监听 `127.0.0.1:7500`，用户名 `admin`，密码随机生成

> dashboard **默认只监听回环地址**，不会直接暴露到公网。确需远程访问时，
> 安装前设 `FRPS_DASHBOARD_ADDR=0.0.0.0`，或装完后改 `frps.toml` 的 `webServer.addr`，
> 并自行配好防火墙。

使用

```shell
vi /usr/local/frp/frps.toml
# 按需修改 bindPort、auth.token、vhost 端口等
sudo systemctl restart frps
```

卸载

```shell
wget https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frps/frps_linux_uninstall.sh -O frps_linux_uninstall.sh && chmod +x frps_linux_uninstall.sh && sudo ./frps_linux_uninstall.sh
# 国内镜像
wget https://ghfast.top/https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frps/frps_linux_uninstall.sh -O frps_linux_uninstall.sh && chmod +x frps_linux_uninstall.sh && sudo ./frps_linux_uninstall.sh
```

卸载只删除 `frps` 自己的程序、`frps.toml` 与 `frps.service`，`/usr/local/frp` 为空时才删除目录，不会影响同机安装的 frpc。

### frps 配置说明

`frps.toml` 常用项：

- **bindPort**：客户端连接端口，默认 7000
- **auth.method** / **auth.token**：需与客户端配置一致
- **vhostHTTPPort** / **vhostHTTPSPort**：HTTP(S) 域名代理时使用，按需取消注释
- **webServer.addr** / **webServer.port** / **webServer.user** / **webServer.password**：dashboard，默认 `127.0.0.1:7500`

客户端 frpc 的 `serverAddr`、`serverPort`、`auth.token` 需与 frps 一致才能连接。

---

## 链接

- GitHub [farfarfun/funfrp](https://github.com/farfarfun/funfrp)
- 原版 frp 项目 [fatedier/frp](https://github.com/fatedier/frp)
- 参考 [stilleshan/frpc](https://github.com/stilleshan/frpc)
- [群晖 NAS 使用 Docker 安装配置 frpc 内网穿透教程](https://www.ioiox.com/archives/26.html)
- [群晖 NAS 安装配置免费 frp 内网穿透教程](https://www.ioiox.com/archives/6.html)
- [新手入门 - 详解 frp 内网穿透 frpc.toml 配置](https://www.ioiox.com/archives/79.html)

---

## 关于 farfarfun

[farfarfun](https://github.com/farfarfun) 是一个专注于实用工具库的开源组织，
涵盖云存储、数据处理、AI、多媒体与开发工具链等方向。

- 🏠 组织主页：<https://github.com/farfarfun>
- 📧 联系：farfarfun@qq.com

本项目基于 [MIT](LICENSE) 协议开源。
