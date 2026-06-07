#!/bin/bash
# 版本信息
version="0.0.1"

# ─── 颜色定义 ────────────────────────────────────────────────
white='\033[0m'
green='\033[0;32m'
blue='\033[0;34m'
red='\033[31m'
yellow='\033[33m'
grey='\e[37m'
pink='\033[38;5;218m'
cyan='\033[96m'

# 将脚本安装到全局路径（运行失败静默忽略）
cp ./yuju.sh /usr/local/bin/yuju > /dev/null 2>&1

# ─── 公用工具函数 ─────────────────────────────────────────────

# 操作完成后按任意键返回
break_end() {
    echo -e "${green}执行完成${white}"
    echo -e "${green}按任意键返回菜单...${white}"
    read -n 1 -s -r -p ""
    echo ""
    clear
}

# 重新进入主菜单（用于子菜单快捷返回）
yuju_sh() {
    yuju
    exit
}

# 纯 root 检测：仅打印提示，失败返回 1
require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${red}提示: ${white}该功能需要root用户才能运行！"
        return 1
    fi
    return 0
}

# root 检测：失败则暂停后返回主菜单
root_test() {
    clear
    if ! require_root; then
        break_end
        yuju_sh
    fi
}

# 通用软件包安装（apt），替代大量重复的 download_xxx 函数
pkg_install() {
    local pkg="$1"
    clear
    apt install "$pkg" -y
    echo "${pkg} 安装完成"
}

# ─── 授权检测 ─────────────────────────────────────────────────
user_authorization="false"

# 用户协议确认
user_agreement() {
    clear
    echo -e "${pink}欢迎使用yuju一键工具${white}"
    echo "此脚本基于自用开发"
    echo -e "${red}请尽量通过选择脚本选项退出${white}"
    echo "如有问题，后果自负"
    echo -e "${pink}============================${white}"
    read -r -p "是否同意？(y/n): " user_input

    if [ "$user_input" = "y" ] || [ "$user_input" = "Y" ]; then
        echo "已同意"
        user_authorization="true"
        sed -i 's/^user_authorization="false"/user_authorization="true"/' ./yuju.sh 2>/dev/null
        sed -i 's/^user_authorization="false"/user_authorization="true"/' /usr/local/bin/yuju 2>/dev/null
        apt install sudo -y
        clear
    else
        echo "已拒绝"
        exit 1
    fi
}

# 若已安装副本已授权，同步本地文件并更新内存变量
authorization_check() {
    if grep -q '^user_authorization="true"' /usr/local/bin/yuju 2>/dev/null; then
        sed -i 's/^user_authorization="false"/user_authorization="true"/' ./yuju.sh 2>/dev/null
        user_authorization="true"
    fi
}

# 若已安装副本未授权，则弹出协议确认
authorization_false() {
    if grep -q '^user_authorization="false"' /usr/local/bin/yuju 2>/dev/null; then
        user_agreement
    fi
}

authorization_check
authorization_false

# ═══════════════════════════════════════════════════════════════
# 1. 系统管理
# ═══════════════════════════════════════════════════════════════

# ─── BBR 工具函数 ──────────────────────────────────────────────

check_bbr_status() {
    [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" == "bbr" ]]
}

check_kernel_bbr() {
    local kver major minor
    kver=$(uname -r | cut -d- -f1)
    major=$(echo "$kver" | cut -d. -f1)
    minor=$(echo "$kver" | cut -d. -f2)
    [[ $major -gt 4 ]] || [[ $major -eq 4 && $minor -ge 9 ]]
}

sysctl_apply_file() {
    local conf_file="$1"
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        local key value
        key=$(echo "$line" | cut -d= -f1 | tr -d ' ')
        value=$(echo "$line" | cut -d= -f2- | tr -d ' ')
        [[ -z "$key" || -z "$value" ]] && continue
        sysctl -w "${key}=${value}" 2>/dev/null || true
    done < "$conf_file"
}

# 主菜单系统信息面板（紧凑双栏布局，直接嵌入主界面）
show_sysinfo() {
    local hostname os_info kernel cpu_arch cpu_info cpu_cores cpu_usage
    local mem_used mem_total mem_pct disk_used disk_total disk_pct
    local swap_used swap_total ipv4 ipv6 isp congestion queue runtime timezone
    local bbr_st bbr_mod_st tcp_tune_st

    hostname=$(hostname)
    os_info=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    kernel=$(uname -r)
    cpu_arch=$(uname -m)
    cpu_info=$(lscpu 2>/dev/null | awk -F': +' '/Model name/{print $2; exit}')
    cpu_cores=$(nproc)
    cpu_usage=$(awk '{u=$2+$4; t=$2+$4+$5; if(NR==1){u1=u;t1=t} \
        else printf "%.0f", (($2+$4-u1)*100/(t-t1))}' \
        <(grep 'cpu ' /proc/stat) <(sleep 0.3; grep 'cpu ' /proc/stat))

    read -r mem_total mem_used  < <(free -m  | awk '/^Mem/{print $2,$3}')
    read -r swap_total swap_used < <(free -m | awk '/^Swap/{print $2,$3}')
    mem_pct=$(( (mem_total > 0) ? mem_used * 100 / mem_total : 0 ))
    read -r disk_used disk_total disk_pct < <(df -h / | awk 'NR==2{print $3,$2,$5}')

    ipv4=$(curl -s --max-time 2 ipv4.ip.sb 2>/dev/null); [ -z "$ipv4" ] && ipv4="-"
    ipv6=$(curl -s --max-time 2 ipv6.ip.sb 2>/dev/null); [ -z "$ipv6" ] && ipv6="-"
    local ipinfo
    ipinfo=$(curl -s --max-time 3 ipinfo.io 2>/dev/null)
    isp=$(echo "$ipinfo" | grep '"org"' | cut -d'"' -f4); [ -z "$isp" ] && isp="-"
    congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    queue=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    runtime=$(awk -F. '{d=int($1/86400);h=int(($1%86400)/3600);m=int(($1%3600)/60); \
        s=""; if(d)s=s d"天 "; if(h)s=s h"时 "; printf s"%d分",m}' /proc/uptime)
    timezone=$(timedatectl 2>/dev/null | awk '/Time zone/{print $3}')

    if check_bbr_status; then
        bbr_st="${green}✅ 已启用${white}"
    else
        bbr_st="${red}❌ 未启用${white}"
    fi
    if lsmod 2>/dev/null | grep -q bbr; then
        bbr_mod_st="${green}✅ 已加载${white}"
    elif grep -q 'CONFIG_TCP_CONG_BBR=y' /boot/config-$(uname -r) 2>/dev/null; then
        bbr_mod_st="${green}✅ 已内置${white}"
    else
        bbr_mod_st="${red}❌ 未加载${white}"
    fi
    if [[ -f /etc/sysctl.d/99-tcp-tune.conf ]]; then
        tcp_tune_st="${green}✅ 已应用${white}"
    else
        tcp_tune_st="${yellow}⬜ 未应用${white}"
    fi

    local L="${pink}─────────────────────────────────────────────────${white}"
    echo -e "$L"
    printf " ${cyan}主机:${white} %-22s  ${cyan}系统:${white} %s\n"  "$hostname"  "$os_info"
    printf " ${cyan}内核:${white} %-22s  ${cyan}架构:${white} %s\n"  "$kernel"    "$cpu_arch"
    echo -e "$L"
    printf " ${cyan}CPU :${white} %s × %s核   ${cyan}占用:${white} %s%%\n" \
        "$cpu_info" "$cpu_cores" "$cpu_usage"
    printf " ${cyan}内存:${white} %s/%s MB (%s%%)   ${cyan}硬盘:${white} %s/%s (%s)   ${cyan}交换:${white} %s/%s MB\n" \
        "$mem_used" "$mem_total" "$mem_pct" \
        "$disk_used" "$disk_total" "$disk_pct" \
        "$swap_used" "$swap_total"
    echo -e "$L"
    printf " ${cyan}IPv4:${white} %-22s  ${cyan}IPv6:${white} %s\n"  "$ipv4" "$ipv6"
    printf " ${cyan}ISP :${white} %-22s  ${cyan}拥塞控制:${white} %s   ${cyan}队列算法:${white} %s\n" "$isp" "$congestion" "$queue"
    echo -e " ${cyan}TCP调优:${white} ${tcp_tune_st}   ${cyan}BBR状态:${white} ${bbr_st}   ${cyan}BBR模块:${white} ${bbr_mod_st}"
    echo -e "$L"
    printf " ${cyan}运行:${white} %-22s  ${cyan}时区:${white} %s\n"  "$runtime" "$timezone"
    echo -e "$L"
}

# 1.1 更新系统软件包
system_update() {
    clear
    apt update -y && apt upgrade -y
    clear
    echo "系统软件包更新完毕"
}

# 1.2 系统清理
system_clean() {
    clear
    if [[ $EUID -ne 0 ]]; then
        echo "此脚本必须以root权限运行"
        exit 1
    fi
    local start_space end_space cleared_space PKG_MANAGER CLEAN_CMD PKG_UPDATE_CMD INSTALL_CMD PURGE_CMD

    start_space=$(df / | tail -n 1 | awk '{print $3}')
    echo -e "${yellow}正在进行系统清理...${white}"

    if command -v apt-get > /dev/null; then
        PKG_MANAGER="apt"
        CLEAN_CMD="apt-get autoremove -y && apt-get clean"
        PKG_UPDATE_CMD="apt-get update"
        INSTALL_CMD="apt-get install -y"
        PURGE_CMD="apt-get purge -y"
    elif command -v dnf > /dev/null; then
        PKG_MANAGER="dnf"
        CLEAN_CMD="dnf autoremove -y && dnf clean all"
        PKG_UPDATE_CMD="dnf update"
        INSTALL_CMD="dnf install -y"
        PURGE_CMD="dnf remove -y"
    elif command -v apk > /dev/null; then
        PKG_MANAGER="apk"
        CLEAN_CMD="apk cache clean"
        PKG_UPDATE_CMD="apk update"
        INSTALL_CMD="apk add"
        PURGE_CMD="apk del"
    else
        echo "不支持的包管理器"
        exit 1
    fi

    echo "正在更新依赖..."
    if [ "$PKG_MANAGER" = "apt" ] && [ ! -x /usr/bin/deborphan ]; then
        $PKG_UPDATE_CMD > /dev/null 2>&1
        $INSTALL_CMD deborphan > /dev/null 2>&1
    fi

    echo "正在删除未使用的内核..."
    if [[ "$PKG_MANAGER" == "apt" || "$PKG_MANAGER" == "dnf" ]]; then
        local current_kernel kernel_packages
        current_kernel=$(uname -r)
        if [[ "$PKG_MANAGER" == "apt" ]]; then
            kernel_packages=$(dpkg --list | grep -E '^ii  linux-(image|headers)-[0-9]+' | awk '{print $2}' | grep -v "$current_kernel")
        else
            kernel_packages=$(rpm -qa | grep -E '^kernel-(core|modules|devel)-[0-9]+' | grep -v "$current_kernel")
        fi
        if [ -n "$kernel_packages" ]; then
            echo "找到旧内核，正在删除：$kernel_packages"
            $PURGE_CMD $kernel_packages > /dev/null 2>&1
            [[ "$PKG_MANAGER" == "apt" ]] && update-grub > /dev/null 2>&1
        else
            echo "没有旧内核需要删除。"
        fi
    fi

    echo "正在清理系统日志文件..."
    find /var/log -type f -name "*.log" -exec truncate -s 0 {} \; > /dev/null 2>&1
    find /root    -type f -name "*.log" -exec truncate -s 0 {} \; > /dev/null 2>&1
    find /home    -type f -name "*.log" -exec truncate -s 0 {} \; > /dev/null 2>&1
    find /ql      -type f -name "*.log" -exec truncate -s 0 {} \; > /dev/null 2>&1

    echo "正在清理缓存目录..."
    find /tmp     -type f -mtime +1 -exec rm -f {} \;
    find /var/tmp -type f -mtime +1 -exec rm -f {} \;
    for user in /home/* /root; do
        local cache_dir="$user/.cache"
        if [ -d "$cache_dir" ]; then
            rm -rf "${cache_dir:?}"/* > /dev/null 2>&1
        fi
    done

    if command -v docker &> /dev/null; then
        echo "正在清理Docker镜像、容器和卷..."
        docker system prune -a -f --volumes > /dev/null 2>&1
    fi

    if [ "$PKG_MANAGER" = "apt" ]; then
        echo "正在清理孤立包..."
        deborphan --guess-all | xargs -r apt-get -y remove --purge > /dev/null 2>&1
    fi

    echo "正在清理包管理器缓存..."
    eval "$CLEAN_CMD" > /dev/null 2>&1

    end_space=$(df / | tail -n 1 | awk '{print $3}')
    cleared_space=$((start_space - end_space))
    echo "系统清理完成，清理了 $((cleared_space / 1024))M 空间！"
}

# 1.3 TCP 调优
tcp_tune() {
    local auto="${1:-}"
    clear
    echo -e "${cyan}正在应用 TCP 深度调优...${white}"
    echo ""
    echo "本操作将优化以下参数："
    echo "  • TIME_WAIT 连接回收与复用"
    echo "  • TCP 连接保活 (keepalive)"
    echo "  • MTU 探测 & PMTU"
    echo "  • 本地端口范围扩展"
    echo "  • SYN Cookie 防 SYN Flood"
    echo "  • 连接追踪表 (nf_conntrack)"
    echo "  • 文件描述符上限"
    echo ""
    if [[ "$auto" != "--auto" ]]; then
        read -rp "确认写入? [y/N]: " confirm_tune
        [[ ! "$confirm_tune" =~ ^[Yy]$ ]] && { echo -e "${yellow}已取消${white}"; return; }
    fi

    cat > /etc/sysctl.d/99-tcp-tune.conf <<'EOF'
net.ipv4.tcp_tw_reuse           = 1
net.ipv4.tcp_max_tw_buckets     = 20000
net.ipv4.tcp_keepalive_time     = 60
net.ipv4.tcp_keepalive_intvl    = 10
net.ipv4.tcp_keepalive_probes   = 6
net.ipv4.tcp_syncookies         = 1
net.ipv4.tcp_syn_retries        = 3
net.ipv4.tcp_synack_retries     = 3
net.ipv4.tcp_max_syn_backlog    = 8192
net.core.somaxconn              = 8192
net.ipv4.ip_local_port_range    = 1024 65535
net.ipv4.tcp_mtu_probing        = 1
net.core.rmem_default           = 262144
net.core.wmem_default           = 262144
net.core.rmem_max               = 33554432
net.core.wmem_max               = 33554432
net.ipv4.tcp_rmem               = 4096 87380 33554432
net.ipv4.tcp_wmem               = 4096 65536 33554432
net.ipv4.tcp_mem                = 786432 1048576 26777216
net.core.netdev_max_backlog     = 10000
net.ipv4.tcp_fastopen           = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_sack               = 1
net.ipv4.tcp_timestamps         = 1
net.ipv4.tcp_window_scaling     = 1
net.ipv4.tcp_no_metrics_save    = 1
net.netfilter.nf_conntrack_max              = 1000000
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
fs.file-max                     = 1000000
EOF

    sysctl_apply_file /etc/sysctl.d/99-tcp-tune.conf

    if ! grep -q "# tcp-tune" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf <<'EOF'

# tcp-tune
* soft nofile 1000000
* hard nofile 1000000
root soft nofile 1000000
root hard nofile 1000000
EOF
    fi

    echo ""
    echo -e "${green}✅ TCP 调优配置已写入${white}"
    echo "   配置文件: /etc/sysctl.d/99-tcp-tune.conf"
    echo "   无需重启，参数立即生效"
}

# 1.4 BBR及TCP优化

enable_bbr() {
    clear
    if check_bbr_status; then
        echo -e "${green}BBR 已处于启用状态，无需重复操作${white}"
        return 0
    fi

    if ! check_kernel_bbr; then
        echo -e "${red}当前内核 $(uname -r) 不支持 BBR，需要内核版本 4.9+${white}"
        return 1
    fi

    echo -e "${cyan}正在写入 BBR 配置...${white}"

    cat > /etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc         = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max               = 33554432
net.core.wmem_max               = 33554432
net.ipv4.tcp_rmem               = 4096 87380 33554432
net.ipv4.tcp_wmem               = 4096 65536 33554432
net.core.netdev_max_backlog     = 10000
net.ipv4.tcp_max_syn_backlog    = 8192
net.core.somaxconn              = 8192
net.ipv4.tcp_fastopen           = 3
net.ipv4.tcp_slow_start_after_idle = 0
EOF

    sysctl_apply_file /etc/sysctl.d/99-bbr.conf
    sysctl -w net.core.default_qdisc=fq 2>/dev/null || true
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null || true

    if check_bbr_status; then
        echo -e "${green}✅ BBR 启用成功！网络加速已生效${white}"
    else
        echo -e "${red}❌ BBR 启用失败，当前环境可能不支持修改拥塞控制算法${white}"
        echo ""
        echo "可能原因："
        echo "  1. LXC/OpenVZ 容器且宿主机未授予 net_admin 权限"
        echo "  2. 内核未编译 BBR 模块（运行: modprobe tcp_bbr 验证）"
        echo "  3. 容器平台锁定了该参数"
        echo ""
        echo "手动验证："
        echo "  modprobe tcp_bbr && echo ok"
        echo "  echo bbr > /proc/sys/net/ipv4/tcp_congestion_control"
        return 1
    fi
}

# 1.5 将时区改为上海
system_time() {
    sudo timedatectl set-timezone Asia/Shanghai
    echo "已成功将时区改为上海"
}

# ── SWAP 操作（三个独立函数，供子菜单和一键优化复用）──────────

# 交互式添加 SWAP
swap_create() {
    echo -e "${green}请输入需要添加的swap，建议为内存的2倍！【单位为MB】${white}"
    read -p "请输入swap数值:" swapsize
    if grep -q "swapfile" /etc/fstab 2>/dev/null; then
        echo -e "${red}swapfile已存在，swap设置失败，请先删除swap后重新设置！${white}"
        return 1
    fi
    echo -e "${green}swapfile未发现，正在为其创建swapfile${white}"
    fallocate -l "${swapsize}M" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap defaults 0 0' >> /etc/fstab
    echo -e "${green}swap创建成功，并查看信息：${white}"
    cat /proc/swaps
    grep Swap /proc/meminfo
}

# 删除 SWAP
swap_delete() {
    if grep -q "swapfile" /etc/fstab 2>/dev/null; then
        echo -e "${green}swapfile已发现，正在将其移除...${white}"
        sed -i '/swapfile/d' /etc/fstab
        echo "3" > /proc/sys/vm/drop_caches
        swapoff -a
        rm -f /swapfile
        echo -e "${green}swap已删除！${white}"
    else
        echo -e "${red}swapfile未发现，swap删除失败！${white}"
    fi
}

# 自动创建 SWAP，供一键优化调用
swap_create_auto() {
    if [[ -d "/proc/vz" ]]; then
        echo -e "${red}Your VPS is based on OpenVZ, not supported!${white}"
        return 1
    fi
    if grep -q "swapfile" /etc/fstab 2>/dev/null; then
        echo -e "${green}发现现有的swapfile，正在删除...${white}"
        sed -i '/swapfile/d' /etc/fstab
        swapoff /swapfile 2>/dev/null
        rm -f /swapfile
        echo -e "${green}现有的swapfile已删除。${white}"
    else
        echo -e "${yellow}未发现现有的swapfile。${white}"
    fi
    local mem_size swap_size mem_gb
    mem_size=$(free -m | awk '/^Mem:/{print $2}')
    mem_gb=$(( mem_size / 1024 ))

    if [[ $mem_gb -le 4 ]]; then
        local double=$(( mem_size * 2 ))
        swap_size=$(( double < 4096 ? double : 4096 ))
    elif [[ $mem_gb -le 8 ]]; then
        swap_size=$mem_size
    elif [[ $mem_gb -le 64 ]]; then
        swap_size=8192
    else
        swap_size=16384
    fi

    echo -e "${green}物理内存: ${mem_size}MB，将创建 ${swap_size}MB 的 swap 文件。${white}"
    fallocate -l "${swap_size}M" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap defaults 0 0' >> /etc/fstab
    echo -e "${green}swap创建成功，当前swap信息如下：${white}"
    cat /proc/swaps
    grep Swap /proc/meminfo
}

# 1.6 SWAP 子菜单
system_swap() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${red}Error:This script must be run as root!${white}"
        exit 1
    fi
    if [[ -d "/proc/vz" ]]; then
        echo -e "${red}Your VPS is based on OpenVZ，not supported!${white}"
        exit 1
    fi

    while true; do
        clear
        echo -e "———————————————————————————————————————"
        echo -e "${green}Linux VPS一键添加/删除swap脚本${white}"
        echo -e "${green}1、添加swap${white}"
        echo -e "${green}2、删除swap${white}"
        echo -e "${green}0、返回主菜单${white}"
        echo -e "———————————————————————————————————————"
        read -p "请输入数字 [0-2]:" num
        case "$num" in
            1) swap_create ;;
            2) swap_delete ;;
            0) clear; yuju_menu; return ;;
            *) clear; echo -e "${green}请输入正确数字 [0-2]${white}" ;;
        esac
    done
}

# 1.7 修改SSH端口
# 可传入端口号参数（供一键优化使用），无参数则交互输入
system_ssh() {
    local port="${1:-}"
    if [[ -z "$port" ]]; then
        read -p "请输入要设置的SSH端口号（按Enter使用默认端口55520）: " port
        port=${port:-55520}
    fi
    sudo sed -i "s/^#\?Port .*/Port $port/g" /etc/ssh/sshd_config
    sudo systemctl restart sshd
    echo "SSH端口已修改为 $port"
}

# 1.8 安装 fail2ban
system_fail2ban() {
    apt install fail2ban -y
    sudo bash -c 'cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
#忽略的IP列表,不受设置限制（白名单）
ignoreip = 127.0.0.1

#允许ipv6
allowipv6 = auto

#日志修改检测机制（gamin、polling和auto这三种）
backend = systemd

[sshd]

#是否激活此项（true/false）
enabled = true

#过滤规则filter的名字，对应filter.d目录下的sshd.conf
filter = sshd

#ssh端口
port = ssh

#动作的相关参数
action = iptables[name=SSH, port=ssh, protocol=tcp]

#检测的系统的登陆日志文件
logpath = /var/log/secure

#屏蔽时间，单位：秒
bantime = 86400

#这个时间段内超过规定次数会被ban掉
findtime = 86400

#最大尝试次数
maxretry = 3
EOF'
    sudo systemctl enable fail2ban
    sudo systemctl restart fail2ban
    clear
    echo "已成功安装fail2ban"
}

# 1.9 密钥登录
system_keygen() {
    if [ -f ~/.ssh/id_rsa ]; then
        echo "SSH Key已经存在"
    else
        echo "创建SSH Key..."
        ssh-keygen -t rsa -f ~/.ssh/id_rsa -q -N ""
    fi
    cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    chmod 700 ~/.ssh
    sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/g' /etc/ssh/sshd_config
    sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/g' /etc/ssh/sshd_config
    sudo systemctl restart sshd
    echo "密码登录已关闭！"
    echo "密钥登录已开启！"
    echo "您的SSH Key为，请牢记！"
    cat ~/.ssh/id_rsa
}

# 1.10 创建普通 Linux 用户
system_add_user() {
    root_test

    local username shell_path password add_sudo public_key ssh_dir
    read -p "请输入要创建的普通用户名: " username
    if [ -z "$username" ]; then
        echo "用户名不能为空。"
        return 1
    fi
    if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "用户名格式不合法。建议使用小写字母、数字、下划线或短横线，且不要以数字开头。"
        return 1
    fi
    if id "$username" >/dev/null 2>&1; then
        echo "用户已存在: $username"
        return 1
    fi

    read -p "登录 Shell [/bin/bash]: " shell_path
    shell_path="${shell_path:-/bin/bash}"
    if [ ! -x "$shell_path" ]; then
        echo "Shell 不存在或不可执行: $shell_path"
        return 1
    fi

    if command -v adduser >/dev/null 2>&1; then
        adduser --disabled-password --gecos "" --shell "$shell_path" "$username" || return 1
    else
        useradd -m -s "$shell_path" "$username" || return 1
    fi

    read -s -p "设置登录密码，留空则不设置密码: " password
    echo ""
    if [ -n "$password" ]; then
        echo "${username}:${password}" | chpasswd
        echo "已设置密码。"
    else
        echo "未设置密码。需要密码登录时请之后执行: passwd $username"
    fi

    read -p "加入 sudo 组吗？[y/N]: " add_sudo
    case "$add_sudo" in
        [Yy])
            apt_install_if_missing sudo || return 1
            usermod -aG sudo "$username"
            echo "已加入 sudo 组。"
            ;;
        *) echo "未加入 sudo 组。" ;;
    esac

    read -r -p "可选：粘贴 SSH 公钥，留空跳过: " public_key
    if [ -n "$public_key" ]; then
        ssh_dir="/home/${username}/.ssh"
        mkdir -p "$ssh_dir"
        printf '%s\n' "$public_key" > "${ssh_dir}/authorized_keys"
        chown -R "${username}:${username}" "$ssh_dir"
        chmod 700 "$ssh_dir"
        chmod 600 "${ssh_dir}/authorized_keys"
        echo "已写入 SSH 公钥: ${ssh_dir}/authorized_keys"
    fi

    echo "普通用户创建完成: $username"
}

# ═══════════════════════════════════════════════════════════════
# 2. 测试脚本
# ═══════════════════════════════════════════════════════════════

# 2.1 SpeedTest 带宽测速
bandwidth_test() {
    clear
    if ! command -v jq &> /dev/null || ! command -v bc &> /dev/null; then
        echo "jq和bc未安装，现在进行安装..."
        sudo apt-get update
        sudo apt-get install -y jq bc
    else
        echo "jq和bc已安装，即将跳过..."
    fi

    local country
    country=$(curl -s ipinfo.io/country)

    if [ "$country" == "CN" ]; then
        echo "国内测速脚本的项目因滥用已被屏蔽，暂无可使用的国内测速API。"
    else
        if ! command -v speedtest &> /dev/null; then
            echo "speedtest-cli 未安装，正在安装..."
            sudo apt-get install curl -y > /dev/null 2>&1
            curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
            sudo apt-get install speedtest -y
        else
            echo "speedtest-cli 已安装，跳过安装步骤。"
        fi
        clear
        echo "本机器地理位置不在中国，使用speedtest-cli测速..."
        echo "测速中，请等待..."
        local json_output timestamp location
        local download_bandwidth download_speed upload_bandwidth upload_speed result_url
        json_output=$(speedtest --accept-license --accept-gdpr -f json-pretty)
        timestamp=$(echo "$json_output"          | jq -r '.timestamp')
        location=$(echo "$json_output"           | jq -r '.server.location')
        download_bandwidth=$(echo "$json_output" | jq -r '.download.bandwidth')
        download_speed=$(echo "scale=2; $download_bandwidth / 1000 / 1000" | bc)
        upload_bandwidth=$(echo "$json_output"   | jq -r '.upload.bandwidth')
        upload_speed=$(echo "scale=2; $upload_bandwidth / 1000 / 1000" | bc)
        result_url=$(echo "$json_output"         | jq -r '.result.url')
        echo "测试时间: $timestamp"
        echo "区域信息: $location"
        echo "下载速度: $download_speed MB/s"
        echo "上传速度: $upload_speed MB/s"
        echo "测试结果链接: $result_url"
    fi
}

# 2.2 IP 质量检测
ip_test() {
    clear
    echo "IP质量检测中..."
    bash <(curl -Ls IP.Check.Place)
}

# 2.3 nxtrace 快速回程测试
router_test() {
    clear
    curl nxtrace.org/nt | bash
    nexttrace --fast-trace --tcp
}

# 2.4 yabs 性能测试
performance_test() {
    clear
    wget -qO- yabs.sh | bash
}

# 2.5 IPv4/IPv6 优先级测试
ip_priority_test() {
    clear
    local ipv4_test="ipv4.test-ipv6.com"
    local ipv6_test="ipv6.test-ipv6.com"
    local ipv4_output ipv6_output ipv6_priority

    ipv4_output=$(curl -4 -s --max-time 5 "$ipv4_test" > /dev/null && echo "IPv4正常工作" || echo "IPv4连接失败")
    ipv6_output=$(curl -6 -s --max-time 5 "$ipv6_test" > /dev/null && echo "IPv6正常工作" || echo "IPv6连接失败")

    echo "测试连通性:"
    echo "$ipv4_output"
    echo "$ipv6_output"
    echo ""
    echo "优先级测试:"
    ipv6_priority=$(grep "precedence ::ffff:0:0/96" /etc/gai.conf 2>/dev/null | grep -v "#" | wc -l)

    if [[ "$ipv6_output" == "IPv6正常工作" && "$ipv4_output" == "IPv4正常工作" ]]; then
        if [ "$ipv6_priority" -gt 0 ]; then
            echo "IPv4的优先级更高"
        else
            echo "IPv6的优先级更高"
        fi
    elif [[ "$ipv6_output" == "IPv6正常工作" ]]; then
        echo "只有IPv6正常工作, 因此IPv6优先级更高"
    elif [[ "$ipv4_output" == "IPv4正常工作" ]]; then
        echo "只有IPv4正常工作, 因此IPv4优先级更高"
    else
        echo "IPv4 和 IPv6 似乎都无法正常工作。"
    fi
}

# 2.6 硬盘 I/O 测试
io_test() {
    (LANG=C dd if=/dev/zero of=test_$$ bs=64k count=16k conv=fdatasync && rm -f test_$$) \
        2>&1 | awk -F, '{io=$NF} END { print io}' | sed 's/^[ \t]*//;s/[ \t]*$//'
}

io_info() {
    echo "开始测试IO性能..."
    local io1 io2 io3 ioraw1 ioraw2 ioraw3 ioall ioavg
    io1=$(io_test); echo "硬盘I/O (第一次测试) : $io1"
    io2=$(io_test); echo "硬盘I/O (第二次测试) : $io2"
    io3=$(io_test); echo "硬盘I/O (第三次测试) : $io3"
    ioraw1=$(echo "$io1" | awk 'NR==1 {print $1}')
    [ "$(echo "$io1" | awk 'NR==1 {print $2}')" == "GB/s" ] && ioraw1=$(awk "BEGIN{print $ioraw1 * 1024}")
    ioraw2=$(echo "$io2" | awk 'NR==1 {print $1}')
    [ "$(echo "$io2" | awk 'NR==1 {print $2}')" == "GB/s" ] && ioraw2=$(awk "BEGIN{print $ioraw2 * 1024}")
    ioraw3=$(echo "$io3" | awk 'NR==1 {print $1}')
    [ "$(echo "$io3" | awk 'NR==1 {print $2}')" == "GB/s" ] && ioraw3=$(awk "BEGIN{print $ioraw3 * 1024}")
    ioall=$(awk "BEGIN{print $ioraw1 + $ioraw2 + $ioraw3}")
    ioavg=$(awk "BEGIN{print $ioall / 3}")
    echo "硬盘I/O (平均值) : $ioavg MB/s"
}

# ═══════════════════════════════════════════════════════════════
# 3. 常用工具安装
# ═══════════════════════════════════════════════════════════════

# 3.11 Starship 终端美化安装器（自包含，检测国内自动切镜像）
starship_install() {
    set -eu
    printf '\n'

    BOLD="$(tput bold 2>/dev/null || printf '')"
    GREY="$(tput setaf 0 2>/dev/null || printf '')"
    UNDERLINE="$(tput smul 2>/dev/null || printf '')"
    RED="$(tput setaf 1 2>/dev/null || printf '')"
    GREEN="$(tput setaf 2 2>/dev/null || printf '')"
    YELLOW="$(tput setaf 3 2>/dev/null || printf '')"
    BLUE="$(tput setaf 4 2>/dev/null || printf '')"
    MAGENTA="$(tput setaf 5 2>/dev/null || printf '')"
    NO_COLOR="$(tput sgr0 2>/dev/null || printf '')"

    detect_in_china() {
        local response
        if command -v curl &>/dev/null; then
            response=$(curl -s --connect-timeout 2 -m 4 cip.cc 2>/dev/null)
        elif command -v wget &>/dev/null; then
            response=$(wget -qO- --timeout=4 cip.cc 2>/dev/null)
        else
            return 1
        fi
        echo "$response" | grep -q "中国"
    }

    SUPPORTED_TARGETS="x86_64-unknown-linux-gnu x86_64-unknown-linux-musl \
                      i686-unknown-linux-musl aarch64-unknown-linux-musl \
                      arm-unknown-linux-musleabihf x86_64-apple-darwin \
                      aarch64-apple-darwin x86_64-pc-windows-msvc \
                      i686-pc-windows-msvc aarch64-pc-windows-msvc \
                      x86_64-unknown-freebsd"

    info()      { printf '%s\n' "${BOLD}${GREY}>${NO_COLOR} $*"; }
    warn()      { printf '%s\n' "${YELLOW}! $*${NO_COLOR}"; }
    error()     { printf '%s\n' "${RED}x $*${NO_COLOR}" >&2; }
    completed() { printf '%s\n' "${GREEN}✓${NO_COLOR} $*"; }
    has()       { command -v "$1" 1>/dev/null 2>&1; }

    curl_is_snap() {
        local curl_path
        curl_path="$(command -v curl)"
        case "$curl_path" in /snap/*) return 0 ;; *) return 1 ;; esac
    }

    get_tmpfile() {
        local suffix="$1"
        if has mktemp; then
            printf "%s.%s" "$(mktemp)" "${suffix}"
        else
            printf "/tmp/starship.%s" "${suffix}"
        fi
    }

    test_writeable() {
        local path="${1:-}/test.txt"
        if touch "${path}" 2>/dev/null; then rm "${path}"; return 0; else return 1; fi
    }

    download() {
        local file="$1" url="$2"
        if has curl && curl_is_snap; then
            warn "curl installed through snap cannot download starship."
            warn "See https://github.com/starship/starship/issues/5403 for details."
            warn "Searching for other HTTP download programs..."
        fi
        local cmd rc
        if has curl && ! curl_is_snap; then
            cmd="curl --fail --silent --location --output $file $url"
        elif has wget; then
            cmd="wget --quiet --output-document=$file $url"
        elif has fetch; then
            cmd="fetch --quiet --output=$file $url"
        else
            error "No HTTP download program (curl, wget, fetch) found, exiting…"
            return 1
        fi
        $cmd && return 0 || rc=$?
        error "Command failed (exit code $rc): ${BLUE}${cmd}${NO_COLOR}"
        printf "\n" >&2
        info "This is likely due to Starship not yet supporting your configuration."
        info "If you would like to see a build for your configuration,"
        info "please create an issue requesting a build for ${MAGENTA}${TARGET}${NO_COLOR}:"
        info "${BOLD}${UNDERLINE}https://github.com/starship/starship/issues/new/${NO_COLOR}"
        return $rc
    }

    unpack() {
        local archive=$1 bin_dir=$2 sudo=${3-}
        case "$archive" in
            *.tar.gz)
                local flags
                flags=$(test -n "${VERBOSE-}" && echo "-xzvof" || echo "-xzof")
                ${sudo} tar "${flags}" "${archive}" -C "${bin_dir}"
                return 0
                ;;
            *.zip)
                local flags
                flags=$(test -z "${VERBOSE-}" && echo "-qqo" || echo "-o")
                UNZIP="${flags}" ${sudo} unzip "${archive}" -d "${bin_dir}"
                return 0
                ;;
        esac
        error "Unknown package extension."
        printf "\n"
        info "This almost certainly results from a bug in this script--please file a"
        info "bug report at https://github.com/starship/starship/issues"
        return 1
    }

    usage() {
        printf "%s\n" \
            "install.sh [option]" \
            "" \
            "Fetch and install the latest version of starship, if starship is already" \
            "installed it will be updated to the latest version."
        printf "\n%s\n" "Options"
        printf "\t%s\n\t\t%s\n\n" \
            "-V, --verbose" "Enable verbose output for the installer" \
            "-f, -y, --force, --yes" "Skip the confirmation prompt during installation" \
            "-p, --platform" "Override the platform identified by the installer [default: ${PLATFORM}]" \
            "-b, --bin-dir" "Override the bin installation directory [default: ${BIN_DIR}]" \
            "-a, --arch" "Override the architecture identified by the installer [default: ${ARCH}]" \
            "-B, --base-url" "Override the base URL used for downloading releases [default: ${BASE_URL}]" \
            "-v, --version" "Install a specific version of starship [default: ${VERSION}]" \
            "-h, --help" "Display this help message"
    }

    elevate_priv() {
        if ! has sudo; then
            error 'Could not find the command "sudo", needed to get permissions for install.'
            info "If you are on Windows, please run your shell as an administrator, then"
            info "rerun this script. Otherwise, please run this script as root, or install"
            info "sudo."
            exit 1
        fi
        if ! sudo -v; then
            error "Superuser not granted, aborting installation"
            exit 1
        fi
    }

    install() {
        local ext="$1"
        local sudo msg archive
        if test_writeable "${BIN_DIR}"; then
            sudo=""
            msg="Installing Starship, please wait…"
        else
            warn "Escalated permissions are required to install to ${BIN_DIR}"
            elevate_priv
            sudo="sudo"
            msg="Installing Starship as root, please wait…"
        fi
        info "$msg"
        archive=$(get_tmpfile "$ext")
        download "${archive}" "${URL}"
        unpack "${archive}" "${BIN_DIR}" "${sudo}"
    }

    detect_platform() {
        local platform
        platform="$(uname -s | tr '[:upper:]' '[:lower:]')"
        case "${platform}" in
            msys_nt*)   platform="pc-windows-msvc" ;;
            cygwin_nt*) platform="pc-windows-msvc" ;;
            mingw*)     platform="pc-windows-msvc" ;;
            linux)      platform="unknown-linux-musl" ;;
            darwin)     platform="apple-darwin" ;;
            freebsd)    platform="unknown-freebsd" ;;
        esac
        printf '%s' "${platform}"
    }

    detect_arch() {
        local arch
        arch="$(uname -m | tr '[:upper:]' '[:lower:]')"
        case "${arch}" in
            amd64) arch="x86_64" ;;
            armv*) arch="arm" ;;
            arm64) arch="aarch64" ;;
        esac
        if [ "${arch}" = "x86_64" ] && [ "$(getconf LONG_BIT)" -eq 32 ]; then
            arch=i686
        elif [ "${arch}" = "aarch64" ] && [ "$(getconf LONG_BIT)" -eq 32 ]; then
            arch=arm
        fi
        printf '%s' "${arch}"
    }

    detect_target() {
        local arch="$1" platform="$2"
        local target="${arch}-${platform}"
        [ "${target}" = "arm-unknown-linux-musl" ] && target="${target}eabihf"
        printf '%s' "${target}"
    }

    confirm() {
        if [ -z "${FORCE-}" ]; then
            printf "%s " "${MAGENTA}?${NO_COLOR} $* ${BOLD}[y/N]${NO_COLOR}"
            set +e
            read -r yn </dev/tty
            local rc=$?
            set -e
            if [ $rc -ne 0 ]; then
                error "Error reading from prompt (please re-run with the '--yes' option)"
                exit 1
            fi
            if [ "$yn" != "y" ] && [ "$yn" != "yes" ]; then
                error 'Aborting (please answer "yes" to continue)'
                exit 1
            fi
        fi
    }

    check_bin_dir() {
        local bin_dir="${1%/}"
        if [ ! -d "$BIN_DIR" ]; then
            error "Installation location $BIN_DIR does not appear to be a directory"
            info "Make sure the location exists and is a directory, then try again."
            usage
            exit 1
        fi
        local good
        good=$(IFS=:; for path in $PATH; do
            if [ "${path%/}" = "${bin_dir}" ]; then printf 1; break; fi
        done)
        [ "${good}" != "1" ] && warn "Bin directory ${bin_dir} is not in your \$PATH"
    }

    print_install() {
        for s in "bash" "zsh" "ion" "tcsh" "xonsh" "fish"; do
            local config_file="~/.${s}rc"
            local config_cmd="eval \"\$(starship init ${s})\""
            case ${s} in
                ion)   config_file="~/.config/ion/initrc"; config_cmd="eval \$(starship init ${s})" ;;
                fish)  config_file="~/.config/fish/config.fish"; config_cmd="starship init fish | source" ;;
                tcsh)  config_cmd="eval \`starship init ${s}\`" ;;
                xonsh) config_cmd="execx(\$(starship init xonsh))" ;;
            esac
            printf "  %s\n  Add the following to the end of %s:\n\n\t%s\n\n" \
                "${BOLD}${UNDERLINE}${s}${NO_COLOR}" \
                "${BOLD}${config_file}${NO_COLOR}" \
                "${config_cmd}"
        done
        for s in "elvish" "nushell"; do
            local warning="${BOLD}Warning${NO_COLOR}"
            local config_file config_cmd
            case ${s} in
                elvish)
                    config_file="~/.elvish/rc.elv"
                    config_cmd="eval (starship init elvish)"
                    warning="${warning} Only elvish v0.17 or higher is supported."
                    ;;
                nushell)
                    config_file="${BOLD}your nu config file${NO_COLOR} (find it by running ${BOLD}\$nu.config-path${NO_COLOR} in Nushell)"
                    config_cmd="mkdir (\$nu.data-dir | path join \"vendor/autoload\")
            starship init nu | save -f (\$nu.data-dir | path join \"vendor/autoload/starship.nu\")"
                    warning="${warning} This will change in the future.
      Only Nushell v0.96 or higher is supported."
                    ;;
            esac
            printf "  %s\n  %s\n  And add the following to the end of %s:\n\n\t%s\n\n" \
                "${BOLD}${UNDERLINE}${s}${NO_COLOR}" \
                "${warning}" \
                "${config_file}" \
                "${config_cmd}"
        done
        printf "  %s\n  Add the following to the end of %s:\n  %s\n\n\t%s\n\n" \
            "${BOLD}${UNDERLINE}PowerShell${NO_COLOR}" \
            "${BOLD}Microsoft.PowerShell_profile.ps1${NO_COLOR}" \
            "You can check the location of this file by querying the \$PROFILE variable in PowerShell." \
            "Invoke-Expression (&starship init powershell)"
        printf "  %s\n  You need to use Clink (v1.2.30+) with Cmd. Add the following to a file %s and place this file in Clink scripts directory:\n\n\t%s\n\n" \
            "${BOLD}${UNDERLINE}Cmd${NO_COLOR}" \
            "${BOLD}starship.lua${NO_COLOR}" \
            "load(io.popen('starship init cmd'):read(\"*a\"))()"
        printf "\n"
    }

    is_build_available() {
        local arch="$1" platform="$2" target="$3"
        local good
        good=$(IFS=" "; for t in $SUPPORTED_TARGETS; do
            if [ "${t}" = "${target}" ]; then printf 1; break; fi
        done)
        if [ "${good}" != "1" ]; then
            error "${arch} builds for ${platform} are not yet available for Starship"
            printf "\n" >&2
            info "If you would like to see a build for your configuration,"
            info "please create an issue requesting a build for ${MAGENTA}${target}${NO_COLOR}:"
            info "${BOLD}${UNDERLINE}https://github.com/starship/starship/issues/new/${NO_COLOR}"
            printf "\n"
            exit 1
        fi
    }

    # 默认值
    [ -z "${PLATFORM-}" ] && PLATFORM="$(detect_platform)"
    [ -z "${BIN_DIR-}" ]  && BIN_DIR=/usr/local/bin
    [ -z "${ARCH-}" ]     && ARCH="$(detect_arch)"
    if [ -z "${BASE_URL-}" ]; then
        if detect_in_china; then
            BASE_URL="https://ghfast.top/https://github.com/starship/starship/releases"
            info "检测到国内机器，已自动切换镜像源"
        else
            BASE_URL="https://github.com/starship/starship/releases"
        fi
    fi
    [ -z "${VERSION-}" ] && VERSION="latest"

    # 解析参数
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -p | --platform)   PLATFORM="$2"; shift 2 ;;
            -b | --bin-dir)    BIN_DIR="$2";  shift 2 ;;
            -a | --arch)       ARCH="$2";     shift 2 ;;
            -B | --base-url)   BASE_URL="$2"; shift 2 ;;
            -v | --version)    VERSION="$2";  shift 2 ;;
            -V | --verbose)    VERBOSE=1;     shift 1 ;;
            -f | -y | --force | --yes) FORCE=1; shift 1 ;;
            -h | --help)       usage; exit ;;
            -p=*) PLATFORM="${1#*=}"; shift 1 ;;
            -b=*) BIN_DIR="${1#*=}";  shift 1 ;;
            -a=*) ARCH="${1#*=}";     shift 1 ;;
            -B=*) BASE_URL="${1#*=}"; shift 1 ;;
            -v=*) VERSION="${1#*=}";  shift 1 ;;
            -V=*) VERBOSE="${1#*=}";  shift 1 ;;
            -f=* | -y=* | --force=* | --yes=*) FORCE="${1#*=}"; shift 1 ;;
            *) error "Unknown option: $1"; usage; exit 1 ;;
        esac
    done

    TARGET="$(detect_target "${ARCH}" "${PLATFORM}")"
    is_build_available "${ARCH}" "${PLATFORM}" "${TARGET}"

    printf "  %s\n" "${UNDERLINE}Configuration${NO_COLOR}"
    info "${BOLD}Bin directory${NO_COLOR}: ${GREEN}${BIN_DIR}${NO_COLOR}"
    info "${BOLD}Platform${NO_COLOR}:      ${GREEN}${PLATFORM}${NO_COLOR}"
    info "${BOLD}Arch${NO_COLOR}:          ${GREEN}${ARCH}${NO_COLOR}"

    if [ -n "${VERBOSE-}" ]; then VERBOSE=v; info "${BOLD}Verbose${NO_COLOR}: yes"; else VERBOSE=; fi

    printf '\n'

    local EXT=tar.gz
    [ "${PLATFORM}" = "pc-windows-msvc" ] && EXT=zip

    local URL
    if [ "${VERSION}" != "latest" ]; then
        URL="${BASE_URL}/download/${VERSION}/starship-${TARGET}.${EXT}"
    else
        URL="${BASE_URL}/latest/download/starship-${TARGET}.${EXT}"
    fi

    info "Tarball URL: ${UNDERLINE}${BLUE}${URL}${NO_COLOR}"
    confirm "Install Starship ${GREEN}${VERSION}${NO_COLOR} to ${BOLD}${GREEN}${BIN_DIR}${NO_COLOR}?"
    check_bin_dir "${BIN_DIR}"
    install "${EXT}"
    completed "Starship ${VERSION} installed"
    printf '\n'
    info "Please follow the steps for your shell to complete the installation:"
    print_install
    set +eu
}

# 3.11 zsh + Starship 终端美化
download_zsh() {
    clear
    apt install zsh -y && apt install curl -y
    chsh -s "$(which zsh)"
    ( starship_install -y ) || echo -e "${yellow}Starship 安装失败，已跳过${white}"
    echo 'eval "$(starship init zsh)"'  >> ~/.zshrc
    echo 'eval "$(starship init bash)"' >> ~/.bashrc
    echo "zsh+Starship安装完成,重新登录终端即可启用"
}

# 3.12 一键安装所有常用工具
download_all() {
    clear
    apt install curl wget nano unzip tar tmux iftop btop gdu fzf -y
    download_zsh
    echo "已全部安装"
}

# ═══════════════════════════════════════════════════════════════
# 4. Docker 管理
# ═══════════════════════════════════════════════════════════════

# 4.1 安装 Docker
docker_os_release() {
    local key="$1"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$key" in
            id) echo "${ID:-}" ;;
            codename) echo "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}" ;;
        esac
    fi
}

docker_start_service() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now docker >/dev/null 2>&1 || systemctl restart docker >/dev/null 2>&1 || true
    else
        service docker restart >/dev/null 2>&1 || true
    fi
}

docker_install_compose_fallback() {
    if docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; then
        return 0
    fi

    apt-get update -y || return 1
    if apt-cache show docker-compose-plugin >/dev/null 2>&1; then
        apt-get install -y docker-compose-plugin && return 0
    fi
    if apt-cache show docker-compose >/dev/null 2>&1; then
        apt-get install -y docker-compose && return 0
    fi

    echo "Docker Compose 未找到可安装包，Docker 本体已继续安装。"
    return 0
}

docker_configure_cn_mirror() {
    mkdir -p /etc/docker
    if [ -f /etc/docker/daemon.json ]; then
        cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date +%F_%H%M%S)"
    fi
    cat > /etc/docker/daemon.json << 'EOF'
{
    "registry-mirrors": ["https://docker.1panel.live"]
}
EOF
}

docker_install_from_apt_repo() {
    local os_id codename arch repo_url optional_pkg
    os_id=$(docker_os_release id)
    codename=$(docker_os_release codename)
    arch=$(dpkg --print-architecture)

    if [ -z "$os_id" ] || [ -z "$codename" ]; then
        echo "无法识别系统发行版，不能自动添加 Docker APT 源。"
        return 1
    fi
    if [ "$os_id" != "debian" ] && [ "$os_id" != "ubuntu" ]; then
        echo "当前仅支持 Debian/Ubuntu 自动安装 Docker。"
        return 1
    fi

    if [ "$os_id" = "debian" ] && [ "$codename" = "buster" ]; then
        echo "检测到 Debian 10 buster。官方一键脚本已不稳定，将改用兼容 APT 安装方式。"
    else
        echo "正在使用 Docker 官方 APT 源安装。"
    fi

    apt-get update -y || return 1
    apt-get install -y ca-certificates curl gnupg || return 1
    install -m 0755 -d /etc/apt/keyrings || return 1

    repo_url="https://download.docker.com/linux/${os_id}"
    curl -fsSL "${repo_url}/gpg" -o /etc/apt/keyrings/docker.asc || return 1
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] ${repo_url} ${codename} stable" > /etc/apt/sources.list.d/docker.list

    apt-get update -y || return 1

    apt-get install -y docker-ce docker-ce-cli containerd.io || return 1

    for optional_pkg in docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras; do
        if apt-cache show "$optional_pkg" >/dev/null 2>&1; then
            apt-get install -y "$optional_pkg" || echo "可选包安装失败，已跳过: $optional_pkg"
        else
            echo "跳过不可用包: $optional_pkg"
        fi
    done

    docker_install_compose_fallback
}

docker_install() {
    clear
    root_test

    local country
    if command -v docker >/dev/null 2>&1; then
        echo "Docker 已安装，检查 Compose 和服务状态..."
        docker_install_compose_fallback
        docker_start_service
        docker --version
        docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true
        return 0
    fi

    apt-get install -y curl >/dev/null 2>&1 || true
    if command -v curl >/dev/null 2>&1; then
        country=$(curl -s --max-time 5 ipinfo.io/country 2>/dev/null || true)
    else
        country=""
    fi

    if [ "$country" = "CN" ]; then
        echo "本机器地理位置为中国，优先使用国内安装脚本..."
        if bash <(curl -fsSL https://linuxmirrors.cn/docker.sh); then
            rm -f ./docker-install
            echo "正在配置 Docker 国内镜像源..."
            docker_configure_cn_mirror
        else
            echo "国内安装脚本失败，改用 Docker 官方 APT 源安装。"
            docker_install_from_apt_repo || return 1
        fi
    else
        echo "本机器地理位置不在中国，使用 Docker 官方 APT 源安装..."
        docker_install_from_apt_repo || return 1
    fi

    docker_start_service
    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker 安装失败：docker 命令不存在。"
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        echo "Docker 已安装，但 Docker 服务未正常启动，请检查: systemctl status docker"
        return 1
    fi

    docker --version
    docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo "Docker Compose 未安装。"
    echo "Docker 安装过程完成。"
}

# 4.2 查看 Docker 全局状态
docker_status() {
    if ! command -v docker &> /dev/null; then
        echo "Docker 环境不存在，请确保 Docker 已安装并配置。"
        return 1
    fi
    echo "Docker版本"
    docker -v
    docker compose version
    echo ""
    echo "Docker镜像列表";  docker image ls;   echo ""
    echo "Docker容器列表";  docker ps -a;       echo ""
    echo "Docker卷列表";    docker volume ls;   echo ""
    echo "Docker网络列表";  docker network ls;  echo ""
    if [ -f /etc/docker/daemon.json ]; then
        local mirrors
        mirrors=$(jq -r '.["registry-mirrors"][]' /etc/docker/daemon.json 2>/dev/null)
        if [ -n "$mirrors" ]; then
            echo "镜像源地址"
            echo "$mirrors"
        else
            echo "未配置镜像源"
        fi
    fi
}

# 4.3 清理无用的镜像容器网络
docker_clean() {
    clear
    read -p "$(echo -e "${yellow}提示: ${white}将清理无用的镜像容器网络，包括停止的容器，确定清理吗？(Y/N): ")" choice
    case "$choice" in
        [Yy]) docker system prune -af --volumes ;;
        [Nn]) ;;
        *)    echo "无效的选择，请输入 Y 或 N。" ;;
    esac
}

# 4.4 更换 Docker 源
docker_mirrors() {
    local docker_daemon="/etc/docker/daemon.json"
    if [ ! -f "$docker_daemon" ]; then
        echo "文件 $docker_daemon 不存在，请确保 Docker 已安装并配置。"
        exit 1
    fi

    local new_mirror
    get_mirror_input() {
        while true; do
            read -p "请输入镜像源地址（含http://或https://），输入'q'退出: " new_mirror
            [ "$new_mirror" = "q" ] && { echo "操作已取消。"; docker_manage; return; }
            [[ "$new_mirror" =~ ^https?:// ]] && break
            echo "错误：镜像源地址必须以 http:// 或 https:// 开头，请重新输入。"
        done
    }

    if grep -q '"registry-mirrors"' "$docker_daemon"; then
        echo "检测到已有镜像源地址。"
        get_mirror_input
        sudo sed -i 's|"registry-mirrors":\s*\[[^]]*\]|"registry-mirrors": ["'"$new_mirror"'"]|' "$docker_daemon"
        echo "镜像源地址已更新为: $new_mirror"
    else
        echo "未检测到镜像源地址。"
        get_mirror_input
        sudo cat > "$docker_daemon" << EOF
{
    "registry-mirrors": ["$new_mirror"]
}
EOF
        echo "registry-mirrors 已添加为: $new_mirror"
    fi
    echo "正在重启 Docker 服务以应用更改..."
    sudo systemctl restart docker
    echo "修改完成！"
}

# 4.5 开启 Docker IPv6
docker_ipv6_on() {
    mkdir -p /etc/docker &>/dev/null
    cat > /etc/docker/daemon.json << 'EOF'
{
  "ipv6": true,
  "fixed-cidr-v6": "2001:db8:1::/64"
}
EOF
    systemctl restart docker
    echo "Docker已开启v6访问"
}

# 4.6 关闭 Docker IPv6
docker_ipv6_off() {
    rm -rf /etc/docker/daemon.json &>/dev/null
    systemctl restart docker
    echo "Docker已关闭v6访问"
}

# 4.9 卸载 Docker
docker_uninstall() {
    clear
    read -p "$(echo -e "${red}注意: ${white}确定卸载docker环境吗？(Y/N): ")" choice
    case "$choice" in
        [Yy])
            docker rm $(docker ps -a -q) && docker rmi $(docker images -q) && docker network prune
            sudo apt-get purge -y docker-engine docker docker.io docker-ce docker-ce-cli
            sudo rm -rf /var/lib/docker
            sudo rm -rf /etc/docker
            sudo rm -rf /var/run/docker.sock
            ;;
        [Nn]) ;;
        *)    echo "无效的选择，请输入 Y 或 N。" ;;
    esac
}


# ═══════════════════════════════════════════════════════════════
# 子菜单
# ═══════════════════════════════════════════════════════════════

# 1. 系统相关子菜单
# 5. 3x-ui secure deployment helpers
apt_install_if_missing() {
    local pkg="$1"
    if command -v "$pkg" >/dev/null 2>&1; then
        return 0
    fi
    apt-get update -y && apt-get install -y "$pkg"
}

docker_compose_run() {
    if docker compose version >/dev/null 2>&1; then
        docker compose "$@"
        return $?
    fi
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose "$@"
        return $?
    fi
    return 127
}

current_ssh_port() {
    local port
    port=$(ss -lntp 2>/dev/null | awk '/sshd/ { sub(/.*:/, "", $4); print $4; exit }')
    if [ -z "$port" ] && [ -f /etc/ssh/sshd_config ]; then
        port=$(awk '$1 == "Port" { print $2; exit }' /etc/ssh/sshd_config)
    fi
    echo "${port:-22}"
}

tailscale_install_config() {
    root_test
    apt_install_if_missing curl || return 1

    if ! command -v tailscale >/dev/null 2>&1; then
        echo "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
    fi

    systemctl enable --now tailscaled 2>/dev/null || true
    echo "Starting tailscale login. If it prints a login URL, open it once."
    tailscale up
    echo "Tailscale IPv4:"
    tailscale ip -4 2>/dev/null || true
    tailscale status 2>/dev/null || true
}

ufw_safe_setup() {
    root_test
    apt_install_if_missing ufw || return 1

    local ssh_port public_ports admin_ip admin_port confirm
    ssh_port=$(current_ssh_port)

    echo "将保留 SSH 访问，并允许 tailscale0 网卡流量。"
    echo "注意: Docker 映射端口可能绕过 UFW，3x-ui 面板仍应绑定到 Tailscale IP。"
    read -p "需要放行的 SSH 端口 [${ssh_port}]: " input_ssh_port
    ssh_port="${input_ssh_port:-$ssh_port}"

    read -p "这会重置现有 UFW 规则，继续吗？[y/N]: " confirm
    case "$confirm" in
        [Yy]) ;;
        *) echo "已取消。"; return 0 ;;
    esac

    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "${ssh_port}/tcp" comment "SSH"
    ufw allow in on tailscale0 comment "Tailscale"

    read -p "需要公网开放的 TCP 端口，空格分隔 [2096 8080]: " public_ports
    public_ports="${public_ports:-2096 8080}"
    for port in $public_ports; do
        [ -n "$port" ] && ufw allow "${port}/tcp" comment "public-service"
    done

    read -p "可选：允许访问面板的管理端来源 IP，留空跳过: " admin_ip
    if [ -n "$admin_ip" ]; then
        read -p "只允许 ${admin_ip} 访问的面板宿主机端口: " admin_port
        if [ -n "$admin_port" ]; then
            ufw allow from "$admin_ip" to any port "$admin_port" proto tcp comment "admin-panel"
        fi
    fi

    ufw --force enable
    ufw status numbered
}

xui_tailscale_ip() {
    tailscale ip -4 2>/dev/null | awk 'NF { print; exit }'
}

xui_prompt_container() {
    local container
    read -p "3x-ui container name [3x-ui]: " container
    container="${container:-3x-ui}"
    if ! docker inspect "$container" >/dev/null 2>&1; then
        echo "未找到容器: $container" >&2
        return 1
    fi
    echo "$container"
}

xui_db_dir() {
    docker inspect "$1" --format '{{range .Mounts}}{{if eq .Destination "/etc/x-ui"}}{{println .Source}}{{end}}{{end}}' 2>/dev/null | awk 'NF { print; exit }'
}

xui_read_db_setting() {
    local db_file="$1"
    local key="$2"
    if [ -f "$db_file" ] && command -v sqlite3 >/dev/null 2>&1; then
        sqlite3 "$db_file" "select value from settings where key='${key}' limit 1;" 2>/dev/null
    fi
}

xui_upsert_db_setting() {
    local db_file="$1"
    local key="$2"
    local value="$3"
    apt_install_if_missing sqlite3 || return 1
    if [ ! -f "$db_file" ]; then
        echo "DB not found: $db_file"
        return 1
    fi
    cp "$db_file" "${db_file}.bak.$(date +%F_%H%M%S)"
    sqlite3 "$db_file" "insert into settings(key,value) values('${key}','${value}') on conflict(key) do update set value=excluded.value;"
}

xui_yaml_escape() {
    printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

xui_backup_container() {
    local container="$1"
    local backup="/root/3xui-backup-$(date +%F_%H%M%S)"
    mkdir -p "$backup"
    docker inspect "$container" > "$backup/docker-inspect.json"
    docker cp "$container:/etc/x-ui" "$backup/etc-x-ui" >/dev/null 2>&1 || true
    docker cp "$container:/root/cert" "$backup/root-cert" >/dev/null 2>&1 || true
    echo "$backup"
}

xui_write_env_yaml() {
    local container="$1"
    local timezone="$2"
    local envs
    envs=$(docker inspect "$container" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -v '^PATH=' | grep -v '^TZ=' || true)

    echo "    environment:"
    echo "      TZ: \"$(xui_yaml_escape "$timezone")\""
    while IFS= read -r envline; do
        [ -z "$envline" ] && continue
        local key="${envline%%=*}"
        local val="${envline#*=}"
        echo "      ${key}: \"$(xui_yaml_escape "$val")\""
    done <<< "$envs"
}

xui_write_mounts_yaml() {
    local container="$1"
    local volumes_file="$2"
    local volume_names_file="$3"
    local mounts
    mounts=$(docker inspect "$container" --format '{{range .Mounts}}{{println .Type "|" .Name "|" .Source "|" .Destination}}{{end}}')

    echo "    volumes:"
    while IFS='|' read -r mtype mname msource mdest; do
        mtype=$(echo "$mtype" | xargs)
        mname=$(echo "$mname" | xargs)
        msource=$(echo "$msource" | xargs)
        mdest=$(echo "$mdest" | xargs)
        [ -z "$mdest" ] && continue
        if [ "$mtype" = "volume" ]; then
            if [ -n "$mname" ]; then
                echo "      - ${mname}:${mdest}"
                if ! grep -qx "$mname" "$volume_names_file" 2>/dev/null; then
                    echo "$mname" >> "$volume_names_file"
                fi
            else
                echo "      - \"$(xui_yaml_escape "$msource"):${mdest}\""
            fi
        else
            echo "      - \"$(xui_yaml_escape "$msource"):${mdest}\""
        fi
    done <<< "$mounts"
}

xui_write_bridge_ports_yaml() {
    local container="$1"
    local tailscale_ip="$2"
    local panel_container_port="$3"
    local panel_host_port="$4"
    local line container_part host_part host_ip host_port container_port proto key
    declare -A seen_ports=()

    echo "    ports:"
    echo "      - \"${tailscale_ip}:${panel_host_port}:${panel_container_port}/tcp\""
    seen_ports["${panel_container_port}/tcp"]=1

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        container_part="${line%% -> *}"
        host_part="${line#* -> }"
        proto="${container_part##*/}"
        container_port="${container_part%%/*}"
        host_port="${host_part##*:}"
        host_ip="${host_part%:*}"
        key="${container_port}/${proto}"

        [ "$key" = "${panel_container_port}/tcp" ] && continue
        [ -n "${seen_ports[$key]}" ] && continue
        seen_ports["$key"]=1

        if echo "$host_ip" | grep -q ':'; then
            continue
        fi
        echo "      - \"${host_port}:${container_port}/${proto}\""
    done < <(docker port "$container" 2>/dev/null)
}

xui_show_container_ports() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker 未安装。"
        return 1
    fi
    local container
    container=$(xui_prompt_container) || return 1
    echo "Container: $container"
    docker inspect "$container" --format 'Image={{.Config.Image}} NetworkMode={{.HostConfig.NetworkMode}}'
    echo "Mounts:"
    docker inspect "$container" --format '{{range .Mounts}}{{println .Type .Name .Source "->" .Destination}}{{end}}'
    echo "Ports:"
    docker port "$container" 2>/dev/null || true
    echo "Tailscale IPv4: $(xui_tailscale_ip)"
}

xui_generate_compose() {
    root_test
    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker 未安装。"
        return 1
    fi
    if ! docker_compose_run version >/dev/null 2>&1; then
        echo "Docker Compose 未安装，请先安装 docker compose 或 docker-compose。"
        return 1
    fi

    local container image network_mode tailscale_ip timezone compose_dir compose_file volume_names_file backup db_dir db_file web_port panel_host_port input_port restart_policy set_listen migrate
    container=$(xui_prompt_container) || return 1
    image=$(docker inspect "$container" --format '{{.Config.Image}}')
    network_mode=$(docker inspect "$container" --format '{{.HostConfig.NetworkMode}}')
    restart_policy=$(docker inspect "$container" --format '{{.HostConfig.RestartPolicy.Name}}')
    restart_policy="${restart_policy:-unless-stopped}"
    tailscale_ip=$(xui_tailscale_ip)
    if [ -z "$tailscale_ip" ]; then
        echo "未找到 Tailscale IPv4，请先完成 Tailscale 安装/登录。"
        return 1
    fi

    read -p "Timezone [Asia/Shanghai]: " timezone
    timezone="${timezone:-Asia/Shanghai}"

    backup=$(xui_backup_container "$container") || return 1
    echo "备份已保存: $backup"

    db_dir=$(xui_db_dir "$container")
    db_file="${db_dir}/x-ui.db"
    if [ -f "$db_file" ]; then
        apt_install_if_missing sqlite3 || return 1
    fi
    web_port=$(xui_read_db_setting "$db_file" webPort)
    web_port="${web_port:-2053}"

    if [ "$network_mode" != "host" ]; then
        read -p "绑定到 Tailscale IP 的面板宿主机端口 [54321]: " input_port
        panel_host_port="${input_port:-54321}"
    fi

    compose_dir="/opt/3x-ui-compose"
    compose_file="${compose_dir}/docker-compose.yml"
    volume_names_file="$(mktemp)"
    mkdir -p "$compose_dir"
    : > "$volume_names_file"

    {
        echo "services:"
        echo "  3x-ui:"
        echo "    image: \"$(xui_yaml_escape "$image")\""
        echo "    container_name: \"${container}\""
        echo "    restart: \"${restart_policy}\""
        xui_write_env_yaml "$container" "$timezone"
        xui_write_mounts_yaml "$container" "$compose_file" "$volume_names_file"
        if [ "$network_mode" = "host" ]; then
            echo "    network_mode: \"host\""
        else
            echo "    cap_add:"
            echo "      - NET_ADMIN"
            echo "      - NET_RAW"
            xui_write_bridge_ports_yaml "$container" "$tailscale_ip" "$web_port" "$panel_host_port"
        fi
        if [ -s "$volume_names_file" ]; then
            echo ""
            echo "volumes:"
            while IFS= read -r vname; do
                [ -n "$vname" ] && echo "  ${vname}:"
                [ -n "$vname" ] && echo "    external: true"
            done < "$volume_names_file"
        fi
    } > "$compose_file"
    rm -f "$volume_names_file"

    echo "Compose 文件已写入: $compose_file"
    if ! docker_compose_run -f "$compose_file" config >/dev/null; then
        echo "Compose 配置校验失败，文件已保留: $compose_file"
        return 1
    fi
    echo "预览:"
    sed -n '1,220p' "$compose_file"

    if [ "$network_mode" = "host" ]; then
        echo "检测到 host 网络模式。安全做法是把 3x-ui 的 webListen 设为 Tailscale IP。"
        echo "当前 webListen: $(xui_read_db_setting "$db_file" webListen)"
        read -p "迁移时设置 webListen=${tailscale_ip} 吗？[Y/n]: " set_listen
        set_listen="${set_listen:-Y}"
    fi

    read -p "现在停止旧容器、重命名备份并启动 Compose 吗？[y/N]: " migrate
    case "$migrate" in
        [Yy])
            docker stop "$container" || return 1
            if docker inspect "${container}.before-compose" >/dev/null 2>&1; then
                echo "已存在 ${container}.before-compose，请先手动处理。"
                docker start "$container" >/dev/null 2>&1 || true
                return 1
            fi
            docker rename "$container" "${container}.before-compose" || {
                docker start "$container" >/dev/null 2>&1 || true
                return 1
            }
            if [ "$network_mode" = "host" ] && [ "$set_listen" = "Y" -o "$set_listen" = "y" ]; then
                xui_upsert_db_setting "$db_file" webListen "$tailscale_ip" || {
                    docker rename "${container}.before-compose" "$container" >/dev/null 2>&1 || true
                    docker start "$container" >/dev/null 2>&1 || true
                    return 1
                }
            fi
            if ! docker_compose_run -f "$compose_file" up -d; then
                echo "Compose 启动失败，正在回滚旧容器。"
                docker rm -f "$container" >/dev/null 2>&1 || true
                docker rename "${container}.before-compose" "$container" >/dev/null 2>&1 || true
                docker start "$container" >/dev/null 2>&1 || true
                return 1
            fi
            docker ps --format "table {{.Names}}\t{{.Ports}}"
            echo "旧容器已保留为 ${container}.before-compose，确认全部正常前不要删除。"
            ;;
        *)
            echo "未执行迁移。你可以检查后手动执行: docker compose -f $compose_file up -d"
            ;;
    esac
}

xui_security_menu() {
    while true; do
        clear
        echo -e "${pink}========================${white}"
        echo "1. 安装/登录 Tailscale"
        echo "2. 配置 UFW 默认安全规则"
        echo "3. 生成/迁移 3x-ui Docker Compose"
        echo "4. 查看 3x-ui 容器、挂载和端口"
        echo -e "${pink}========================${white}"
        echo "0. 返回"
        echo -e "${pink}========================${white}"
        read -p "请输入你的选择: " sub_choice
        case $sub_choice in
            1) clear; tailscale_install_config ;;
            2) clear; ufw_safe_setup ;;
            3) clear; xui_generate_compose ;;
            4) clear; xui_show_container_ports ;;
            0) yuju_menu ;;
            *) echo "无效的输入" ;;
        esac
        break_end
    done
}

system_related() {
    while true; do
        clear
        echo -e "${pink}========================${white}"
        echo "1. 更新系统软件包"
        echo "2. 系统清理"
        echo "3. TCP调优"
        echo "4. 安装并启用 BBR"
        echo "5. 将时区改为上海"
        echo "6. 修改SWAP"
        echo "7. 修改SSH端口"
        echo "8. 安装fail2ban"
        echo "9. 密钥登录"
        echo "10. 创建普通用户"
        echo -e "${pink}========================${white}"
        echo "0. 返回主菜单"
        echo -e "${pink}========================${white}"
        read -p "请输入你的选择: " sub_choice
        case $sub_choice in
            1)  clear; system_update ;;
            2)  clear; system_clean ;;
            3)  clear; tcp_tune ;;
            4)  clear; enable_bbr ;;
            5)  clear; system_time ;;
            6)  clear; system_swap ;;
            7)  clear; system_ssh ;;
            8)  clear; system_fail2ban ;;
            9)  clear; system_keygen ;;
            10) clear; system_add_user ;;
            0)  yuju_menu ;;
            *) echo "无效的输入!" ;;
        esac
        break_end
    done
}

# 2. 测试脚本子菜单
test_script() {
    while true; do
        clear
        echo -e "${pink}========================${white}"
        echo "1. SpeedTest带宽测速"
        echo "2. xykt_IP质量体检脚本"
        echo "3. nxtrace快速回程测试脚本"
        echo "4. yabs性能测试"
        echo "5. IPv4/IPv6优先级测试"
        echo "6. 硬盘I/O测试"
        echo -e "${pink}========================${white}"
        echo "0. 返回主菜单"
        echo -e "${pink}========================${white}"
        read -p "请输入你的选择: " sub_choice
        case $sub_choice in
            1) clear; bandwidth_test ;;
            2) clear; ip_test ;;
            3) clear; router_test ;;
            4) clear; performance_test ;;
            5) clear; ip_priority_test ;;
            6) clear; io_info ;;
            0) yuju_menu ;;
            *) echo "无效的输入!" ;;
        esac
        break_end
    done
}

# 3. 常用工具下载子菜单
# 单个包安装通过 pkg_install 完成，消除了 10 个重复的 download_xxx 函数
useful_tools() {
    while true; do
        clear
        echo -e "${pink}========================${white}"
        echo "1.  curl下载工具"
        echo "2.  wget下载工具"
        echo "3.  nano文档工具"
        echo "4.  unzip解压缩工具"
        echo "5.  tar解压缩工具"
        echo "6.  tmux后台工具"
        echo "7.  iftop网络流量监控工具"
        echo "8.  btop现代化监控工具"
        echo "9.  gdu磁盘占用查看工具"
        echo "10. fzf文件管理工具"
        echo "11. zsh+Starship终端美化工具"
        echo -e "${pink}========================${white}"
        echo "12. 一键安装所有"
        echo -e "${pink}========================${white}"
        echo "0. 返回主菜单"
        echo -e "${pink}========================${white}"
        read -p "请输入你的选择: " sub_choice
        case $sub_choice in
            1)  pkg_install curl ;;
            2)  pkg_install wget ;;
            3)  pkg_install nano ;;
            4)  pkg_install unzip ;;
            5)  pkg_install tar ;;
            6)  pkg_install tmux ;;
            7)  pkg_install iftop ;;
            8)  pkg_install btop ;;
            9)  pkg_install gdu ;;
            10) pkg_install fzf ;;
            11) clear; download_zsh ;;
            12) clear; download_all ;;
            0)  yuju_menu ;;
            *)  echo "无效的输入!" ;;
        esac
        break_end
    done
}

# 4. Docker 管理子菜单
docker_manage() {
    while true; do
        clear
        echo -e "${pink}========================${white}"
        echo "1. 安装Docker环境"
        echo "2. 查看Docker全局状态"
        echo "3. Docker清理无用的镜像容器网络"
        echo "4. 更换Docker源"
        echo "5. 开启Docker-ipv6访问"
        echo "6. 关闭Docker-ipv6访问"
        echo -e "${pink}========================${white}"
        echo "9. 卸载Docker环境"
        echo -e "${pink}========================${white}"
        echo "0. 返回主菜单"
        echo -e "${pink}========================${white}"
        read -p "请输入你的选择: " sub_choice
        case $sub_choice in
            1) clear; docker_install ;;
            2) clear; docker_status ;;
            3) clear; docker_clean ;;
            4) clear; docker_mirrors ;;
            5) clear; docker_ipv6_on ;;
            6) clear; docker_ipv6_off ;;
            9) clear; docker_uninstall ;;
            0) yuju_menu ;;
            *) echo "无效的输入!" ;;
        esac
        break_end
    done
}

# ═══════════════════════════════════════════════════════════════
# 9. 一键优化
# ═══════════════════════════════════════════════════════════════

onekey_optimization() {
    root_test
    echo "一键优化"
    echo -e "${pink}============================${white}"
    echo "优化内容如下："
    echo "- 更新系统软件包"
    echo "- 系统清理"
    echo -e "- TCP调优"
    echo -e "- 安装并启用 BBR"
    echo -e "- 设置时区到${yellow}上海${white}"
    echo -e "- 自动设置${yellow}虚拟内存${white}"
    echo -e "- 安装fail2ban"
    echo -e "- 安装${yellow}所有常用工具${white}"
    echo -e "- 设置SSH端口号为${yellow}55520${white}"
    echo -e "- 修改为密钥登录"
    echo -e "${pink}============================${white}"
    echo -e "${red}注意：请牢记端口号和密钥，否则重启后无法登录${white}"
    read -p "确定一键优化吗？(Y/N): " choice

    case "$choice" in
        [Yy])
            clear
            echo -e "${pink}============================${white}"
            system_update
            echo -e "[${green}OK${white}] 1/10. 更新系统到最新"

            echo -e "${pink}============================${white}"
            system_clean
            echo -e "[${green}OK${white}] 2/10. 清理系统垃圾文件"

            echo -e "${pink}============================${white}"
            tcp_tune --auto
            echo -e "[${green}OK${white}] 3/10. TCP调优"

            echo -e "${pink}============================${white}"
            enable_bbr
            echo -e "[${green}OK${white}] 4/10. 安装并启用 BBR"


            echo -e "${pink}============================${white}"
            system_time
            echo -e "[${green}OK${white}] 5/10. 设置时区到${yellow}上海${white}"

            echo -e "${pink}============================${white}"
            swap_create_auto
            echo -e "[${green}OK${white}] 6/10. 自动设置${yellow}虚拟内存${white}"

            echo -e "${pink}============================${white}"
            system_fail2ban
            echo -e "[${green}OK${white}] 7/10. 安装fail2ban"

            echo -e "${pink}============================${white}"
            download_all
            docker_install
            echo -e "[${green}OK${white}] 8/10. 安装${yellow}Docker等常用工具${white}"

            echo -e "${pink}============================${white}"
            system_ssh 55520
            echo -e "[${green}OK${white}] 9/10. 设置SSH端口号为${yellow}55520${white}"

            echo -e "${pink}============================${white}"
            system_keygen
            echo -e "[${green}OK${white}] 10/10. 修改为密钥登录"
            echo -e "${pink}============================${white}"

            clear
            echo -e "${green}一键优化已完成${white}"
            echo "您现在的SSH端口为55520，您的SSH Key如下，请牢记："
            cat ~/.ssh/id_rsa
            ;;
        [Nn])
            echo "已取消"
            ;;
        *)
            echo "无效的选择，请输入 Y 或 N。"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# 主界面
# ═══════════════════════════════════════════════════════════════

yuju_menu() {
    while true; do
        echo -e "${pink}============================${white}"
        echo -e "${pink}\   /  |    |     |   |    | "
        echo " \ /   |    |     |   |    | "
        echo "  |    |    |     |   |    | "
        echo -e "  |    |____|  ___|   |____| ${white}"
        echo -e "${pink}============================${white}"
        echo -e "${pink}yuju工具箱 【v$version】        输入 ${red}yuju${pink} 可快速启动${white}"
        show_sysinfo
        echo -e "${pink}============================${white}"
        echo "1. 系统相关->"
        echo "2. 测试脚本->"
        echo "3. 常用工具下载->"
        echo "4. Docker管理->"
        echo "5. 3x-ui安全部署->"
        echo -e "${pink}============================${white}"
        echo "9. 一键优化"
        echo -e "${pink}============================${white}"
        echo "555. 卸载脚本"
        echo -e "${pink}============================${white}"
        echo "0. 退出脚本"
        echo -e "${pink}============================${white}"
        read -p "请输入你的选择: " choice

        case $choice in
            1)   clear; system_related ;;
            2)   clear; test_script ;;
            3)   clear; useful_tools ;;
            4)   clear; docker_manage ;;
            5)   clear; xui_security_menu ;;
            9)   clear; onekey_optimization ;;
            555)
                clear
                echo "卸载yuju工具箱"
                echo -e "${pink}============================${white}"
                echo "将彻底卸载yuju工具箱，不影响已安装的功能"
                read -p "确定继续吗？(Y/N): " confirm
                if [[ "$confirm" == "Y" || "$confirm" == "y" ]]; then
                    clear
                    rm -f /usr/local/bin/yuju
                    rm -f ./yuju.sh
                    echo "脚本已卸载，祝您生活愉快！"
                    exit
                else
                    echo "操作已取消。"
                fi
                ;;
            0)   clear; exit ;;
            *)   echo -e "无效的输入!" ;;
        esac
        break_end
    done
}

# ─── 入口 ─────────────────────────────────────────────────────
if [ "$#" -eq 0 ]; then
    yuju_menu
else
    echo -e "无效参数"
fi
