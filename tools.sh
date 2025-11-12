#!/bin/bash
# 定义美观显示的颜色变量
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

# 当前脚本路径及远程脚本 URL（用于更新）
CURRENT_SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
SCRIPT_URL="https://raw.githubusercontent.com/mikamoe/vpstools/refs/heads/main/tools.sh"

# SSH美化内容（萌萌哒提示喵～(ฅ'ω'ฅ)）
BEAUTIFY_CONTENT='
# 命令行美化 - 萌萌哒配置
parse_git_branch() {
    git branch 2> /dev/null | sed -e '\''/^[^*]/d'\'' -e '\''s/* \(.*\)/ (\1)/'\''
}
PS1='\''\[\033[01;38;5;117m\]\u\[\033[01;33m\]@\[\033[01;33m\]\h\[\033[00m\]:\[\033[01;35m\]\w\[\033[01;35m\]$(parse_git_branch)\[\033[00m\] \[\033[01;36m][\D{%H:%M:%S}]\[\033[00m\]\n\[\033[01;37m\]\$ \[\033[00m\]'\''
# 命令行美化结束 - 快来体验可爱风格吧～(=^･ω･^=)
'

###########################################
# 设置 Q/q 快捷指令（通过符号链接）
###########################################
setup_q_command() {
    if [ ! -L "/usr/local/bin/q" ] || [ ! -L "/usr/local/bin/Q" ]; then
        sudo ln -sf "$CURRENT_SCRIPT_PATH" /usr/local/bin/q
        sudo ln -sf "$CURRENT_SCRIPT_PATH" /usr/local/bin/Q
    fi
}
setup_q_command

###########################################
# 检测网络栈类型
###########################################
detect_network_stack() {
    local has_ipv4=0 has_ipv6=0
    if ip -4 route get 8.8.8.8 &>/dev/null; then has_ipv4=1; fi
    if ip -6 route get 2001:4860:4860::8888 &>/dev/null; then has_ipv6=1; fi
    if [ $has_ipv4 -eq 1 ] && [ $has_ipv6 -eq 1 ]; then
        echo "dual"
    elif [ $has_ipv4 -eq 1 ]; then
        echo "ipv4"
    elif [ $has_ipv6 -eq 1 ]; then
        echo "ipv6"
    else
        echo "none"
    fi
}

###########################################
# 通用安装包管理器函数
###########################################
install_package() {
    local package=$1
    if command -v apt &>/dev/null; then
        apt install -y "$package"
    elif command -v yum &>/dev/null; then
        yum install -y "$package"
    elif command -v dnf &>/dev/null; then
        dnf install -y "$package"
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm "$package"
    elif command -v zypper &>/dev/null; then
        zypper install -y "$package"
    elif command -v apk &>/dev/null; then
        apk add --no-cache "$package"
    else
        echo -e "${RED}未知的包管理器，无法安装 ${package}${NC}"
        return 1
    fi
}

###########################################
# 设置 DNS 并永久生效（仅适配 Debian / Ubuntu）
###########################################
set_dns() {
    local network_stack
    network_stack=$(detect_network_stack)
    if [ "$network_stack" = "none" ]; then
        echo -e "${RED}未检测到网络，无法设置 DNS${NC}"
        read -n1 -s -r -p "按任意键继续..."
        return
    fi

    echo -e "${YELLOW}正在禁用 systemd-resolved 并断开 resolv.conf 链接喵～${NC}"
    sudo systemctl disable --now systemd-resolved >/dev/null 2>&1
    sudo systemctl mask systemd-resolved >/dev/null 2>&1

    if [ -L /etc/resolv.conf ]; then
        sudo unlink /etc/resolv.conf
    fi

    # 清空 resolv.conf，不添加空行
    sudo truncate -s 0 /etc/resolv.conf

    if [[ $network_stack == "ipv4" || $network_stack == "dual" ]]; then
        echo "nameserver $dns1_ipv4" | sudo tee -a /etc/resolv.conf >/dev/null
        echo "nameserver $dns2_ipv4" | sudo tee -a /etc/resolv.conf >/dev/null
    fi
    if [[ $network_stack == "ipv6" || $network_stack == "dual" ]]; then
        echo "nameserver $dns1_ipv6" | sudo tee -a /etc/resolv.conf >/dev/null
        echo "nameserver $dns2_ipv6" | sudo tee -a /etc/resolv.conf >/dev/null
    fi

    sudo chattr +i /etc/resolv.conf 2>/dev/null

    echo -e "${GREEN}DNS 优化完成，当前配置：${NC}"
    cat /etc/resolv.conf
    read -n1 -s -r -p "按任意键继续..."
}

###########################################
# DNS 优化交互界面（专为 Debian/Ubuntu 优化）
###########################################
set_dns_ui() {
    while true; do
        clear
        echo "======= 优化 DNS 地址 ======="
        echo "当前 DNS 配置："
        cat /etc/resolv.conf
        echo "------------------------------"
        echo "1) 国外 DNS 优化"
        echo "   IPv4: 1.1.1.1  8.8.8.8"
        echo "   IPv6: 2606:4700:4700::1111  2001:4860:4860::8888"
        echo "2) 国内 DNS 优化"
        echo "   IPv4: 223.5.5.5  183.60.83.19"
        echo "   IPv6: 2400:3200::1  2400:da00::6666"
        echo "3) 手动编辑 /etc/resolv.conf"
        echo "0) 返回主菜单"
        echo "------------------------------"
        read -e -p "请输入你的选择: " choice
        case "$choice" in
            1)
                dns1_ipv4="1.1.1.1"; dns2_ipv4="8.8.8.8"
                dns1_ipv6="2606:4700:4700::1111"; dns2_ipv6="2001:4860:4860::8888"
                set_dns
                ;;
            2)
                dns1_ipv4="223.5.5.5"; dns2_ipv4="183.60.83.19"
                dns1_ipv6="2400:3200::1"; dns2_ipv6="2400:da00::6666"
                set_dns
                ;;
            3)
                if ! command -v nano &>/dev/null; then
                    install_package nano
                fi
                sudo chattr -i /etc/resolv.conf 2>/dev/null
                sudo nano /etc/resolv.conf
                sudo chattr +i /etc/resolv.conf 2>/dev/null
                ;;
            0) break ;;
            *)
                echo -e "${RED}无效选项喵～(╥﹏╥)，按任意键继续...${NC}"
                read -n1 -s -r
                ;;
        esac
    done
}

###########################################
# SSH 命令行美化
###########################################
ssh_beautify() {
    clear
    echo -e "${YELLOW}SSH命令行美化选项喵～(≧◡≦)${NC}"
    echo -e "1. 安装命令行美化 (｡♥‿♥｡)"
    echo -e "2. 卸载命令行美化 (╥﹏╥)"
    echo -e "3. 返回主菜单喵～(ฅ'ω'ฅ)"
    read -p "请输入选项 (1/2/3)喵～: " choice

    case $choice in
        1)
            if grep -q "# 命令行美化" ~/.bashrc; then
                echo -e "${YELLOW}命令行美化已经安装过喵～(｡•́︿•̀｡)${NC}"
            else
                # 添加萌萌哒 PS1 美化
                cat << 'EOF' >> ~/.bashrc
# 命令行美化 - 萌萌哒配置
parse_git_branch() {
    git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}
PS1='\[\033[01;38;5;117m\]\u\[\033[01;33m\]@\[\033[01;33m\]\h\[\033[00m\]:\[\033[01;35m\]\w\[\033[01;35m\]$(parse_git_branch)\[\033[00m\] \[\033[01;36m][\D{%H:%M:%S}]\[\033[00m\]\n\[\033[01;37m\]\$ \[\033[00m\]'
# 命令行美化结束 - 快来体验可爱风格吧～(=^･ω･^=)
EOF

                # 添加 ls 颜色高亮：仅当未存在时才追加
                if ! grep -q "export LS_OPTIONS" ~/.bashrc; then
                    cat << 'EOF' >> ~/.bashrc
#
# ls 颜色高亮配置
export LS_OPTIONS='--color=auto'
eval "$(dircolors)"  # 加载颜色方案
alias ls='ls $LS_OPTIONS'
alias ll='ls $LS_OPTIONS -l'
alias l='ls $LS_OPTIONS -lA'
#
EOF
                fi

                source ~/.bashrc
                echo -e "${GREEN}命令行美化及 ls 高亮已安装并立即生效喵～(=^･ω･^=)${NC}"
            fi
            read -n1 -s -r -p "按任意键返回菜单喵～"
            ;;
        2)
            if grep -q "# 命令行美化" ~/.bashrc; then
                # 移除 PS1 美化
                sed -i '/# 命令行美化/,/# 命令行美化结束/d' ~/.bashrc
            fi
            if grep -q "ls 颜色高亮配置" ~/.bashrc; then
                # 移除 ls 高亮配置
                sed -i '/# ls 颜色高亮配置/,/#$/d' ~/.bashrc
            fi
            source ~/.bashrc
            echo -e "${GREEN}命令行美化及 ls 高亮已卸载并立即生效喵～(｡•́︿•̀｡)${NC}"
            read -n1 -s -r -p "按任意键返回菜单喵～"
            ;;
        3) return ;;
        *)
            echo -e "${RED}无效选项喵～(╥﹏╥)，按任意键继续...${NC}"
            read -n1 -s -r
            ;;
    esac
}

###########################################
# 系统更新
###########################################
system_update() {
    echo -e "${YELLOW}正在系统更新喵～(๑>◡<๑)${NC}"
    if command -v apt &>/dev/null; then
        apt update -y && apt upgrade -y && apt dist-upgrade -y && apt autoremove -y
    elif command -v yum &>/dev/null; then
        yum update -y && yum upgrade -y
    elif command -v dnf &>/dev/null; then
        dnf update -y && dnf upgrade -y
    elif command -v pacman &>/dev/null; then
        pacman -Syu --noconfirm
    elif command -v zypper &>/dev/null; then
        zypper refresh && zypper update -y
    elif command -v apk &>/dev/null; then
        apk update && apk upgrade
    else
        echo -e "${RED}未知的包管理器，无法执行系统更新喵～(╥﹏╥)${NC}"
    fi
    echo -e "${GREEN}系统更新完成喵～(=^･ω･^=)${NC}"
    read -n1 -s -r -p "按任意键返回菜单喵～"
}

###########################################
# 系统清理
###########################################
system_clean() {
    echo -e "${YELLOW}正在系统清理喵～(｡•̀ᴗ-)✧${NC}"
    steps=(
        "清理包管理器缓存喵～"
        "删除系统日志喵～"
        "删除临时文件喵～"
        "清理 APK 缓存喵～"
        "清理 YUM/DNF 缓存喵～"
        "清理 APT 缓存喵～"
        "清理 Pacman 缓存喵～"
        "清理 Zypper 缓存喵～"
        "清理 Opkg 缓存喵～"
    )
    for step in "${steps[@]}"; do
        echo -e "${YELLOW}${step}${NC}"
        case $step in
            *包管理器缓存*)   
                command -v dnf &>/dev/null && dnf clean all
                command -v yum &>/dev/null && yum clean all
                command -v apt &>/dev/null && { apt clean; apt autoclean; }
                command -v apk &>/dev/null && apk cache clean
                command -v pacman &>/dev/null && pacman -Scc --noconfirm
                command -v zypper &>/dev/null && zypper clean --all
                command -v opkg &>/dev/null && opkg clean
                ;;
            *系统日志*)        
                journalctl --rotate && journalctl --vacuum-time=1s && journalctl --vacuum-size=500M
                ;;
            *临时文件*)        
                rm -rf /tmp/* /var/tmp/*
                ;;
        esac
    done
    echo -e "${GREEN}系统清理完成喵～(=^･ω･^=)${NC}"
    read -n1 -s -r -p "按任意键返回菜单喵～"
}

###########################################
# 更新脚本
###########################################
update_script() {
    echo -e "${YELLOW}正在更新脚本喵～(｡•̀ᴗ-)✧${NC}"
    if curl -s "$SCRIPT_URL" -o "$CURRENT_SCRIPT_PATH"; then
        chmod +x "$CURRENT_SCRIPT_PATH"
        echo -e "${GREEN}脚本更新成功喵～(=^･ω･^=)${NC}"
        read -n1 -s -r -p ""
        exec "$CURRENT_SCRIPT_PATH"
    else
        echo -e "${RED}脚本更新失败，请检查网络或 URL 是否正确喵～(╥﹏╥)${NC}"
        read -n1 -s -r -p "按任意键继续..."
    fi
}

###########################################
# 卸载脚本
###########################################
uninstall_script() {
    echo -e "${YELLOW}正在卸载脚本喵～(｡•́︿•̀｡)${NC}"
    [ -L "/usr/local/bin/q" ] && sudo rm -f /usr/local/bin/q
    [ -L "/usr/local/bin/Q" ] && sudo rm -f /usr/local/bin/Q
    if [[ -f "$CURRENT_SCRIPT_PATH" ]]; then
        rm -f "$CURRENT_SCRIPT_PATH"
        echo -e "${GREEN}脚本文件已删除喵～(=^･ω･^=)${NC}"
    else
        echo -e "${YELLOW}脚本文件不存在喵～(๑•̀ㅂ•́)و✧${NC}"
    fi
    echo -e "${GREEN}脚本卸载完成喵～(=^･ω･^=)${NC}"
    exit 0
}

###########################################
# 主菜单
###########################################
show_menu() {
    clear
    echo -e "${MAGENTA}========================================${NC}"
    echo -e "${GREEN}tools.sh～(=^･ω･^=)${NC}"
    echo -e "${BLUE}https://github.com/mikamoe/vpstools${NC}"
    echo -e "${MAGENTA}========================================${NC}"
    echo -e "${YELLOW}1. 优化 DNS 地址${NC}"
    echo -e "${CYAN}2. 系统更新${NC}"
    echo -e "${GREEN}3. 系统清理${NC}"
    echo -e "${BLUE}4. Fail2ban 配置${NC}"
    echo -e "${MAGENTA}5. IPv4/IPv6 配置${NC}"
    echo -e "${CYAN}6. 添加系统信息${NC}"
    echo -e "${YELLOW}7. SSH 命令行美化${NC}"
    echo -e "${GREEN}8. 超萌 BBR 管理脚本${NC}"
    echo -e "${BLUE}9. DanmakuRender${NC}"
    echo -e "${MAGENTA}10.更新脚本${NC}"
    echo -e "${CYAN}11.卸载脚本${NC}"
    echo -e "${RED}0. 退出脚本${NC}"
    echo -e "${MAGENTA}========================================${NC}"
}

# 主循环
while true; do
    show_menu
    read -p "请输入选项数字: " choice
    case $choice in
        1) set_dns_ui ;;
        2) system_update ;;
        3) system_clean ;;
        4) bash <(curl -sL https://raw.githubusercontent.com/mikamoe/vpstools/refs/heads/main/install_fail2ban.sh) ;;
        5) bash <(curl -sL https://raw.githubusercontent.com/mikamoe/vpstools/refs/heads/main/IPControlCenter.sh) ;;
        6) bash <(curl -s https://raw.githubusercontent.com/mikamoe/vpstools/refs/heads/main/system_info.sh) ;;
        7) ssh_beautify ;;
        8)
            if ! command -v wget &>/dev/null; then
                install_package wget
            fi
            sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/byJoey/Actions-bbr-v3/refs/heads/main/install.sh)"
            read -n1 -s -r -p "按任意键返回菜单喵～"
            ;;
        9) bash <(wget -qO- https://raw.githubusercontent.com/mikamoe/vpstools/refs/heads/v5/dmr.sh) ;;
        10) update_script ;;
        11) uninstall_script ;;
        0) echo -e "${MAGENTA}退出脚本${NC}" ; break ;;
        *)
            echo -e "${RED}无效选项喵～(╥﹏╥)，按任意键继续...${NC}"
            read -n1 -s -r
            ;;
    esac
done
