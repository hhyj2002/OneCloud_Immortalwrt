
#!/bin/bash

# 安装和更新软件包（精简版）
# 说明：第一个最精简 config 已移除所有第三方应用，仅保留系统核心 + LuCI +
#       argon 主题 + 必要硬件支持。因此这里只保留 argon 主题的源码拉取，
#       其余代理 / NAS / 下载 / istore / 磁盘工具等第三方仓库源全部清除。
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)  # 第5个参数为自定义名称列表
	local REPO_NAME=${PKG_REPO#*/}

	echo " "

	# 删除本地可能存在的不同名称的软件包
	for NAME in "${PKG_LIST[@]}"; do
		# 查找匹配的目录
		echo "搜索目录: $NAME"
		local FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)

		# 删除找到的目录
		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "删除目录: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "目录中没有发现: $NAME"
		fi
	done

	# 克隆 GitHub 仓库
	git clone --depth=1 --single-branch --branch $PKG_BRANCH "https://github.com/$PKG_REPO.git"

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find ./$REPO_NAME/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf ./$REPO_NAME/
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f $REPO_NAME $PKG_NAME
	fi
}

# 仅保留 argon 主题源（第一个最精简 config 保留 luci-theme-argon）。
# 若你已按第 9 轮把主题改成 bootstrap：bootstrap 由 luci feed 自带，无需拉源，
# 可把下面这一行连同 argon 一起删除，本文件即不再需要克隆任何外部仓库。
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
