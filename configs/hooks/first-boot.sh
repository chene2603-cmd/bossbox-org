#!/bin/bash
# BOSS-BOX 首次启动脚本
# 在系统首次启动时执行

set -e

LOG_FILE="/var/log/bossbox-first-boot.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================"
echo "BOSS-BOX 首次启动配置"
echo "日期: $(date)"
echo "========================================"

# 等待网络连接
echo "等待网络连接..."
for i in {1..30}; do
    if ping -c 1 -W 1 8.8.8.8 &>/dev/null; then
        echo "网络连接正常"
        break
    fi
    sleep 1
done

# 更新系统
echo "更新系统包列表..."
apt-get update

# 安装 Ollama
if ! command -v ollama &> /dev/null; then
    echo "安装 Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
fi

# 下载模型
echo "下载 AI 模型..."
export OLLAMA_HOST="127.0.0.1"
export OLLAMA_NUM_PARALLEL=1

# 启动 Ollama 服务
systemctl enable ollama
systemctl start ollama

# 等待服务启动
sleep 5

# 拉取模型
echo "正在下载 qwen2.5:1.5b 模型..."
ollama pull qwen2.5:1.5b-instruct-q4_K_M

# 创建数据目录
echo "创建数据目录..."
mkdir -p /opt/bossbox/{data,models,plugins,backups}
chown -R boss:boss /opt/bossbox
chmod 755 /opt/bossbox

# 创建桌面快捷方式
echo "创建桌面快捷方式..."
cat > /home/boss/Desktop/bossbox.desktop << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=BOSS-BOX AI
Comment=Private AI Assistant
Exec=/opt/bossbox/bossbox-app
Icon=/opt/bossbox/icon.png
Terminal=false
Categories=Utility;AI;
EOF

chmod +x /home/boss/Desktop/bossbox.desktop
chown boss:boss /home/boss/Desktop/bossbox.desktop

# 设置自动启动
echo "设置自动启动..."
mkdir -p /home/boss/.config/autostart
cp /home/boss/Desktop/bossbox.desktop /home/boss/.config/autostart/

# 创建启动脚本
cat > /opt/bossbox/start-bossbox.sh << 'EOF'
#!/bin/bash
# BOSS-BOX 启动脚本

# 等待网络
sleep 3

# 启动 Ollama
if ! pgrep ollama > /dev/null; then
    ollama serve &
    sleep 5
fi

# 启动应用
cd /opt/bossbox
./bossbox-app
EOF

chmod +x /opt/bossbox/start-bossbox.sh

# 设置环境变量
echo "设置环境变量..."
cat >> /home/boss/.bashrc << 'EOF'
# BOSS-BOX
export OLLAMA_HOST="127.0.0.1:11434"
export BOSSBOX_HOME="/opt/bossbox"
export PATH="$PATH:$BOSSBOX_HOME/bin"
EOF

# 安全设置
echo "配置安全设置..."
# 禁用root SSH登录
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
# 禁用密码认证
sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# 配置防火墙
echo "配置防火墙..."
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp  # SSH
ufw allow 11434/tcp  # Ollama
ufw allow 3000/tcp  # Web界面
ufw reload

# 创建备份任务
echo "创建备份任务..."
cat > /etc/cron.daily/bossbox-backup << 'EOF'
#!/bin/bash
# 每日备份脚本

BACKUP_DIR="/opt/bossbox/backups"
DATA_DIR="/opt/bossbox/data"
LOG_FILE="/var/log/bossbox-backup.log"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/bossbox_backup_$TIMESTAMP.tar.gz"

echo "[$(date)] 开始备份..." >> "$LOG_FILE"

# 创建备份
tar -czf "$BACKUP_FILE" \
    --exclude="*.tmp" \
    --exclude="*.log" \
    "$DATA_DIR" \
    /home/boss/.config/bossbox 2>> "$LOG_FILE"

if [ $? -eq 0 ]; then
    echo "[$(date)] 备份成功: $BACKUP_FILE" >> "$LOG_FILE"
    
    # 删除7天前的备份
    find "$BACKUP_DIR" -name "bossbox_backup_*.tar.gz" -mtime +7 -delete >> "$LOG_FILE"
else
    echo "[$(date)] 备份失败!" >> "$LOG_FILE"
fi
EOF

chmod +x /etc/cron.daily/bossbox-backup

# 首次启动完成标记
touch /opt/bossbox/.first-boot-complete

echo "========================================"
echo "首次启动配置完成！"
echo "请重启系统以应用所有更改。"
echo "========================================"

# 重启提示
read -p "是否现在重启系统？(y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    reboot
fi