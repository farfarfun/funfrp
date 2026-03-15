# funfrp

## 项目简介

基于 [fatedier/frp](https://github.com/fatedier/frp) 原版 frp 的一键安装卸载脚本，支持 **frpc（客户端）** 与 **frps（服务端）**。支持群晖 NAS、Linux 服务器等多种环境安装部署。

- GitHub [farfarfun/funfrp](https://github.com/farfarfun/funfrp)

## 目录结构

```
script/
├── frpc/          # frp 客户端
│   ├── frpc_linux_install.sh
│   ├── frpc_linux_uninstall.sh
│   ├── frpc_synology_install.sh
│   └── frpc_synology_uninstall.sh
└── frps/          # frp 服务端
    ├── frps_linux_install.sh
    └── frps_linux_uninstall.sh
```

## 更新

- **2024-03-03** 更新到新版本，支持 toml 配置文件
- Linux 一键脚本同时支持 X86 和 ARM 架构
- 目前 X86 群晖 DMS 7.0 可直接使用 Linux 版本脚本，ARM 版请自行尝试

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

[详情点击查看教程](https://www.ioiox.com/archives/6.html)

### 3. frpc Linux 服务器一键脚本安装

> *本脚本同时支持 Linux X86 和 ARM 架构*

安装

```shell
wget https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frpc/frpc_linux_install.sh -O frpc_linux_install.sh && chmod +x frpc_linux_install.sh && ./frpc_linux_install.sh
# 国内镜像
wget https://ghfast.top/https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frpc/frpc_linux_install.sh -O frpc_linux_install.sh && chmod +x frpc_linux_install.sh && ./frpc_linux_install.sh
```

使用

```shell
vi /usr/local/frp/frpc.toml
# 修改 frpc.toml 配置
sudo systemctl restart frpc
# 重启 frpc 服务即可生效
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
# 配置 frpc.toml（可复制 script/frpc/frpc.toml 到指定目录后修改）
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
wget https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frps/frps_linux_install.sh -O frps_linux_install.sh && chmod +x frps_linux_install.sh &&sudo ./frps_linux_install.sh
# 国内镜像
wget https://ghfast.top/https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frps/frps_linux_install.sh -O frps_linux_install.sh && chmod +x frps_linux_install.sh && ./frps_linux_install.sh
```

安装完成后会生成默认 `frps.toml`（bindPort=7000，随机 auth.token），并注册 systemd 服务 **frps**。

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
wget https://ghfast.top/https://raw.githubusercontent.com/farfarfun/funfrp/master/script/frps/frps_linux_uninstall.sh -O frps_linux_uninstall.sh && chmod +x frps_linux_uninstall.sh && ./frps_linux_uninstall.sh
```

### frps 配置说明

`frps.toml` 常用项：

- **bindPort**：客户端连接端口，默认 7000
- **auth.method** / **auth.token**：需与客户端配置一致
- **vhostHTTPPort** / **vhostHTTPSPort**：HTTP(S) 域名代理时使用，按需取消注释

客户端 frpc 的 `serverAddr`、`serverPort`、`auth.token` 需与 frps 一致才能连接。

---

## 链接

- GitHub [farfarfun/funfrp](https://github.com/farfarfun/funfrp)
- 原版 frp 项目 [fatedier/frp](https://github.com/fatedier/frp)
- 参考 [stilleshan/frpc](https://github.com/stilleshan/frpc)
- [群晖 NAS 使用 Docker 安装配置 frpc 内网穿透教程](https://www.ioiox.com/archives/26.html)
- [群晖 NAS 安装配置免费 frp 内网穿透教程](https://www.ioiox.com/archives/6.html)
- [新手入门 - 详解 frp 内网穿透 frpc.toml 配置](https://www.ioiox.com/archives/79.html)
