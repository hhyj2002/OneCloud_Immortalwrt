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

# 解压底包
./AmlImg unpack ./uboot.img burn/

# ========= 寻找可用的系统镜像 =========
echo "=== 开始扫描 bin/targets 目录 ==="
find openwrt/bin/targets/ -type f
echo "================================"

# 1. 优先找现成的 .img 文件（25.12 默认产出这个）
diskimg=$(find openwrt/bin/targets/ -type f -name "*.img" ! -name "*.burn.img" | head -n 1)

if [ -n "$diskimg" ]; then
    echo "✅ 找到现成的磁盘镜像: $diskimg"
    # 直接打包现有镜像
    sudo img2simg ${diskimg} burn/rootfs.simg
    sudo img2simg ${diskimg} burn/boot.simg
else
    # 2. 如果没找到 .img，退回去找 .tar.gz 自己造盘
    rootfs_tar=$(find openwrt/bin/targets/ -type f \( -name "*.tar.gz" -o -name "*.tar" \) ! -name "*kernel*" | head -n 1)
    
    if [ -z "$rootfs_tar" ]; then
        echo "❌ 既没找到 .img 也没找到 .tar.gz，请检查上方扫描日志。"
        exit 1
    fi
    
    echo "✅ 找到根文件系统包: $rootfs_tar，正在自行造盘..."
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
    sudo img2simg ${boot_img} burn/boot.simg
    sudo rm -rf ${boot_img} rootfs_mnt
fi

# ========= 【核心修复】 =========
# 追加系统指令，保留原版 UBOOT 等指令
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
