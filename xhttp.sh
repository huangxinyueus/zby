#!/usr/bin/env bash

# ========================================================
# 脚本名称: xhttp.sh
# 仓库路径: huangxinyueus/zby
# 功能: Xray-go XHTTP 完整管理菜单 (包含 Argo Token/协议选择/Path注入/本地订阅)
# ========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

SUB_CONF="/etc/xray_sub_service.conf"
SUB_SERVICE="/etc/systemd/system/xray-sub.service"
SUB_DIR="/var/www/xray_sub"

# 获取 Xray 配置文件路径
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
        if net == 'xhttp':
            xs = ss.setdefault('xhttpSettings', {})
            if path_val:
                xs['path'] = path_val
            else:
                xs.pop('path', None)
        elif net == 'ws':
            ws = ss.setdefault('wsSettings', {})
            if path_val:
                ws['path'] = path_val
            else:
                ws.pop('path', None)
    with open(f_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
except Exception:
    sys.exit(1)
EOF
    systemctl restart xray
}

# 生成单节点链接
generate_node_link() {
    local conf
    conf=$(get_config_path)
    [[ -z "$conf" ]] && return

    python3 - "$conf" << 'EOF'
import sys, json, urllib.parse

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
    
    # 优先从本地记录中获取保存的隧道域名
    host = "node.example.com"
    try:
        with open("/etc/xray_tunnel_domain.txt", "r") as tf:
            saved_h = tf.read().strip()
            if saved_h: host = saved_h
    except Exception:
        pass
    
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

# 更新订阅文本内容（Base64 编码）
update_sub_content_file() {
    [[ ! -f "$SUB_CONF" ]] && return
    source "$SUB_CONF"
    local raw_link
    raw_link=$(generate_node_link)
    [[ -z "$raw_link" ]] && return

    mkdir -p "$SUB_DIR"
    echo -n "$raw_link" | base64 -w 0 > "$SUB_DIR/$SUB_PATH"
}

# 1. 一键安装 / 重新部署
install_xray() {
    clear
    echo -e "${SKYBLUE}======================================================${PLAIN}"
    echo -e "               开始部署 Xray-go 节点                  "
    echo -e "${SKYBLUE}======================================================${PLAIN}"
    
    # 1. 协议选择
    read -r -p "请输入 Argo 协议 (quic/http2, 默认 quic): " argo_protocol
    [[ -z "$argo_protocol" ]] && argo_protocol="quic"

    # 2. 本地回源端口
    read -r -p "请输入本地回源端口 (默认 8001): " local_port
    local_port=$(echo "$local_port" | xargs)
    [[ -z "$local_port" ]] && local_port="8001"

    # 3. 隧道域名
    read -r -p "请输入 Cloudflare Tunnel 域名 (完整主机名，示例 node.example.com): " tunnel_domain
    tunnel_domain=$(echo "$tunnel_domain" | xargs)
    [[ -z "$tunnel_domain" ]] && tunnel_domain="node.example.com"
    echo "$tunnel_domain" > /etc/xray_tunnel_domain.txt

    # 4. Token 交互
    echo ""
    echo -e "${YELLOW}【Cloudflare Tunnel Token 设置】${PLAIN}"
    echo -e " • 输入 Cloudflare 后台生成的 Tunnel Token 可实现自动启动穿透隧道"
    echo -e " • 直接按 [回车] 则跳过本地 cloudflared 自动托管 (手动运行或已存在隧道)"
    echo -e "${YELLOW}------------------------------------------------------${PLAIN}"
    read -r -p "请输入 Cloudflare Tunnel Token: " argo_token
    argo_token=$(echo "$argo_token" | xargs)

    # 5. Path 自定义
    echo ""
    echo -e "${YELLOW}【Path 路径设置】${PLAIN}"
    echo -e " • 直接按 [回车]：保持默认无路径模式"
    echo -e " • 输入自定义路径 (示例: my-path 或 /my-path)"
    echo -e "${YELLOW}------------------------------------------------------${PLAIN}"
    read -r -p "请输入自定义 Path: " raw_path

    local custom_path=""
    if [[ -n "$raw_path" ]]; then
        local clean_p
        clean_p=$(echo "$raw_path" | xargs)
        [[ "$clean_p" != /* ]] && clean_p="/$clean_p"
        custom_path="${clean_p%/}"
        echo -e ">>> 已记录自定义 Path: ${GREEN}${custom_path}${PLAIN}"
    else
        echo -e ">>> 未输入 Path，默认使用无路径模式。"
    fi

    echo -e ">>> 正在生成配置并部署服务..."
    
    apt-get update -y >/dev/null 2>&1 || yum update -y >/dev/null 2>&1
    apt-get install -y curl jq python3 openssl qrencode >/dev/null 2>&1 || yum install -y curl jq python3 openssl qrencode >/dev/null 2>&1

    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1

    local conf_dir="/usr/local/etc/xray"
    mkdir -p "$conf_dir"
    local uuid
    uuid=$(xray uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)

    cat << EOF > "$conf_dir/config.json"
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $local_port,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "mode": "auto"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

    if [[ -n "$custom_path" ]]; then
        apply_path_patch "$custom_path"
    fi

    systemctl daemon-reload
    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray

    # 如果输入了 Token，则配置运行 cloudflared
    if [[ -n "$argo_token" ]]; then
        echo -e ">>> 检测到已输入 Token，正在配置并启动 cloudflared..."
        if ! command -v cloudflared &> /dev/null; then
            curl -L --output /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 >/dev/null 2>&1
            chmod +x /usr/local/bin/cloudflared
        fi
        cloudflared service install "$argo_token" >/dev/null 2>&1
        systemctl restart cloudflared 2>/dev/null
    fi

    update_sub_content_file

    echo -e "${GREEN}>>> Xray-go 部署完成！${PLAIN}"
    view_xray_config
}

# 2. 启动 Xray
start_xray() {
    systemctl start xray
    echo -e "${GREEN}Xray 服务已启动${PLAIN}"
}

# 3. 停止 Xray
stop_xray() {
    systemctl stop xray
    echo -e "${YELLOW}Xray 服务已停止${PLAIN}"
}

# 4. 重启 Xray
restart_xray() {
    systemctl restart xray
    echo -e "${GREEN}Xray 服务已重启${PLAIN}"
}

# 5. 查看运行状态
status_xray() {
    echo ""
    echo -e "${SKYBLUE}>>> Xray 服务运行状态:${PLAIN}"
    systemctl status xray --no-pager
    echo ""
    echo -e "${SKYBLUE}>>> 本地端口监听情况:${PLAIN}"
    ss -tulpn | grep -E "xray|8001"
}

# 6. 查看运行日志
logs_xray() {
    echo -e "${SKYBLUE}>>> 正在获取最近 50 行运行日志 (按 Ctrl+C 退出):${PLAIN}"
    journalctl -u xray -e --no-pager -n 50
}

# 7. 查看配置及节点链接 (含 Path 详情展示)
view_xray_config() {
    local conf
    conf=$(get_config_path)
    if [[ ! -f "$conf" ]]; then
        echo -e "${RED}未找到配置文件，请先执行选项 1 安装服务。${PLAIN}"
        return
    fi

    clear
    echo -e "${SKYBLUE}======================================================${PLAIN}"
    echo -e "               Xray-go 节点详细配置信息               "
    echo -e "${SKYBLUE}======================================================${PLAIN}"

    python3 - "$conf" << 'EOF'
import sys, json, urllib.parse

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
    path_display = f'\033[0;32m{path}\033[0m'
else:
    path_display = '\033[0;33m无 (根路径)\033[0m'

host = "node.example.com"
try:
    with open("/etc/xray_tunnel_domain.txt", "r") as tf:
        saved_h = tf.read().strip()
        if saved_h: host = saved_h
except Exception:
    pass

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
}

# 8. 本地 IP 订阅分享链接子菜单
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

# 8-1: 重置安装本地IP订阅链接
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
    echo -e "说明: 复制该链接粘贴到客户端订阅管理中即可一键拉取节点更新。"
    echo -e "${GREEN}======================================================${PLAIN}"
    read -r -p "按回车键继续..."
}

# 8-2: 更换订阅链接路径密码
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

# 8-3: 更换订阅链接端口
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

# 8-4: 卸载本地 IP 订阅链接
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

# 9. 自定义 / 切换路径
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

# 10. 卸载 Xray-go
uninstall_xray() {
    read -r -p "确认卸载 Xray-go 及其核心服务吗? [y/N]: " confirm_del
    if [[ "$confirm_del" == [yY] ]]; then
        systemctl stop xray 2>/dev/null
        systemctl disable xray 2>/dev/null
        rm -f /etc/systemd/system/xray.service
        rm -rf /usr/local/etc/xray /etc/xray /usr/local/bin/xray
        systemctl daemon-reload
        echo -e "${GREEN}Xray-go 服务已彻底卸载。${PLAIN}"
    else
        echo "已取消卸载。"
    fi
    read -r -p "按回车键继续..."
}

# 主菜单交互
show_main_menu() {
    while true; do
        clear
        echo "=================================================="
        echo "              Xray-go 中文管理菜单                "
        echo "=================================================="
        echo " 1. 一键安装 / 重新部署 (含Token/协议/自定义Path)"
        echo " 2. 启动 Xray 服务"
        echo " 3. 停止 Xray 服务"
        echo " 4. 重启 Xray 服务"
        echo " 5. 查看运行状态"
        echo " 6. 查看运行日志"
        echo " 7. 查看配置及节点链接 (含Path详情与自适应链接)"
        echo " 8. 设置本地IP订阅分享链接"
        echo " 9. 自定义/切换路径 (Path) 并检测生效"
        echo " 10. 卸载 Xray-go"
        echo " 0. 退出"
        echo "=================================================="
        read -r -p "请输入选项 [0-10]: " main_opt

        case "$main_opt" in
            1) install_xray ;;
            2) start_xray; read -r -p "按回车键继续..." ;;
            3) stop_xray; read -r -p "按回车键继续..." ;;
            4) restart_xray; read -r -p "按回车键继续..." ;;
            5) status_xray; read -r -p "按回车键继续..." ;;
            6) logs_xray ;;
            7) view_xray_config; read -r -p "按回车键继续..." ;;
            8) sub_menu ;;
            9) switch_path_menu ;;
            10) uninstall_xray ;;
            0) exit 0 ;;
            *)
                echo -e "${RED}输入有误，请重新选择！${PLAIN}"
                sleep 1
                ;;
        esac
    done
}

show_main_menu