# WordTagger

一个基于 SwiftUI 的智能单词标签管理应用，专为学习者设计的多语言词汇管理工具。

## 🚀 项目简介

WordTagger 是一个现代化的词汇管理应用，帮助用户高效地组织、标记和学习不同语言的单词。通过直观的界面和强大的功能，让语言学习变得更加轻松有趣。

## ✨ 核心功能

### 📚 多层级学科管理
- **学科分层**：支持不同学科的词汇分层管理（如：英语、法语、德语等）
- **快速切换**：使用 `Command+K` 快速切换不同学科层
- **可视化界面**：每个学科层都有独特的颜色标识

### 🏷️ 智能标签系统
- **多维标签**：支持词性、难度、主题等多种标签类型
- **标签重命名**：灵活的标签类型显示名称自定义
- **智能搜索**：基于标签的快速检索功能

### 📝 丰富的内容管理
- **单词详情**：包含音标、释义、例句等完整信息
- **Markdown 支持**：使用内置 Vditor 编辑器编写学习笔记
- **图片管理**：支持插入和管理学习相关的图片资源

### 🔍 强大的命令面板
- **快捷操作**：`Command+K` 唤起命令面板
- **智能搜索**：模糊搜索单词、标签、命令
- **键盘导航**：完全支持键盘快捷键操作

### 💾 灵活的数据存储
- **外部存储**：数据存储在用户选择的外部路径
- **数据安全**：使用 Security-Scoped Bookmark 确保文件访问权限
- **数据结构**：JSON 格式存储，便于备份和迁移

## 🛠️ 技术架构

### 前端技术
- **SwiftUI**: 现代化的用户界面框架
- **Combine**: 响应式编程框架
- **WebKit**: 集成 Vditor 编辑器

### 数据管理
- **外部数据管理器**: `ExternalDataManager` 统一管理外部存储
- **响应式存储**: `NodeStore` 使用 `@Published` 属性实现状态同步
- **安全访问**: Security-Scoped Bookmark 技术确保沙盒环境下的文件访问

### 架构模式
- **MVVM**: Model-View-ViewModel 架构
- **单例模式**: 核心数据管理使用单例确保一致性
- **异步编程**: Task/async-await 处理异步操作

## 📂 项目结构

```
WordTagger/
├── WordTagger/
│   ├── Models/           # 数据模型
│   │   ├── Node.swift
│   │   ├── Tag.swift
│   │   └── Layer.swift
│   ├── Views/            # 界面视图
│   │   ├── ContentView.swift
│   │   ├── DetailPanel.swift
│   │   ├── CommandPaletteView.swift
│   │   └── SettingsView.swift
│   ├── Services/         # 业务逻辑
│   │   ├── Store.swift
│   │   ├── ExternalDataManager.swift
│   │   └── CommandParser.swift
│   └── Components/       # 可复用组件
│       ├── VditorWebView.swift
│       └── TagView.swift
├── Resources/            # 资源文件
└── README.md
```

## 🚦 快速开始

### 系统要求
- macOS 14.0 或更高版本
- Xcode 15.0 或更高版本
- Swift 5.9 或更高版本

### 安装步骤

1. **克隆仓库**
   ```bash
   git clone https://github.com/introvert24312/connection.git
   cd connection
   ```

2. **打开项目**
   ```bash
   open WordTagger.xcodeproj
   ```

3. **运行应用**
   - 在 Xcode 中选择目标设备
   - 按 `Command+R` 运行应用

### 首次使用

1. **选择数据文件夹**: 首次启动时选择一个文件夹来存储您的数据
2. **创建学科层**: 使用 `Command+K` 创建您的第一个学科层
3. **添加单词**: 开始添加和管理您的词汇

## ⌨️ 快捷键

| 快捷键 | 功能 |
|--------|------|
| `Command+K` | 打开命令面板 |
| `Command+R` | 创建新学科层 |
| `Command+U` | 打开/关闭单词详情面板 |
| `Command+I` | 打开/关闭单词信息面板 |
| `Escape` | 关闭当前面板 |
| `↑/↓` | 在命令面板中导航 |
| `Enter` | 执行选中的命令 |

## 📊 数据格式

WordTagger 使用 JSON 格式存储数据，主要包含：

```json
{
  "layers": [...],      // 学科层信息
  "nodes": [...],       // 单词节点数据
  "metadata": {...},    // 元数据信息
  "tagMappings": [...]  // 标签映射关系
}
```

外部存储结构：
```
YourDataFolder/
├── data/
│   ├── layers/
│   ├── nodes/
│   ├── metadata/
│   └── tags/
├── Images/              // 图片资源
├── Markdown/            // Markdown 文件
└── backups/            // 备份文件
```

## 🔧 开发指南

### 代码规范
- 使用 SwiftLint 进行代码规范检查
- 遵循 Swift API 设计指南
- 优先使用 async/await 而非回调

### 贡献指南
1. Fork 此仓库
2. 创建特性分支: `git checkout -b feature/amazing-feature`
3. 提交更改: `git commit -m 'Add amazing feature'`
4. 推送分支: `git push origin feature/amazing-feature`
5. 提交 Pull Request

### 常见问题

**Q: 如何备份数据？**
A: 直接复制您选择的数据文件夹即可完整备份所有数据。

**Q: 支持导入导出功能吗？**
A: 目前支持 JSON 格式的数据导入导出，未来会支持更多格式。

**Q: 如何切换数据存储位置？**
A: 在设置中重新选择数据文件夹，应用会提示您迁移现有数据。

## 🚀 未来计划

- [ ] 支持更多导入导出格式（CSV, Excel等）
- [ ] 添加学习进度跟踪功能
- [ ] 支持单词发音播放
- [ ] 添加复习提醒功能
- [ ] 支持数据同步（iCloud等）
- [ ] 添加学习统计图表
- [ ] 支持主题自定义

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 👨‍💻 作者

**Patronum** - *主要开发者*

## 🙏 致谢

- 感谢 [Vditor](https://github.com/Vanessa219/vditor) 提供的优秀 Markdown 编辑器
- 感谢所有为开源社区做出贡献的开发者们

---

如果您觉得这个项目有帮助，请给它一个 ⭐️！