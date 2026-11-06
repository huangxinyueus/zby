/dev/fd/63: line 26: `    read -rp 是否开启 Reality 伪装? [yN] (默认 n)  input_reality'
```[cite: 2]

### 出错原因
提示文字两端的**双引号丢失了**[cite: 2]。在 Bash 中，没有被引号包裹的圆括号 `(默认 n)` 会被当作**子 Shell 语法**进行解析，从而触发语法错误并直接中断执行[cite: 2]。

---

### 解决办法

进入你的 GitHub 仓库（`[https://github.com/huangxinyueus/zby](https://github.com/huangxinyueus/zby)`）编辑 `install.sh`，将整个文件内容替换为以下修正后的无特殊符号版本，并**Commit changes**保存：

```bash
#!/usr/bin/env bash
set -e

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[错误] 必须使用 root 权限运行此脚本！${PLAIN}"
        exit 1
    fi
}

install_node() {
    clear
    echo -e "${GREEN}==========================================${PLAIN}"
    echo -e "${GREEN}      Xray-go 交互式一键部署引导          ${PLAIN}"
    echo -e "${GREEN}==========================================${PLAIN}"
    
    # 1. Reality 伪装配置
    read -rp "是否开启 Reality 伪装？[y/n 默认 n]: " input_reality
    reality="${input_reality:-n}"

    # 2. HTTP/3 配置
    read -rp "是否开启 HTTP/3？[y/n 默认 y]: " input_h3
    h3="${input_h3:-y}"

    # 3. 传输协议
    echo "请选择本地传输协议（推荐选择 1）:"
    echo "  1. http2"
    echo "  2. http"
    read -rp "请输入序号 [1-2 默认 1]: " proto_choice
    case "$proto_choice" in
        2) protocol="http" ;;
        *) protocol="http2" ;;
    esac

    # 4. 端口
    read -rp "请输入本地监听端口 [默认 8001]: " input_port
    port="${input_port:-8001}"

    # 5. 域名
    while true; do
        read -rp "请输入 Cloudflare 固定隧道域名: " domain
        [ -n "$domain" ] && break
        echo -e "${YELLOW}[!] 域名不能为空，请重新输入。${PLAIN}"
    done

    # 6. Token
    while true; do
        read -rp "请输入 Cloudflare Tunnel Token: " token
        [ -n "$token" ] && break
        echo -e "${YELLOW}[!] Token 不能为空，请重新输入。${PLAIN}"
    done

    echo -e "\n${YELLOW}正在调用底层脚本进行部署...${PLAIN}\n"
    CMD="bash <(curl -Ls https://raw.githubusercontent.com/eishare/Xray-go/main/xray-go.sh) reality\"$reality\" h3\"$h3\" argo protocol\"$protocol\" port\"$port\" domain\"$domain\" token\"$token\""
    eval "$CMD"
}

uninstall_all() {
    clear
    echo -e "${RED}==========================================${PLAIN}"
    echo -e "${RED}           彻底卸载 Xray 与固定隧道       ${PLAIN}"
    echo -e "${RED}==========================================${PLAIN}"
    read -rp "确认彻底卸载并清理残留吗？[y/n]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消卸载。"
        return
    fi

    echo -e "${YELLOW}正在停止并清理服务...${PLAIN}"
    systemctl stop cloudflared 2>/dev/null || true
    systemctl disable cloudflared 2>/dev/null || true
    systemctl stop xray 2>/dev/null || true
    systemctl disable xray 2>/dev/null || true

    pkill -9 cloudflared 2>/dev/null || true
    pkill -9 xray 2>/dev/null || true

    rm -f /etc/systemd/system/cloudflared.service
    rm -f /etc/systemd/system/xray.service
    systemctl daemon-reload

    rm -rf /etc/xray /usr/local/bin/xray /usr/local/bin/cloudflared /etc/cloudflared /root/.cloudflared

    echo -e "${GREEN}[成功] 所有服务及残留已清理完毕！${PLAIN}"
}

check_status() {
    clear
    echo -e "${GREEN}================ 服务状态 ================${PLAIN}"
    echo -e "\n${YELLOW}[Xray 状态]${PLAIN}"
    systemctl status xray --no-pager 2>/dev/null || ps aux | grep xray | grep -v grep || echo "未找到 Xray 进程"

    echo -e "\n${YELLOW}[Cloudflared 隧道状态]${PLAIN}"
    systemctl status cloudflared --no-pager 2>/dev/null || ps aux | grep cloudflared | grep -v grep || echo "未找到 Cloudflared 进程"
    echo -e "${GREEN}==========================================${PLAIN}"
    read -rp "按回车键返回菜单..."
}

show_menu() {
    clear
    echo -e "${GREEN}==========================================${PLAIN}"
    echo -e "${GREEN}        Xray-go 综合交互管理菜单          ${PLAIN}"
    echo -e "${GREEN}==========================================${PLAIN}"
    echo -e " 1. ${GREEN}安装 / 重新部署${PLAIN}"
    echo -e " 2. ${RED}完全卸载清理${PLAIN}"
    echo -e " 3. 查看运行状态"
    echo -e " 0. 退出"
    echo -e "------------------------------------------"
    read -rp "请输入选项 [0-3]: " choice
    case "$choice" in
        1) install_node ;;
        2) uninstall_all ;;
        3) check_status; show_menu ;;
        0) exit 0 ;;
        *) echo "输入无效"; sleep 1; show_menu ;;
    esac
}

check_root
show_menu
