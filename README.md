ip-switcher.sh  切换IP

感觉大佬仓库：https://github.com/eishare/Xray-go



方法一：curl

curl -fsSL -o /tmp/ip-switcher.sh https://raw.githubusercontent.com/huangxinyueus/zby/main/ip-switcher.sh && chmod +x /tmp/ip-switcher.sh && bash /tmp/ip-switcher.sh

方法二：wget


wget -O /tmp/ip-switcher.sh https://raw.githubusercontent.com/huangxinyueus/zby/main/ip-switcher.sh && chmod +x /tmp/ip-switcher.sh && bash /tmp/ip-switcher.sh

xtpps节点


bash <(curl -fsSL https://raw.githubusercontent.com/huangxinyueus/zby/main/xray-go-menu.sh)

xtpps节点支持路径自定义(Path)

目前是，xttp快捷

bash <(curl -fsSL "https://raw.githubusercontent.com/huangxinyueus/zby/refs/heads/main/xray-go-menu-xttp-multisub.sh")


xtpps节点支持路径自定义改支持Alpine

curl：
bash <(curl -fsSL https://raw.githubusercontent.com/huangxinyueus/zby/main/xhttp.sh)


wget：
bash <(wget -qO- https://raw.githubusercontent.com/huangxinyueus/zby/main/xhttp.sh)






Alpine Linux

Alpine 默认可能没有 Bash，需要先安装运行环境。

curl：
apk add --no-cache bash curl wget coreutils
curl -fsSL https://raw.githubusercontent.com/huangxinyueus/zby/main/xhttp.sh -o /tmp/xhttp.sh && bash /tmp/xhttp.sh


wget：
apk add --no-cache bash curl wget coreutils
wget -qO /tmp/xhttp.sh https://raw.githubusercontent.com/huangxinyueus/zby/main/xhttp.sh && bash /tmp/xhttp.sh
