
#!/bin/bash

# 用法:
#   ./convert.sh                 -> 使用下面 SRC 变量配置的"精简版(非 docker)"固件
#   ./convert.sh 0  或  1        -> 同上(兼容旧 yml 的编号入参，统一走 SRC)
#   ./convert.sh <URL或.img.gz>  -> 直接转换你指定的镜像
#
# 作用: 把已编译好的 OpenWrt 镜像(.img.gz) + 玩客云 U-Boot 打成晶晨 AmlImg 可直刷包(.burn.img)。
# 这是玩客云(meson8b)的刷机机制，与第三方应用 / docker / LuCI 主题无关，故打包管线全部保留。

# ====== 精简版固件来源(去 docker 后请填你自己编译产出的非 docker 镜像 URL) ======
SRC="https://github.com/hhyj2002/OneCloud_Immortalwrt/releases/download/你的tag/immortalwrt-meson-meson8b-thunder-onecloud-ext4-squashfs-sysupgrade.tar"

if [ ! -z "$1" ];then
	idtype=$1
fi

sudo apt install -y android-sdk-libsparse-utils
ver="v0.3.2"
curl -L -o ./AmlImg https://github.com/rmoyulong/AmlImg/releases/download/$ver/AmlImg_${ver}_linux_amd64
chmod +x ./AmlImg
curl -L -o ./uboot.img https://github.com/rmoyulong/u-boot-onecloud/releases/download/Onecloud_Uboot_23.12.24_18.15.09/eMMC.burn.img
rm -rf openwrt/upload
mkdir -p openwrt/upload

# 去 docker: 原 0/1 编号对应的 hub docker 迷你/正常版镜像已移除。
# 编号 0/1 或空 -> 统一使用 SRC(精简版固件); 传入 URL/路径 -> 直接使用。
if [[ "${idtype}" == "0" || "${idtype}" == "1" || -z "${idtype}" ]]; then
  curl -L -o openwrt/upload/onecloud.img.gz "$SRC"
  echo "使用精简版固件来源: $SRC"
else
  curl -L -o openwrt/upload/onecloud.img.gz "${idtype}"
  echo "使用指定镜像: ${idtype}"
fi

./AmlImg unpack ./uboot.img burn/

gunzip  openwrt/upload/*.gz
diskimg=$(ls openwrt/upload/*.img)
loop=$(sudo losetup --find --show --partscan $diskimg)
img_ext="openwrt.img"
img_mnt="xd"
rootfs_mnt="img"
boot_img=${img_ext}
boot_img_mnt=${img_mnt}
rootfs_img_mnt=${rootfs_mnt}
echo ${boot_img}
echo ${boot_img_mnt}
echo ${rootfs_img_mnt}
sudo rm -rf ${boot_img}
sudo rm -rf ${boot_img_mnt}
sudo rm -rf ${rootfs_img_mnt}
sudo dd if=/dev/zero of=${boot_img} bs=1M count=2000
sudo mkfs.ext4 ${boot_img}
sudo mkdir ${boot_img_mnt}
sudo mkdir ${rootfs_img_mnt}
sudo mount ${boot_img} ${boot_img_mnt}
sudo mount ${loop}p2 ${rootfs_img_mnt}
cd ${rootfs_img_mnt}
sudo cp -r * ../${boot_img_mnt}
cd ..
sudo sync
sudo umount ${boot_img_mnt}
sudo umount ${rootfs_img_mnt}
sudo img2simg ${loop}p1 burn/boot.simg
sudo img2simg openwrt.img burn/rootfs.simg
sudo rm -rf *.img
sudo losetup -d $loop
cat <<EOF >>burn/commands.txt
PARTITION:boot:sparse:boot.simg
PARTITION:rootfs:sparse:rootfs.simg
EOF
prefix=$(ls openwrt/upload/*.img | sed 's/\.img$//')
burnimg=${prefix}.burn.img
./AmlImg pack $burnimg burn/
for f in openwrt/upload/*.burn.img; do
  sha256sum "$f" >"${f}.sha"
  xz -9 --threads=0 --compress "$f"
done
mv ${burnimg}.xz openwrt/upload/openwrt-onecloud_$(date +"%Y-%m-%d_%H_%M")-burn.img.xz
sudo rm -rf openwrt/upload/*.img
sudo rm -rf openwrt/upload/*.gz
