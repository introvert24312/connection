# WordTagger Vditor Markdown编辑器实现总结

## 🎯 实现目标
在 macOS 原生 App 内实现 "像 Typora 的即时渲染（输入即所见）Markdown + Mermaid"，最快上线、稳定、可离线。

## ✅ 已完成功能（按7阶段计划）

### ① 内核搭好 ✅ 
- ✅ 集成 Vditor.js/css、Mermaid.min.js 到 App Bundle（离线可用）
- ✅ WKWebView 加载本地 index.html
- ✅ 初始化 Vditor：mode: 'ir'（即时渲染，Typora 体验）
- ✅ 验收通过：输入 Markdown 直接渲染，```mermaid 代码块自动渲染

### ② 双向通信 ✅
- ✅ WKScriptMessageHandler 建立 JS ↔ Swift 通道
- ✅ JS → Swift：内容变更/保存/就绪事件  
- ✅ Swift → JS：设置/获取 Markdown、插入文本、切换主题
- ✅ 验收通过：保存按钮获取内容，打开文件灌回编辑器

### ③ 文件与状态 ✅
- ✅ 文档模型（DocumentState类）：URL、修改状态、自动保存、关闭提示
- ✅ 支持拖拽/粘贴图片到本地资源目录并自动插入相对路径
- ✅ 验收通过：新建/打开/保存/另存为/自动保存全打通

### ④ 主题与外观 ✅  
- ✅ 监听系统外观（浅/深色）→ 调用 JS 切换编辑器主题
- ✅ Mermaid 主题同切，批量重渲染
- ✅ 验收通过：切系统外观，编辑器与图表一起变

### ⑤ 安全与性能 ✅
- ✅ Mermaid securityLevel: 'strict'，Markdown 预览开启 sanitize  
- ✅ 渲染节流：对频繁变动的内容做防抖（300ms）
- ✅ 验收通过：恶意 HTML 不被注入，大文档滚动/输入不卡顿

### ⑥ API 接入 🚧 
- ⭕ 暂未实现（按需添加）
- 📋 预留方案：JS 发消息 → Swift 用 URLSession 调接口

### ⑦ 打包与更新 ✅
- ✅ 所有前端静态资源走 Bundle，不依赖网络
- ✅ 用 App 沙盒内目录管理附件/图片  
- ✅ 验收通过：断网可用，首次启动即完整功能

## 📁 新增文件结构

```
WordTagger/
├── DocumentState.swift           # 文档状态管理类
├── MarkdownEditorWindow.swift    # Markdown编辑器窗口
├── ResourceManager.swift         # 资源文件管理工具类
└── Resources/                    # 静态资源目录
    ├── vditor/
    │   ├── index.css            # Vditor样式文件（43KB）  
    │   └── index.min.js         # Vditor核心JS（268KB）
    ├── mermaid/
    │   └── mermaid.min.js       # Mermaid图表库（2.3MB）
    └── templates/               # HTML模板（预留）
```

## 🚀 核心技术特性

### 1. 即时渲染（IR模式）
- 采用 Vditor 的 `mode: 'ir'` 配置  
- 实现真正的"所见即所得"体验，媲美 Typora
- 无需切换预览模式，编辑与渲染同步进行

### 2. 完全离线可用
- 所有依赖资源已本地化，无需联网
- App Bundle 包含完整的 Vditor + Mermaid 静态资源
- 首次启动即可使用全部功能

### 3. 安全防护
- Mermaid securityLevel 设置为 'strict'
- HTML 内容启用 sanitize 清理
- 防止恶意脚本注入和 XSS 攻击

### 4. 性能优化
- 输入防抖：300ms 延迟减少频繁更新
- 渲染节流：大文档优化显示性能
- 资源懒加载：按需渲染图表组件

### 5. 原生集成
- SwiftUI + WKWebView 架构
- 原生菜单：⌘E 快捷键打开编辑器
- 系统主题自动切换：支持深/浅色模式

## 🎮 使用方法

### 启动编辑器
1. **菜单方式**：点击菜单栏"Markdown编辑器"
2. **快捷键**：按 ⌘E 快速打开
3. **命令面板**：⌘⇧P 搜索"Markdown"

### 文件操作
- **新建**：⌘N
- **打开**：⌘O  
- **保存**：⌘S
- **另存为**：⌘⇧S
- **自动保存**：30秒间隔自动保存

### 图片处理
- **拖拽上传**：直接拖拽图片到编辑器
- **粘贴上传**：⌘V 粘贴剪贴板图片
- **自动管理**：图片保存到文档同名_files目录
- **相对路径**：自动插入正确的相对路径引用

## ✨ 完成版 1.0 检查清单

- [x] 新建/打开/保存/自动保存
- [x] 即时渲染 Markdown + Mermaid
- [x] 主题联动与安全策略  
- [x] 零网络、离线可用
- [x] 基础粘贴/拖拽图片

## 🔮 后续扩展计划

1. **API 集成**：云同步、在线服务
2. **导出功能**：HTML/PDF 导出
3. **插件系统**：自定义扩展
4. **协作功能**：多人编辑
5. **版本控制**：Git 集成

---

📝 **实现状态**：完整的 Typora 风格 Markdown 编辑器现已就绪！  
🚀 **技术栈**：SwiftUI + WKWebView + Vditor + Mermaid  
⚡ **特色**：即时渲染 + 完全离线 + 原生体验