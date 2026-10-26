#!/bin/bash

# 默认主路由
rm -rf ./files/etc/config/network

# 如果 files/etc/config 文件夹不存在，创建文件夹
if [ ! -d "./files/etc/config" ]; then
  mkdir -p ./files/etc/config
fi

ip="$1"
ip_server="$2"

# 判断是否传入了合法的 IP（针对你可能未来还需要静态 IP 的情况）
if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ $ip_server =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "玩客云IP地址 $ip 符合规范，将使用静态 IP 模式。"
    cat > files/etc/config/network <<EOF
config interface 'loopback'
	option device 'lo'
	option proto 'static'
	option ipaddr '127.0.0.1'
	option netmask '255.0.0.0'

config globals 'globals'
	option packet_steering '1'
	option ula_prefix 'fd3d:7b8e:953e::/48'

config interface 'lan'
	option device 'br-lan'
	option proto 'static'
	option ipaddr '$ip'
	option netmask '255.255.255.0'
	option ip6assign '60'
	option gateway '$ip_server'
	list dns '$ip_server'

config interface 'lan6'
	option device 'br-lan'
	option proto 'dhcpv6'
	option reqaddress 'try'
	option reqprefix 'auto'

config device
	option name 'br-lan'
	option type 'bridge'
	list ports 'eth0'
EOF

else
    # 如果没传参数（例如通过 Actions 编译时），则使用 DHCP 客户端模式
    echo "未提供合法 IP 参数，使用 DHCP 客户端模式（不对外提供 DHCP 服务）。"
    cat > files/etc/config/network <<EOF
config interface 'loopback'
	option device 'lo'
	option proto 'static'
	option ipaddr '127.0.0.1'
	option netmask '255.0.0.0'

config globals 'globals'
	option packet_steering '1'
	option ula_prefix 'fd3d:7b8e:953e::/48'

config interface 'lan'
	option device 'br-lan'
	option proto 'dhcp'

config interface 'lan6'
	option device 'br-lan'
	option proto 'dhcpv6'
	option reqaddress 'try'
	option reqprefix 'auto'

config device
	option name 'br-lan'
	option type 'bridge'
	list ports 'eth0'
EOF
fi
