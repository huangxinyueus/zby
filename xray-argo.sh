#!/usr/bin/env bash

# ========================================================
# 脚本名称: xray-argo.sh
# 仓库路径: huangxinyueus/zby
# 功能: Xray-go 增强版 (原生支持自定义 Path 与回车默认无路径)
# ========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

get_config_path() {
    for conf in /usr/local/etc/xray/config.json /etc/xray/config.json; do
        if [[ -f "$conf" ]]; then
            echo "$conf"
            return
        fi
    done
    echo ""
}

apply_path_patch() {
    local p="$1"
    local conf
    conf=$(get_config_path)
    [[ -z "$conf" ]] && return

    python3 -c "
import json
path_val = '$p'
f_path = '$conf'
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
"
    systemctl restart xray
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
}

modify_path_only() {
    local conf
    conf=$(get_config_path)
    if [[ -z "$conf" ]]; then
        echo -e "${RED}未找到 Xray 配置文件，请先执行选项 1 安装。${PLAIN}"
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

    if [[ -n "$p" ]]; then
        echo -e "${GREEN}>>> 路径已修改为: $p 并已重启 Xray 服务！${PLAIN}"
    else
        echo -e "${GREEN}>>> 路径已清除，已恢复为默认无路径模式！${PLAIN}"
    fi
}

show_menu() {
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
    echo " 0. 退出"
    echo "=================================================="
    read -r -p "请输入选项 [0-6]: " opt

    case "$opt" in
        1) install_xray ;;
        2) modify_path_only ;;
        3) 
            systemctl restart xray
            echo -e "${GREEN}Xray 服务已重启${PLAIN}"
            ;;
        4)
            echo ""
            echo ">>> 端口监听情况:"
            sudo ss -tulpn | grep LISTEN
            echo ""
            echo ">>> Xray 服务状态:"
            systemctl status xray --no-pager
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
            ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入有误，请重新输入${PLAIN}" ;;
    esac
}

show_menu