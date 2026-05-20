#!/bin/bash
# BOSS-BOX 开发环境设置脚本

set -e

echo "🚀 开始设置 BOSS-BOX 开发环境..."

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then 
    echo "⚠️  请使用 sudo 运行此脚本"
    exit 1
fi

# 检查操作系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
else
    echo "❌ 无法检测操作系统"
    exit 1
fi

echo "📦 检测到系统: $OS $VER"

# 安装依赖
echo "📦 安装系统依赖..."
if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
    apt-get update
    apt-get install -y \
        git \
        curl \
        wget \
        build-essential \
        python3 \
        python3-pip \
        python3-venv \
        docker.io \
        live-build \
        debootstrap \
        xorriso \
        isolinux \
        syslinux-efi \
        grub-pc-bin \
        grub-efi-amd64-bin \
        mtools \
        dosfstools \
        squashfs-tools \
        cryptsetup
    
elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Rocky"* ]] || [[ "$OS" == *"Fedora"* ]]; then
    dnf install -y \
        git \
        curl \
        wget \
        python3 \
        python3-pip \
        docker \
        livecd-tools \
        syslinux \
        grub2-efi-x64 \
        grub2-pc \
        xorriso \
        dosfstools \
        squashfs-tools \
        cryptsetup
    
else
    echo "❌ 不支持的操作系统: $OS"
    echo "请手动安装依赖包"
    exit 1
fi

# 创建虚拟环境
echo "🐍 设置 Python 虚拟环境..."
python3 -m venv venv
source venv/bin/activate

# 安装 Python 依赖
echo "📦 安装 Python 依赖..."
pip install --upgrade pip
pip install -r requirements.txt 2>/dev/null || pip install \
    requests \
    pyyaml \
    jinja2 \
    tqdm

# 创建必要的目录
echo "📁 创建项目目录..."
mkdir -p build/{iso,img,logs}
mkdir -p configs/{syslinux,grub,packages}
mkdir -p tests/{unit,integration,hardware}

# 下载基础镜像
echo "⬇️  下载 Ubuntu Core 基础..."
if [ ! -f "build/ubuntu-core-24.04-base.tar.gz" ]; then
    wget -O build/ubuntu-core-24.04-base.tar.gz \
        https://cdimage.ubuntu.com/ubuntu-core/24/stable/current/ubuntu-core-24.04-amd64.img.xz
    xz -d build/ubuntu-core-24.04-base.tar.gz
fi

# 设置 Docker（用于构建环境）
echo "🐳 设置 Docker..."
systemctl enable --now docker
usermod -aG docker $SUDO_USER

# 克隆子模块
echo "🔗 初始化子模块..."
git submodule update --init --recursive 2>/dev/null || echo "无子模块"

# 设置 Ollama 环境
echo "🤖 设置 Ollama 环境..."
mkdir -p build/ollama
if [ ! -f "build/ollama/ollama" ]; then
    echo "下载 Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
fi

# 创建默认配置文件
echo "⚙️  创建配置文件..."
cat > configs/build.conf << EOF
# BOSS-BOX 构建配置
PROJECT_NAME="BOSS-BOX"
VERSION="0.1.0"
BUILD_DATE="$(date +%Y%m%d)"
ARCH="amd64"

# 系统配置
BASE_SYSTEM="ubuntu-core-24.04"
HOSTNAME="bossbox"
USERNAME="boss"
PASSWORD=\$(openssl rand -base64 12)

# 分区配置
DISK_SIZE="16G"  # 最终镜像大小
BOOT_SIZE="512M"
ROOT_SIZE="12G"
DATA_SIZE="3G"

# 加密配置
ENCRYPT_ROOT="yes"
ENCRYPT_DATA="yes"
LUKS_KEYFILE="/etc/luks.key"

# 网络配置
NETWORK_MANAGER="network-manager"
WIFI_SUPPORT="yes"

# 软件包配置
PACKAGES="
  linux-image-generic
  systemd
  network-manager
  openssh-server
  python3
  python3-pip
  curl
  wget
  git
  vim
  htop
"

# AI 配置
AI_MODEL="qwen2.5:1.5b"
AI_PORT="11434"
AI_MEMORY="4G"
EOF

# 设置权限
echo "🔐 设置文件权限..."
chmod +x scripts/*.sh
chown -R $SUDO_USER:$SUDO_USER .

# 完成
echo ""
echo "✅ 开发环境设置完成！"
echo ""
echo "接下来可以："
echo "1. 查看构建配置: cat configs/build.conf"
echo "2. 构建测试镜像: ./scripts/build-iso.sh"
echo "3. 运行测试: ./scripts/run-tests.sh"
echo ""
echo "💡 提示：重新登录以使 Docker 组权限生效"