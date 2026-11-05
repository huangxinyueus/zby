#!/bin/bash

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本！(sudo -i)"
  exit 1
fi

# 快捷命令安装路径
BIN_PATH="/usr/local/bin/ip-qh"

# 获取当前默认出网 IPv4 和来源 IP
get_current_ipv4() {
    local route_info=$(ip route show default 2>/dev/null)
    local dev=$(echo "$route_info" | awk '/default/ {print $5}')
    local src=$(echo "$route_info" | grep -oP 'src \K\S+')
    if [ -z "$src" ] && [ -n "$dev" ]; then
        src=$(ip -4 addr show dev "$dev" | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n1)
    fi
    echo "${src:-未明确指定} (网卡: ${dev:-未知})"
}

# 获取当前默认出网 IPv6 和来源 IP
get_current_ipv6() {
    local route_info=$(ip -6 route show default 2>/dev/null)
    local dev=$(echo "$route_info" | awk '/default/ {print $5}')
    local src=$(echo "$route_info" | grep -oP 'src \K\S+')
    if [ -z "$src" ] && [ -n "$dev" ]; then
        src=$(ip -6 addr show dev "$dev" | grep inet6 | grep -v 'fe80' | awk '{print $2}' | cut -d/ -f1 | head -n1)
    fi
    echo "${src:-未明确指定} (网卡: ${dev:-未知})"
}

# 显示主菜单
show_menu() {
    clear
    echo "=========================================="
    echo "       VPS 多 IP 可视化管理与出口切换工具       "
    echo "=========================================="
    echo -e " 当前默认 IPv4 出口: \033[32m$(get_current_ipv4)\033[0m"
    echo -e " 当前默认 IPv6 出口: \033[32m$(get_current_ipv6)\033[0m"
    echo "------------------------------------------"
    echo " 1. 查看当前所有 IP 地址及网络状态"
    echo " 2. 切换系统默认 IPv4 出口"
    echo " 3. 切换系统默认 IPv6 出口"
    echo " 4. 测试指定 IP 的出网连通性"
    echo " 5. 卸载本工具及快捷命令"
    echo " 0. 退出脚本"
    echo "=========================================="
    read -p "请输入数字选项 [0-5]: " choice
}

# 获取并展示所有 IP
list_ips() {
    echo -e "\n--- 当前网卡及所有 IP 地址 ---"
    ip -o addr show | awk '{print "网卡: " $2 " | IP: " $4}'
    echo "--------------------------------"
    read -p "按回车键返回主菜单..."
}

# 切换 IPv4 出口
change_ipv4() {
    while true; do
        echo -e "\n--- 可用的 IPv4 地址列表 ---"
        local_ipv4s=($(ip -4 addr show | grep inet | awk '{print $2}' | cut -d/ -f1))
        
        for i in "${!local_ipv4s[@]}"; do
            echo " [$i] ${local_ipv4s[$i]}"
        end
        echo " [b] 返回上一级菜单"
        
        read -p "请选择要作为默认出口的 IPv4 编号: " ip_idx
        if [ "$ip_idx" = "b" ] || [ "$ip_idx" = "B" ]; then
            return
        fi
        
        if [[ "${local_ipv4s[$ip_idx]}" ]]; then
            chosen_ip="${local_ipv4s[$ip_idx]}"
            default_dev=$(ip route show default | awk '/default/ {print $5}' | head -n1)
            if [ -z "$default_dev" ]; then
                default_dev=$(ip route show | awk '/^default/ {print $5}' | head -n1)
            fi
            
            if [ -n "$default_dev" ]; then
                ip route replace default dev "$default_dev" src "$chosen_ip"
                echo -e "\n[成功] 已将默认 IPv4 出口切换为: $chosen_ip (网卡: $default_dev)"
            else
                echo -e "\n[错误] 未能自动识别默认网卡设备！"
            fi
            read -p "按回车键继续..."
            return
        else
            echo "输入错误，请重新选择！"
            sleep 1
        fi
    done
}

# 切换 IPv6 出口
change_ipv6() {
    while true; do
        echo -e "\n--- 可用的 IPv6 地址列表 ---"
        local_ipv6s=($(ip -6 addr show | grep inet6 | grep -v 'fe80' | awk '{print $2}' | cut -d/ -f1))
        
        if [ ${#local_ipv6s[@]} -eq 0 ]; then
            echo "当前系统没有检测到可用的公网 IPv6 地址！"
            read -p "按回车键返回主菜单..."
            return
        fi
        
        for i in "${!local_ipv6s[@]}"; do
            echo " [$i] ${local_ipv6s[$i]}"
        end
        echo " [b] 返回上一级菜单"
        
        read -p "请选择要作为默认出口的 IPv6 编号: " ip_idx
        if [ "$ip_idx" = "b" ] || [ "$ip_idx" = "B" ]; then
            return
        fi
        
        if [[ "${local_ipv6s[$ip_idx]}" ]]; then
            chosen_ip="${local_ipv6s[$ip_idx]}"
            default_dev=$(ip -6 route show default | awk '/default/ {print $5}' | head -n1)
            if [ -z "$default_dev" ]; then
                default_dev=$(ip -6 route show | awk '/^default/ {print $5}' | head -n1)
            fi
            
            if [ -n "$default_dev" ]; then
                ip -6 route replace default dev "$default_dev" src "$chosen_ip"
                echo -e "\n[成功] 已将默认 IPv6 出口切换为: $chosen_ip (网卡: $default_dev)"
            else
                echo -e "\n[错误] 未能自动识别 IPv6 默认网卡设备！"
            fi
            read -p "按回车键继续..."
            return
        else
            echo "输入错误，请重新选择！"
            sleep 1
        fi
    done
}

# 测试指定 IP 连通性
test_ip() {
    echo -e "\n--- 测试 IP 出口 ---"
    read -p "请输入你要测试的本地 IP (直接回车返回): " test_src_ip
    [ -z "$test_src_ip" ] && return
    
    if [[ "$test_src_ip" =~ : ]]; then
        echo "正在使用 IPv6 ($test_src_ip) 请求外部测试..."
        curl -6 --interface "$test_src_ip" -s https://api64.ipify.org?format=json
    else
        echo "正在使用 IPv4 ($test_src_ip) 请求外部测试..."
        curl -4 --interface "$test_src_ip" -s https://api.ipify.org?format=json
    fi
    echo -e "\n"
    read -p "按回车键返回主菜单..."
}

# 卸载功能
uninstall_tool() {
    read -p "确认要卸载本工具及快捷命令吗？[y/N]: " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        rm -f "$BIN_PATH"
        rm -f /usr/local/bin/ip-switcher.sh
        echo "已成功卸载！"
        exit 0
    fi
}

# 自动注册快捷键命令 `ip-qh`
setup_shortcut() {
    # 将当前脚本保存到系统目录
    cp "$0" /usr/local/bin/ip-switcher.sh 2>/dev/null
    chmod +x /usr/local/bin/ip-switcher.sh
    
    cat << 'EOF' > "$BIN_PATH"
#!/bin/bash
bash /usr/local/bin/ip-switcher.sh
EOF
    chmod +x "$BIN_PATH"
}

# 如果是通过远程直接管道执行，先完成安装与注册
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_shortcut
fi

# 主循环
while true; do
    show_menu
    case "$choice" in
        1) list_ips ;;
        2) change_ipv4 ;;
        3) change_ipv6 ;;
        4) test_ip ;;
        5) uninstall_tool ;;
        0) echo "退出脚本。"; exit 0 ;;
        *) echo "无效选项，请重新选择！"; sleep 1 ;;
    esac
done
