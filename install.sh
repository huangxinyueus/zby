#!/bin/bash

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本！(sudo -i)"
  exit 1
fi

# 显示主菜单
show_menu() {
    clear
    echo "=========================================="
    echo "       VPS 多 IP 可视化管理与出口切换工具       "
    echo "=========================================="
    echo " 1. 查看当前所有 IP 地址及网络状态"
    echo " 2. 临时/永久切换系统默认 IPv4 出口"
    echo " 3. 临时/永久切换系统默认 IPv6 出口"
    echo " 4. 测试指定 IP 的出网连通性"
    echo " 0. 退出脚本"
    echo "=========================================="
    read -p "请输入数字选项 [0-4]: " choice
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
    echo -e "\n--- 可用的 IPv4 地址列表 ---"
    local_ipv4s=($(ip -4 addr show | grep inet | awk '{print $2}' | cut -d/ -f1))
    
    for i in "${!local_ipv4s[@]}"; do
        echo " [$i] ${local_ipv4s[$i]}"
    done
    
    read -p "请选择要作为默认出口的 IPv4 编号: " ip_idx
    if [[ ! "${local_ipv4s[$ip_idx]}" ]]; then
        echo "输入错误！"
        sleep 1
        return
    fi
    
    chosen_ip="${local_ipv4s[$ip_idx]}"
    default_dev=$(ip route show default | awk '/default/ {print $5}' | head -n1)
    
    # 通过 ip route src 强制指定该网卡默认发包源 IP
    ip route replace default dev "$default_dev" src "$chosen_ip"
    echo -e "\n[成功] 已将默认 IPv4 出口切换为: $chosen_ip (网卡: $default_dev)"
    read -p "按回车键返回主菜单..."
}

# 切换 IPv6 出口
change_ipv6() {
    echo -e "\n--- 可用的 IPv6 地址列表 ---"
    local_ipv6s=($(ip -6 addr show | grep inet6 | grep -v 'fe80' | awk '{print $2}' | cut -d/ -f1))
    
    if [ ${#local_ipv6s[@]} -eq 0 ]; then
        echo "当前系统没有检测到可用的公网 IPv6 地址！"
        sleep 2
        return
    fi
    
    for i in "${!local_ipv6s[@]}"; do
        echo " [$i] ${local_ipv6s[$i]}"
    done
    
    read -p "请选择要作为默认出口的 IPv6 编号: " ip_idx
    if [[ ! "${local_ipv6s[$ip_idx]}" ]]; then
        echo "输入错误！"
        sleep 1
        return
    fi
    
    chosen_ip="${local_ipv6s[$ip_idx]}"
    default_dev=$(ip -6 route show default | awk '/default/ {print $5}' | head -n1)
    
    ip -6 route replace default dev "$default_dev" src "$chosen_ip"
    echo -e "\n[成功] 已将默认 IPv6 出口切换为: $chosen_ip"
    read -p "按回车键返回主菜单..."
}

# 测试指定 IP 连通性
test_ip() {
    echo -e "\n--- 测试 IP 出口 ---"
    read -p "请输入你要测试的本地 IP (IPv4 或 IPv6): " test_src_ip
    
    if [[ "$test_src_ip" =~ : ]]; then
        # IPv6 测试
        echo "正在使用 IPv6 ($test_src_ip) 请求外部测试..."
        curl -6 --interface "$test_src_ip" -s https://api64.ipify.org?format=json
    else
        # IPv4 测试
        echo "正在使用 IPv4 ($test_src_ip) 请求外部测试..."
        curl -4 --interface "$test_src_ip" -s https://api.ipify.org?format=json
    fi
    echo -e "\n"
    read -p "按回车键返回主菜单..."
}

# 主循环
while true; do
    show_menu
    case "$choice" in
        1) list_ips ;;
        2) change_ipv4 ;;
        3) change_ipv6 ;;
        4) test_ip ;;
        0) echo "退出脚本。"; exit 0 ;;
        *) echo "无效选项，请重新选择！"; sleep 1 ;;
    esac
done
