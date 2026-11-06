#!/usr/bin/env bash
# Cloudflare Quick Tunnel 一键后台管理脚本
# 适用：常见 Linux VPS / Linux 容器（amd64、arm64）
# 说明：Quick Tunnel 使用随机 trycloudflare.com 域名，不需要 Cloudflare 账号或固定域名。

set -u

APP_NAME="Cloudflare 临时隧道"
BASE_DIR="${CLOUDFLARED_HOME:-$HOME/.cloudflare-quick-tunnel}"
BIN="$BASE_DIR/cloudflared"
LOG="$BASE_DIR/tunnel.log"
PIDFILE="$BASE_DIR/tunnel.pid"
URLFILE="$BASE_DIR/tunnel.url"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

say()  { printf "%b\n" "$1"; }
info() { say "${CYAN}$1${NC}"; }
ok()   { say "${GREEN}$1${NC}"; }
warn() { say "${YELLOW}$1${NC}"; }
err()  { say "${RED}$1${NC}"; }

mkdir -p "$BASE_DIR" 2>/dev/null || {
  err "无法创建目录：$BASE_DIR"
  exit 1
}

get_pid() {
  if [ -f "$PIDFILE" ]; then
    cat "$PIDFILE" 2>/dev/null
  fi
}

is_running() {
  local p
  p="$(get_pid)"
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}

detect_asset() {
  case "$(uname -m)" in
    x86_64|amd64) echo "cloudflared-linux-amd64" ;;
    aarch64|arm64) echo "cloudflared-linux-arm64" ;;
    *)
      err "暂不支持当前 CPU 架构：$(uname -m)"
      err "目前脚本支持 x86_64/amd64 和 aarch64/arm64。"
      return 1
      ;;
  esac
}

download_binary() {
  local asset url tmp
  asset="$(detect_asset)" || return 1
  url="https://github.com/cloudflare/cloudflared/releases/latest/download/$asset"
  tmp="$BASE_DIR/cloudflared.download"

  info "正在下载 cloudflared（$asset）..."
  if command -v curl >/dev/null 2>&1; then
    curl -fL --connect-timeout 15 --retry 2 "$url" -o "$tmp" || {
      err "下载失败，请检查 VPS/容器的网络连接。"
      rm -f "$tmp"
      return 1
    }
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$tmp" "$url" || {
      err "下载失败，请检查 VPS/容器的网络连接。"
      rm -f "$tmp"
      return 1
    }
  else
    err "系统没有 curl 或 wget。请先安装其中一个再运行脚本。"
    return 1
  fi

  chmod 755 "$tmp"
  mv "$tmp" "$BIN"
  if ! "$BIN" --version >/dev/null 2>&1; then
    err "cloudflared 文件无法执行，可能是系统架构或运行环境不兼容。"
    rm -f "$BIN"
    return 1
  fi
  ok "cloudflared 安装完成：$("$BIN" --version 2>&1 | head -n 1)"
}

start_tunnel() {
  local port i url
  if is_running; then
    warn "隧道已经在后台运行。"
    show_status
    return
  fi