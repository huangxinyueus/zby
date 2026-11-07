#!/usr/bin/env bash

# ========================================================
# 脚本名称: xhttp.sh
# 仓库路径: huangxinyueus/zby
# 功能: eishare/Xray-go 原版无损增强版 (支持 Path 注入与本地 IP 订阅)
# ========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

SUB_CONF="/etc/xray_sub_service.conf"
SUB_SERVICE="/etc/systemd/system/xray-sub.service"
SUB_DIR="/var/www/xray_sub"
DOMAIN_RECORD="/etc/xray_tunnel_domain.txt"

# 自动寻找配置文件
get_config_path() {
    for c in /usr/local/etc/xray/config.json /etc/xray/config.json; do
        if [[ -f "$c" ]]; then
            echo "$c"
            return
        fi
    done
    echo ""
}

# 获取公网 IP
get_public_ip() {
    local ip
    ip=$(curl -s4m 5 https://api.ipify.org || curl -s4m 5 https://ipv4.icanhazip.com || curl -s4m 5 https://ifconfig.me)
    echo "$ip"
}

# 注入或删除 Path 到 config.json
apply_path_patch() {
    local p="$1"
    local conf
    conf=$(get_config_path)
    [[ -z "$conf" ]] && return 1

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
        if net in ['xhttp', 'ws']:
            k = 'xhttpSettings' if net == 'xhttp' else 'wsSettings'
            xs = ss.setdefault(k, {})
            if path_val:
                xs['path'] = path_val
            else:
                xs.pop('path', None)
    with open(f_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
except Exception:
    sys.exit(1)
EOF
    systemctl restart xray 2>/dev/null
}

# 提取当前生成的节点 VLESS 链接
generate_node_link() {
    local conf
    conf=$(get_config_path)
    [[ -z "$conf" ]] && return

    python3 - "$conf" "$DOMAIN_RECORD" << 'EOF'
import sys, json, urllib.parse, os

conf = sys.argv[1]
dom_file = sys.argv[2]

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
    if os.path.exists(dom_file):
        with open(dom_file, "r") as tf:
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

# 更新订阅文本
update_sub_content_file() {
    [[ ! -f "$SUB_CONF" ]] && return
    source "$SUB_CONF"
    local raw_link
    raw_link=$(generate_node_link)
    [[ -z "$raw_link" ]] && return

    mkdir -p "$SUB_DIR"
    echo -n "$raw_link" | base64 -w 0 > "$SUB_DIR/$SUB_PATH"
}

# 1. 调用原作者完整一键部署 (带前置交互与后置注入)
install_full_flow() {
    clear
    echo -e "${SKYBLUE}======================================================${PLAIN}"
    echo -e "         Xray-go 完整安装部署 (原版集成无损版)        "
    echo -e "${SKYBLUE}======================================================${PLAIN}"
    
    echo -e "${YELLOW}【Path 路径设置】${PLAIN}"
    echo -e " • 直接按 [回车]：保持原版默认无路径模式"
    echo -e " • 输入自定义路径 (示例: my-path 或 /my-path)"
    echo -e "${YELLOW}------------------------------------------------------${PLAIN}"
    read -r -p "请输入自定义 Path: " raw_path

    local custom_path=""
    if [[ -n "$raw_path" ]]; then
        local clean_p
        clean_p=$(echo "$raw_path" | xargs)
        [[ "$clean_p" != /* ]] && clean_p="/$clean_p"
        custom_path="${clean_p%/}"
        echo -e ">>> 已设定自定义 Path: ${GREEN}${custom_path}${PLAIN}"
    else
        echo -e ">>> 未输入 Path，使用默认无路径模式。"
    fi

    echo ""
    read -r -p "请输入你的 Cloudflare Tunnel 域名 (完整主机名，示例 node.example.com): " user_domain
    user_domain=$(echo "$user_domain" | xargs)
    [[ -n "$user_domain" ]] && echo "$user_domain" > "$DOMAIN_RECORD"

    echo ""
    echo -e "${SKYBLUE}>>> 正在拉取并执行 eishare/Xray-go 官方原版部署流程...${PLAIN}"
    echo ""

    # 下载并直接执行原作者完整的官方部署脚本，不作任何删减
    local orig_script="/tmp/xray_go_official.sh"
    curl -fsSL https://raw.githubusercontent.com/eishare/Xray-go/main/xray-go.sh | tr -d '\r' > "$orig_script"
    
    if [[ ! -s "$orig_script" ]]; then
        # 备选拉取你仓库的备份
        curl -fsSL https://raw.githubusercontent.com/huangxinyueus/zby/main/xray-go-menu.sh | tr -d '\r' > "$orig_script"
    fi

    chmod +x "$orig_script"
    bash "$orig_script"
    rm -f "$orig_script"

    # 安装完成后，无损注入自定义 Path（如果有输入）
    if [[ -n "$custom_path" ]]; then
        apply_path_patch "$custom_path"
    fi

    update_sub_content_file
    echo ""
    read -r -p "部署完毕，按回车键查看配置与链接..."
    view_xray_config
}

# 7. 查看配置及节点链接 (含 Path 详情与自动附带 Path)
view_xray_config() {
    local conf
    conf=$(get_config_path)
    if [[ ! -f "$conf" ]]; then
        echo -e "${RED}未找到配置文件，请先执行选项 1 安装。${PLAIN}"
        read -r -p "按回车键继续..."
        return
    fi

    clear
    echo -e "${SKYBLUE}======================================================${PLAIN}"
    echo -e "               Xray-go 节点详细配置信息               "
    echo -e "${SKYBLUE}======================================================${PLAIN}"

    python3 - "$conf" "$DOMAIN_RECORD" << 'EOF'
import sys, json, urllib.parse, os

conf_path = sys.argv[1]
dom_file = sys.argv[2]

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
    path_display = f'\033[0;32m{path}\033[0m'
else:
    path_display = '\033[0;33m无 (根路径)\033[0m'

host = "node.example.com"
if os.path.exists(dom_file):
    with open(dom_file, "r") as tf:
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
print(f'\033[0;36m{link}\033[0m')
print('------------------------------------------------------')
print('• Cloudflare 后台 Public Hostname Path 请填: ' + (path.lstrip('/') if path else '留空不填'))
print('• 客户端 (如 v2rayN) 导入后 Path 对应为: ' + (path if path else '留空不填'))
EOF
    echo -e "${SKYBLUE}======================================================${PLAIN}"
    read -r -p "按回车键继续..."
}

# 8. 设置本地 IP 订阅分享链接 (多交互子菜单)
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

PORT = $in_port
DIRECTORY = "$SUB_DIR"

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

with socketserver.TCPServer(("", PORT), Handler) as httpd:
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
    echo -e "说明: 复制该链接粘贴到客户端订阅管理中即可拉取节点。"
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
    sed -i "s/SUB_PATH=.*/SUB_PATH=\"$new_pwd\"/" "$SUB_CONF"
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

    sed -i "s/SUB_PORT=.*/SUB_PORT=\"$new_port\"/" "$SUB_CONF"
    sed -i "s/PORT = .*/PORT = $new_port/" /usr/local/bin/xray_sub_server.py

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

# 9. 单独修改 / 切换路径
switch_path_menu() {
    local conf
    conf=$(get_config_path)
    if [[ ! -f "$conf" ]]; then
        echo -e "${RED}未找到 Xray 配置文件，请先执行选项 1 安装。${PLAIN}"
        read -r -p "按回车键继续..."
        return
    fi

    echo ""
    read -r -p "请输入新 Path 路径 (直接按 [回车] 则清除路径，恢复无路径模式): " input_p
    local p=""
    if [[ -n "$input_p" ]]; then
        local clean_p
        clean_p=$(echo "$input_p" | xargs)
        [[ "$clean_p" != /* ]] && clean_p="/$clean_p"
        p="${clean_p%/}"
    fi

    apply_path_patch "$p"
    update_sub_content_file

    if [[ -n "$p" ]]; then
        echo -e "${GREEN}>>> 路径已修改为: $p 并已重启 Xray 服务！${PLAIN}"
        echo -e "${YELLOW}>>> 请同步在 Cloudflare 规则与客户端中将 Path 更新为: $p${PLAIN}"
    else
        echo -e "${GREEN}>>> 已清除路径，已恢复为默认无路径模式！${PLAIN}"
    fi
    read -r -p "按回车键继续..."
}

# 10. 官方卸载逻辑
uninstall_all() {
    echo -e "${YELLOW}>>> 正在调用官方卸载逻辑彻底清理...${PLAIN}"
    bash <(curl -Ls https://raw.githubusercontent.com/eishare/Xray-go/main/uninstall.sh)
    systemctl stop xray-sub 2>/dev/null
    systemctl disable xray-sub 2>/dev/null
    rm -f "$SUB_SERVICE"
    rm -rf "$SUB_DIR" "$SUB_CONF" "$DOMAIN_RECORD"
    systemctl daemon-reload
    echo -e "${GREEN}Xray 及所有关联服务已彻底卸载！${PLAIN}"
    read -r -p "按回车键继续..."
}

# 主控制台
show_main_menu() {
    while true; do
        clear
        echo "=================================================="
        echo "          Xray-go 完整管理菜单 (XHTTP 增强版)     "
        echo "=================================================="
        echo " 1. 一键安装 / 重新部署 (原版全部参数 + Path 注入)"
        echo " 2. 启动 Xray 服务"
        echo " 3. 停止 Xray 服务"
        echo " 4. 重启 Xray 服务"
        echo " 5. 查看运行状态"
        echo " 6. 查看运行日志"
        echo " 7. 查看配置及节点链接 (含Path详情与自适应链接)"
        echo " 8. 设置本地IP订阅分享链接"
        echo " 9. 自定义/切换路径 (Path) 并检测生效"
        echo " 10. 彻底卸载 Xray-go"
        echo " 0. 退出"
        echo "=================================================="
        read -r -p "请输入选项 [0-10]: " main_opt

        case "$main_opt" in
            1) install_full_flow ;;
            2) systemctl start xray; echo -e "${GREEN}服务已启动${PLAIN}"; sleep 1 ;;
            3) systemctl stop xray; echo -e "${YELLOW}服务已停止${PLAIN}"; sleep 1 ;;
            4) systemctl restart xray; echo -e "${GREEN}服务已重启${PLAIN}"; sleep 1 ;;
            5) systemctl status xray --no-pager; read -r -p "按回车键继续..." ;;
            6) journalctl -u xray -e --no-pager -n 50 ;;
            7) view_xray_config ;;
            8) sub_menu ;;
            9) switch_path_menu ;;
            10) uninstall_all ;;
            0) exit 0 ;;
            *)
                echo -e "${RED}输入有误，请重新选择！${PLAIN}"
                sleep 1
                ;;
        esac
    done
}

show_main_menu