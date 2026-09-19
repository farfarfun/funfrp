# 更新日志

本项目不发布 PyPI 包，版本按日期记录，倒序排列。

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
