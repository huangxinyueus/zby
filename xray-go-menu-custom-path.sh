#!/usr/bin/env bash
# Xray-go 中文菜单管理脚本（支持自定义 Argo XHTTP Path）
# 基于原菜单封装；上游核心安装流程仍由 eishare/Xray-go 执行。
set -Eeuo pipefail
export LANG=C.UTF-8

UPSTREAM_INSTALL="https://raw.githubusercontent.com/eishare/Xray-go/main/xray-go.sh"
WORK_DIR="/etc/xray"
TMP_INSTALL="$(mktemp -t xray-go-install.XXXXXX.sh)"
trap 'rm -f "$TMP_INSTALL"' EXIT

c_green()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_yellow() { printf '\033[1;33m%s\033[0m\n' "$*"; }
c_red()    { printf '\033[1;31m%s\033[0m\n' "$*"; }

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    c_red "请使用 root 权限运行：sudo bash xray-go-menu.sh"
    exit 1
  fi
}
has_systemd() { command -v systemctl >/dev/null 2>&1 && { [[ -d /run/systemd/system ]] || [[ -d /etc/systemd/system ]]; }; }
has_openrc() { command -v rc-service >/dev/null 2>&1; }
pause() { read -r -p $'\n按回车键返回菜单...' _; }

ask_yes_no() {
  local prompt="$1" default="$2" answer
  while true; do
    if [[ "$default" == "y" ]]; then
      read -r -p "$prompt [Y/n]: " answer; answer=${answer:-y}
    else
      read -r -p "$prompt [y/N]: " answer; answer=${answer:-n}
    fi
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) echo "请输入 y 或 n。" ;;
    esac
  done
}

valid_path() {
  local p="$1"
  # 仅允许 URL path 常见安全字符；拒绝空格、查询串、片段和路径穿越。
  [[ "$p" =~ ^/[A-Za-z0-9._~/-]+$ ]] || return 1
  [[ "$p" != *".."* ]] || return 1
  [[ "$p" != *"//"* ]] || return 1
}

fetch_and_patch_upstream() {
  command -v curl >/dev/null 2>&1 || { c_red "未找到 curl。"; return 1; }
  command -v python3 >/dev/null 2>&1 || { c_red "需要 python3 用于安全修改上游脚本。"; return 1; }

  c_yellow "正在下载上游 Xray-go 安装脚本..."
  if ! curl --fail --location --silent --show-error --connect-timeout 10 --max-time 180 \
      "$UPSTREAM_INSTALL" -o "$TMP_INSTALL"; then
    c_red "下载失败，请检查 VPS 网络。"; return 1
  fi
  [[ -s "$TMP_INSTALL" ]] && head -n 1 "$TMP_INSTALL" | grep -q '^#!/.*bash' || {
    c_red "上游脚本校验失败，停止执行。"; return 1;
  }

  # 给上游安装器增加 argopath 参数，并让 Argo 入站和分享链接使用同一路径。
  python3 - "$TMP_INSTALL" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
checks = [
    ('ARG_ARGO_TOKEN=""', 'ARG_ARGO_TOKEN=""\nARG_ARGO_PATH=""'),
    ('    elif [[ "$clean_arg" =~ ^argo[tT][oO][kK][eE][nN](.*)$ ]] || [[ "$clean_arg" =~ ^[tT][oO][kK][eE][nN](.*)$ ]]; then\n        ARG_ARGO_TOKEN="${BASH_REMATCH[1]}"',
     '    elif [[ "$clean_arg" =~ ^argo[tT][oO][kK][eE][nN](.*)$ ]] || [[ "$clean_arg" =~ ^[tT][oO][kK][eE][nN](.*)$ ]]; then\n        ARG_ARGO_TOKEN="${BASH_REMATCH[1]}"\n    elif [[ "$clean_arg" =~ ^argo[pP][aA][tT][hH](.*)$ ]]; then\n        ARG_ARGO_PATH="${BASH_REMATCH[1]}"'),
    ('argo_path="${uuid}-argo"', 'argo_path="${ARG_ARGO_PATH:-${uuid}-argo}"'),
    ('\"path\": \"/$argo_path\"', '\"path\": \"$argo_path\"'),
    ('path=/${argo_path}#', 'path=${argo_path}#'),
]
for old, new in checks:
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"上游脚本结构与预期不符（匹配次数 {count}）：{old[:70]!r}；未执行安装。")
    s = s.replace(old, new, 1)
p.write_text(s, encoding="utf-8")
PY
  chmod 700 "$TMP_INSTALL"
}

install_xray() {
  local reality h3 protocol port domain token argo_path
  echo
  c_green "========== Xray-go 安装向导 =========="
  echo "按提示选择协议；至少启用 Reality、H3 或 Argo 其中一项。"

  if ask_yes_no "部署 VLESS-TCP-REALITY Vision？" "y"; then reality="y"; else reality="n"; fi
  if ask_yes_no "部署 XHTTP H3 直连？" "y"; then
    read -r -p "H3 端口（输入 y 表示随机端口，默认随机）: " h3
    h3=${h3:-y}
    if [[ "$h3" != "y" && ! "$h3" =~ ^[0-9]+$ ]]; then c_red "端口格式无效。"; return 1; fi
    if [[ "$h3" =~ ^[0-9]+$ ]] && (( h3 < 1 || h3 > 65535 )); then c_red "端口必须在 1-65535 之间。"; return 1; fi
  else h3="n"; fi

  if ask_yes_no "部署 Cloudflare Argo 固定隧道？" "n"; then
    read -r -p "Argo 协议（quic/http2，默认 quic）: " protocol
    protocol=${protocol:-quic}; protocol=${protocol,,}
    [[ "$protocol" == "quic" || "$protocol" == "http2" ]] || { c_red "协议只能填写 quic 或 http2。"; return 1; }
    read -r -p "本地回源端口（默认 8001）: " port
    port=${port:-8001}
    [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )) || { c_red "端口格式无效。"; return 1; }
    read -r -p "Cloudflare Tunnel 域名（完整主机名）: " domain
    read -r -s -p "Cloudflare Tunnel Token: " token; echo
    [[ -n "$domain" && -n "$token" ]] || { c_red "启用 Argo 时，域名和 Token 均不能为空。"; return 1; }

    read -r -p "自定义 Argo XHTTP Path（默认 /jiedian，例如 /my-node/ws）: " argo_path
    argo_path=${argo_path:-/jiedian}
    # 兼容用户输入 jiedian 的情况，自动补前导斜杠并移除尾部斜杠。
    [[ "$argo_path" == /* ]] || argo_path="/$argo_path"
    while [[ "$argo_path" != "/" && "$argo_path" == */ ]]; do argo_path="${argo_path%/}"; done
    valid_path "$argo_path" || {
      c_red "Path 格式无效。只允许以 / 开头，使用字母、数字、点、下划线、短横线和斜杠，且不能包含 ..、空格、? 或 #。"
      return 1
    }
  else
    protocol="quic"; port="8001"; domain=""; token=""; argo_path=""
  fi

  if [[ "$reality" == "n" && "$h3" == "n" && -z "$token" ]]; then c_red "你没有启用任何协议，已取消安装。"; return 1; fi

  echo
  c_yellow "即将按以下选项调用安装脚本："
  echo "Reality: $reality"
  echo "H3: $h3"
  echo "Argo: $([[ -n "$token" ]] && echo 已启用 || echo 未启用)"
  if [[ -n "$token" ]]; then
    echo "Argo 协议: $protocol；回源端口: $port；域名: $domain；Path: $argo_path"
  fi
  ask_yes_no "确认开始安装？" "n" || { echo "已取消。"; return 0; }

  fetch_and_patch_upstream || return 1
  bash "$TMP_INSTALL" "reality${reality}" "h3${h3}" "protocol${protocol}" \
    "argoport${port}" "domain${domain}" "token${token}" "argopath${argo_path}"
}

service_action() {
  local action="$1"
  if has_systemd; then systemctl "$action" xray
  elif has_openrc; then
    case "$action" in
      start) rc-service xray start ;; stop) rc-service xray stop ;;
      restart) rc-service xray restart ;; status) rc-service xray status ;;
      *) return 2 ;;
    esac
  else c_red "未检测到 systemd 或 OpenRC。"; return 1; fi
}
show_status() {
  echo
  if has_systemd; then systemctl --no-pager --full status xray || true
  elif has_openrc; then rc-service xray status || true
  else c_yellow "未检测到受支持的服务管理器。"; fi
  if [[ -x "$WORK_DIR/cloudflared" ]]; then
    echo; c_yellow "Cloudflared 相关进程："
    pgrep -af "$WORK_DIR/cloudflared tunnel" || echo "未发现本项目 Cloudflared 隧道进程。"
  fi
}
show_logs() {
  if has_systemd; then journalctl -u xray -n 80 --no-pager || true
  elif [[ -f "$WORK_DIR/xray.log" ]]; then tail -n 80 "$WORK_DIR/xray.log"
  else c_yellow "没有找到 Xray 日志。"; fi
  if [[ -f "$WORK_DIR/cloudflared.log" ]]; then
    echo; c_yellow "------ Cloudflared 最近日志 ------"; tail -n 50 "$WORK_DIR/cloudflared.log"
  fi
}
show_config() {
  if [[ -f "$WORK_DIR/config.json" ]]; then
    if command -v python3 >/dev/null 2>&1; then python3 -m json.tool "$WORK_DIR/config.json" 2>/dev/null || cat "$WORK_DIR/config.json"
    else cat "$WORK_DIR/config.json"; fi
    echo; c_yellow "节点链接文件位置：$WORK_DIR/url.txt"
    [[ -f "$WORK_DIR/url.txt" ]] && cat "$WORK_DIR/url.txt"
  else c_yellow "未找到配置文件：$WORK_DIR/config.json"; fi
}
uninstall_xray() {
  echo
  c_red "警告：卸载将停止 Xray 服务并删除 $WORK_DIR（包括配置、证书、节点链接和日志）。"
  ask_yes_no "确认卸载本脚本部署的 Xray-go？" "n" || { echo "已取消卸载。"; return 0; }
  if has_systemd; then
    systemctl disable --now xray 2>/dev/null || true
    rm -f /etc/systemd/system/xray.service
    systemctl daemon-reload 2>/dev/null || true
  fi
  if has_openrc; then
    rc-service xray stop 2>/dev/null || true
    rc-update del xray default 2>/dev/null || true
    rm -f /etc/init.d/xray
  fi
  if command -v pgrep >/dev/null 2>&1; then
    local pids pid
    pids="$(pgrep -f "^${WORK_DIR}/cloudflared tunnel" 2>/dev/null || true)"
    for pid in $pids; do kill "$pid" 2>/dev/null || true; done
    pids="$(pgrep -f "^${WORK_DIR}/xray run -config ${WORK_DIR}/config.json" 2>/dev/null || true)"
    for pid in $pids; do kill "$pid" 2>/dev/null || true; done
  fi
  rm -rf -- "$WORK_DIR"
  c_green "卸载步骤已完成。"
}
main_menu() {
  need_root
  while true; do
    clear 2>/dev/null || true
    echo "=============================================="
    c_green "          Xray-go 中文管理菜单"
    echo "=============================================="
    echo "  1. 一键安装 / 重新部署"
    echo "  2. 启动 Xray 服务"
    echo "  3. 停止 Xray 服务"
    echo "  4. 重启 Xray 服务"
    echo "  5. 查看运行状态"
    echo "  6. 查看运行日志"
    echo "  7. 查看配置及节点链接"
    echo "  8. 卸载 Xray-go"
    echo "  0. 退出"
    echo "=============================================="
    read -r -p "请输入选项 [0-8]: " choice
    case "$choice" in
      1) install_xray; pause ;; 2) service_action start || true; pause ;;
      3) service_action stop || true; pause ;; 4) service_action restart || true; pause ;;
      5) show_status; pause ;; 6) show_logs; pause ;; 7) show_config; pause ;;
      8) uninstall_xray; pause ;; 0) exit 0 ;;
      *) c_red "无效选项。"; pause ;;
    esac
  done
}
main_menu
