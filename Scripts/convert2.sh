#!/bin/bash
set -x

sudo apt update && sudo apt install -y android-sdk-libsparse-utils
ver="v0.3.2"

curl -L -o ./AmlImg https://github.com/rmoyulong/AmlImg/releases/download/$ver/AmlImg_${ver}_linux_amd64
chmod +x ./AmlImg
curl -L -o ./uboot.img https://github.com/rmoyulong/u-boot-onecloud/releases/download/Onecloud_Uboot_23.12.24_18.15.09/eMMC.burn.img

if [ ! -f "uboot.img" ] || [ ! -f "AmlImg" ]; then
  echo "❌ 下载工具失败"
  exit 1
fi

./AmlImg unpack ./uboot.img burn/

# ========= 暴力侦察 =========
echo "=== 开始扫描 bin/targets 目录 ==="
find openwrt/bin/targets/ -type f
echo "================================"

# 自动匹配任何可能带有 rootfs / tar / gz 的文件（排除掉 sha 校验文件和内核文件）
rootfs_tar=$(find openwrt/bin/targets/ -type f \( -name "*.tar.gz" -o -name "*.tar" -o -name "*.rootfs*" \) ! -name "*kernel*" ! -name "*sha256*" | head -n 1)

if [ -z "$rootfs_tar" ]; then
    echo "❌ 找不到根文件系统包，请把上面扫描到的文件列表发给我。"
    exit 1
fi

echo "✅ 找到根文件系统: $rootfs_tar"

boot_img="openwrt.img"
sudo rm -rf ${boot_img} rootfs_mnt
sudo dd if=/dev/zero of=${boot_img} bs=1M count=2000
sudo mkfs.ext4 ${boot_img}
sudo mkdir rootfs_mnt
sudo mount ${boot_img} rootfs_mnt

# 不管三七二十一，看后缀解压
if [[ "$rootfs_tar" == *.gz ]]; then
    echo "正在解压 .gz 文件..."
    sudo tar -xzf "$rootfs_tar" -C rootfs_mnt || sudo gunzip -c "$rootfs_tar" | sudo tar -xf - -C rootfs_mnt
else
    echo "正在解压 .tar 文件..."
    sudo tar -xf "$rootfs_tar" -C rootfs_mnt || sudo cp -rf "$rootfs_tar"/* rootfs_mnt/ || sudo cp -rf "$rootfs_tar" rootfs_mnt/
fi

sudo sync
sudo umount rootfs_mnt

sudo img2simg ${boot_img} burn/rootfs.simg
sudo img2simg ${boot_img} burn/boot.simg

sudo rm -rf ${boot_img} rootfs_mnt

cat <<EOF > burn/commands.txt
PARTITION:boot:sparse:boot.simg
PARTITION:rootfs:sparse:rootfs.simg
EOF

burnimg="openwrt/bin/targets/amlogic/meson8b/OneCloud.burn.img"

./AmlImg pack $burnimg burn/

for f in openwrt/bin/targets/*.burn.img; do
  if [ -f "$f" ]; then
    sha256sum "$f" >"${f}.sha"
    xz -9 --threads=0 --compress "$f"
  fi
done

mv openwrt/bin/targets/*/*.burn.img.xz openwrt/bin/targets/ 2>/dev/null || true
mv openwrt/bin/targets/*.burn.img.xz openwrt/bin/targets/ 2>/dev/null || true
