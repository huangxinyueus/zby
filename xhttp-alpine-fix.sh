#!/usr/bin/env bash
# Xray-go xhttp.sh Alpine/Debian/Ubuntu compatibility bootstrap
# Downloads the maintained 667-line menu script, patches mktemp, validates, then runs it.
set -Eeuo pipefail

RAW_URL="https://raw.githubusercontent.com/huangxinyueus/zby/main/xhttp.sh"
TMP_DIR="${TMPDIR:-/tmp}"
WORK_FILE="$(mktemp "${TMP_DIR%/}/xhttp-fixed.XXXXXX")"
trap 'rm -f "$WORK_FILE"' EXIT

say() { printf '\033[1;32m%s\033[0m\n' "$*"; }
err() { printf '\033[1;31m%s\033[0m\n' "$*" >&2; }

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  err "请使用 root 运行：sudo bash xhttp.sh"
  exit 1
fi

if [[ -f /etc/alpine-release ]] || grep -qi '^ID=alpine' /etc/os-release 2>/dev/null; then
  command -v apk >/dev/null 2>&1 || { err "未找到 apk"; exit 1; }
  apk add --no-cache bash curl wget coreutils unzip openssl iptables python3
elif grep -Eqi '^(ID|ID_LIKE)=.*(debian|ubuntu)' /etc/os-release 2>/dev/null; then
  command -v apt-get >/dev/null 2>&1 || { err "未找到 apt-get"; exit 1; }
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y bash curl wget coreutils unzip openssl iptables python3
else
  err "仅支持 Debian、Ubuntu、Alpine。"
  exit 1
fi

command -v curl >/dev/null 2>&1 || { err "curl 安装失败"; exit 1; }
say "正在下载 GitHub 原版 xhttp.sh……"
curl -fL --connect-timeout 15 --max-time 180 "$RAW_URL" -o "$WORK_FILE"

if [[ ! -s "$WORK_FILE" ]] || ! head -n 1 "$WORK_FILE" | grep -q '^#!/.*bash'; then
  err "下载内容校验失败，停止运行。"
  exit 1
fi

# Replace only the known incompatible mktemp line; leave all other menu logic intact.
if grep -Fq 'TMP_INSTALL="$(mktemp -t xray-go-install.XXXXXX.sh)"' "$WORK_FILE"; then
  sed -i 's|^TMP_INSTALL=.*|TMP_INSTALL="$(mktemp "${TMPDIR:-/tmp}/xray-go-install.XXXXXX")"|' "$WORK_FILE"
elif ! grep -Fq 'TMP_INSTALL="$(mktemp "${TMPDIR:-/tmp}/xray-go-install.XXXXXX")"' "$WORK_FILE"; then
  err "未找到预期的 TMP_INSTALL 行，可能上游脚本已变化；为避免误改，停止运行。"
  exit 1
fi

bash -n "$WORK_FILE" || { err "Bash 语法检查失败，停止运行。"; exit 1; }
chmod 700 "$WORK_FILE"
say "修复完成：mktemp 已兼容 Alpine BusyBox；Bash 语法检查通过。"
say "即将启动完整 Xray-go 中文管理菜单（原有功能保留）。"
exec bash "$WORK_FILE"
