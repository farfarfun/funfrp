# 更新日志

本项目不发布 PyPI 包，版本按日期记录，倒序排列。

## 未发布

### 新增

- 新增 `script/frpc/frpc_synology_service.sh`：群晖 DSM 没有 systemd，此前只能靠 `nohup ... &` 起后台进程，既没有 stop/status，也没有 PID 管理。新脚本提供 `start`（后台）/ `run`（前台 `exec`）/ `stop` / `restart` / `status` / `log`，PID 与日志统一放在 `/usr/local/frp/.run/` 下，拒绝重复启动并能区分「陈旧 PID 文件」与「进程真的活着」。安装脚本会自动装好它。

### 修复

- 卸载脚本不再 `rm -rf /usr/local/frp`：frpc 与 frps 共用该目录，整目录删除会在同机装了两个组件时连带删掉另一个组件的程序和配置。现改为只删除本组件自己的二进制、`.toml`、service 文件与 `.run/` 运行时文件，目录为空时才 `rmdir`。涉及 `frpc_linux_uninstall.sh`、`frpc_synology_uninstall.sh`、`frps_linux_uninstall.sh`（`frp_manager.sh` 原本就是正确的）。
- 不再内置任何可用的 frp token：`frpc.toml` 与三个安装脚本生成的客户端配置改为 `CHANGE_ME_FRPS_SERVER_ADDR` / `CHANGE_ME_FRPS_TOKEN` 占位符，可用环境变量 `FRPC_SERVER_ADDR` / `FRPC_SERVER_PORT` / `FRPC_AUTH_TOKEN` 在安装时写入。占位符未替换时安装脚本只注册服务、**不自动启动**，避免「装完即把内网流量接到某个默认第三方中转」这种用户没预期的行为。
- frps dashboard 默认监听地址由 `0.0.0.0` 改为 `127.0.0.1`：装完即把管理界面暴露到公网不是安全的默认值（SPEC §9.3）。需要远程访问时设 `FRPS_DASHBOARD_ADDR=0.0.0.0`。
- 修复三个安装脚本的下载落盘路径：`wget -P "${WORK_PATH}" ... -O "${FILE_NAME}.tar.gz"` 中 `-O` 会覆盖 `-P`，压缩包与解压目录实际落在**当前工作目录**而非 `WORK_PATH`，导致从其他目录执行脚本时 `mv` 找不到文件、结尾的清理也清不掉残留。现统一把 `-O` 与解压目标写成 `WORK_PATH` 下的绝对路径。
- `frpc_synology_install.sh` 的 `FRP_VERSION` 从 `0.61.2` 更新到 `0.67.0`（与其余脚本一致），下载代理从已失效的 `https://ghp.ci/` 改为 `https://ghfast.top/`。
- 两个群晖脚本是 `#!/bin/sh`，但用了 `echo -e`（shellcheck SC3037：POSIX sh 下 echo 的选项行为未定义，dash 会把 `-e` 原样打印）。统一改为 `printf '%b\n'`。
- `rm -rf "${WORK_PATH}/${FILE_NAME}"` 在变量为空时会展开成 `rm -rf /`（shellcheck SC2115），改为 `"${WORK_PATH:?}/${FILE_NAME:?}"`。
- 去掉 `cat /dev/urandom | head` 的无用 `cat`。

### 变更

- README 补齐群晖一键脚本的完整安装/卸载命令、安装后各文件路径表、`start`/`run`/`stop`/`restart`/`status` 用法与开机自启说明，不再只给一条外部教程链接；新增「配置与凭据」章节说明占位符与环境变量用法；frps 章节补充 dashboard 的地址/端口/账号说明；卸载语义的描述与脚本实际行为对齐。

- README `frps` 安装命令里的 `chmod +x frps_linux_install.sh &&sudo ./frps_linux_install.sh` 缺空格，`&&sudo` 不是合法的 shell 连接写法，已改为 `&& sudo`。
- 删除过时且从未被任何脚本引用的静态 `script/frpc/frpc.service`：其 `ExecStart` 仍指向已废弃的 `frpc.ini`，与安装脚本实际生成、指向 `frpc.toml` 的 systemd unit 不一致，容易误导手动复用该文件的用户；安装脚本本身会在安装时正确生成指向 `.toml` 的 service 文件，无需再保留这份静态文件。
- 把脚本里残留的英文注释（`fonts color`/`variable`/`check pkg`/`check network`/`check arch`/`download`/`configure ...`/`finish install`/`clean` 等）统一翻译为中文，与组织现有代码风格保持一致。

## 2026-09-19

### 修复

- `frps` dashboard 默认密码不再固定为 `admin`，改为随机生成，且不在终端回显；`auth.token` 同样不再打印到终端，改为提示查看配置文件。
- 修复安装/卸载脚本用 `ps -A | grep -w` 按子串匹配后 `kill -9` 第一个匹配进程的问题：改为按精确进程名（`pgrep -x`，或退化为按 `ps` 末字段整字段匹配）清理，避免误杀命令行中恰好包含 `frpc`/`frps` 字样的无关进程。
- 所有脚本补充 `set -eu`（bash 脚本另加 `pipefail`），给变量展开统一加引号，路径解析统一基于脚本自身位置，关键步骤失败后不再静默继续。

### 变更

- 颜色相关变量统一改为 `UPPER_SNAKE` 命名（`GREEN`/`RED`/`YELLOW`/`GREEN_BG`/`RED_BG`/`FONT`）。
- `frpc.toml` 默认模板补充注释，说明 `serverAddr`/`auth.token` 指向 freefrp.net 公开发布的免费测试中转服务，仅用于快速验证连通性，生产环境需替换为自有 frps。
- `.gitignore` 补充 `*.db`、`*.rar`、`.run/`、`logs/`、`.idea/`、`.vscode/`、`node_modules/` 等规则。
- README 末尾补充「关于 farfarfun」组织介绍区块。

## 2026-08-26

### 修复

- 补充 MIT `LICENSE` 文件。
- 把构建产物移出版本管理。

## 2026-03-15

### 新增

- 新增 `frp_manager.sh` 一键管理脚本：交互式选择 frpc/frps 组件与安装/更新/卸载操作，按机器架构自动下载对应版本。

### 变更

- 重构项目结构，安装脚本升级支持 toml 配置文件，优化检测逻辑与配置处理。

## 2025-03-29

### 新增

- 初始版本：frpc/frps 在 Linux 服务器与群晖 NAS 上的一键安装/卸载脚本。
