#!/usr/bin/env bash
# Xray-go 中文菜单管理脚本
# 上游项目: https://github.com/eishare/Xray-go
# 本脚本仅作为菜单封装；安装核心逻辑仍由上游 xray-go.sh 执行。

set -Eeuo pipefail
export LANG=C.UTF-8

UPSTREAM_INSTALL="https://raw.githubusercontent.com/eishare/Xray-go/main/xray-go.sh"
WORK_DIR="/etc/xray"
SUB_PORT_FILE="$WORK_DIR/sub_port"
SUB_TOKEN_FILE="$WORK_DIR/sub_token"
TMP_INSTALL="$(mktemp -t xray-go-install.XXXXXX.sh)"
trap 'rm -f "$TMP_INSTALL"' EXIT

c_green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_yellow() { printf '\033[1;33m%s\033[0m\n' "$*"; }
c_red() { printf '\033[1;31m%s\033[0m\n' "$*"; }

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    c_red "请使用 root 权限运行：sudo bash xray-go-menu.sh"
    exit 1
  fi
}

has_systemd() {
  command -v systemctl >/dev/null 2>&1 && { [[ -d /run/systemd/system ]] || [[ -d /etc/systemd/system ]]; }
}

has_openrc() {
  command -v rc-service >/dev/null 2>&1
}

pause() { read -r -p $'\n按回车键返回菜单...' _; }

fetch_upstream_installer() {
  local curl_args=(--fail --location --silent --show-error --connect-timeout 10 --max-time 180)
  if ! command -v curl >/dev/null 2>&1; then
    c_red "未找到 curl，请先安装 curl。"
    return 1
  fi
  c_yellow "正在下载上游官方安装脚本..."
  if ! curl "${curl_args[@]}" "$UPSTREAM_INSTALL" -o "$TMP_INSTALL"; then
    c_red "下载失败，请检查 VPS 网络或稍后重试。"
    return 1
  fi
  if [[ ! -s "$TMP_INSTALL" ]] || ! head -n 1 "$TMP_INSTALL" | grep -q '^#!/.*bash'; then
    c_red "下载内容校验失败，已停止执行。"
    return 1
  fi
  chmod 700 "$TMP_INSTALL"
}

ask_yes_no() {
  local prompt="$1" default="$2" answer
  while true; do
    if [[ "$default" == "y" ]]; then
      read -r -p "$prompt [Y/n]: " answer
      answer=${answer:-y}
    else
      read -r -p "$prompt [y/N]: " answer
      answer=${answer:-n}
    fi
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) echo "请输入 y 或 n。" ;;
    esac
  done
}

install_xray() {
  local reality h3 argo protocol port domain token
  echo
  c_green "========== Xray-go 安装向导 =========="
  echo "按提示选择协议；至少启用 Reality、H3 或 Argo 其中一项。"

  if ask_yes_no "部署 VLESS-TCP-REALITY Vision？" "y"; then reality="y"; else reality="n"; fi

  if ask_yes_no "部署 XHTTP H3 直连？" "y"; then
    read -r -p "H3 端口（输入 y 表示随机端口，默认随机）: " h3
    h3=${h3:-y}
    if [[ "$h3" != "y" && ! "$h3" =~ ^[0-9]+$ ]]; then
      c_red "端口格式无效。"; return 1
    fi
    if [[ "$h3" =~ ^[0-9]+$ ]] && (( h3 < 1 || h3 > 65535 )); then
      c_red "端口必须在 1-65535 之间。"; return 1
    fi
  else
    h3="n"
  fi

  if ask_yes_no "部署 Cloudflare Argo 固定隧道？" "n"; then
    read -r -p "Argo 协议（quic/http2，默认 quic）: " protocol
    protocol=${protocol:-quic}
    protocol=${protocol,,}
    if [[ "$protocol" != "quic" && "$protocol" != "http2" ]]; then
      c_red "协议只能填写 quic 或 http2。"; return 1
    fi
    read -r -p "本地回源端口（默认 8001）: " port
    port=${port:-8001}
    if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
      c_red "端口格式无效。"; return 1
    fi
    read -r -p "Cloudflare Tunnel 域名（完整主机名）: " domain
    read -r -p "Cloudflare Tunnel Token: " token
    if [[ -z "$domain" || -z "$token" ]]; then
      c_red "启用 Argo 时，域名和 Token 均不能为空。"; return 1
    fi
  else
    protocol="quic"; port="8001"; domain=""; token=""
  fi

  # 自定义路径：只允许安全 URL 路径字符，避免写入 JSON / Shell 时产生转义问题。
  h3_custom_path=""
  argo_custom_path=""
  if [[ "$h3" != "n" ]]; then
    echo
    c_yellow "H3-XHTTP 路径设置（必须与 Cloudflare/客户端填写的 Path 完全一致）"
    read -r -p "输入自定义路径（可不带 /，留空则沿用随机 UUID 路径）: " h3_custom_path
    h3_custom_path="${h3_custom_path#/}"
    if [[ -n "$h3_custom_path" && ! "$h3_custom_path" =~ ^[A-Za-z0-9._~-]{1,120}$ ]]; then
      c_red "路径仅允许 1-120 位字母、数字、点、下划线、短横线或波浪线。"; return 1
    fi
  fi
  if [[ -n "$token" ]]; then
    echo
    c_yellow "Argo-XHTTP 路径设置（Cloudflare Tunnel 域名对应的 Path）"
    read -r -p "输入自定义路径（可不带 /，留空则沿用随机 UUID 路径）: " argo_custom_path
    argo_custom_path="${argo_custom_path#/}"
    if [[ -n "$argo_custom_path" && ! "$argo_custom_path" =~ ^[A-Za-z0-9._~-]{1,120}$ ]]; then
      c_red "路径仅允许 1-120 位字母、数字、点、下划线、短横线或波浪线。"; return 1
    fi
  fi

  if [[ "$reality" == "n" && "$h3" == "n" && -z "$token" ]]; then
    c_red "你没有启用任何协议，已取消安装。"; return 1
  fi

  echo
  c_yellow "即将按以下选项调用上游安装脚本："
  echo "Reality: $reality"
  echo "H3: $h3"
  echo "Argo: $([[ -n "$token" ]] && echo 已启用 || echo 未启用)"
  [[ "$h3" != "n" ]] && echo "H3 Path: ${h3_custom_path:+/$h3_custom_path}${h3_custom_path:-随机 UUID 路径}"
  if [[ -n "$token" ]]; then
    echo "Argo 协议: $protocol；回源端口: $port；域名: $domain"
    echo "Argo Path: ${argo_custom_path:+/$argo_custom_path}${argo_custom_path:-随机 UUID 路径}"
  fi
  if ! ask_yes_no "确认开始安装？" "n"; then echo "已取消。"; return 0; fi

  fetch_upstream_installer || return 1

  # 上游目前将 H3/Argo 路径写死为 UUID 派生值。只对下载到临时目录的脚本做精确替换，
  # 不修改上游仓库，也不影响原有随机路径逻辑。
  if [[ -n "$h3_custom_path" ]]; then
    sed -i 's|^h3_path="${uuid}-xu"$|h3_path="'"$h3_custom_path"'"|' "$TMP_INSTALL"
  fi
  if [[ -n "$argo_custom_path" ]]; then
    sed -i 's|^argo_path="${uuid}-argo"$|argo_path="'"$argo_custom_path"'"|' "$TMP_INSTALL"
  fi
  # 参数采用上游脚本支持的关键字形式，避免 shell 引号被提前剥离。
  bash "$TMP_INSTALL" "reality${reality}" "h3${h3}" "protocol${protocol}" "argoport${port}" "domain${domain}" "token${token}"
}

service_action() {
  local action="$1"
  if has_systemd; then
    systemctl "$action" xray
  elif has_openrc; then
    case "$action" in
      start) rc-service xray start ;;
      stop) rc-service xray stop ;;
      restart) rc-service xray restart ;;
      status) rc-service xray status ;;
      *) return 2 ;;
    esac
  else
    c_red "未检测到 systemd 或 OpenRC 服务管理器。"; return 1
  fi
}

show_status() {
  echo
  if has_systemd; then
    systemctl --no-pager --full status xray || true
  elif has_openrc; then
    rc-service xray status || true
  else
    c_yellow "未检测到受支持的服务管理器。"
  fi
  if [[ -x "$WORK_DIR/cloudflared" ]]; then
    echo
    c_yellow "Cloudflared 相关进程："
    pgrep -af "$WORK_DIR/cloudflared tunnel" || echo "未发现本项目 Cloudflared 隧道进程。"
  fi
}

show_logs() {
  if has_systemd; then
    journalctl -u xray -n 80 --no-pager || true
  elif [[ -f "$WORK_DIR/xray.log" ]]; then
    tail -n 80 "$WORK_DIR/xray.log"
  else
    c_yellow "没有找到 Xray 日志。"
  fi
  if [[ -f "$WORK_DIR/cloudflared.log" ]]; then
    echo; c_yellow "------ Cloudflared 最近日志 ------"; tail -n 50 "$WORK_DIR/cloudflared.log"
  fi
}

show_config() {
  echo
  c_green "========== 节点配置信息 =========="
  if [[ -f "$WORK_DIR/config.json" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      python3 - "$WORK_DIR/config.json" <<'PY'
import json, sys
try:
    data=json.load(open(sys.argv[1], encoding="utf-8"))
    for i, item in enumerate(data.get("inbounds", []), 1):
        ss=item.get("streamSettings", {})
        net=ss.get("network", "unknown")
        sec=ss.get("security", "none")
        settings=ss.get("xhttpSettings", {}) if net in ("xhttp","splithttp") else ss.get("wsSettings", {}) if net in ("ws","websocket") else {}
        print(f"\n节点 {i}: {item.get('tag','未命名')}")
        print(f"  协议: {item.get('protocol','')}  端口: {item.get('port','')}")
        print(f"  传输: {net}  加密: {sec}")
        print(f"  Host: {settings.get('host','') or '未设置'}")
        print(f"  Path: {settings.get('path','') or '无'}")
        clients=item.get("settings",{}).get("clients",[])
        if clients: print(f"  UUID: {clients[0].get('id','')}")
except Exception as e:
    print("解析配置失败：", e)
PY
    else
      cat "$WORK_DIR/config.json"
    fi
    echo
    c_yellow "节点链接文件：$WORK_DIR/url.txt"
    [[ -f "$WORK_DIR/url.txt" ]] && cat "$WORK_DIR/url.txt"
  else
    c_yellow "未找到配置文件：$WORK_DIR/config.json"
  fi
}


subscription_menu() {
  while true; do
    echo
    c_green "========== 本地订阅管理 =========="
    echo "  1. 生成 / 更新订阅链接"
    echo "  2. 查看订阅链接"
    echo "  3. 查看订阅内容"
    echo "  4. 停止并卸载本地订阅服务"
    echo "  0. 返回上一级"
    echo "=================================="
    read -r -p "请选择 [0-4]: " sub_choice
    case "$sub_choice" in
      1) create_subscription; pause ;;
      2) show_subscription_link; pause ;;
      3) show_subscription_content; pause ;;
      4) remove_subscription; pause ;;
      0) return 0 ;;
      *) c_red "无效选项。" ;;
    esac
  done
}

create_subscription() {
  if [[ ! -s "$WORK_DIR/url.txt" ]]; then
    c_red "没有找到节点文件 $WORK_DIR/url.txt，请先完成安装。"; return 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    c_red "本地订阅服务需要 Python 3，请先安装 python3。"; return 1
  fi
  local port token ip python_bin
  python_bin="$(command -v python3)"
  read -r -p "订阅服务端口（默认 18080）: " port
  port=${port:-18080}
  if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
    c_red "端口必须是 1-65535。"; return 1
  fi
  token="$(openssl rand -hex 24 2>/dev/null || head -c 48 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-48)"
  mkdir -p "$WORK_DIR"
  printf '%s\n' "$port" > "$SUB_PORT_FILE"
  printf '%s\n' "$token" > "$SUB_TOKEN_FILE"
  chmod 600 "$SUB_TOKEN_FILE"
  cat > "$WORK_DIR/sub_server.py" <<'PY'
#!/usr/bin/env python3
import base64, http.server, pathlib
ROOT=pathlib.Path("/etc/xray")
PORT=int((ROOT/"sub_port").read_text().strip())
TOKEN=(ROOT/"sub_token").read_text().strip()
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/sub/"+TOKEN:
            self.send_error(404); return
        src=ROOT/"url.txt"
        if not src.is_file():
            self.send_error(404, "node list missing"); return
        body=base64.b64encode(src.read_bytes())
        self.send_response(200)
        self.send_header("Content-Type","text/plain; charset=utf-8")
        self.send_header("Content-Length",str(len(body)))
        self.send_header("Cache-Control","no-store")
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, fmt, *args):
        pass
http.server.ThreadingHTTPServer(("0.0.0.0",PORT),Handler).serve_forever()
PY
  chmod 700 "$WORK_DIR/sub_server.py"
  if has_systemd; then
    cat > /etc/systemd/system/xray-sub.service <<EOF
[Unit]
Description=Xray local subscription service
After=network.target
[Service]
Type=simple
User=root
ExecStart=$python_bin $WORK_DIR/sub_server.py
Restart=on-failure
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now xray-sub
  elif has_openrc; then
    cat > /etc/init.d/xray-sub <<EOF
#!/sbin/openrc-run
description="Xray local subscription service"
command="$python_bin"
command_args="$WORK_DIR/sub_server.py"
command_background="yes"
pidfile="/run/xray-sub.pid"
depend() { need net; }
EOF
    chmod +x /etc/init.d/xray-sub
    rc-update add xray-sub default
    rc-service xray-sub restart
  else
    c_red "未检测到 systemd 或 OpenRC，无法注册订阅服务。"; return 1
  fi
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "$port/tcp" >/dev/null 2>&1 || true
  fi
  if command -v iptables >/dev/null 2>&1; then
    iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
  fi
  ip="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || curl -6 -fsS --max-time 5 https://api64.ipify.org 2>/dev/null || true)"
  if [[ "$ip" == *:* ]]; then ip="[$ip]"; fi
  [[ -z "$ip" ]] && ip="你的VPS公网IP"
  c_green "订阅服务已启动。"
  echo "订阅地址：http://${ip}:${port}/sub/${token}"
  c_yellow "注意：当前为 HTTP 明文订阅。建议仅在可信网络使用，或通过 HTTPS 反向代理保护。"
}

show_subscription_link() {
  if [[ ! -s "$SUB_PORT_FILE" || ! -s "$SUB_TOKEN_FILE" ]]; then
    c_yellow "尚未生成订阅链接。"; return 1
  fi
  local ip port token
  port="$(cat "$SUB_PORT_FILE")"; token="$(cat "$SUB_TOKEN_FILE")"
  ip="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || curl -6 -fsS --max-time 5 https://api64.ipify.org 2>/dev/null || true)"
  [[ "$ip" == *:* ]] && ip="[$ip]"
  [[ -z "$ip" ]] && ip="你的VPS公网IP"
  echo "订阅地址：http://${ip}:${port}/sub/${token}"
  if has_systemd; then systemctl --no-pager --full status xray-sub 2>/dev/null | head -n 12 || true
  elif has_openrc; then rc-service xray-sub status 2>/dev/null || true; fi
}

show_subscription_content() {
  if [[ ! -s "$WORK_DIR/url.txt" ]]; then c_yellow "未找到节点文件。"; return 1; fi
  c_yellow "原始节点内容："
  cat "$WORK_DIR/url.txt"
  echo
  c_yellow "Base64 订阅内容："
  base64 < "$WORK_DIR/url.txt" | tr -d '\n'
  echo
}

remove_subscription() {
  if ! ask_yes_no "确认停止并删除本地订阅服务？" "n"; then echo "已取消。"; return 0; fi
  if has_systemd; then
    systemctl disable --now xray-sub 2>/dev/null || true
    rm -f /etc/systemd/system/xray-sub.service
    systemctl daemon-reload 2>/dev/null || true
  fi
  if has_openrc; then
    rc-service xray-sub stop 2>/dev/null || true
    rc-update del xray-sub default 2>/dev/null || true
    rm -f /etc/init.d/xray-sub
  fi
  rm -f "$WORK_DIR/sub_server.py" "$SUB_PORT_FILE" "$SUB_TOKEN_FILE"
  c_green "本地订阅服务及密钥已删除。"
  c_yellow "防火墙放行规则未自动删除，以免影响其他服务规则。"
}

uninstall_xray() {
  echo
  c_red "警告：卸载将停止 Xray 服务并删除 $WORK_DIR（包括配置、证书、节点链接和日志）。"
  c_yellow "本菜单不会执行上游卸载脚本中的全局 pkill -f xray/cloudflared。"
  if ! ask_yes_no "确认卸载本脚本部署的 Xray-go？" "n"; then echo "已取消卸载。"; return 0; fi

  # 先停止由服务管理器管理的本项目服务。
  if has_systemd; then
    systemctl disable --now xray 2>/dev/null || true
    rm -f /etc/systemd/system/xray.service
    systemctl daemon-reload 2>/dev/null || true
  fi
  if has_openrc; then
    rc-service xray stop 2>/dev/null || true
    rc-update del xray default 2>/dev/null || true
    rm -f /etc/init.d/xray
    rc-service xray-sub stop 2>/dev/null || true
    rc-update del xray-sub default 2>/dev/null || true
    rm -f /etc/init.d/xray-sub
  fi
  if has_systemd; then
    systemctl disable --now xray-sub 2>/dev/null || true
    rm -f /etc/systemd/system/xray-sub.service
    systemctl daemon-reload 2>/dev/null || true
  fi

  # 只匹配本项目安装目录下的二进制路径，不按进程名全局杀进程。
  if command -v pgrep >/dev/null 2>&1; then
    local pids pid
    pids="$(pgrep -f "^${WORK_DIR}/cloudflared tunnel" 2>/dev/null || true)"
    for pid in $pids; do kill "$pid" 2>/dev/null || true; done
    pids="$(pgrep -f "^${WORK_DIR}/xray run -config ${WORK_DIR}/config.json" 2>/dev/null || true)"
    for pid in $pids; do kill "$pid" 2>/dev/null || true; done
  fi

  rm -rf -- "$WORK_DIR"
  c_green "卸载步骤已完成。"
  c_yellow "提示：原项目安装时添加的防火墙放行规则可能仍然存在；本脚本不会清理规则，以免误删其他服务规则。"
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
    echo "  7. 查看配置及节点路径信息"
    echo "  8. 本地订阅链接管理"
    echo "  9. 卸载 Xray-go"
    echo "  0. 退出"
    echo "=============================================="
    read -r -p "请输入选项 [0-9]: " choice
    case "$choice" in
      1) install_xray; pause ;;
      2) service_action start || true; pause ;;
      3) service_action stop || true; pause ;;
      4) service_action restart || true; pause ;;
      5) show_status; pause ;;
      6) show_logs; pause ;;
      7) show_config; pause ;;
      8) subscription_menu ;;
      9) uninstall_xray; pause ;;
      0) exit 0 ;;
      *) c_red "无效选项。"; pause ;;
    esac
  done
}

main_menu
