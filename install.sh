#!/bin/bash

# 显示颜色
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}=== 开始安装 Sing-box 多 IP 分流/出口脚本 ===${NC}"

# 1. 检测系统并安装必要组件
if command -v apt &> /dev/null; then
    apt update && apt install -y curl wget jq
elif command -v yum &> /dev/null; then
    yum makecache && yum install -y curl wget jq
fi

# 2. 安装 Sing-box (如果未安装)
if ! command -v sing-box &> /dev/null; then
    echo -e "${GREEN}正在安装 Sing-box...${NC}"
    bash <(curl -fsSL https://sing-box.app/install.sh)
fi

# 3. 创建配置目录
mkdir -p /etc/sing-box

# 4. 生成包含 bind_address 多出口配置的 config.json
# （这里可以根据实际需求动态填入 IP）
cat << 'EOF' > /etc/sing-box/config.json
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "::",
      "listen_port": 1080
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "out-ip1",
      "bind_address": "2001:db8::1"
    },
    {
      "type": "direct",
      "tag": "out-ip2",
      "bind_address": "2001:db8::2"
    }
  ]
}
EOF

# 5. 重启并设置开机自启
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

echo -e "${GREEN}=== 安装完成！Sing-box 已成功运行 ===${NC}"