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
# 彻底删除源码目录，防止菜单被依赖强行拉回
rm -rf feeds/luci/applications/luci-app-aria2
rm -rf package/feeds/luci/luci-app-aria2
rm -rf feeds/luci/applications/luci-app-dockerman
rm -rf package/feeds/luci/luci-app-dockerman
# 顺带清理可能存在的旧版本依赖包
rm -rf feeds/packages/net/ariang
rm -rf package/feeds/packages/ariang
# ==========================================================

# 固件版本号添加个人标识和日期
# 注：ImmortalWrt 通常没有 package/lean 目录，这里做了兼容性判断
FILE="package/lean/default-settings/files/zzz-default-settings"
dist_info="Openwrt ImmortalWrt 25.12 莫小小($(TZ=UTC-8 date +%Y.%m.%d))"

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
# 使用 2>/dev/null 屏蔽查找失败的错误，|| true 确保即使没找到文件也不会中断编译流程
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $cur_time')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" 2>/dev/null) || true

# 修改默认 WIFI 名
sed -i "s/\.ssid=.*/\.ssid=Openwrt_WiFi/g" $(find ./package/kernel/mac80211/ ./package/network/config/ -type f -name "mac80211.*")

# 设置密码为 password
sed -i 's/root:::0:99999:7:::/root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.:0:0:99999:7:::/' package/base-files/files/etc/shadow

# 优化连接数
sed -i '/customized in this file/a fs.file-max=102400\nnet.ipv4.neigh.default.gc_thresh1=512\nnet.ipv4.neigh.default.gc_thresh2=2048\nnet.ipv4.neigh.default.gc_thresh3=4096\nnet.netfilter.nf_conntrack_max=65535' package/base-files/files/etc/sysctl.conf

# 修改 argon 为默认主题
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# 修改默认 banner
echo 'Modify default banner...'
build_date=$(date +"%Y-%m-%d %H:%M:%S")
echo "      %D %C ${build_date}                   " >> package/base-files/files/etc/banner
echo " ------------------------------------------------------------- " >> package/base-files/files/etc/banner
echo " ------------------------------------------------------------- " >> package/base-files/files/etc/banner
echo "                                                               " >> package/base-files/files/etc/banner
