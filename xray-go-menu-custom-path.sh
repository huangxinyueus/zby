#!/usr/bin/env bash

# ========================================================
# 脚本名称: xray-argo-path-installer.sh
# 仓库路径: huangxinyueus/zby
# 功能: 完整保留 Xray-go 原版功能，原生集成自定义 Path 交互与生效检测
# ========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

UPSTREAM_URL="https://raw.githubusercontent.com/eishare/Xray-go/main/Xray-go.sh"

get_config_path() {
    for conf in /usr/local/etc/xray/config.json /etc/xray/config.json; do
        if [[ -f "$conf" ]]; then
            echo "$conf"
            return
        fi
    done
    echo ""
}

# 核心注入函数：将路径精准写入配置文件，或留空时安全清除路径
apply_path_to_config() {
    local target_path="$1"
    local config_file
    config_file=$(get_config_path)

    if [[ -z "$config_file" ]]; then
        echo -e "${RED}错误：未找到 Xray 配置文件，无法注入路径。${PLAIN}"
        return 1
    fi

    python3 -c "
import json

path_val = '$target_path'
f_path = '$config_file'

try:
    with open(f_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    modified = False
    for ib in data.get('inbounds', []):
        ss = ib.get('streamSettings', {})
        net = ss.get('network')
        
        if net == 'xhttp':
            xs = ss.setdefault('xhttpSettings', {})
            if path_val:
                xs['path'] = path_val
            else:
                xs.pop('path', None)
            modified = True
            
        elif net == 'ws':
            ws = ss.setdefault('wsSettings', {})
            if path_val:
                ws['path'] = path_val
            else:
                ws.pop('path', None)
            modified = True

    if modified:
        with open(f_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print('SUCCESS')
    else:
        print('NO_STREAM_FOUND')
except Exception as e:
    print('ERROR:', e)
" > /tmp/xray_patch.log

    local res
    res=$(cat /tmp/xray_patch.log)
    rm -f /tmp/xray_patch.log

    if [[ "$res" == "SUCCESS" ]]; then
        systemctl restart xray
        return 0
    else
        return 1
    fi
}

# 自动化生效检测
verify_path_status() {
    local target_path="$1"
    local config_file
    config_file=$(get_config_path)

    echo ""
    echo -e "${YELLOW}=================== 路径生效检测报告 ===================${PLAIN}"
    
    # 1. 检查 Xray 进程
    if systemctl is-active --quiet xray; then
        echo -e "1. Xray 核心运行状态: ${GREEN}[运行中 (Active)]${PLAIN}"
    else
        echo -e "1. Xray 核心运行状态: ${RED}[未运行或崩溃]${PLAIN}"
        echo -e "${RED}日志查看: journalctl -u xray -e --no-pager${PLAIN}"
        return
    fi

    # 2. 检查配置中的 Path 字段
    local current_path
    current_path=$(python3 -c "
import json
with open('$config_file', 'r', encoding='utf-8') as f:
    d = json.load(f)
paths = []
for ib in d.get('inbounds', []):
    ss = ib.get('streamSettings', {})
    if 'xhttpSettings' in ss and 'path' in ss['xhttpSettings']:
        paths.append(ss['xhttpSettings']['path'])
    if 'wsSettings' in ss and 'path' in ss['wsSettings']:
        paths.append(ss['wsSettings']['path'])
print(','.join(paths) if paths else 'NONE')
")

    if [[ -z "$target_path" ]]; then
        if [[ "$current_path" == "NONE" ]]; then
            echo -e "2. 配置文件路径验证: ${GREEN}[已生效：当前为原生无路径模式]${PLAIN}"
        else
            echo -e "2. 配置文件路径验证: ${YELLOW}[存在旧路径: $current_path]${PLAIN}"
        fi
    else
        if [[ "$current_path" == "$target_path" ]]; then
            echo -e "2. 配置文件路径验证: ${GREEN}[已成功生效: $current_path]${PLAIN}"
        else
            echo -e "2. 配置文件路径验证: ${RED}[不匹配，当前为: $current_path]${PLAIN}"
        fi
    fi

    # 3. 检查端口与回环连通性
    local listen_port
    listen_port=$(python3 -c "
import json
with open('$config_file', 'r', encoding='utf-8') as f:
    d = json.load(f)
ports = [str(ib.get('port')) for ib in d.get('inbounds', []) if ib.get('port')]
print(ports[0] if ports else '')
")

    if [[ -n "$listen_port" ]]; then
        echo -e "3. 检查后端本地监听端口: ${GREEN}$listen_port${PLAIN}"
        if ss -tulpn | grep -q ":$listen_port "; then
            echo -e "   端口监听状态: ${GREEN}[正常 LISTEN]${PLAIN}"
        else
            echo -e "   端口监听状态: ${RED}[未检测到监听]${PLAIN}"
        fi

        local probe_url="http://127.0.0.1:${listen_port}${target_path}"
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 3 "$probe_url" 2>/dev/null)
        echo -e "4. 本地回环响应测试 ($probe_url):"
        if [[ "$http_code" == "000" ]]; then
            echo -e "   测试结果: ${RED}[连接被拒绝]${PLAIN}"
        else
            echo -e "   测试结果: ${GREEN}[握手成功 (HTTP 状态码: $http_code)]${PLAIN}"
        fi
    fi

    echo -e "${YELLOW}========================================================${PLAIN}"
    if [[ -n "$target_path" ]]; then
        echo -e "${GREEN}恭喜！自定义路径设置已就绪。${PLAIN}"
        echo -e "请务必保证三处一致："
        echo -e " 1. Cloudflare 隧道 Public Hostname 的 Path: ${GREEN}${target_path#/}${PLAIN}"
        echo -e " 2. 客户端 (v2rayN/Clash) 节点 Path: ${GREEN}${target_path}${PLAIN}"
    else
        echo -e "${GREEN}无路径模式设置成功！请确保 Cloudflare 与客户端均未填写 Path。${PLAIN}"
    fi
}

# 执行原生安装并在安装后挂接 Path 处理
run_upstream_install_with_path() {
    local temp_script="/tmp/upstream_xray_go.sh"
    echo -e ">>> 正在获取上游原生脚本..."
    if ! curl -fsSL "$UPSTREAM_URL" -o "$temp_script"; then
        echo -e "${RED}获取上游脚本失败，请检查网络。${PLAIN}"
        return
    fi
    chmod +x "$temp_script"

    echo ""
    echo -e "${YELLOW}----------------------------------------------------------${PLAIN}"
    echo -e "【路径预设】"
    echo -e " • 直接按 [回车]：保持大佬原版模式（无路径）"
    echo -e " • 输入路径（如 tianxia 或 /tianxia）：自动转为带路径节点"
    echo -e "${YELLOW}----------------------------------------------------------${PLAIN}"
    read -r -p "请输入自定义 XHTTP/Argo 路径: " raw_path

    local target_path=""
    if [[ -n "$raw_path" ]]; then
        local clean_path
        clean_path=$(echo "$raw_path" | xargs)
        [[ "$clean_path" != /* ]] && clean_path="/$clean_path"
        target_path="${clean_path%/}"
        echo -e ">>> 已预设路径: ${GREEN}${target_path}${PLAIN}"
    else
        echo -e ">>> 未输入路径，将全程走原版无路径流程。"
    fi

    # 执行原版安装（原汁原味调用选项 1 的逻辑）
    bash "$temp_script" 1
    rm -f "$temp_script"

    # 如果用户输入了自定义路径，打补丁并检测
    if [[ -n "$target_path" ]]; then
        echo -e ">>> 正在自动打入自定义路径补丁..."
        if apply_path_to_config "$target_path"; then
            verify_path_status "$target_path"
        else
            echo -e "${RED}路径补丁应用失败，请手动在菜单中使用选项 9 配置。${PLAIN}"
        fi
    fi
}

# 菜单中单独修改路径
menu_modify_path() {
    local config_file
    config_file=$(get_config_path)
    if [[ -z "$config_file" ]]; then
        echo -e "${RED}未检测到 Xray 配置文件，请先执行选项 1 安装。${PLAIN}"
        return
    fi

    echo ""
    echo -e "${YELLOW}请输入要切换的路径 (输入空直接回车则恢复为原生无路径模式):${PLAIN}"
    read -r -p "Path: " raw_path
    local target_path=""
    if [[ -n "$raw_path" ]]; then
        local clean_path
        clean_path=$(echo "$raw_path" | xargs)
        [[ "$clean_path" != /* ]] && clean_path="/$clean_path"
        target_path="${clean_path%/}"
    fi

    apply_path_to_config "$target_path"
    verify_path_status "$target_path"
}

# ================= 1:1 对齐的主管理菜单 =================
show_main_menu() {
    clear
    echo "=================================================="
    echo "               Xray-go 中文管理菜单               "
    echo "=================================================="
    echo " 1. 一键安装 / 重新部署 (支持回车无路径 / 自定义Path)"
    echo " 2. 启动 Xray 服务"
    echo " 3. 停止 Xray 服务"
    echo " 4. 重启 Xray 服务"
    echo " 5. 查看运行状态"
    echo " 6. 查看运行日志"
    echo " 7. 查看配置及节点链接"
    echo " 8. 卸载 Xray-go"
    echo " 9. 自定义/切换路径 (Path) 并检测生效"
    echo " 0. 退出"
    echo "=================================================="
    read -r -p "请输入选项 [0-9]: " choice

    case "$choice" in
        1)
            run_upstream_install_with_path
            ;;
        2)
            systemctl start xray
            echo -e "${GREEN}Xray 服务已启动${PLAIN}"
            ;;
        3)
            systemctl stop xray
            echo -e "${YELLOW}Xray 服务已停止${PLAIN}"
            ;;
        4)
            systemctl restart xray
            echo -e "${GREEN}Xray 服务已重启${PLAIN}"
            ;;
        5)
            systemctl status xray --no-pager
            ;;
        6)
            journalctl -u xray -e --no-pager -n 50
            ;;
        7)
            local config_file
            config_file=$(get_config_path)
            if [[ -f "$config_file" ]]; then
                echo -e "${GREEN}>>> 配置文件内容 ($config_file):${PLAIN}"
                cat "$config_file"
            else
                echo -e "${RED}未找到配置文件${PLAIN}"
            fi
            ;;
        8)
            read -r -p "确认卸载 Xray 吗? [y/N]: " confirm_del
            if [[ "$confirm_del" == [yY] ]]; then
                systemctl stop xray 2>/dev/null
                systemctl disable xray 2>/dev/null
                rm -f /etc/systemd/system/xray.service
                rm -rf /usr/local/etc/xray /etc/xray /usr/local/bin/xray
                systemctl daemon-reload
                echo -e "${GREEN}Xray 已彻底卸载完成。${PLAIN}"
            fi
            ;;
        9)
            menu_modify_path
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${RED}请输入正确的选项 [0-9]${PLAIN}"
            ;;
    esac
}

show_main_menu
