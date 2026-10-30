#公用函数
source $GITHUB_WORKSPACE/Scripts/functions.sh

# 【新增】清理底层源码中自动拉取和安装的所有 luci-app，确保不安装任何代理/服务类插件
# 先清理已经克隆到本地的 luci-app，防止 feeds install 安装它们
rm -rf feeds/luci/applications/luci-app-*
# 注释掉 feeds 中所有的第三方 luci 应用源，防止 update 再次拉取
find feeds/luci/feeds.conf.default -type f -exec sed -i '/luci-app/s/^/# /g' {} \;
# 清理 feeds/luci 目录下的 luci-app 索引文件
rm -f feeds/luci/applications/luci-app-*/Makefile

./scripts/feeds update -a
./scripts/feeds install -a

# rm -rf feeds/luci/applications/luci-app-homeproxy
# merge_package main https://github.com/VIKINGYFY/packages package luci-app-homeproxy

# rm -rf feeds/luci/applications/luci-app-amlogic
# git clone https://github.com/ophub/luci-app-amlogic package/luci-app-amlogic

# rm -rf feeds/luci/applications/luci-app-ssr-plus
# git clone https://github.com/stupidloud/helloworld package/helloworld

# rm -rf feeds/packages/net/hysteria/*
# rm -rf feeds/packages/net/xray-core/*
# rm -rf feeds/packages/net/v2ray-core/*
# cp -rf package/helloworld/hysteria/* feeds/packages/net/hysteria
# cp -rf package/helloworld/xray-core/* feeds/packages/net/v2ray-core
# cp -rf package/helloworld/v2ray-geodata/* feeds/packages/net/v2ray-geodata

# rm -rf feeds/packages/net/v2ray-geodata
# rm -rf package/helloworld/v2ray-geodata
# git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata

# rm -rf feeds/packages/net/sing-box
# merge_package main https://github.com/VIKINGYFY/packages  feeds/packages/net sing-box

cd package
$GITHUB_WORKSPACE/Scripts/Packages.sh
$GITHUB_WORKSPACE/Scripts/Handles.sh
