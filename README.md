# YujuToolBox
一个Shell脚本工具箱

## 简介
本工具箱集成了一系列有用的系统管理工具和脚本，旨在帮助用户轻松管理和优化Linux服务器。

## 支持列表
仅支持Debian、Ubuntu系统

## 使用方法
### 准备
安装curl
```
apt update -y  && apt install -y curl
```
或者
```
apt update -y  && apt install -y wget
```

或者手动下载本脚本至服务器

### 下载并执行
用curl下载
```
curl -sS -O https://raw.githubusercontent.com/lubenwei95SDF/YujuToolBox/main/yuju.sh && chmod +x yuju.sh && ./yuju.sh
```
用wget下载
```
wget -q https://raw.githubusercontent.com/lubenwei95SDF/YujuToolBox/main/yuju.sh && chmod +x yuju.sh && ./yuju.sh
```

## 功能介绍
- 系统管理、测试脚本、常用工具、Docker 管理。
- Realm 端口转发管理：自动安装/更新官方版本，生成受限权限的 systemd 服务，并支持配置、启停、状态和日志查看。
- 系统管理菜单支持创建普通 Linux 用户，可选密码、sudo 组和 SSH 公钥。
- 3x-ui 安全部署菜单：安装/登录 Tailscale、配置 UFW 默认安全规则、生成/迁移 3x-ui Docker Compose。
- 支持全新安装 3x-ui Docker Compose：默认面板和订阅端口只绑定 Tailscale IP，公网节点端口由用户输入。
- 3x-ui 迁移会先备份 `/etc/x-ui` 和容器信息，保留旧容器为 `3x-ui.before-compose`，不会删除 Docker 卷。
- bridge 网络模式会把 3x-ui 面板宿主机端口绑定到 Tailscale IP，并可把订阅端口改为只绑定 Tailscale IP。
- host 网络模式会保留 `network_mode: host`，并可把 3x-ui `webListen` 设置为 Tailscale IP。

### Realm 端口转发

进入主菜单的 `6. Realm端口转发管理`，先选择安装，再编辑
`/etc/realm/config.toml`。安装不会覆盖已有配置，首次安装也不会自动启动；
配置完成后可在菜单中启动，等价命令为：

```bash
systemctl enable --now realm
```

支持 Debian/Ubuntu `amd64` 与 `arm64`。更新正在运行的 Realm 时会校验新版本，
然后重启并确认服务保持运行，因此会有一次很短的连接中断；如果新版本启动失败，
脚本会回滚原二进制和 systemd 单元。为配合只读文件系统沙箱，systemd 服务会用
命令行参数强制日志输出到 journald，配置文件中的 `log.output` 不会覆盖它：

```bash
journalctl -u realm -n 100 --no-pager
```

为保持最小权限，systemd 服务不授予 `CAP_NET_RAW`，因此 Realm 的
`interface`/`listen_interface` 绑定选项不在此菜单的支持范围内；普通 IP/端口
转发不受影响。

## 项目参考
https://github.com/kejilion/sh

https://github.com/xykt/IPQuality
