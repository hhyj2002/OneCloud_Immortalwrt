#!/bin/bash
#===============================================================================
# convert2.sh —— 玩客云(OneCloud / Amlogic Meson8b) USB 直刷包(burn.img)生成
#
# 产物: openwrt/bin/targets/*/*/*.burn.img  +  *.burn.img.sha  +  *.burn.img.xz
#
# 【本版核心修复：解决 USB_Burning_Tool "校验错误"】
#
#   USB_Burning_Tool 烧完最后一个分区后，会按烧录包自带的校验信息做一次回读校验：
#     a) image.cfg 中 [LIST_VERIFY] 段列出的分区；
#     b) 容器里与分区同名的 VERIFY 项（内容就是一行 "sha1sum <40位hash>"）。
#   我们追加的 boot / rootfs 是从 openwrt 产物现场生成的稀疏镜像：
#     - 没有配对的 VERIFY 值；
#     - rootfs 逻辑大小 2GB，回读算 SHA1 必然超时 / 对不上。
#   于是工具在 97%~99% 处报“校验错误”，烧录中断（其实数据已经写完了）。
#   手工用 Multi_Image_Kitchen 删掉 image.cfg 里的 [LIST_VERIFY] 行，就是让工具
#   跳过这次回读校验，所以能烧成功。
#
#   本脚本在 AmlImg pack 之前自动完成同样的动作，并且更彻底：
#     1) 找 image.cfg（解包后叫 "N.image_cfg.conf"），删除其中的 [LIST_VERIFY] 段头，
#        让这些条目并入 [LIST_NORMAL]，同时清掉行内的 verify="..." 属性；
#     2) 从 commands.txt 中丢弃所有 VERIFY: 项 —— 没有校验基准值，工具不会再对
#        任何分区发起 SHA1 回读；
#     3) 打包后自动回读成品自检：只要还残留 [LIST_VERIFY] 或 VERIFY 项，
#        或缺少 boot/rootfs 分区，就直接失败退出，不再上传“带病的包”。
#
#   想保留校验(自用调试)：KEEP_VERIFY=1 ./convert2.sh
#   只想去掉 image.cfg 里的段头、保留 VERIFY 项：DROP_VERIFY_ITEMS=0 ./convert2.sh
#
# 用法:
#   ./Scripts/convert2.sh                 完整流程：编译产物 -> burn.img.xz
#   ./Scripts/convert2.sh patch <dir>     只对已解包目录做“去校验”补丁
#   ./Scripts/convert2.sh check <img>     只检查某个 burn.img 是否符合要求
#===============================================================================

set -euo pipefail

# ------------------------------ 可调参数 --------------------------------------
AMLIMG_VER="${AMLIMG_VER:-v0.3.2}"
UBOOT_IMG_URL="${UBOOT_IMG_URL:-https://github.com/rmoyulong/u-boot-onecloud/releases/download/Onecloud_Uboot_23.12.24_18.15.09/eMMC.burn.img}"
# 换用自己的 uboot 直刷包：
#   UBOOT_IMG_URL="https://github.com/hhyj2002/u-boot-onecloud/releases/download/<tag>/eMMC.burn.img" ./convert2.sh

BOOT_SIZE_MB="${BOOT_SIZE_MB:-2000}"      # boot 分区镜像大小(MB)，与原脚本一致
KEEP_VERIFY="${KEEP_VERIFY:-0}"           # 1 = 完全保留烧录后 SHA1 校验（不推荐）
DROP_VERIFY_ITEMS="${DROP_VERIFY_ITEMS:-1}"  # 1 = 同时丢弃容器里的 VERIFY 项

BASE_DIR="${BASE_DIR:-${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}}"

log()  { printf '\033[32m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

#===============================================================================
# 去掉烧录包里的“回读校验”信息
#   $1 = AmlImg unpack 出来的目录（含 commands.txt 及各 item 文件）
#===============================================================================
patch_burn_dir() {
    local dir="$1"
    [ -d "$dir" ]                    || die "目录不存在: $dir"
    [ -f "$dir/commands.txt" ]       || die "$dir/commands.txt 缺失，不是有效的 AmlImg 解包目录"

    if [ "$KEEP_VERIFY" = "1" ]; then
        warn "KEEP_VERIFY=1 —— 保留烧录后 SHA1 校验，大固件很可能再次报“校验错误”"
        return 0
    fi

    # ---- 1) image.cfg: 删掉 [LIST_VERIFY] 段头 -------------------------------
    # unpack 出来的文件名是 "<id>.<Name>.<Type>"，例如 4.image_cfg.conf，
    # 用通配匹配以兼容不同来源的 uboot 包（有的有 image.cfg，有的压根没有）。
    local cfg found=0 n
    shopt -s nullglob
    for cfg in "$dir"/*image*cfg* "$dir"/*IMAGE*CFG*; do
        [ -f "$cfg" ] || continue
        case "$cfg" in *.bak) continue ;; esac
        if grep -qi 'LIST_VERIFY' "$cfg"; then
            cp -f "$cfg" "$cfg.bak"
            # ① 段头整行删除：其下的 file="xxx" 条目自动并入上一节 [LIST_NORMAL]
            grep -vi 'LIST_VERIFY' "$cfg.bak" > "$cfg"
            # ② 兜底清掉行内校验属性 verify="xxx" / verify=xxx
            sed -i -E 's/[[:space:]]+verify="[^"]*"//g; s/[[:space:]]+verify=[^[:space:]]+//g' "$cfg"
            log "已从 $(basename "$cfg") 移除 [LIST_VERIFY] 段（差异见 $(basename "$cfg").bak）"
            found=1
        fi
    done
    shopt -u nullglob
    [ "$found" = "1" ] || log "该 uboot 包内没有 image.cfg/[LIST_VERIFY]，跳过第 1 步"

    # ---- 2) commands.txt: 丢弃所有 VERIFY: 项 --------------------------------
    # 没有 VERIFY 项 = 工具没有 SHA1 基准值 = 不会发起回读校验。
    # 用过滤而不是逐条删除，原有 item 顺序（0、1、2…）保持不变。
    if [ "$DROP_VERIFY_ITEMS" = "1" ] && grep -q '^VERIFY:' "$dir/commands.txt"; then
        n=$(grep -c '^VERIFY:' "$dir/commands.txt")
        cp -f "$dir/commands.txt" "$dir/commands.txt.bak"
        grep -v '^VERIFY:' "$dir/commands.txt.bak" > "$dir/commands.txt"
        log "已移除 $n 个 VERIFY 项"
    fi

    log "补丁后 commands.txt:"
    sed 's/^/    /' "$dir/commands.txt"
}

#===============================================================================
# 成品自检：回读 burn.img，确认里面不再有校验信息
#   $1 = 生成的 *.burn.img   （需在 BASE_DIR 下有可执行的 AmlImg）
#===============================================================================
check_burn_img() {
    local img="$1" tmp bad=0
    [ -f "$img" ] || die "找不到待检查的文件: $img"

    tmp="$(mktemp -d)"
    if ! ./AmlImg unpack "$img" "$tmp" >/dev/null 2>&1; then
        rm -rf "$tmp"; die "回读失败，烧录包结构异常: $img"
    fi

    if grep -q '^VERIFY:' "$tmp/commands.txt"; then
        warn "成品中仍残留 VERIFY 项:"; grep '^VERIFY:' "$tmp/commands.txt" >&2; bad=1
    fi
    if grep -rli 'LIST_VERIFY' "$tmp" >/dev/null 2>&1; then
        warn "成品中仍残留 [LIST_VERIFY]:"; grep -rli 'LIST_VERIFY' "$tmp" >&2; bad=1
    fi
    grep -q '^PARTITION:boot:'   "$tmp/commands.txt" || { warn "缺少 boot 分区项";   bad=1; }
    grep -q '^PARTITION:rootfs:' "$tmp/commands.txt" || { warn "缺少 rootfs 分区项"; bad=1; }

    if [ "$bad" != "0" ]; then
        rm -rf "$tmp"; die "自检未通过，该包烧录时仍会触发“校验错误”: $img"
    fi

    log "自检通过: $(basename "$img") 无 [LIST_VERIFY] / VERIFY 项，boot + rootfs 齐全"
    log "分区清单:"
    grep '^PARTITION:' "$tmp/commands.txt" | sed 's/^/    /'
    rm -rf "$tmp"
}

#===============================================================================
# 子命令
#===============================================================================
case "${1:-build}" in
  patch) cd "$BASE_DIR"; patch_burn_dir "${2:?用法: convert2.sh patch <dir>}"; exit 0 ;;
  check) cd "$BASE_DIR"; check_burn_img "${2:?用法: convert2.sh check <img>}"; exit 0 ;;
  build) : ;;
  *)     die "未知子命令: $1（可用: build / patch / check）" ;;
esac

#===============================================================================
# 主流程
#===============================================================================
cd "$BASE_DIR"
log "工作目录: $BASE_DIR"

# ---- 0. 依赖 ----------------------------------------------------------------
if ! command -v img2simg >/dev/null 2>&1; then
    log "安装 img2simg (android-sdk-libsparse-utils)"
    sudo apt-get update -qq
    sudo apt-get install -y -qq android-sdk-libsparse-utils
fi
command -v img2simg >/dev/null 2>&1 || die "img2simg 安装失败"

# ---- 1. 工具与 uboot 直刷包 -------------------------------------------------
if [ ! -x ./AmlImg ]; then
    log "下载 AmlImg $AMLIMG_VER"
    curl -fL --retry 3 -o ./AmlImg \
        "https://github.com/rmoyulong/AmlImg/releases/download/${AMLIMG_VER}/AmlImg_${AMLIMG_VER}_linux_amd64"
    chmod +x ./AmlImg
fi

if [ ! -f ./uboot.img ]; then
    log "下载 uboot 直刷包"
    curl -fL --retry 3 -o ./uboot.img "$UBOOT_IMG_URL"
fi

# ---- 2. 解包（必须先清空 burn/，否则上次残留文件会被一起打进包） ------------
sudo rm -rf burn
./AmlImg unpack ./uboot.img burn/
log "解包完成，原始内容:"
sed 's/^/    /' burn/commands.txt

# ---- 3. 去掉回读校验（核心修复） --------------------------------------------
patch_burn_dir burn

# ---- 4. 用 openwrt 产物制作 boot / rootfs 稀疏镜像 ---------------------------
shopt -s nullglob
for f in openwrt/bin/targets/*/*/*.img.gz; do gzip -df "$f"; done
shopt -u nullglob

diskimg="$(find openwrt/bin/targets -type f -name '*.img' ! -name '*.burn.img' | head -n 1)"
[ -n "$diskimg" ] || die "找不到编译产物 *.img（请确认 CONFIG_TARGET_ROOTFS_EXT4FS=y）"
log "源镜像: $diskimg"

boot_img="openwrt.img"
boot_mnt="xd"
rootfs_mnt="img"

loop="$(sudo losetup --find --show --partscan "$diskimg")"
[ -n "$loop" ] || die "losetup 失败"
log "loop 设备: $loop"

cleanup_loop() {
    sudo umount -l "$boot_mnt"   2>/dev/null || true
    sudo umount -l "$rootfs_mnt" 2>/dev/null || true
    sudo losetup -d "$loop"      2>/dev/null || true
}
trap cleanup_loop EXIT

log "创建 ${BOOT_SIZE_MB}MB boot 分区镜像"
sudo rm -rf "$boot_img" "$boot_mnt" "$rootfs_mnt"
sudo dd if=/dev/zero of="$boot_img" bs=1M count="$BOOT_SIZE_MB" status=none
sudo mkfs.ext4 -q -F "$boot_img"
sudo mkdir -p "$boot_mnt" "$rootfs_mnt"
sudo mount "$boot_img"   "$boot_mnt"
sudo mount "${loop}p2"   "$rootfs_mnt"

# 把 rootfs 整棵树拷进 boot 镜像（玩客云单分区启动方式）
sudo cp -a "$rootfs_mnt"/. "$boot_mnt"/
sudo rm -rf "$boot_mnt/lost+found"
sudo sync

log "生成稀疏镜像 boot.simg / rootfs.simg"
sudo img2simg "${loop}p1"  burn/boot.simg
sudo img2simg "$boot_img"  burn/rootfs.simg

sudo umount "$boot_mnt"
sudo umount "$rootfs_mnt"
sudo losetup -d "$loop"
trap - EXIT

sudo rm -rf "$boot_img" "$boot_mnt" "$rootfs_mnt"

# ---- 5. 追加分区项 ----------------------------------------------------------
cat <<'EOF' >> burn/commands.txt
PARTITION:boot:sparse:boot.simg
PARTITION:rootfs:sparse:rootfs.simg
EOF

# ---- 6. 打包 ----------------------------------------------------------------
prefix="$(echo "$diskimg" | sed 's/\.img$//')"
burnimg="${prefix}.burn.img"

log "打包 => $burnimg"
./AmlImg pack "$burnimg" burn/

# ---- 7. 自检（不通过就中断，避免上传坏包） ----------------------------------
check_burn_img "$burnimg"

# ---- 8. 校验文件与压缩 ------------------------------------------------------
( cd "$(dirname "$burnimg")" && sha256sum "$(basename "$burnimg")" > "$(basename "$burnimg").sha" )
xz -9 --threads=0 --compress -f "$burnimg"

# ---- 9. 清理源镜像（保留 burn/ 便于排查） -----------------------------------
sudo rm -f openwrt/bin/targets/*/*/*.img openwrt/bin/targets/*/*/*.img.gz 2>/dev/null || true
log "完成: ${burnimg}.xz"
ls -lh "$(dirname "$burnimg")" | sed 's/^/    /'
