#!binsh

# 定义工作路径与日志
WORK_DIR=tmpcf_tunnel_workspace
mkdir -p $WORK_DIR
LOG_FILE=$WORK_DIRtunnel.log
BIN_FILE=$WORK_DIRcloudflared

# 1. 自动检测系统并下载 cloudflared 客户端
install_dependencies() {
    if [ ! -f $BIN_FILE ]; then
        echo 正在下载 cloudflared 客户端...
        if [ -f etcalpine-release ]  grep -qi Alpine etcissue 2devnull; then
            wget -O $BIN_FILE httpsgithub.comcloudflarecloudflaredreleaseslatestdownloadcloudflared-linux-amd64
        else
            if command -v curl devnull 2&1; then
                curl -L --output $BIN_FILE httpsgithub.comcloudflarecloudflaredreleaseslatestdownloadcloudflared-linux-amd64
            else
                wget -O $BIN_FILE httpsgithub.comcloudflarecloudflaredreleaseslatestdownloadcloudflared-linux-amd64
            fi
        fi
        chmod +x $BIN_FILE
    fi
}

# 2. 启动隧道核心逻辑
start_tunnel() {
    PORT=${1-22837}
    
    # 清理旧进程与旧日志
    pkill -f cloudflared tunnel 2devnull
    rm -f $LOG_FILE

    echo 正在为本地端口 $PORT 启动 Cloudflare 临时隧道...
    nohup $BIN_FILE tunnel --url httplocalhost${PORT}  $LOG_FILE 2&1 &

    echo -n 正在等待获取动态隧道域名
    i=1
    while [ $i -le 15 ]; do
        sleep 2
        echo -n .
        if [ -f $LOG_FILE ]; then
            URL=$(grep -oE https[a-zA-Z0-9.-]+.trycloudflare.com $LOG_FILE  head -n 1)
            if [ -n $URL ]; then
                echo 
                echo ==========================================
                echo ✔ 隧道启动成功！
                echo 临时访问地址 $URL
                echo 转发本地端口 $PORT
                echo ==========================================
                exit 0
            fi
        fi
        i=$((i + 1))
    done

    echo 
    echo ❌ 获取域名超时，请检查日志 cat $LOG_FILE
    exit 1
}

# 3. 停止隧道函数
stop_tunnel() {
    pkill -f cloudflared tunnel
    echo 已成功停止所有 Cloudflare 隧道进程。
}

# 4. 主控分发逻辑
case $1 in
    stop)
        stop_tunnel
        ;;
    log)
        [ -f $LOG_FILE ] && cat $LOG_FILE  echo 暂无日志文件
        ;;
    )
        install_dependencies
        start_tunnel $1
        ;;
esac