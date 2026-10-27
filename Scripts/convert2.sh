#!/bin/bash
set -x # 开启调试打印，可以在日志里看到执行过程

sudo apt update && sudo apt install -y android-sdk-libsparse-utils
ver="v0.3.2"

# 下载工具
curl -L -o ./AmlImg https://github.com/rmoyulong/AmlImg/releases/download/$ver/AmlImg_${ver}_linux_amd64
chmod +x ./AmlImg
curl -L -o ./uboot.img https://github.com/rmoyulong/u-boot-onecloud/releases/download/Onecloud_Uboot_23.12.24_18.15.09/eMMC.burn.img

if [ ! -f "uboot.img" ] || [ ! -f "AmlImg" ]; then
  echo "❌ 下载工具失败"
  exit 1
fi

./AmlImg unpack ./uboot.img burn/

# ========= 核心修改：寻找根文件系统并自己造镜像 =========
# 寻找编译生成的 rootfs tar 压缩包
rootfs_tar=$(find openwrt/bin/targets/ -name "*rootfs.tar.gz" | head -n 1)

if [ -z "$rootfs_tar" ]; then
    echo "❌ 找不到 rootfs.tar.gz，编译肯定失败了，请检查上方日志。"
    exit 1
fi

echo "✅ 找到根文件系统: $rootfs_tar"

# 制作一个 2GB 的空磁盘镜像
boot_img="openwrt.img"
sudo rm -rf ${boot_img} rootfs_mnt
sudo dd if=/dev/zero of=${boot_img} bs=1M count=2000
sudo mkfs.ext4 ${boot_img}
sudo mkdir rootfs_mnt
sudo mount ${boot_img} rootfs_mnt

# 解压 rootfs 到空磁盘里
sudo tar -xzf "$rootfs_tar" -C rootfs_mnt
sudo sync
sudo umount rootfs_mnt

# 使用 img2simg 转换为稀疏镜像
sudo img2simg ${boot_img} burn/rootfs.simg
# 玩客云标准的直刷包逻辑
sudo img2simg ${boot_img} burn/boot.simg

# 清理文件
sudo rm -rf ${boot_img} rootfs_mnt

# 写入分区表指令
cat <<EOF > burn/commands.txt
PARTITION:boot:sparse:boot.simg
PARTITION:rootfs:sparse:rootfs.simg
EOF

# 打包
prefix=$(basename $(dirname "$rootfs_tar"))_$(basename "$rootfs_tar" .tar.gz | sed 's/-rootfs//')
burnimg="openwrt/bin/targets/${prefix}.burn.img"
./AmlImg pack $burnimg burn/

# 压缩并计算哈希
for f in openwrt/bin/targets/*.burn.img; do
  if [ -f "$f" ]; then
    sha256sum "$f" >"${f}.sha"
    xz -9 --threads=0 --compress "$f"
  fi
done

# 把生成的 burn.img.xz 移动到 targets 目录下，方便 yml 抓取
mv openwrt/bin/targets/*/*.burn.img.xz openwrt/bin/targets/ 2>/dev/null || true
mv openwrt/bin/targets/*.burn.img.xz openwrt/bin/targets/ 2>/dev/null || true
