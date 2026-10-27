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

# ========= 核心逻辑：先找现成的 .img，找不到再自己造 =========
echo "=== 开始扫描 bin/targets 目录 ==="
find openwrt/bin/targets/ -type f
echo "================================"

diskimg=$(find openwrt/bin/targets/ -type f -name "*.img" ! -name "*.burn.img" | head -n 1)

if [ -n "$diskimg" ]; then
    echo "✅ 找到现成的磁盘镜像: $diskimg"
    # 如果找到了 img，直接打包（原版逻辑）
    sudo modprobe loop || true
    loop=$(sudo losetup --find --show --partscan "$diskimg")
    sudo img2simg ${loop}p1 burn/boot.simg || sudo img2simg $diskimg burn/boot.simg
    sudo img2simg ${loop}p2 burn/rootfs.simg || sudo img2simg $diskimg burn/rootfs.simg
    sudo losetup -d $loop 2>/dev/null || true
else
    # 如果没找到 img，退回去找 .tar.gz 自己造盘
    rootfs_tar=$(find openwrt/bin/targets/ -type f -name "*.tar.gz" ! -name "*kernel*" | head -n 1)
    
    if [ -z "$rootfs_tar" ]; then
        echo "❌ 既没找到 .img 也没找到 .tar.gz，请检查上方扫描日志。"
        exit 1
    fi
    
    echo "✅ 找到根文件系统: $rootfs_tar，正在自行造盘..."
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

    sudo img2simg ${boot_img} burn/rootfs.simg
    sudo img2simg ${boot_img} burn/boot.simg
    sudo rm -rf ${boot_img} rootfs_mnt
fi

# ========= 【核心修复】保留底包并追加指令 =========
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
