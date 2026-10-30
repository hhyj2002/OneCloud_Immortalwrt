#!/bin/bash

# 公用处理脚本（Handles.sh）-- 已按第一个最精简 config 处理
# 原脚本的补丁逻辑全部针对第三方应用/主题或代理内核编译依赖：
#   homeproxy 数据预置、argon/aurora 主题美化、qca-nss 启动顺序、
#   tailscale 冲突修复、rust 编译修复、diskman 编译修复、netspeedtest 修复。
# 最精简 config 不装任何第三方应用、使用 bootstrap 自带主题、目标平台 meson8b
# (无高通 nss)，因此以上分支均无作用对象，整段移除。
# 本脚本保留为空壳，后续如需自定义处理可在此追加。

PKG_PATH="$GITHUB_WORKSPACE/openwrt/package/"
