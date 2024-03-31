
port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
global-client-fingerprint: chrome
dns:
  enable: true
  listen: :53
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver: 
    - 223.5.5.5
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4


proxy-providers:
  jichang:   #名称，默认即可
    type: http
    url: "https://nidedingyuelianjie"  #此处必填，url里面填入你的机场订阅链接
    interval: 3600
    path: ./sub/jichang.yaml   #机场订阅文件下载后的文件名及文件地址，默认即可
    health-check:
      enable: true
      interval: 600
      url: https://www.gstatic.com/generate_204


proxy-groups:

  - name: 节点选择
    type: select
    proxies:
      - 自动选择   
      - DIRECT 
    use:
      - jichang
      

  - name: 自动选择
    type: url-test #选出延迟最低的机场节点
    use:
      - jichang    #proxy-providers中的名字，默认即可
    url: "http://www.gstatic.com/generate_204"
    interval: 300
    tolerance: 50



rules:
    - DOMAIN,clash.razord.top,DIRECT
    - DOMAIN,yacd.haishan.me,DIRECT
    - GEOIP,LAN,DIRECT
    - GEOIP,CN,DIRECT
    - GEOSITE,CN,DIRECT
    - MATCH,节点选择