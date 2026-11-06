#!usrbinenv bash
# ====================================================
# Project Xray-go Interactive Manager
# Description Interactive installer & uninstaller for eishareXray-go
# ====================================================

RED=033[31m
GREEN=033[32m
YELLOW=033[33m
PLAIN=033[0m

function check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e ${RED}[错误] 必须使用 root 权限运行此脚本！${PLAIN}
        exit 1
    fi
}

function install_node() {
    clear
    echo -e ${GREEN}==========================================${PLAIN}
    echo -e ${GREEN}      Xray-go 交互式一键部署引导          ${PLAIN}
    echo -e ${GREEN}==========================================${PLAIN}
    
    # 1. Reality 伪装配置
    read -rp 是否开启 Reality 伪装？[yN] (默认 n)  input_reality
    reality=${input_reality-n}

    # 2. HTTP3 (QUICUDP) 配置
    read -rp 是否开启 HTTP3 (QUICUDP)？[yN] (默认 y)  input_h3
    h3=${input_h3-y}

    # 3. 传输协议
    echo 请选择本地传输协议（与 Cloudflare 隧道配合推荐 http2）：
    echo   1) http2 (推荐)
    echo   2) http
    read -rp 请输入序号 [1-2] (默认 1)  proto_choice
    case $proto_choice in
        2) protocol=http ;;
        ) protocol=http2 ;;
    esac

    # 4. 本地监听端口
    read -rp 请输入本地监听端口 (默认 8001)  input_port
    port=${input_port-8001}

    # 5. Cloudflare 隧道域名
    while true; do
        read -rp 请输入 Cloudflare 固定隧道域名 (例如 node.example.com)  domain
        [ -n $domain ] && break
        echo -e ${YELLOW}[!] 域名不能为空，请重新输入。${PLAIN}
    done

    # 6. Cloudflare Tunnel Token
    while true; do
        read -rp 请输入 Cloudflare Tunnel Token  token
        [ -n $token ] && break
        echo -e ${YELLOW}[!] Token 不能为空，请重新输入。${PLAIN}
    done

    # 自动拼接 eishareXray-go 特有的传参格式
    CMD=bash (curl -Ls httpsraw.githubusercontent.comeishareXray-gomainxray-go.sh) reality$reality h3$h3 argo protocol$protocol port$port domain$domain token$token

    echo -e n${YELLOW}正在调用底层核心脚本部署...${PLAIN}n
    eval $CMD
}

function uninstall_all() {
    clear
    echo -e ${RED}==========================================${PLAIN}
    echo -e ${RED}           彻底卸载 Xray 与固定隧道       ${PLAIN}
    echo -e ${RED}==========================================${PLAIN}
    read -rp 确认彻底卸载并清理所有相关文件吗？[yN]  confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo 已取消卸载。
        return
    fi

    echo -e ${YELLOW}正在停止并禁用 systemd 服务...${PLAIN}
    systemctl stop cloudflared 2devnull  true
    systemctl disable cloudflared 2devnull  true
    systemctl stop xray 2devnull  true
    systemctl disable xray 2devnull  true

    echo -e ${YELLOW}正在终止残留进程...${PLAIN}
    pkill -9 cloudflared 2devnull  true
    pkill -9 xray 2devnull  true

    echo -e ${YELLOW}正在清理相关配置文件与二进制执行文件...${PLAIN}
    rm -f etcsystemdsystemcloudflared.service
    rm -f etcsystemdsystemxray.service
    systemctl daemon-reload

    rm -rf etcxray
    rm -rf usrlocalbinxray
    rm -rf usrlocalbincloudflared
    rm -rf etccloudflared
    rm -rf root.cloudflared

    echo -e ${GREEN}[成功] 所有服务及残留文件已彻底清除干净！${PLAIN}
}

function check_status() {
    clear
    echo -e ${GREEN}================ 服务运行状态 ================${PLAIN}
    echo -e n${YELLOW}[Xray 服务状态]${PLAIN}
    systemctl status xray --no-pager 2devnull  ps aux  grep xray  grep -v grep  echo 未找到 Xray 服务

    echo -e n${YELLOW}[Cloudflared 隧道状态]${PLAIN}
    systemctl status cloudflared --no-pager 2devnull  ps aux  grep cloudflared  grep -v grep  echo 未找到 Cloudflared 服务
    echo -e ${GREEN}==============================================${PLAIN}
    read -rp 按回车键返回主菜单...
}

function show_menu() {
    clear
    echo -e ${GREEN}==========================================${PLAIN}
    echo -e ${GREEN}        Xray-go 综合交互管理菜单          ${PLAIN}
    echo -e ${GREEN}==========================================${PLAIN}
    echo -e  1. ${GREEN}安装  重新部署节点${PLAIN}
    echo -e  2. ${RED}完全卸载并清理残留${PLAIN}
    echo -e  3. 查看服务运行状态
    echo -e  0. 退出脚本
    echo -e ------------------------------------------
    read -rp 请输入选项 [0-3]  choice
    case $choice in
        1) install_node ;;
        2) uninstall_all ;;
        3) check_status; show_menu ;;
        0) exit 0 ;;
        ) echo 输入无效; sleep 1; show_menu ;;
    esac
}

check_root
show_menu