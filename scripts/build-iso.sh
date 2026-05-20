#!/bin/bash
# BOSS-BOX ISO 镜像构建脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 加载配置
CONFIG_FILE="configs/build.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo -e "${RED}❌ 配置文件不存在: $CONFIG_FILE${NC}"
    exit 1
fi

# 参数解析
BUILD_TYPE="full"
OUTPUT_DIR="build/iso"
LOG_DIR="build/logs"
DEBUG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--type)
            BUILD_TYPE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  -t, --type TYPE    构建类型: minimal|full|test (默认: full)"
            echo "  -o, --output DIR   输出目录 (默认: build/iso)"
            echo "  -d, --debug        调试模式"
            echo "  -h, --help         显示此帮助"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ 未知选项: $1${NC}"
            exit 1
            ;;
    esac
done

# 创建目录
mkdir -p "$OUTPUT_DIR"
mkdir -p "$LOG_DIR"
mkdir -p build/{chroot,cache,workspace}

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    exit 1
}

# 检查依赖
check_deps() {
    log_info "检查构建依赖..."
    
    local deps=("lb" "xorriso" "grub-mkrescue" "mksquashfs" "cryptsetup")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "缺少依赖: ${missing[*]}"
    fi
}

# 清理函数
cleanup() {
    log_info "清理临时文件..."
    
    # 卸载可能挂载的目录
    for mount in build/chroot/{dev,proc,sys,run,boot}; do
        if mountpoint -q "$mount"; then
            umount -l "$mount" 2>/dev/null || true
        fi
    done
    
    # 清理临时文件
    rm -rf build/chroot/*
    rm -rf build/workspace/*
    
    log_info "清理完成"
}

# 构建配置
build_config() {
    log_info "生成 live-build 配置..."
    
    CONFIG_DIR="build/config"
    mkdir -p "$CONFIG_DIR"
    
    # 生成 auto/config
    cat > "$CONFIG_DIR/auto/config" << EOF
#!/bin/bash
# 自动配置脚本

# 基本配置
LB_ARCHITECTURES="amd64"
LB_MODE="ubuntu-core"
LB_DISTRIBUTION="noble"
LB_IMAGE_TYPE="iso"
LB_BINARY_IMAGES="iso"
LB_CACHE="true"
LB_CACHE_PACKAGES="true"
LB_MIRROR_BOOTSTRAP="http://archive.ubuntu.com/ubuntu/"
LB_MIRROR_CHROOT="http://archive.ubuntu.com/ubuntu/"
LB_MIRROR_BINARY="http://archive.ubuntu.com/ubuntu/"
LB_BUILD_WITH_CHROOT="true"
LB_BUILD_WITH_TMPFS="true"

# 主机名
LB_HOSTNAME="bossbox"

# 用户名和密码
LB_USERNAME="boss"
LB_USER_FULLNAME="BOSS User"
LB_USER_PASSWORD="boss123"

# 时区
LB_TIMEZONE="Asia/Shanghai"

# 语言
LB_LANGUAGE="en"
LB_KEYBOARD_KEYMAP="us"
LB_KEYBOARD_KEYMAP_TOGGLE=""

# 安全配置
LB_SECURITY="true"
LB_SNAPSHOT="false"

# 软件包
LB_APT_INDICES="false"
LB_APT_RECOMMENDS="false"

# 输出配置
LB_ISO_TITLE="BOSS-BOX"
LB_ISO_VOLUME="BOSS-BOX \$(date +%Y%m%d)"
LB_ISO_APPLICATION="BOSS-BOX Private AI Assistant"
EOF

    # 生成包列表
    cat > "$CONFIG_DIR/config/package-lists/bossbox.list.chroot" << EOF
# 内核和基础
linux-image-generic
linux-modules-extra-generic
systemd
systemd-sysv
udev

# 网络
network-manager
wpasupplicant
iw
wireless-tools
net-tools
curl
wget

# 工具
vim
nano
htop
iotop
lsof
pciutils
usbutils
fdisk
parted
gdisk
cryptsetup
cryptsetup-initramfs
lvm2

# 文件系统
squashfs-tools
dosfstools
exfat-utils
ntfs-3g
btrfs-progs

# 开发
python3
python3-pip
python3-venv
git
build-essential

# 显示
xserver-xorg-core
xinit
openbox
tint2
pcmanfm
lxterminal
feh

# 字体
fonts-dejavu
fonts-wqy-microhei

# 清理
deborphan
localepurge
EOF

    # 生成 GRUB 配置
    mkdir -p "$CONFIG_DIR/config/bootloaders/grub-pc"
    cat > "$CONFIG_DIR/config/bootloaders/grub-pc/grub.cfg" << EOF
set default=0
set timeout=5
set gfxmode=auto
set gfxpayload=keep

menuentry "BOSS-BOX AI Assistant" {
    linux /casper/vmlinuz quiet splash ---
    initrd /casper/initrd
}

menuentry "BOSS-BOX (Safe Mode)" {
    linux /casper/vmlinuz quiet splash nomodeset ---
    initrd /casper/initrd
}

menuentry "Memory Test (memtest86+)" {
    linux16 /memtest86+.bin
}

menuentry "Boot from first hard disk" {
    exit
}
EOF

    log_info "配置生成完成"
}

# 构建镜像
build_iso() {
    log_info "开始构建 ISO 镜像..."
    
    local BUILD_LOG="$LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"
    
    # 进入构建目录
    cd build/config || log_error "构建目录不存在"
    
    # 清理之前的构建
    sudo lb clean --purge 2>/dev/null || true
    
    # 开始构建
    log_info "运行 live-build (详细日志: $BUILD_LOG)"
    
    if [ "$DEBUG" = true ]; then
        sudo lb build 2>&1 | tee "$BUILD_LOG"
    else
        if ! sudo lb build 2>&1 | tee "$BUILD_LOG" | grep -E "(ERROR|FAIL|WARN|INFO:.*error)"; then
            log_info "构建输出已记录到 $BUILD_LOG"
        fi
    fi
    
    # 检查构建结果
    if [ -f "binary.iso" ]; then
        local ISO_NAME="bossbox-${VERSION}-${BUILD_DATE}-${BUILD_TYPE}.iso"
        mv "binary.iso" "../iso/$ISO_NAME"
        cd ..
        
        # 计算文件信息
        local ISO_SIZE=$(du -h "iso/$ISO_NAME" | cut -f1)
        local ISO_MD5=$(md5sum "iso/$ISO_NAME" | cut -d' ' -f1)
        
        log_info "✅ ISO 镜像构建成功！"
        echo "========================================"
        echo "镜像文件: $ISO_NAME"
        echo "文件大小: $ISO_SIZE"
        echo "MD5: $ISO_MD5"
        echo "输出目录: $(pwd)/iso/"
        echo "构建时间: $(date)"
        echo "========================================"
        
        # 生成构建报告
        cat > "iso/build-info.txt" << EOF
BOSS-BOX 构建报告
=================
版本: $VERSION
构建日期: $BUILD_DATE
构建类型: $BUILD_TYPE
系统: $BASE_SYSTEM
架构: $ARCH
主机名: $HOSTNAME
用户名: $USERNAME
加密: $ENCRYPT_ROOT
AI模型: $AI_MODEL
文件: $ISO_NAME
大小: $ISO_SIZE
MD5: $ISO_MD5
构建日志: $BUILD_LOG
EOF
        
    else
        log_error "ISO 镜像构建失败，请查看日志: $BUILD_LOG"
    fi
}

# 主函数
main() {
    log_info "========================================"
    log_info "    BOSS-BOX 镜像构建工具 v$VERSION"
    log_info "========================================"
    
    # 检查依赖
    check_deps
    
    # 清理环境
    cleanup
    
    # 构建配置
    build_config
    
    # 构建镜像
    build_iso
    
    log_info "✅ 构建流程完成！"
    log_info "镜像保存在: $OUTPUT_DIR/"
    log_info "使用以下命令写入U盘:"
    echo "sudo dd if=$OUTPUT_DIR/bossbox-*.iso of=/dev/sdX bs=4M status=progress"
    echo "注意：将 /dev/sdX 替换为你的U盘设备"
}

# 设置退出时清理
trap cleanup EXIT INT TERM

# 运行主函数
main "$@"