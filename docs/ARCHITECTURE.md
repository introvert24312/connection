# 架构简述

## 核心思路

Connection 是一个 **SwiftUI + 单一数据源** 的架构：

```
UI组件 ← → Store.swift ← → 数据持久化 ← → Git同步
```

## 关键文件

### 数据层
- **Store.swift** (3066行) - 应用的"大脑"，管理所有数据和状态
- **Models.swift** - 定义 Node、Layer、Tag 等数据结构
- **ExternalDataService.swift** - 负责保存和加载数据

### 服务层  
- **GitService.swift** - Git 版本控制
- **SearchService.swift** - 搜索功能
- **WindowFocusManager.swift** - 多窗口管理

### UI层
- **ContentView.swift** - 主界面布局
- **DetailPanel.swift** - 节点编辑面板
- **MapContainer.swift** - 地图组件
- **CommandPaletteView.swift** - 命令面板

## 数据流

### 用户操作 → 数据更新
1. 用户在UI中操作（点击、输入等）
2. UI调用 Store 中的方法
3. Store 更新 @Published 属性
4. SwiftUI 自动刷新相关界面
5. ExternalDataService 自动保存数据
6. GitService 可选同步到远程

### 实际例子
```swift
// 用户创建节点的流程
用户输入 "苹果" → 
CommandPaletteView 调用 store.addNode("苹果") → 
Store 更新 nodes 数组 → 
UI 自动显示新节点 → 
ExternalDataService 保存到文件
```

## 关键设计决策

### 为什么用单一 Store？
- **简单**: 所有状态在一个地方，易于理解和调试
- **可靠**: 避免多个数据源不同步的问题
- **高效**: SwiftUI 的 @Published 机制天然适合这种模式

### 为什么 Store.swift 有3066行？
- 它承担了应用的核心逻辑
- 包含节点、层、标签、搜索等所有功能
- 虽然文件很大，但逻辑清晰，按功能分组

### 多窗口怎么处理？
- 每个窗口有独立的 Store 实例
- 通过 NotificationCenter 协调窗口间通信
- WindowFocusManager 防止窗口操作冲突

## 扩展指南

### 添加新功能
1. **数据模型**: 在 Models.swift 中定义
2. **业务逻辑**: 在 Store.swift 中添加方法
3. **UI组件**: 创建新的 SwiftUI View
4. **数据持久化**: 更新 ExternalDataService

### 性能考虑
- Store 使用 @Published 属性，避免过度细粒度的分割
- 搜索等重操作在后台队列执行
- UI 组件使用 @ObservedObject 连接 Store

这就是整个架构 - 简单、直接、有效！ 🏗️