# Connection 应用打包完成

## 🎉 应用重命名和打包成功！

你的应用已经成功从"WordTagger"重命名为"Connection"并打包完成。

## 📦 打包详情

### 应用信息
- **应用名称**: Connection
- **Bundle ID**: com.example.Connection
- **版本**: 1.0
- **构建配置**: Release (优化版本)
- **目标平台**: macOS 14.0+
- **架构**: Apple Silicon (arm64)

### 文件位置
- **应用位置**: `~/Desktop/Connection.app`
- **应用大小**: ~7.4 MB
- **构建时间**: 2025年8月15日 20:03

## 🔧 完成的修改

### 1. 项目配置修改
- ✅ 修改了 `PRODUCT_BUNDLE_IDENTIFIER` 为 `com.example.Connection`
- ✅ 修改了 `PRODUCT_NAME` 为 `Connection`
- ✅ 更新了 Debug 和 Release 两个构建配置

### 2. 应用内名称修改
- ✅ 关于页面标题：从"节点标签管理器" → "Connection"
- ✅ 版权信息：从"© 2024 WordTagger" → "© 2024 Connection"
- ✅ 数据存储提示：从"WordTagger的数据" → "Connection的数据"

### 3. 构建优化
- ✅ 使用 Release 配置构建，包含代码优化
- ✅ 启用了 Hardened Runtime 安全特性
- ✅ 生成了调试符号文件 (dSYM)
- ✅ 应用已签名并可直接运行

## 🚀 如何使用

### 直接运行
1. 在桌面找到 `Connection.app`
2. 双击运行即可

### 安装到应用程序文件夹
```bash
# 复制到应用程序文件夹
cp -R ~/Desktop/Connection.app /Applications/
```

### 从命令行运行
```bash
# 直接运行
open ~/Desktop/Connection.app

# 或者运行可执行文件
~/Desktop/Connection.app/Contents/MacOS/Connection
```

## ✨ 应用功能

Connection 是一个强大的层级管理和节点关系可视化应用，具有以下特性：

### 核心功能
- 🏗️ **智能层管理**: 支持普通层和复合层的创建与管理
- ⌨️ **快捷键操作**: Command+K 打开命令面板，Command+R 创建新层
- 🔍 **模糊搜索**: 支持层名的智能搜索和过滤
- 📊 **图谱可视化**: 层结构关系的可视化展示
- 💾 **数据持久化**: 支持外部数据存储和同步

### 层管理特性
- **普通层创建**: 输入单个名称 + Command+R
- **复合层创建**: 输入"层R 层A 层B"格式 + Command+R
- **层过滤器**: Command+J 添加层，Command+Shift+J 移除层
- **层切换**: Command+点击图谱中的层节点

### 界面特性
- 🎨 现代化的 SwiftUI 界面
- 🌙 支持深色模式
- 📱 响应式布局设计
- ⚙️ 完整的设置面板

## 🔒 安全说明

应用使用本地签名，首次运行时可能需要：
1. 右键点击应用 → "打开"
2. 在弹出的安全提示中点击"打开"
3. 或在"系统偏好设置" → "安全性与隐私"中允许运行

## 📝 技术细节

- **开发语言**: Swift 5.0
- **UI框架**: SwiftUI
- **最低系统要求**: macOS 14.0
- **架构支持**: Apple Silicon (M1/M2/M3)
- **代码签名**: 本地开发签名

---

🎊 **恭喜！你的 Connection 应用已经准备就绪，可以开始使用了！**