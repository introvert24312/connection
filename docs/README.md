# Connection 

一个 macOS 标签管理和地图导航应用。

## 🚀 快速开始

### 运行应用
```bash
# 方法1: 直接启动已打包应用
open ~/Desktop/Connection.app

# 方法2: 从源码运行
cd /Users/Patronum/Desktop/Connection
open WordTagger.xcodeproj
# 然后在 Xcode 中按 Cmd+R
```

### 核心功能
- **标签管理**: 创建和管理带标签的节点
- **地图可视化**: 在地图上显示带位置信息的节点  
- **命令面板**: 快捷键 `Cmd+K` 打开命令面板
- **Git 同步**: 自动同步数据到 Git 仓库
- **Markdown 编辑**: 节点支持 Markdown 内容

## 📁 核心文件

### 入口文件
- `WordTagger/WordTaggerApp.swift` - 应用主入口
- `WordTagger/ContentView.swift` - 主界面

### 核心组件
- `WordTagger/Store.swift` - 数据管理中心 (3066行)
- `WordTagger/Models.swift` - 数据模型定义
- `WordTagger/ExternalDataService.swift` - 数据持久化
- `WordTagger/GitService.swift` - Git 集成

### 主要界面
- `WordTagger/DetailPanel.swift` - 节点详情面板
- `WordTagger/MapContainer.swift` - 地图视图
- `WordTagger/CommandPaletteView.swift` - 命令面板
- `WordTagger/SettingsView.swift` - 设置界面

## 🛠️ 开发指南

### 添加新功能
1. 修改 `Models.swift` 添加数据模型
2. 在 `Store.swift` 中添加相关方法
3. 创建或修改 UI 组件
4. 测试功能是否正常

### 数据流程
```
UI 操作 → Store 更新 → ExternalDataService 保存 → Git 同步
```

### 调试技巧
- 查看 Console 输出了解数据流
- 使用 `print()` 调试关键方法
- 检查 `~/Documents/WordTagger/` 数据文件

## 🔧 常见问题

**Q: 如何添加新的标签类型？**
A: 在命令面板中输入 `标签内容[标签类型]`

**Q: 地图不显示位置怎么办？**  
A: 确保标签格式为 `loc @纬度,经度[位置名称]`

**Q: Git 同步失败？**
A: 检查设置中的 Git 凭据是否正确

## 📦 构建信息

- **应用名**: Connection
- **版本**: 1.0
- **平台**: macOS 14.0+
- **构建**: Release (已优化)

---
*简单、实用、易懂的文档 - 让工程师快速上手*