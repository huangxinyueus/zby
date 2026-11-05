#!/usr/bin/env bash
# VPS 多 IP 查看与默认路由首选源地址切换工具
# GitHub 仓库：https://github.com/huangxinyueus/zby
# 建议将本文件放在仓库根目录，文件名为 ip-switcher.sh

set -u

RAW_URL="https://raw.githubusercontent.com/huangxinyueus/zby/main/ip-switcher.sh"
INSTALL_PATH="/usr/local/bin/ip-switcher.sh"
LAUNCHER_PATH="/usr/local/bin/ip-qh"

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "请使用 root 权限运行：sudo bash ip-switcher.sh"
        return 1
    fi
}

pause_screen() {
    read -r -p "按回车键返回主菜单..." _
}

get_default_dev() {
    local family="$1"
    if [ "$family" = "6" ]; then
        ip -6 route show default 2>/dev/null | awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
    else
        ip -4 route show default 2>/dev/null | awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
    fi
}

get_default_src() {
    local family="$1"
    if [ "$family" = "6" ]; then
        ip -6 route show default 2>/dev/null | awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}'
    else
        ip -4 route show default 2>/dev/null | awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}'
    fi
}

show_current() {
    local v4dev v4src v6dev v6src
    v4dev="$(get_default_dev 4)"; v4src="$(get_default_src 4)"
    v6dev="$(get_default_dev 6)"; v6src="$(get_default_src 6)"
    printf '当前默认 IPv4：%s  网卡：%s\n' "${v4src:-系统未指定源地址}" "${v4dev:-未知}"
    printf '当前默认 IPv6：%s  网卡：%s\n' "${v6src:-系统未指定源地址}" "${v6dev:-未知}"
}

list_ips() {
    echo; echo '--- 当前网卡 IP 地址 ---'
    ip -o addr show 2>/dev/null | awk '{print "网卡: "$2" | 类型: "$3" | IP: "$4}'
    echo; echo '--- IPv4 默认路由 ---'; ip -4 route show default 2>/dev/null
    echo; echo '--- IPv6 默认路由 ---'; ip -6 route show default 2>/dev/null
    echo; pause_screen
}

change_ip() {
    local family="$1" label index chosen confirm
    local -a addresses=()
    if [ "$family" = "4" ]; then
        label="IPv4"
        mapfile -t addresses < <(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
    else
        label="IPv6"
        mapfile -t addresses < <(ip -o -6 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
    fi

    echo; echo "--- 可用的 ${label} 地址 ---"
    if [ "${#addresses[@]}" -eq 0 ]; then
        echo "没有找到 scope global 的 ${label} 地址。"; pause_screen; return
    fi
    local i
    for i in "${!addresses[@]}"; do printf ' [%s] %s\n' "$i" "${addresses[$i]}"; done
    echo ' [b] 返回'
    read -r -p "请选择要设为默认首选源地址的编号：" index
    [[ "$index" == "b" || "$index" == "B" ]] && return
    if ! [[ "$index" =~ ^[0-9]+$ ]] || [ "$index" -ge "${#addresses[@]}" ]; then
        echo '编号无效。'; pause_screen; return
    fi

    chosen="${addresses[$index]}"
    if [ -z "$(get_default_dev "$family")" ]; then
        echo "没有检测到 IPv${family} 默认路由，无法切换。"; pause_screen; return
    fi
    echo
    echo "即将把 IPv${family} 默认路由的首选源地址设为：$chosen"
    echo "此操作尝试保留现有网关、网卡和路由 metric，不会新增或替换网关。"
    echo '注意：云服务商的网络配置、策略路由或多条默认路由可能影响结果。建议先确保有 VPS 控制台/救援模式。'
    read -r -p '确认执行？[y/N]：' confirm
    [[ "$confirm" == "y" || "$confirm" == "Y" ]] || { echo '已取消。'; return; }

    if [ "$family" = "4" ]; then
        if ip -4 route change default src "$chosen"; then echo "IPv4 首选源地址已设置为：$chosen";
        else echo 'IPv4 切换失败。可能存在多条默认路由或策略路由，请检查：ip -4 route show default'; fi
    else
        if ip -6 route change default src "$chosen"; then echo "IPv6 首选源地址已设置为：$chosen";
        else echo 'IPv6 切换失败。可能存在多条默认路由或策略路由，请检查：ip -6 route show default'; fi
    fi
    pause_screen
}

test_ip() {
    local source_ip
    echo
    read -r -p '请输入本机已有的 IP 地址（回车返回）：' source_ip
    [ -z "$source_ip" ] && return
    if [[ "$source_ip" == *:* ]]; then
        if ! command -v curl >/dev/null 2>&1; then echo '缺少 curl，请先安装 curl。'; pause_screen; return; fi
        echo "使用 IPv6 地址 $source_ip 测试..."
        curl -6 --interface "$source_ip" --connect-timeout 8 --max-time 15 -fsS https://api64.ipify.org || echo 'IPv6 测试失败。'
    else
        if ! command -v curl >/dev/null 2>&1; then echo '缺少 curl，请先安装 curl。'; pause_screen; return; fi
        echo "使用 IPv4 地址 $source_ip 测试..."
        curl -4 --interface "$source_ip" --connect-timeout 8 --max-time 15 -fsS https://api.ipify.org || echo 'IPv4 测试失败。'
    fi
    echo; pause_screen
}

install_shortcut() {
    local confirm
    echo
    echo "将从 GitHub 下载最新版脚本到：$INSTALL_PATH"
    echo "下载地址：$RAW_URL"
    read -r -p '确认安装/更新 ip-qh 快捷命令？[y/N]：' confirm
    [[ "$confirm" == "y" || "$confirm" == "Y" ]] || return

    if command -v curl >/dev/null 2>&1; then
        curl -fL --connect-timeout 10 --max-time 60 "$RAW_URL" -o "$INSTALL_PATH" || { echo '下载失败，请检查仓库是否公开、分支名和文件路径。'; rm -f "$INSTALL_PATH"; pause_screen; return; }
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$INSTALL_PATH" "$RAW_URL" || { echo '下载失败，请检查仓库是否公开、分支名和文件路径。'; rm -f "$INSTALL_PATH"; pause_screen; return; }
    else
        echo '系统缺少 curl 和 wget，无法下载。'; pause_screen; return
    fi

    chmod 755 "$INSTALL_PATH"
    cat > "$LAUNCHER_PATH" <<'LAUNCHER'
#!/usr/bin/env bash
exec bash /usr/local/bin/ip-switcher.sh
LAUNCHER
    chmod 755 "$LAUNCHER_PATH"
    echo '安装/更新成功！以后输入 ip-qh 即可启动。'
    pause_screen
}

uninstall_tool() {
    local confirm
    read -r -p '确认删除 ip-qh 快捷命令和已安装脚本？[y/N]：' confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        rm -f "$LAUNCHER_PATH" "$INSTALL_PATH"
        echo '已删除快捷命令和已安装脚本。'
        exit 0
    fi
}

main() {
    if ! command -v ip >/dev/null 2>&1; then
        echo '缺少 ip 命令。Debian/Ubuntu 可执行：apt update && apt install -y iproute2'
        exit 1
    fi
    while true; do
        clear 2>/dev/null || true
        echo '=============================================='
        echo '       VPS 多 IP 管理与出口源地址切换工具'
        echo '=============================================='
        show_current
        echo '----------------------------------------------'
        echo ' 1. 查看所有 IP 地址及默认路由'
        echo ' 2. 切换默认 IPv4 首选源地址'
        echo ' 3. 切换默认 IPv6 首选源地址'
        echo ' 4. 测试指定 IP 的出网连通性'
        echo ' 5. 安装 / 更新 ip-qh 快捷命令'
        echo ' 6. 卸载快捷命令及已安装脚本'
        echo ' 0. 退出'
        echo '=============================================='
        read -r -p '请输入选项 [0-6]：' choice
        case "$choice" in
            1) list_ips ;;
            2) change_ip 4 ;;
            3) change_ip 6 ;;
            4) test_ip ;;
            5) install_shortcut ;;
            6) uninstall_tool ;;
            0) echo '已退出。'; exit 0 ;;
            *) echo '无效选项。'; sleep 1 ;;
        esac
    done
}

require_root || exit 1
main
