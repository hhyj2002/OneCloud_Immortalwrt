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

# 解压底包，会生成 burn/ 目录及里面的各种 USB/PARTITION 文件
./AmlImg unpack ./uboot.img burn/

# ========= 寻找 rootfs 并挂载提取 =========
rootfs_tar=$(find openwrt/bin/targets/ -type f \( -name "*.tar.gz" -o -name "*.tar" \) ! -name "*kernel*" | head -n 1)

if [ -z "$rootfs_tar" ]; then
    echo "❌ 找不到根文件系统包"
    exit 1
fi

echo "✅ 找到根文件系统: $rootfs_tar"

boot_img="openwrt.img"
sudo rm -rf ${boot_img} rootfs_mnt
sudo dd if=/dev/zero of=${boot_img} bs=1M count=2000
sudo mkfs.ext4 ${boot_img}
sudo mkdir rootfs_mnt
sudo mount ${boot_img} rootfs_mnt

if [[ "$rootfs_tar" == *.gz ]]; then
    sudo tar -xzf "$rootfs_tar" -C rootfs_mnt
else
    sudo tar -xf "$rootfs_tar" -C rootfs_mnt
fi

sudo sync
sudo umount rootfs_mnt

# 转换为 Android 稀疏格式
sudo img2simg ${boot_img} burn/rootfs.simg
# 把整个盘也作为 boot.simg（或者你有单独的内核分区就放内核）
sudo img2simg ${boot_img} burn/boot.simg

sudo rm -rf ${boot_img} rootfs_mnt

# ========= 【核心修复】 =========
# 不要覆盖原有的 commands.txt，而是追加。原版指令用于加载 UBOOT 等，我们追加系统指令。
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
