#!/bin/bash
set -x

sudo apt update && sudo apt install -y android-sdk-libsparse-utils
ver="v0.3.2"

# 下载打包工具和原版底包
curl -L -o ./AmlImg https://github.com/rmoyulong/AmlImg/releases/download/$ver/AmlImg_${ver}_linux_amd64
chmod +x ./AmlImg
curl -L -o ./uboot.img https://github.com/rmoyulong/u-boot-onecloud/releases/download/Onecloud_Uboot_23.12.24_18.15.09/eMMC.burn.img

if [ ! -f "uboot.img" ] || [ ! -f "AmlImg" ]; then
  echo "❌ 下载工具失败"
  exit 1
fi

./AmlImg unpack ./uboot.img burn/

# ========= 寻找原生 .img 镜像 =========
diskimg=$(find openwrt/bin/targets/ -type f -name "*.img" ! -name "*.burn.img" | head -n 1)

if [ -z "$diskimg" ]; then
    echo "❌ 找不到原生 .img 镜像！请确保 .config 里开启了 CONFIG_TARGET_ROOTFS_EXT4FS_IMG=y"
    exit 1
fi

echo "✅ 找到原生镜像: $diskimg"

# 挂载原始 img，提取分区
sudo modprobe loop || true
loop=$(sudo losetup --find --show --partscan "$diskimg")

# 玩客云原厂底包需要 boot.simg 和 rootfs.simg
# 原生镜像通常是单分区或双分区，我们直接把原始镜像转换为 Android 稀疏格式
sudo img2simg ${loop}p1 burn/boot.simg || sudo img2simg $diskimg burn/boot.simg
sudo img2simg ${loop}p2 burn/rootfs.simg || sudo img2simg $diskimg burn/rootfs.simg

sudo losetup -d $loop 2>/dev/null || true

# ========= 【核心修复】 =========
# 保留原有的 commands.txt，追加系统指令。
echo "PARTITION:boot:sparse:boot.simg" >> burn/commands.txt
echo "PARTITION:rootfs:sparse:rootfs.simg" >> burn/commands.txt

# 打包
burnimg="openwrt/bin/targets/OneCloud.burn.img"
./AmlImg pack $burnimg burn/

# 压缩
for f in openwrt/bin/targets/*.burn.img; do
  if [ -f "$f" ]; then
    sha256sum "$f" >"${f}.sha"
    xz -9 --threads=0 --compress "$f"
  fi
done
