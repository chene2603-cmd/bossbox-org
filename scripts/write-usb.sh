#!/bin/bash
# BOSS-BOX U盘写入工具

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 显示横幅
show_banner() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════╗"
    echo "║         BOSS-BOX U盘写入工具           ║"
    echo "║      The Private AI on a USB Stick      ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}❌ 请使用 sudo 运行此脚本${NC}"
        exit 1
    fi
}

# 显示磁盘信息
show_disks() {
    echo -e "${YELLOW}📀 检测到的磁盘设备：${NC}"
    echo ""
    
    # 获取磁盘信息
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL | grep -E "^(NAME|sd|nvme|mmc)" | while read line; do
        if [[ $line == NAME* ]]; then
            echo -e "${GREEN}$line${NC}"
        elif [[ $line == *"disk"* ]]; then
            echo -e "  ${BLUE}$line${NC}"
        elif [[ $line == *"part"* ]]; then
            echo "    $line"
        fi
    done
    
    echo ""
}

# 选择磁盘设备
select_disk() {
    while true; do
        read -p "请输入要写入的设备（如 /dev/sdb）: " DEVICE
        
        if [ -z "$DEVICE" ]; then
            echo -e "${RED}❌ 设备不能为空${NC}"
            continue
        fi
        
        if [ ! -b "$DEVICE" ]; then
            echo -e "${RED}❌ 设备 $DEVICE 不存在${NC}"
            continue
        fi
        
        # 检查是否是整个磁盘（不是分区）
        if [[ "$DEVICE" =~ [0-9]$ ]]; then
            echo -e "${RED}❌ 请选择整个磁盘设备，而不是分区（如 /dev/sdb 而不是 /dev/sdb1）${NC}"
            continue
        fi
        
        # 显示确认信息
        echo ""
        echo -e "${RED}⚠️  ⚠️  ⚠️  警告！⚠️  ⚠️  ⚠️${NC}"
        echo -e "${RED}设备 $DEVICE 上的所有数据将被永久删除！${NC}"
        echo ""
        
        read -p "确认要写入 $DEVICE 吗？(yes/no): " CONFIRM
        if [ "$CONFIRM" = "yes" ] || [ "$CONFIRM" = "y" ]; then
            break
        else
            echo "操作已取消"
            exit 0
        fi
    done
}

# 选择ISO文件
select_iso() {
    ISO_DIR="build/iso"
    
    if [ ! -d "$ISO_DIR" ]; then
        echo -e "${YELLOW}📦 未找到构建的ISO，正在搜索...${NC}"
        ISO_DIR="."
    fi
    
    # 查找ISO文件
    ISOS=($(find "$ISO_DIR" -name "*.iso" -type f 2>/dev/null))
    
    if [ ${#ISOS[@]} -eq 0 ]; then
        echo -e "${RED}❌ 未找到ISO文件${NC}"
        echo "请先运行 ./scripts/build-iso.sh 构建镜像"
        exit 1
    fi
    
    echo -e "${GREEN}📁 找到的ISO文件：${NC}"
    echo ""
    
    for i in "${!ISOS[@]}"; do
        SIZE=$(du -h "${ISOS[$i]}" | cut -f1)
        echo "  $((i+1)). ${ISOS[$i]##*/} ($SIZE)"
    done
    
    echo ""
    
    while true; do
        read -p "请选择ISO文件编号 (1-${#ISOS[@]}): " CHOICE
        
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le ${#ISOS[@]} ]; then
            SELECTED_ISO="${ISOS[$((CHOICE-1))]}"
            break
        else
            echo -e "${RED}❌ 无效选择${NC}"
        fi
    done
    
    echo -e "${GREEN}✅ 选择: $SELECTED_ISO${NC}"
}

# 写入模式选择
select_mode() {
    echo ""
    echo -e "${YELLOW}🔧 选择写入模式：${NC}"
    echo "  1. 快速模式 (dd，默认)"
    echo "  2. 增强模式 (持久化存储)"
    echo "  3. 双启动模式 (Linux + Windows)"
    echo ""
    
    read -p "请选择模式 (1-3): " MODE_CHOICE
    
    case $MODE_CHOICE in
        2)
            MODE="enhanced"
            echo -e "${GREEN}✅ 选择增强模式${NC}"
            ;;
        3)
            MODE="dual"
            echo -e "${GREEN}✅ 选择双启动模式${NC}"
            ;;
        *)
            MODE="fast"
            echo -e "${GREEN}✅ 选择快速模式${NC}"
            ;;
    esac
}

# 快速模式写入
write_fast() {
    echo ""
    echo -e "${YELLOW}🚀 开始快速写入...${NC}"
    echo "设备: $DEVICE"
    echo "ISO: $SELECTED_ISO"
    echo ""
    
    # 卸载所有分区
    for partition in $(lsblk -lnpo NAME "$DEVICE" | grep -E "${DEVICE}[0-9]+"); do
        if mountpoint -q "$partition" || findmnt "$partition" >/dev/null 2>&1; then
            echo "卸载分区: $partition"
            umount "$partition" 2>/dev/null || true
        fi
    done
    
    # 使用dd写入
    echo -e "${RED}⚠️  正在写入，请不要移除设备或断电...${NC}"
    echo "这可能需要几分钟，请耐心等待..."
    
    if dd if="$SELECTED_ISO" of="$DEVICE" bs=4M status=progress oflag=sync; then
        echo -e "${GREEN}✅ 写入完成！${NC}"
        sync
    else
        echo -e "${RED}❌ 写入失败${NC}"
        exit 1
    fi
}

# 增强模式写入
write_enhanced() {
    echo ""
    echo -e "${YELLOW}🔧 准备增强模式写入...${NC}"
    
    # 创建持久化存储
    TOTAL_SIZE=$(lsblk -b -n -o SIZE "$DEVICE" | head -1)
    PERSISTENT_SIZE=$((TOTAL_SIZE * 70 / 100))  # 70%用于持久化
    
    # 使用gdisk分区
    echo "创建分区表..."
    parted "$DEVICE" mklabel gpt
    
    # 创建EFI分区
    parted "$DEVICE" mkpart primary fat32 1MiB 513MiB
    parted "$DEVICE" set 1 esp on
    
    # 创建系统分区
    parted "$DEVICE" mkpart primary 514MiB 3GiB
    
    # 创建持久化分区
    parted "$DEVICE" mkpart primary 3GiB 100%
    
    # 格式化分区
    echo "格式化分区..."
    mkfs.fat -F32 "${DEVICE}1"
    mkfs.ext4 "${DEVICE}2"
    mkfs.ext4 "${DEVICE}3" -L "persistent"
    
    # 挂载并复制文件
    echo "复制系统文件..."
    TEMP_MNT=$(mktemp -d)
    
    # 挂载ISO
    mount -o loop "$SELECTED_ISO" "$TEMP_MNT"
    
    # 挂载EFI分区
    mkdir -p "$TEMP_MNT/efi"
    mount "${DEVICE}1" "$TEMP_MNT/efi"
    
    # 复制EFI文件
    cp -r "$TEMP_MNT/EFI" "$TEMP_MNT/efi/"
    cp -r "$TEMP_MNT/boot" "$TEMP_MNT/efi/"
    
    # 挂载系统分区
    mkdir -p "$TEMP_MNT/system"
    mount "${DEVICE}2" "$TEMP_MNT/system"
    
    # 提取squashfs
    unsquashfs -f -d "$TEMP_MNT/system" "$TEMP_MNT/casper/filesystem.squashfs"
    
    # 安装grub
    grub-install --target=x86_64-efi --efi-directory="$TEMP_MNT/efi" --boot-directory="$TEMP_MNT/efi/boot" --removable
    
    # 清理
    umount "$TEMP_MNT/efi"
    umount "$TEMP_MNT/system"
    umount "$TEMP_MNT"
    rm -rf "$TEMP_MNT"
    
    echo -e "${GREEN}✅ 增强模式写入完成！${NC}"
}

# 验证写入
verify_write() {
    echo ""
    echo -e "${YELLOW}🔍 验证写入...${NC}"
    
    # 检查设备是否可读
    if dd if="$DEVICE" bs=512 count=1 2>/dev/null | file - | grep -q "DOS/MBR boot sector"; then
        echo -e "${GREEN}✅ 启动扇区验证通过${NC}"
    else
        echo -e "${YELLOW}⚠️  启动扇区可能有问题${NC}"
    fi
    
    # 显示分区信息
    echo ""
    echo -e "${GREEN}📊 最终分区信息：${NC}"
    fdisk -l "$DEVICE" | grep -A 20 "Disk $DEVICE"
    
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}🎉 BOSS-BOX 已成功写入U盘！${NC}"
    echo ""
    echo "下一步操作："
    echo "1. 安全弹出U盘"
    echo "2. 将U盘插入目标电脑"
    echo "3. 开机时按 F12/F10/Del 进入启动菜单"
    echo "4. 选择从U盘启动"
    echo "5. 开始使用 BOSS-BOX！"
    echo -e "${BLUE}══════════════════════════════════════════════${NC}"
}

# 主函数
main() {
    show_banner
    check_root
    show_disks
    select_disk
    select_iso
    select_mode
    
    case $MODE in
        "fast")
            write_fast
            ;;
        "enhanced")
            write_enhanced
            ;;
        "dual")
            echo -e "${YELLOW}🚧 双启动模式开发中...${NC}"
            echo "暂时使用快速模式"
            write_fast
            ;;
    esac
    
    verify_write
}

# 运行主函数
main "$@"