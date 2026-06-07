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
- 系统管理菜单支持创建普通 Linux 用户，可选密码、sudo 组和 SSH 公钥。
- 3x-ui 安全部署菜单：安装/登录 Tailscale、配置 UFW 默认安全规则、生成/迁移 3x-ui Docker Compose。
- 支持全新安装 3x-ui Docker Compose：默认面板只绑定 Tailscale IP，公开端口由用户输入。
- 3x-ui 迁移会先备份 `/etc/x-ui` 和容器信息，保留旧容器为 `3x-ui.before-compose`，不会删除 Docker 卷。
- bridge 网络模式会把 3x-ui 面板宿主机端口绑定到 Tailscale IP，并保留原有公开服务端口。
- host 网络模式会保留 `network_mode: host`，并可把 3x-ui `webListen` 设置为 Tailscale IP。

## 项目参考
https://github.com/kejilion/sh

https://github.com/xykt/IPQuality
