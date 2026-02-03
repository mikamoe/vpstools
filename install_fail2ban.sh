#!/usr/bin/env bash
# install_fail2ban.sh - Debian/Ubuntu 交互脚本（美化日志前缀，功能同原版）
set -euo pipefail

# 颜色与样式
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"
BLUE="\033[34m"; CYAN="\033[36m"; BOLD="\033[1m"; NC="\033[0m"

# 日志前缀（采用用户提供的示例样式）
LOG_INFO="${BLUE}${BOLD}[i]${NC} "
LOG_SUCCESS="${GREEN}${BOLD}[✓]${NC} "
LOG_WARN="${YELLOW}${BOLD}[!]${NC} "
LOG_ERROR="${RED}${BOLD}[✗]${NC} "

# 简洁日志函数
log_info(){ printf "%b%s\n" "${LOG_INFO}" "$*"; }
log_success(){ printf "%b%s\n" "${LOG_SUCCESS}" "$*"; }
log_warn(){ printf "%b%s\n" "${LOG_WARN}" "$*"; }
# log_error 输出到 stderr 并退出
log_error(){ printf "%b%s\n" "${LOG_ERROR}" "$*" >&2; exit 1; }

# 确保以 root 运行
if [ "$EUID" -ne 0 ]; then
  log_error "请以 root 或 sudo 运行：sudo bash $0"
fi

# ---------- 可调项 ----------
SSH_PORT=22
BANTIME=600
JAIL="sshd"
JAIL_DIR="/etc/fail2ban/jail.d"
JAIL_FILE="${JAIL_DIR}/sshd-ufw.local"
FAIL2BAN_LOG="/var/log/fail2ban.log"
SSH_AUTH_LOG="/var/log/auth.log"
SSH_SECURE_LOG="/var/log/secure"
CLEAR_SCRIPT="/usr/local/bin/clear_fail2ban_log.sh"
CRON_MARK="# clear_fail2ban_log every 15 days"
CRON_LINE="0 3 */15 * * ${CLEAR_SCRIPT} >/dev/null 2>&1"
SEP="=============================="

press_any(){
  printf "\n${CYAN}按任意键继续...${NC}"
  read -r -n1 -s
  printf "\n"
}

is_installed(){ command -v "$1" >/dev/null 2>&1; }

show_install_status(){
  if is_installed fail2ban-client || dpkg -s fail2ban >/dev/null 2>&1; then
    printf "${BOLD}Fail2ban:${NC} ${GREEN}已安装${NC}    "
  else
    printf "${BOLD}Fail2ban:${NC} ${RED}未安装${NC}    "
  fi
  if is_installed ufw || dpkg -s ufw >/dev/null 2>&1; then
    printf "${BOLD}UFW:${NC} ${GREEN}已安装${NC}\n"
  else
    printf "${BOLD}UFW:${NC} ${RED}未安装${NC}\n"
  fi
}

# 选择合适的 ssh 日志路径
detect_ssh_logpath(){
  if [ -f "${SSH_AUTH_LOG}" ]; then
    printf "%s" "${SSH_AUTH_LOG}"
  elif [ -f "${SSH_SECURE_LOG}" ]; then
    printf "%s" "${SSH_SECURE_LOG}"
  else
    printf "%s" "%(sshd_log)s"
  fi
}

# 确保 crontab 可用：若不存在则尝试安装 cron 并启用
ensure_crontab_available(){
  if command -v crontab >/dev/null 2>&1; then
    return 0
  fi

  log_info "检测到系统缺少 crontab 命令，尝试安装 cron 包..."
  apt-get update -y || true
  if ! apt-get install -y cron; then
    log_warn "尝试安装 cron 失败，请手动安装 cron 或 crontab"
    return 1
  fi

  if systemctl list-unit-files | grep -q '^cron\.service'; then
    systemctl enable --now cron || log_warn "启动/启用 cron 服务失败（但安装已完成）"
  fi

  if command -v crontab >/dev/null 2>&1; then
    log_info "crontab 命令已可用。"
    return 0
  fi

  log_warn "安装 cron 后仍未找到 crontab 命令，后续将跳过添加 crontab 操作。"
  return 1
}

# 创建清空日志脚本并添加 cron（若不存在）
setup_periodic_log_clear(){
  cat > "${CLEAR_SCRIPT}" <<'EOF'
#!/usr/bin/env bash
LOG="/var/log/fail2ban.log"
if [ -f "${LOG}" ]; then
  : > "${LOG}"
  chown root:root "${LOG}" 2>/dev/null || true
  chmod 644 "${LOG}" 2>/dev/null || true
fi
EOF
  chmod 755 "${CLEAR_SCRIPT}"
  log_info "已创建 ${CLEAR_SCRIPT}（用于清空 ${FAIL2BAN_LOG}）"

  if ! ensure_crontab_available; then
    log_warn "crontab 不可用，已创建清空脚本但未添加定时任务。"
    return 0
  fi

  CRONTAB_CONTENT="$(crontab -l 2>/dev/null || true)"
  if printf "%s\n" "$CRONTAB_CONTENT" | grep -Fq "${CRON_MARK}"; then
    log_info "crontab 中已存在定时清理任务，跳过添加。"
  else
    TMP_CRON="$(mktemp)"
    {
      printf "%s\n" "$CRONTAB_CONTENT"
      printf "%s\n" "${CRON_MARK}"
      printf "%s\n" "${CRON_LINE}"
    } > "${TMP_CRON}"
    if crontab "${TMP_CRON}" 2>/dev/null; then
      log_info "已将定时任务添加到 root 的 crontab：${CRON_LINE}"
    else
      log_warn "写入 crontab 失败（权限或格式问题）"
    fi
    rm -f "${TMP_CRON}"
  fi
}

install_fail2ban(){
  log_info "开始安装流程：更新并安装 UFW 与 Fail2Ban"
  export DEBIAN_FRONTEND=noninteractive

  log_info "apt-get update && apt-get upgrade -y"
  apt-get update -y
  apt-get upgrade -y

  log_info "正在安装 UFW..."
  apt-get install -y ufw
  log_success "UFW 安装完成（或已存在）"

  log_info "正在安装 Fail2Ban..."
  apt-get install -y fail2ban
  log_success "Fail2Ban 安装完成（或已存在）"

  log_info "确保 UFW 允许 SSH ${SSH_PORT}/tcp（避免被锁死）"
  ufw allow "${SSH_PORT}/tcp" || log_warn "ufw allow 返回非零（若 ufw 未启用这是正常的）"

  log_info "将 UFW 设置为允许所有传入连接（UFW 仅用于配合 Fail2Ban 封禁）"
  ufw default allow incoming || log_warn "设置 ufw default allow incoming 返回非零"
  ufw default allow outgoing || true
  ufw allow "${SSH_PORT}/tcp" || true

  ufw --force enable || log_warn "启用 UFW 返回非零"
  if systemctl list-units --type=service --all | grep -q '^ufw\.service'; then
    systemctl restart ufw || log_warn "重启 ufw 返回非零"
  fi

  SSH_LOGPATH="$(detect_ssh_logpath)"
  log_info "使用 SSH 日志路径：${SSH_LOGPATH}"

  log_info "写入 Fail2Ban 配置（覆盖）：${JAIL_FILE}"
  mkdir -p "${JAIL_DIR}"
  cat > "${JAIL_FILE}" <<EOF
[${JAIL}]
enabled = true
port    = ${SSH_PORT}
filter  = sshd
logpath = ${SSH_LOGPATH}
ignoreip = 127.0.0.1/8 ::1
maxretry = 4
findtime = 300
bantime  = ${BANTIME}
banaction = ufw
EOF
  chmod 644 "${JAIL_FILE}"
  log_success "配置已写入：${JAIL_FILE}"

  log_info "重启 fail2ban 服务"
  systemctl restart fail2ban || log_warn "重启 fail2ban 返回非零"

  setup_periodic_log_clear

  printf "\n${SEP}\n"
  log_info "安装与配置已完成，显示 fail2ban 服务状态前先展示配置文件内容："

  if [ -f "${JAIL_FILE}" ]; then
    log_info "显示 ${JAIL_FILE} 的内容："
    sed -n '1,200p' "${JAIL_FILE}" || true
  else
    log_warn "${JAIL_FILE} 未找到。显示 /etc/fail2ban 下的文件列表："
    ls -la /etc/fail2ban || true
  fi

  log_info "显示 fail2ban 服务状态："
  systemctl status fail2ban --no-pager -l || true
  printf "\n${SEP}\n"
}

show_status(){
  printf "\n${SEP}\n"
  log_info "fail2ban 服务状态："
  systemctl status fail2ban --no-pager -l || true
  printf "\n${SEP}\n"
}

show_config(){
  printf "\n${SEP}\n"
  if [ -f "${JAIL_FILE}" ]; then
    log_info "显示 ${JAIL_FILE} 内容："
    sed -n '1,200p' "${JAIL_FILE}" || true
  else
    log_warn "${JAIL_FILE} 未找到。"
    if [ -d "/etc/fail2ban" ]; then
      log_info "/etc/fail2ban 下的文件："
      ls -la /etc/fail2ban || true
    fi
  fi
  printf "\n${SEP}\n"
}

show_logs(){
  if [ ! -f "${FAIL2BAN_LOG}" ]; then
    log_warn "${FAIL2BAN_LOG} 不存在，检查 Fail2Ban 是否在写日志。"
    press_any
    return
  fi
  log_info "开始 tail -n 50 -F ${FAIL2BAN_LOG}（按 Ctrl+C 返回菜单）"
  printf "\n${SEP}\n"
  trap 'log_info "停止日志查看，返回菜单"; trap - INT; return 0' INT
  tail -n 50 -F "${FAIL2BAN_LOG}" || true
  trap - INT
  printf "\n${SEP}\n"
}

show_bans(){
  printf "\n${SEP}\n"
  if ! systemctl is-active --quiet fail2ban; then
    log_warn "fail2ban 未运行。"
    printf "\n${SEP}\n"
    return
  fi

  BANS_RAW="$(fail2ban-client get ${JAIL} banip --with-time 2>/dev/null || true)"

  declare -A BAN_MAP
  if [ -n "${BANS_RAW}" ]; then
    log_info "当前封禁列表："
    IFS=$'\n'
    i=1
    for line in ${BANS_RAW}; do
      ip=$(printf "%s" "${line}" | awk '{print $1}')
      t=$(printf "%s" "${line}" | cut -d' ' -f2-)
      printf " %2d) %-15s      Ban  %s\n" "${i}" "${ip}" "${t}"
      BAN_MAP[$i]="${ip}"
      ((i++))
    done
    unset IFS
  else
    BANS_LINE="$(fail2ban-client status ${JAIL} 2>/dev/null | sed -n 's/.*Banned IP list:\s*//p' || true)"
    if [ -z "${BANS_LINE}" ]; then
      log_info "当前没有被封禁的 IP。"
      printf "\n${SEP}\n"
      return
    fi
    log_info "当前封禁列表（不含时间）："
    i=1
    for ip in ${BANS_LINE}; do
      printf " %2d) %-15s      Ban  N/A\n" "${i}" "${ip}"
      BAN_MAP[$i]="${ip}"
      ((i++))
    done
  fi

  echo
  read -r -p "输入序号解除封禁 (0 返回菜单): " UNBAN_CHOICE
  if [ "${UNBAN_CHOICE}" = "0" ]; then
    printf "\n${SEP}\n"
    return
  elif [[ -n "${BAN_MAP[$UNBAN_CHOICE]:-}" ]]; then
    ip="${BAN_MAP[$UNBAN_CHOICE]}"
    log_info "正在解除封禁 IP: ${ip}"
    fail2ban-client set ${JAIL} unbanip "${ip}" || log_warn "解除封禁失败"
  else
    log_warn "无效序号"
  fi
  printf "\n${SEP}\n"
}

uninstall_fail2ban(){
  printf "\n${SEP}\n"
  log_warn "你即将卸载 Fail2Ban 并清理配置与日志。此操作不可撤销。"
  printf "确认卸载？请输入 ${YELLOW}[Y/n]${NC} （默认 N，即取消）: "
  read -r CONF
  case "${CONF:-n}" in
    [Yy])
      log_info "确认：开始卸载并清理..."
      systemctl stop fail2ban || true
      apt-get purge -y fail2ban || true
      apt-get autoremove -y || true
      apt-get autoclean -y || true

      log_info "清理配置和日志"
      rm -rf /etc/fail2ban
      rm -f "${FAIL2BAN_LOG}"

      if [ -f "${CLEAR_SCRIPT}" ]; then
        rm -f "${CLEAR_SCRIPT}"
        log_info "已删除 ${CLEAR_SCRIPT}"
      fi

      if command -v crontab >/dev/null 2>&1; then
        OLD_CRON="$(crontab -l 2>/dev/null || true)"
        if [ -n "${OLD_CRON}" ]; then
          NEW_CRON="$(printf "%s\n" "${OLD_CRON}" | awk -v m="${CRON_MARK}" -v l="${CRON_LINE}" '$0!=m && $0!=l')"
          printf "%s\n" "${NEW_CRON}" | crontab - 2>/dev/null || true
          log_info "已从 crontab 中移除定时清理任务（如存在）"
        fi
      else
        CRON_FILE="/var/spool/cron/crontabs/root"
        if [ -f "${CRON_FILE}" ]; then
          OLD_CRON="$(cat "${CRON_FILE}")" || true
          NEW_CRON="$(printf "%s\n" "${OLD_CRON}" | awk -v m="${CRON_MARK}" -v l="${CRON_LINE}" '$0!=m && $0!=l')"
          printf "%s\n" "${NEW_CRON}" > "${CRON_FILE}" || true
          log_info "已修改 ${CRON_FILE}，移除定时任务（如存在）"
        fi
      fi

      systemctl daemon-reload || true

      printf "是否同时卸载 UFW？请输入 ${YELLOW}[y/N]${NC} （默认 N）: "
      read -r UNINSTALL_UFW
      case "${UNINSTALL_UFW:-n}" in
        [Yy]*)
          log_info "开始卸载并重置 UFW..."
          if command -v ufw >/dev/null 2>&1; then
            ufw --force reset || log_warn "ufw reset 返回非零（若 ufw 未启用这可能是正常的）"
          fi
          systemctl stop ufw || true
          systemctl disable ufw || true
          apt-get purge -y ufw || true
          apt-get autoremove -y || true
          apt-get autoclean -y || true
          log_info "UFW 已卸载并尝试清理规则。"
          ;;
        *)
          log_info "保留 UFW（未卸载）。"
          ;;
      esac

      log_info "卸载并清理完成。"
      ;;
    *)
      log_info "已取消卸载操作。"
      ;;
  esac
  printf "\n${SEP}\n"
}

# 主循环
while true; do
  printf "\n${SEP}\n"
  show_install_status
  printf "\n${SEP}\n"

  printf "${CYAN}请选择操作：${NC}\n"
  printf " ${GREEN}1)${NC} 安装并配置 Fail2Ban（并设置每15天清空日志）\n"
  printf " ${GREEN}2)${NC} 查看 fail2ban 服务状态\n"
  printf " ${GREEN}3)${NC} 查看 fail2ban 配置文件\n"
  printf " ${GREEN}4)${NC} 查看实时日志\n"
  printf " ${GREEN}5)${NC} 查看封禁情况并可解除封禁\n"
  printf " ${GREEN}6)${NC} 卸载 Fail2Ban（含配置与日志，需确认 Y/y 才卸载；会询问是否同时卸载 UFW）\n"
  printf " ${GREEN}0)${NC} 退出\n\n"

  read -r -p "$(printf "${YELLOW}输入选项 [0-6]: ${NC}")" CHOICE

  case "${CHOICE}" in
    1) printf "\n${SEP}\n"; install_fail2ban; press_any ;;
    2) printf "\n${SEP}\n"; show_status; press_any ;;
    3) printf "\n${SEP}\n"; show_config; press_any ;;
    4) printf "\n${SEP}\n"; show_logs; press_any ;;
    5) printf "\n${SEP}\n"; show_bans; press_any ;;
    6) printf "\n${SEP}\n"; uninstall_fail2ban; press_any ;;
    0) log_info "退出脚本"; exit 0 ;;
    *) log_warn "无效选项，请重新选择"; press_any ;;
  esac
done
