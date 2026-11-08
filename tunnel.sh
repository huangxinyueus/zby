#!/bin/sh
W="/tmp/cf_tunnel_workspace"
mkdir -p "$W"
B="$W/cloudflared"
L="$W/tunnel.log"
PORT="${1:-22837}"

if [ ! -f "$B" ]; then
    echo "正在下载 cloudflared..."
    wget -O "$B" https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
    chmod +x "$B"
fi

pkill -f "cloudflared tunnel" 2>/dev/null
rm -f "$L"

echo "正在启动本地端口 $PORT 的隧道..."
nohup "$B" tunnel --url "http://localhost:${PORT}" > "$L" 2>&1 &

i=1
while [ $i -le 15 ]; do
    sleep 2
    if [ -f "$L" ]; then
        URL=$(grep -oE "https://[a-zA-Z0-9.-]+\.trycloudflare\.com" "$L" | head -n 1)
        if [ -n "$URL" ]; then
            echo "✔ 隧道启动成功！临时地址: $URL"
            exit 0
        fi
    fi
    i=$((i + 1))
done

echo "获取超时，请检查日志: cat $L"
exit 1