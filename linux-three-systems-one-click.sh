#!/usr/bin/env bash
# Debian / Ubuntu / Alpine one-click launcher for Xray-go xhttp menu.
set -Eeuo pipefail

BOOTSTRAP_URL="https://raw.githubusercontent.com/huangxinyueus/zby/main/xhttp-alpine-fix.sh"
TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/xhttp-bootstrap.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "请使用 root 运行：sudo bash linux-three-systems-one-click.sh"
  exit 1
fi

if [[ -f /etc/alpine-release ]] || grep -qi '^ID=alpine' /etc/os-release 2>/dev/null; then
  command -v apk >/dev/null 2>&1 || { echo "未找到 apk"; exit 1; }
  apk add --no-cache bash curl
elif grep -Eqi '^(ID|ID_LIKE)=.*(debian|ubuntu)' /etc/os-release 2>/dev/null; then
  command -v apt-get >/dev/null 2>&1 || { echo "未找到 apt-get"; exit 1; }
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y bash curl
else
  echo "仅支持 Debian、Ubuntu、Alpine。"
  exit 1
fi

curl -fL --connect-timeout 15 --max-time 120 "$BOOTSTRAP_URL" -o "$TMP_FILE"
head -n 1 "$TMP_FILE" | grep -q '^#!/.*bash' || { echo "下载校验失败"; exit 1; }
bash -n "$TMP_FILE"
exec bash "$TMP_FILE"
