#!/bin/bash
set -x

sudo apt install -y android-sdk-libsparse-utils
ver="v0.3.2"

# 下载工具和底包
curl -L -o ./AmlImg https://github.com/rmoyulong/AmlImg/releases/download/$ver/AmlImg_${ver}_linux_amd64
chmod +x ./AmlImg
curl -L -o ./uboot.img https://github.com/rmoyulong/u-boot-onecloud/releases/download/Onecloud_Uboot_23.12.24_18.15.09/eMMC.burn.img
./AmlImg unpack ./uboot.img burn/

# ========= 修复点 1：兼容 25.12 的生成格式 =========
# 先尝试找 .gz 并解压（如果存在）
gz_files=$(find openwrt/bin/targets/ -name "*.gz" ! -name "*kernel*" | head -n 1)
if [ -n "$gz_files" ]; then
    gunzip $gz_files
fi

# 然后找 .img 文件
diskimg=$(find openwrt/bin/targets/ -name "*.img" ! -name "*.burn.img" | head -n 1)

if [ -z "$diskimg" ]; then
    echo "❌ 找不到 .img 文件！请确保 .config 里开启了 CONFIG_TARGET_ROOTFS_EXT4FS_IMG=y"
    exit 1
fi

echo "✅ 找到磁盘镜像: $diskimg"

# ========= 以下完全照搬 24.10 成功版的核心逻辑 =========
loop=$(sudo losetup --find --show --partscan $diskimg)
img_ext="openwrt.img"
img_mnt="xd"
rootfs_mnt="img"
boot_img=${img_ext}
boot_img_mnt=${img_mnt}
rootfs_img_mnt=${rootfs_mnt}

sudo rm -rf ${boot_img} ${boot_img_mnt} ${rootfs_img_mnt}
sudo dd if=/dev/zero of=${boot_img} bs=1M count=2000
sudo mkfs.ext4 ${boot_img}
sudo mkdir ${boot_img_mnt}
sudo mkdir ${rootfs_img_mnt}
sudo mount ${boot_img} ${boot_img_mnt}

# 挂载原镜像的分区 2
sudo mount ${loop}p2 ${rootfs_img_mnt}

# 复制文件系统
cd ${rootfs_img_mnt}
sudo cp -r * ../${boot_img_mnt}
cd ..
sudo sync
sudo umount ${boot_img_mnt}
sudo umount ${rootfs_img_mnt}

# 转换为 simg（切分 boot 和 rootfs 分区）
sudo img2simg ${loop}p1 burn/boot.simg
sudo img2simg openwrt.img burn/rootfs.simg
sudo rm -rf *.img
sudo losetup -d $loop

# ========= 追加指令并打包 =========
# 注意：必须用 >> 追加，不能覆盖，否则丢失 U-Boot 引导
cat <<EOF >>burn/commands.txt
PARTITION:boot:sparse:boot.simg
PARTITION:rootfs:sparse:rootfs.simg
EOF

burnimg="openwrt/bin/targets/OneCloud.burn.img"
./AmlImg pack $burnimg burn/

for f in openwrt/bin/targets/*.burn.img; do
  if [ -f "$f" ]; then
    sha256sum "$f" >"${f}.sha"
    xz -9 --threads=0 --compress "$f"
  fi
done
