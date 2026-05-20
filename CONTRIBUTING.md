# 🤝 贡献指南

欢迎参与 BOSS-BOX 开源项目！以下是参与贡献的指南。

## 🎯 如何开始

1. **Fork 仓库**
   - 点击右上角 Fork 按钮
   - 克隆你的 fork: `git clone https://github.com/YOUR_USERNAME/bossbox-core.git`

2. **设置开发环境**
bash

cd bossbox-core

./scripts/setup-dev.sh
3. **选择任务**
- 查看 [Good First Issues](https://github.com/bossbox-org/bossbox-core/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
- 查看 [Help Wanted](https://github.com/bossbox-org/bossbox-core/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22)

## 📁 项目结构
bossbox-core/

├── scripts/              # 构建和部署脚本

├── configs/             # 配置文件

├── docs/               # 文档

├── tests/              # 测试代码

├── build/              # 构建输出

└── .github/            # GitHub Actions
## 🚀 开发工作流

### 1. 创建功能分支
bash

git checkout -b feature/your-feature-name
### 2. 提交变更
bash

git add .

git commit -m "feat: 添加xx功能"

git push origin feature/your-feature-name
### 3. 创建 Pull Request
- 在 GitHub 创建 PR
- 描述你的变更
- 链接相关 Issues
- 等待代码审查

## 📝 提交规范

我们使用 Conventional Commits 规范：

- `feat:` 新功能
- `fix:` bug修复
- `docs:` 文档更新
- `style:` 代码格式
- `refactor:` 代码重构
- `test:` 测试相关
- `chore:` 构建/工具

示例：
feat: 添加LUKS全盘加密支持

fix: 修复U盘启动兼容性问题

docs: 更新快速开始指南
## 🧪 测试要求

- 新功能必须包含测试
- 确保现有测试通过
- 运行测试: `./scripts/run-tests.sh`

## 🎯 开发优先级

### P0 (最高)
- U盘启动兼容性
- 基础AI对话功能
- 数据加密安全

### P1 (高)
- 业务插件开发
- 手机无线访问
- 性能优化

### P2 (中)
- 更多模型支持
- 插件市场
- 企业功能

## 📚 学习资源

- [Ubuntu Core 文档](https://ubuntu.com/core/docs)
- [Ollama 使用指南](https://github.com/ollama/ollama)
- [Tauri 开发指南](https://tauri.app/)
- [LUKS 加密配置](https://wiki.archlinux.org/title/Dm-crypt)

## ❓ 获取帮助

- 查看 [讨论区](https://github.com/bossbox-org/bossbox-core/discussions)
- 加入 [Telegram 群组](链接)
- 查看 [Wiki](https://github.com/bossbox-org/bossbox-core/wiki)

## 🙏 致谢

感谢每一位贡献者！你的代码将帮助成千上万的中小企业主。
