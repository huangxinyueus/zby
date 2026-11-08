cat << 'EOF' > /usr/local/bin/cf-tunnel
#!/bin/sh

# 1. 自动检测并安装必要依赖 (兼容 Alpine/Debian/Ubuntu)
install_dependencies() {
    if ! command -v cloudflared >/dev/null 2>&1; then
        echo "正在下载安装 cloudflared 客户端..."
        if [ -f /etc/alpine-release ] || [ "$(uname -s)" = "Linux" ] && grep -q "Alpine" /etc/issue 2>/dev/null; then
            wget -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
        else
            curl -L --output /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
        fi
        chmod +x /usr/local/bin/cloudflared
    fi
}

# 2. 启动隧道核心逻辑
start_tunnel() {
    PORT=${1:-22837}
    LOG_FILE="/tmp/cloudflared_tunnel.log"

    pkill -f "cloudflared tunnel" 2>/dev/null

    echo "正在为本地端口 $PORT 启动跨平台 Cloudflare 临时隧道..."
    nohup cloudflared tunnel --url "http://localhost:${PORT}" > "$LOG_FILE" 2>&1 &

    echo -n "正在等待获取动态隧道域名"
    for i in $(seq 1 15); do
        sleep 2
        echo -n "."
        URL=$(grep -oE "https://[a-zA-Z0-9.-]+\.trycloudflare\.com" "$LOG_FILE" | head -n 1)
        if [ -n "$URL" ]; then
            echo -e "\n\n=========================================="
            echo "✔ 隧道启动成功！"
            echo "临时访问地址: $URL"
            echo "转发本地端口: $PORT"
            echo "=========================================="
            exit 0
        fi
    done

    echo -e "\n❌ 获取域名超时，请检查日志: cat $LOG_FILE"
    exit 1
}

# 命令分发
case "$1" in
    stop)
        pkill -f "cloudflared tunnel"
        echo "已停止所有 Cloudflare 隧道进程。"
        ;;
    log)
        cat /tmp/cloudflared_tunnel.log
        ;;
    *)
        install_dependencies
        start_tunnel "$1"
        ;;
esac
EOF

chmod +x /usr/local/bin/cf-tunnel
