#!/usr/bin/env bash

# ========================================================
# 脚本名称: xhttp.sh
# 仓库路径: huangxinyueus/zby
# 功能: Xray-go 增强版 (原生支持自定义 Path 与回车默认无路径、查看配置详情与本地订阅分享)
# ========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

SUB_CONF="/etc/xray_sub_service.conf"
SUB_SERVICE="/etc/systemd/system/xray-sub.service"
SUB_DIR="/var/www/xray_sub"

get_config_path() {
    for conf in /usr/local/etc/xray/config.json /etc/xray/config.json; do
        if [[ -f "$conf" ]]; then
            echo "$conf"
            return
        fi
    done
    echo ""
}

get_public_ip() {
    local ip
    ip=$(curl -s4m 5 https://api.ipify.org || curl -s4m 5 https://ipv4.icanhazip.com || curl -s4m 5 https://ifconfig.me)
    echo "$ip"
}

apply_path_patch() {
    local p="$1"
    local conf
    conf=$(get_config_path)
    [[ -z "$conf" ]] && return

    python3 - "$p" "$conf" << 'EOF'
import sys, json
path_val = sys.argv[1]
f_path = sys.argv[2]
try:
    with open(f_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    for ib in data.get('inbounds', []):
        ss = ib.get('streamSettings', {})
        net = ss.get('network')
        if net == 'xhttp':
            xs = ss.setdefault('xhttpSettings', {})
            if path_val: xs['path'] = path_val
            else: xs.pop('path', None)
        elif net == 'ws':
            ws = ss.setdefault('wsSettings', {})
            if path_val: ws['path'] = path_val
            else: ws.pop('path', None)
    with open(f_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
except Exception:
    pass
EOF
    systemctl restart xray
}

generate_node_link() {
    local conf
    conf=$(get_config_path)
    [[ -z "$conf" ]] && return

    python3 - "$conf" << 'EOF'
import sys, json, urllib.parse, os

conf = sys.argv[1]
try:
    with open(conf, 'r', encoding='utf-8') as f:
        d = json.load(f)
    ib = d['inbounds'][0]
    uuid = ib['settings']['clients'][0]['id']
    ss = ib.get('streamSettings', {})
    net = ss.get('network', 'xhttp')
    
    sk = 'xhttpSettings' if net == 'xhttp' else 'wsSettings'
    path = ss.get(sk, {}).get('path', '')
    
    host = "node.example.com"
    if os.path.exists("/etc/xray_tunnel_domain.txt"):
        with open("/etc/xray_tunnel_domain.txt", "r") as tf:
            val = tf.read().strip()
            if val: host = val
            
    params = {
        'encryption': 'none',
        'security': 'tls',
        'sni': host,
        'type': net
    }
    if path:
        params['path'] = path
    
    query = urllib.parse.urlencode(params)
    link = f'vless://{uuid}@{host}:443?{query}#Argo_{net}_Node'
    print(link)
except Exception:
    pass
EOF
}

update_sub_content_file() {
    [[ ! -f "$SUB_CONF" ]] && return
    source "$SUB_CONF"
    local raw_link
    raw_link=$(generate_node_link)
    [[ -z "$raw_link" ]] && return

    mkdir -p "$SUB_DIR"
    echo -n "$raw_link" | base64 -w 0 > "$SUB_DIR/$SUB_PATH"
}

install_xray() {
    echo ""
    echo -e "${YELLOW}----------------------------------------------------------${PLAIN}"
    echo -e "【路径设置】"
    echo -e " • 直接按 [回车]：保持默认无路径模式"
    echo -e " • 输入自定义路径 (例如: tianxia 或 /tianxia)"
    echo -e "${YELLOW}----------------------------------------------------------${PLAIN}"
    read -r -p "请输入自定义 Path 路径: " raw_path

    local custom_path=""
    if [[ -n "$raw_path" ]]; then
        local clean_p
        clean_p=$(echo "$raw_path" | xargs)
        [[ "$clean_p" != /* ]] && clean_p="/$clean_p"
        custom_path="${clean_p%/}"
        echo -e ">>> 已设定路径: ${GREEN}${custom_path}${PLAIN}"
    else
        echo ">>> 未设置路径，将使用默认无路径模式。"
    fi

    # 下载并执行你仓库原版的基础安装流程
    local temp_installer="/tmp/xray_original_menu.sh"
    curl -fsSL https://raw.githubusercontent.com/huangxinyueus/zby/main/xray-go-menu.sh | tr -d '\r' > "$temp_installer"
    
    # 调起原版安装交互
    bash "$temp_installer"
    rm -f "$temp_installer"

    # 若输入了路径，后置写入配置
    if [[ -n "$custom_path" ]]; then
        apply_path_patch "$custom_path"
        echo ""
        echo -e "${GREEN}==========================================================${PLAIN}"
        echo -e "${GREEN}>>> 自定义路径已注入生效: $custom_path${PLAIN}"
        echo -e "${YELLOW}>>> 请同步确认：${PLAIN}"
        echo -e " 1. Cloudflare 控制台 Public Hostname 的 Path 为: ${GREEN}${custom_path#/}${PLAIN}"
        echo -e " 2. 客户端 (如 v2rayN) 节点设置中的 Path 为: ${GREEN}${custom_path}${PLAIN}"
        echo -e "${GREEN}==========================================================${PLAIN}"
    fi

    update_sub_content_file
    read -r -p "按回车键继续..."
}

modify_path_only() {
    local conf
    conf=$(get_config_path)
    if [[ -z "$conf" ]]; then
        echo -e "${RED}未找到 Xray 配置文件，请先执行选项 1 安装。${PLAIN}"
        read -r -p "按回车键继续..."
        return
    fi

    echo ""
    read -r -p "请输入新 Path (直接按 [回车] 则清除路径恢复为无路径): " raw_p
    local p=""
    if [[ -n "$raw_p" ]]; then
        local clean_p
        clean_p=$(echo "$raw_p" | xargs)
        [[ "$clean_p" != /* ]] && clean_p="/$clean_p"
        p="${clean_p%/}"
    fi

    apply_path_patch "$p"
    update_sub_content_file

    if [[ -n "$p" ]]; then
        echo -e "${GREEN}>>> 路径已修改为: $p 并已重启 Xray 服务！${PLAIN}"
    else
        echo -e "${GREEN}>>> 路径已清除，已恢复为默认无路径模式！${PLAIN}"
    fi
    read -r -p "按回车键继续..."
}

view_xray_config() {
    local conf
    conf=$(get_config_path)
    if [[ ! -f "$conf" ]]; then
        echo -e "${RED}未找到配置文件，请先执行选项 1 安装服务。${PLAIN}"
        read -r -p "按回车键继续..."
        return
    fi

    clear
    echo -e "${SKYBLUE}======================================================${PLAIN}"
    echo -e "               Xray-go 节点详细配置信息               "
    echo -e "${SKYBLUE}======================================================${PLAIN}"

    python3 - "$conf" << 'EOF'
import sys, json, urllib.parse, os

conf_path = sys.argv[1]
with open(conf_path, 'r', encoding='utf-8') as f:
    d = json.load(f)

ib = d.get('inbounds', [{}])[0]
port = ib.get('port', '未知')
clients = ib.get('settings', {}).get('clients', [{}])
uuid = clients[0].get('id', '未知')
ss = ib.get('streamSettings', {})
net = ss.get('network', 'xhttp')
sk = 'xhttpSettings' if net == 'xhttp' else 'wsSettings'
path = ss.get(sk, {}).get('path', '')

if path:
    path_display = f'[0;32m{path}[0m'
else:
    path_display = '[0;33m无 (根路径)[0m'

host = "node.example.com"
if os.path.exists("/etc/xray_tunnel_domain.txt"):
    with open("/etc/xray_tunnel_domain.txt", "r") as tf:
        val = tf.read().strip()
        if val: host = val

print(f'协议类型 (Protocol)   : VLESS')
print(f'传输协议 (Network)    : {net}')
print(f'用户 ID (UUID)        : {uuid}')
print(f'本地监听端口 (Port)   : {port}')
print(f'路径详情 (Path)       : {path_display}')
print('------------------------------------------------------')

params = {
    'encryption': 'none',
    'security': 'tls',
    'sni': host,
    'type': net
}
if path:
    params['path'] = path

q = urllib.parse.urlencode(params)
link = f'vless://{uuid}@{host}:443?{q}#Argo_{net}_Node'

print('节点链接 (VLESS 链接):')
print(f'[0;36m{link}[0m')
print('------------------------------------------------------')
print('• Cloudflare 后台 Public Hostname Path 请填: ' + (path.lstrip('/') if path else '留空不填'))
print('• 客户端 (如 v2rayN) 导入后 Path 对应为: ' + (path if path else '留空不填'))
EOF
    echo -e "${SKYBLUE}======================================================${PLAIN}"
    read -r -p "按回车键继续..."
}

sub_menu() {
    while true; do
        clear
        echo -e "${SKYBLUE}======================================================${PLAIN}"
        echo -e "              本地 IP 订阅分享链接管理                "
        echo -e "${SKYBLUE}======================================================${PLAIN}"
        echo -e " 1: 重置安装本地IP订阅链接"
        echo -e " 2: 更换订阅链接路径密码"
        echo -e " 3: 更换订阅链接端口"
        echo -e " 4: 卸载本地IP订阅链接"
        echo -e " 0: 返回上层"
        echo -e "${SKYBLUE}======================================================${PLAIN}"
        read -r -p "请选择【0-4】: " sub_opt

        case "$sub_opt" in
            1) reset_install_sub ;;
            2) change_sub_path ;;
            3) change_sub_port ;;
            4) uninstall_sub ;;
            0) break ;;
            *)
                echo -e "${RED}输入有误，请重新选择！${PLAIN}"
                sleep 1
                ;;
        esac
    done
}

reset_install_sub() {
    clear
    echo -e "${YELLOW}>>> 正在配置本地 IP 订阅共享服务...${PLAIN}"

    local public_ip
    public_ip=$(get_public_ip)
    if [[ -z "$public_ip" ]]; then
        read -r -p "无法自动获取公网 IP，请手动输入服务器公网 IP: " public_ip
    fi

    local default_pwd
    default_pwd=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    read -r -p "请输入订阅链接路径密码 (直接回车随机生成: $default_pwd): " in_pwd
    [[ -z "$in_pwd" ]] && in_pwd="$default_pwd"
    in_pwd=$(echo "$in_pwd" | tr -d '/')

    read -r -p "请输入本地订阅服务端口 (默认 2095): " in_port
    [[ -z "$in_port" ]] && in_port="2095"

    mkdir -p "$SUB_DIR"
    cat << EOF > "$SUB_CONF"
SUB_IP="$public_ip"
SUB_PORT="$in_port"
SUB_PATH="$in_pwd"
EOF

    update_sub_content_file

    cat << EOF > /usr/local/bin/xray_sub_server.py
import http.server
import socketserver
import os

conf_file = "/etc/xray_sub_service.conf"
port = $in_port
directory = "$SUB_DIR"

if os.path.exists(conf_file):
    with open(conf_file) as f:
        for line in f:
            if line.startswith("SUB_PORT="):
                try:
                    port = int(line.split("=")[1].strip().strip('"'))
                except Exception:
                    pass

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=directory, **kwargs)

with socketserver.TCPServer(("", port), Handler) as httpd:
    httpd.serve_forever()
EOF

    cat << EOF > "$SUB_SERVICE"
[Unit]
Description=Xray Local IP Subscription Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/xray_sub_server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xray-sub >/dev/null 2>&1
    systemctl restart xray-sub

    echo ""
    echo -e "${GREEN}======================================================${PLAIN}"
    echo -e "${GREEN}>>> 本地 IP 订阅链接重置安装成功！${PLAIN}"
    echo -e "订阅链接地址:"
    echo -e "${SKYBLUE}http://${public_ip}:${in_port}/${in_pwd}${PLAIN}"
    echo -e "说明: 复制该链接粘贴到客户端订阅管理中即可一键拉取节点更新。"
    echo -e "${GREEN}======================================================${PLAIN}"
    read -r -p "按回车键继续..."
}

change_sub_path() {
    if [[ ! -f "$SUB_CONF" ]]; then
        echo -e "${RED}尚未安装本地订阅服务，请先选择 1 进行安装！${PLAIN}"
        sleep 1.5
        return
    fi
    source "$SUB_CONF"

    echo ""
    echo -e "当前订阅路径密码: ${GREEN}${SUB_PATH}${PLAIN}"
    read -r -p "请输入新的路径密码: " new_pwd
    new_pwd=$(echo "$new_pwd" | tr -d '/')
    if [[ -z "$new_pwd" ]]; then
        echo -e "${RED}密码不能为空！${PLAIN}"
        sleep 1.5
        return
    fi

    rm -f "$SUB_DIR/$SUB_PATH"
    sed -i "s/SUB_PATH=.*/SUB_PATH="$new_pwd"/" "$SUB_CONF"
    update_sub_content_file

    echo -e "${GREEN}>>> 订阅路径已更新！新订阅链接为:${PLAIN}"
    echo -e "${SKYBLUE}http://${SUB_IP}:${SUB_PORT}/${new_pwd}${PLAIN}"
    read -r -p "按回车键继续..."
}

change_sub_port() {
    if [[ ! -f "$SUB_CONF" ]]; then
        echo -e "${RED}尚未安装本地订阅服务，请先选择 1 进行安装！${PLAIN}"
        sleep 1.5
        return
    fi
    source "$SUB_CONF"

    echo ""
    echo -e "当前订阅端口: ${GREEN}${SUB_PORT}${PLAIN}"
    read -r -p "请输入新的服务端口 (1-65535): " new_port
    if [[ -z "$new_port" ]]; then
        echo -e "${RED}端口不能为空！${PLAIN}"
        sleep 1.5
        return
    fi

    sed -i "s/SUB_PORT=.*/SUB_PORT="$new_port"/" "$SUB_CONF"

    systemctl restart xray-sub
    echo -e "${GREEN}>>> 订阅端口已更换！新订阅链接为:${PLAIN}"
    echo -e "${SKYBLUE}http://${SUB_IP}:${new_port}/${SUB_PATH}${PLAIN}"
    read -r -p "按回车键继续..."
}

uninstall_sub() {
    if [[ ! -f "$SUB_CONF" ]]; then
        echo -e "${RED}本地订阅服务未安装。${PLAIN}"
        sleep 1.5
        return
    fi

    read -r -p "确认彻底卸载本地 IP 订阅分享服务吗? [y/N]: " confirm_del
    if [[ "$confirm_del" == [yY] ]]; then
        systemctl stop xray-sub 2>/dev/null
        systemctl disable xray-sub 2>/dev/null
        rm -f "$SUB_SERVICE"
        rm -f /usr/local/bin/xray_sub_server.py
        rm -rf "$SUB_DIR"
        rm -f "$SUB_CONF"
        systemctl daemon-reload
        echo -e "${GREEN}>>> 本地 IP 订阅分享服务已彻底卸载清理！${PLAIN}"
    else
        echo "已取消卸载。"
    fi
    read -r -p "按回车键继续..."
}

show_menu() {
    while true; do
        clear
        echo "=================================================="
        echo "            Xray-go 管理菜单 (增强版)             "
        echo "=================================================="
        echo " 1. 一键安装 / 重新部署 (支持路径输入/回车无路径)"
        echo " 2. 单独修改/切换 Path 路径 (回车清除路径)"
        echo " 3. 重启 Xray 服务"
        echo " 4. 查看当前运行状态与监听端口"
        echo " 5. 查看运行日志"
        echo " 6. 卸载 Xray-go"
        echo " 7. 查看配置及节点链接 (含Path详情与自适应链接)"
        echo " 8. 设置本地IP订阅分享链接"
        echo " 0. 退出"
        echo "=================================================="
        read -r -p "请输入选项 [0-8]: " opt

        case "$opt" in
            1) install_xray ;;
            2) modify_path_only ;;
            3) 
                systemctl restart xray
                echo -e "${GREEN}Xray 服务已重启${PLAIN}"
                sleep 1
                ;;
            4)
                echo ""
                echo ">>> 端口监听情况:"
                sudo ss -tulpn | grep LISTEN
                echo ""
                echo ">>> Xray 服务状态:"
                systemctl status xray --no-pager
                read -r -p "按回车键继续..."
                ;;
            5) journalctl -u xray -e --no-pager -n 50 ;;
            6)
                read -r -p "确认卸载 Xray 吗? [y/N]: " confirm_del
                if [[ "$confirm_del" == [yY] ]]; then
                    systemctl stop xray 2>/dev/null
                    systemctl disable xray 2>/dev/null
                    rm -f /etc/systemd/system/xray.service
                    rm -rf /usr/local/etc/xray /etc/xray /usr/local/bin/xray
                    systemctl daemon-reload
                    echo -e "${GREEN}Xray 已彻底清理卸载完成。${PLAIN}"
                fi
                read -r -p "按回车键继续..."
                ;;
            7) view_xray_config ;;
            8) sub_menu ;;
            0) exit 0 ;;
            *) echo -e "${RED}输入有误，请重新输入${PLAIN}"; sleep 1 ;;
        esac
    done
}

show_menu
