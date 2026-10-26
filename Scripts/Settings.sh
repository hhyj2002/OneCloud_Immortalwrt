#!/bin/bash
             
## 配置 IP 等
# 修改默认 IP 地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$OWRT_IP/g" ./package/base-files/files/bin/config_generate
# 修改默认主机名
sed -i "s/hostname='.*'/hostname='$OWRT_NAME'/g" ./package/base-files/files/bin/config_generate
# 修改默认时区
sed -i "s/timezone='.*'/timezone='CST-8'/g" ./package/base-files/files/bin/config_generate
sed -i "/timezone='.*'/a\\\t\t\set system.@system[-1].zonename='Asia/Shanghai'" ./package/base-files/files/bin/config_generate

# 最新 golang
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang

# Modify default NTP server
echo 'Modify default NTP server...'
sed -i 's/ntp.aliyun.com/ntp.ntsc.ac.cn/' package/base-files/files/bin/config_generate
sed -i 's/time1.cloud.tencent.com/ntp.aliyun.com/' package/base-files/files/bin/config_generate
sed -i 's/time.ustc.edu.cn/cn.ntp.org.cn/' package/base-files/files/bin/config_generate
sed -i 's/cn.pool.ntp.org/pool.ntp.org/' package/base-files/files/bin/config_generate

######################################################################################################

# ================= 强制清理不需要的菜单组件 =================
echo "正在强制清理 Aria2 和 Docker 残留..."
rm -rf feeds/luci/applications/luci-app-aria2
rm -rf package/feeds/luci/luci-app-aria2
rm -rf feeds/luci/applications/luci-app-dockerman
rm -rf package/feeds/luci/luci-app-dockerman
rm -rf feeds/packages/net/ariang
rm -rf package/feeds/packages/ariang
# ==========================================================

# 固件版本号添加个人标识和日期
FILE="package/lean/default-settings/files/zzz-default-settings"
dist_info="Openwrt ImmortalWrt 25.12 ($(TZ=UTC-8 date +%Y.%m.%d))"

if [ -f "$FILE" ]; then
  sed -i "/^DISTRIB_DESCRIPTION=/d" "$FILE"
  echo "DISTRIB_DESCRIPTION='$dist_info'" >> "$FILE"
else
  FILE="package/base-files/files/etc/openwrt_release"
  if [ -f "$FILE" ]; then
    sed -i "/^DISTRIB_DESCRIPTION=/d" "$FILE"
    echo "DISTRIB_DESCRIPTION='$dist_info'" >> "$FILE"
  fi
fi

# 添加编译日期标识（修复 25.12 源码可能找不到 10_system.js 导致的报错）
cur_time=$(TZ=UTC-8 date +%y.%m.%d_%H.%M.%S)
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $cur_time')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" 2>/dev/null) || true

# 修改默认 WIFI 名
sed -i "s/\.ssid=.*/\.ssid=Openwrt_WiFi/g" $(find ./package/kernel/mac80211/ ./package/network/config/ -type f -name "mac80211.*")

# 设置密码为 password
sed -i 's/root:::0:99999:7:::/root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.:0:0:99999:7:::/' package/base-files/files/etc/shadow

# 优化连接数
sed -i '/customized in this file/a fs.file-max=102400\nnet.ipv4.neigh.default.gc_thresh1=512\nnet.ipv4.neigh.default.gc_thresh2=2048\nnet.ipv4.neigh.default.gc_thresh3=4096\nnet.netfilter.nf_conntrack_max=65535' package/base-files/files/etc/sysctl.conf

# ================= 修改默认主题为 bootstrap =================
# 确保 bootstrap 主题启用，并移除其他的默认主题强制设置
echo "Setting default theme to bootstrap..."
sed -i 's/luci-theme-argon/luci-theme-bootstrap/g' feeds/luci/collections/luci/Makefile
# 如果你的配置文件里带了 argon，这里也顺便把它在配置里关掉（如果你需要的话）
sed -i 's/CONFIG_PACKAGE_luci-theme-argon=y/# CONFIG_PACKAGE_luci-theme-argon is not set/' .config

# ================= 修改默认 banner（Onecloud 版） =================
echo 'Modify default banner...'
> package/base-files/files/etc/banner

cat << 'EOF' >> package/base-files/files/etc/banner
   ____             _                 _ 
  / __ \           | |               | |
 | |  | |_ __   ___| | ___  _   _  __| |
 | |  | | '_ \ / _ \ |/ _ \| | | |/ _` |
 | |__| | | | |  __/ | (_) | |_| | (_| |
  \____/|_| |_|\___|_|\___/ \__,_|\__,_|
                                        
EOF

build_date=$(date +"%Y-%m-%d %H:%M:%S")
echo " ------------------------------------------------------------- " >> package/base-files/files/etc/banner
echo "  %D %C ${build_date} " >> package/base-files/files/etc/banner
echo " ------------------------------------------------------------- " >> package/base-files/files/etc/banner
echo "                                                               " >> package/base-files/files/etc/banner
