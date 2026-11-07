#!/usr/bin/env bash

# ========================================================
# 脚本名称: xray-argo-path-installer.sh
# 仓库路径: huangxinyueus/zby
# 功能: 1:1 对齐 Xray-go 中文管理菜单 + 独立路径设置与生效检测
# ========================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 定位 Xray 配置文件
get_config_path() {
    for conf in /usr/local/etc/xray/config.json /etc/xray/config.json; do
        if [[ -f "$conf" ]]; then
            echo "$conf"
            return
        fi
    done
    echo ""
}

# 独立功能：设置/修改自定义路径并检测生效
set_and_verify_path() {
    local config_file
    config_file=$(get_config_path)

    if [[ -z "$config_file" ]]; then
        echo -e "${RED}错误：未找到 Xray 配置文件，请先执行选项 1 安装 Xray-go。${PLAIN}"
        return
    fi

    echo ""
    echo -e "${YELLOW}=================== 自定义路径设置 ===================${PLAIN}"
    echo -e "说明："
    echo -e " 1. 若要添加/修改路径，请输入路径名（例如: ${GREEN}tianxia${PLAIN} 或 ${GREEN}/tianxia${PLAIN}）。"
    echo -e " 2. 若要恢复为默认的【无路径模式】，请${YELLOW}直接按 [回车] 留空${PLAIN}。"
    echo -e "${YELLOW}======================================================${PLAIN}"
    read -r -p "请输入路径: " raw_path

    local target_path=""
    if [[ -n "$raw_path" ]]; then
        local clean_path
        clean_path=$(echo "$raw_path" | xargs)
        [[ "$clean_path" != /* ]] && clean_path="/$clean_path"
        target_path="${clean_path%/}"
        echo -e ">>> 准备写入路径: ${GREEN}${target_path}${PLAIN}"
    else
        echo -e ">>> 检测到输入为空，准备恢复为【无路径模式】..."
    fi

    # 使用 Python 安全操作 JSON
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
        
        # 处理 xhttp
        if net == 'xhttp':
            xs = ss.setdefault('xhttpSettings', {})
            if path_val:
                xs['path'] = path_val
            else:
                xs.pop('path', None)
            modified = True
            
        # 处理 ws
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

    if [[ "$res" != "SUCCESS" ]]; then
        echo -e "${RED}配置注入失败: $res${PLAIN}"
        return
    fi

    # 重启服务使配置生效
    echo -e ">>> 正在重启 Xray 服务..."
    systemctl restart xray
    sleep 2

    # ---------------- 自动化生效检测 ----------------
    echo ""
    echo -e "${YELLOW}=================== 路径生效检测报告 ===================${PLAIN}"
    
    # 1. 检查进程状态
    if systemctl is-active --quiet xray; then
        echo -e "1. Xray 核心运行状态: ${GREEN}[运行中 (Active)]${PLAIN}"
    else
        echo -e "1. Xray 核心运行状态: ${RED}[未运行或启动崩溃]${PLAIN}"
        echo -e "${RED}请检查日志: journalctl -u xray -e --no-pager${PLAIN}"
        return
    fi

    # 2. 检查配置文件中的实际 Path 字段
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

    if [[ "$target_path" == "" ]]; then
        if [[ "$current_path" == "NONE" ]]; then
            echo -e "2. 配置文件路径验证: ${GREEN}[已清除，当前为无路径模式]${PLAIN}"
        else
            echo -e "2. 配置文件路径验证: ${YELLOW}[存在残留路径: $current_path]${PLAIN}"
        fi
    else
        if [[ "$current_path" == "$target_path" ]]; then
            echo -e "2. 配置文件路径验证: ${GREEN}[已生效: $current_path]${PLAIN}"
        else
            echo -e "2. 配置文件路径验证: ${RED}[不匹配，当前读取到: $current_path]${PLAIN}"
        fi
    fi

    # 3. 获取监听端口并探测本地响应
    local listen_port
    listen_port=$(python3 -c "
import json
with open('$config_file', 'r', encoding='utf-8') as f:
    d = json.load(f)
ports = [str(ib.get('port')) for ib in d.get('inbounds', []) if ib.get('port')]
print(ports[0] if ports else '')
")

    if [[ -n "$listen_port" ]]; then
        echo -e "3. 检测到后端本地监听端口: ${GREEN}$listen_port${PLAIN}"
        
        # 探测端口监听
        if ss -tulpn | grep -q ":$listen_port "; then
            echo -e "   端口监听状态: ${GREEN}[正常 LISTEN]${PLAIN}"
        else
            echo -e "   端口监听状态: ${RED}[未检测到监听]${PLAIN}"
        fi

        # 发送本地 HTTP/XHTTP 探测
        local probe_url="http://127.0.0.1:${listen_port}${target_path}"
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 3 "$probe_url" 2>/dev/null)

        echo -e "4. 本地回环连通测试 ($probe_url):"
        if [[ "$http_code" == "000" ]]; then
            echo -e "   测试结果: ${RED}[连接被拒绝 (Connection Refused)]${PLAIN}"
        else
            echo -e "   测试结果: ${GREEN}[响应正常 (HTTP 状态码: $http_code)]${PLAIN}"
        fi
    fi

    echo -e "${YELLOW}========================================================${PLAIN}"
    if [[ -n "$target_path" ]]; then
        echo -e "${GREEN}设置完成！请同步确认：${PLAIN}"
        echo -e " 1. Cloudflare 控制台 Public Hostname 的 Path 是否为: ${GREEN}${target_path#/}${PLAIN}"
        echo -e " 2. 客户端 (如 v2rayN) 节点设置中的 Path 是否为: ${GREEN}${target_path}${PLAIN}"
    else
        echo -e "${GREEN}无路径模式切换完成！请确认 Cloudflare 与客户端均不要填写 Path。${PLAIN}"
    fi
    echo ""
}

# ================= 主菜单界面 =================
show_menu() {
    clear
    echo "=================================================="
    echo "               Xray-go 中文管理菜单               "
    echo "=================================================="
    echo " 1. 一键安装 / 重新部署"
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
            # 原汁原味调用上游安装程序，不破坏上游脚本结构
            bash <(curl -fsSL https://raw.githubusercontent.com/eishare/Xray-go/main/install.sh)
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
            set_and_verify_path
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${RED}请输入正确的选项 [0-9]${PLAIN}"
            ;;
    esac
}

show_menu