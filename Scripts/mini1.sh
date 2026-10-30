#公用函数（提供 merge_package 等函数）
source $GITHUB_WORKSPACE/Scripts/functions.sh

#更新并安装 feeds（系统核心 + LuCI + 中文 + argon 主题均来自默认 feed）
./scripts/feeds update -a
./scripts/feeds install -a

# 说明：本脚本已依照「最精简 config」清理。
# 原 setup.sh 中所有为第三方应用准备源码仓库的逻辑全部删除，包括：
#   - luci-app-homeproxy / VIKINGYFY packages（代理）
#   - luci-app-ssr-plus / helloworld / stupidloud（代理）
#   - hysteria / xray-core / v2ray-core / v2ray-geodata / sing-box（代理内核与库）
#   - luci-app-amlogic / ophub（晶晨宝盒，玩客云刷机/固件更新工具）
# 这些包在精简 config 中已全部未启用，故无需拉取外部 feed，避免无效克隆与编译冲突。

#自定义包/配置处理脚本（属于你自己的脚本逻辑，按需保留）
#注意：若 Packages.sh / Handles.sh 内部仍会写入代理/第三方应用，请一并清理以保持与精简 config 一致。
cd package
$GITHUB_WORKSPACE/Scripts/Packages-mini.sh
$GITHUB_WORKSPACE/Scripts/Handles.sh
