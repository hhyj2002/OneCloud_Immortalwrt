#!/bin/bash
set -e # 遇到错误立即退出，防止静默失败

sudo apt install -y android-sdk-libsparse-utils
ver="v0.3.2"
curl -L -o ./AmlImg https://github.com/rmoyulong/AmlImg/releases/download/$ver/AmlImg_${ver}_linux_amd64
chmod +x ./AmlImg
curl -L -o ./uboot.img https://github.com/rmoyulong/u-boot-onecloud/releases/download/Onecloud_Uboot_23.12.24_18.15.09/eMMC.burn.img
./AmlImg unpack ./uboot.img burn/

# 兼容处理：寻找并解压 .gz
gz_files=$(ls openwrt/bin/targets/*/*/*.gz 2>/dev/null || true)
if [ -n "$gz_files" ]; then
    gunzip $gz_files
fi

diskimg=$(ls openwrt/bin/targets/*/*/*.img 2>/dev/null | grep -v "burn.img" | head -n 1)
if [ -z "$diskimg" ]; then
    echo "❌ 错误: 在 openwrt/bin/targets/ 中找不到 .img 文件，编译可能失败了。"
    exit 1
fi

echo "找到磁盘镜像: $diskimg"
loop=$(sudo losetup --find --show --partscan "$diskimg")
img_ext="openwrt.img"
img_mnt="xd"
rootfs_mnt="img"
boot_img=${img_ext}
boot_img_mnt=${img_mnt}
rootfs_img_mnt=${rootfs_mnt}

sudo rm -rf ${boot_img} ${boot_img_mnt} ${rootfs_img_mnt}
sudo dd if=/dev/zero of=${boot_img} bs=1M count=2000
sudo mkfs.ext4 ${boot_img}
sudo mkdir ${boot_img_mnt} ${rootfs_img_mnt}
sudo mount ${boot_img} ${boot_img_mnt}
sudo mount ${loop}p2 ${rootfs_img_mnt}

cd ${rootfs_img_mnt}
sudo cp -r * ../${boot_img_mnt}
cd ..
sudo sync
sudo umount ${boot_img_mnt} ${rootfs_img_mnt}

sudo img2simg ${loop}p1 burn/boot.simg
sudo img2simg ${boot_img} burn/rootfs.simg

sudo losetup -d $loop
sudo rm -rf *.img
rm -rf ${boot_img_mnt} ${rootfs_img_mnt}

cat <<EOF >>burn/commands.txt
PARTITION:boot:sparse:boot.simg
PARTITION:rootfs:sparse:rootfs.simg
EOF

prefix=$(ls openwrt/bin/targets/*/*/*.img | sed 's/\.img$//')
burnimg=${prefix}.burn.img
./AmlImg pack $burnimg burn/

for f in openwrt/bin/targets/*/*/*.burn.img; do
  sha256sum "$f" >"${f}.sha"
  xz -9 --threads=0 --compress "$f"
done

sudo rm -rf openwrt/bin/targets/*/*/*.img openwrt/bin/targets/*/*/*.gz
