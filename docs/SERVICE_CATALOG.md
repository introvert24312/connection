# 真实服务清单

基于实际代码分析的服务清单，**确保每个服务都真实存在**。

## 🎯 核心服务 (5个)

### NodeStore (Store.swift)
- **文件**: `Store.swift` (3066行)
- **作用**: 应用的数据中心，管理所有节点、层、标签
- **关键方法**:
  - `addNode()` - 添加节点
  - `updateNode()` - 更新节点
  - `deleteNode()` - 删除节点
  - `performSearch()` - 执行搜索
  - `setCurrentLayer()` - 切换层
- **状态**: ✅ 核心服务，3066行代码

### ExternalDataService
- **文件**: `ExternalDataService.swift`
- **作用**: 数据持久化，JSON 序列化/反序列化
- **关键方法**:
  - `saveData()` - 保存数据到文件
  - `loadData()` - 从文件加载数据
  - `createBackup()` - 创建数据备份
- **状态**: ✅ 实际使用

### GitService  
- **文件**: `GitService.swift`
- **作用**: Git 版本控制集成
- **关键方法**:
  - `commitAndPush()` - 提交并推送
  - `setupRepository()` - 设置仓库
  - `handleAuthentication()` - 处理认证
- **状态**: ✅ 实际使用，自动同步功能

### SearchService
- **文件**: `SearchService.swift`
- **作用**: 搜索功能实现
- **关键方法**:
  - `search()` - 执行搜索
  - `fuzzyMatch()` - 模糊匹配
- **状态**: ✅ 实际使用

### GraphService
- **文件**: `GraphService.swift`  
- **作用**: 图谱数据生成和分析
- **关键方法**:
  - `generateGraphData()` - 生成图谱数据
  - `analyzeRelationships()` - 分析关系
- **状态**: ✅ 实际使用

## 🔧 管理器组件 (8个)

### WindowFocusManager
- **文件**: `WindowFocusManager.swift`
- **作用**: 多窗口焦点管理，防止竞态条件
- **状态**: ✅ 解决多窗口问题的关键组件

### KeyboardEventManager
- **文件**: `KeyboardEventManager.swift`  
- **作用**: 全局键盘事件处理和错误恢复
- **状态**: ✅ 实际使用

### ExternalDataManager
- **文件**: `ExternalDataManager.swift`
- **作用**: 外部数据存储路径管理
- **状态**: ✅ 实际使用

### TagGraphWindowManager
- **文件**: `TagGraphWindowManager.swift`
- **作用**: 标签图谱窗口管理
- **状态**: ✅ 实际使用

### KeychainManager
- **文件**: `KeychainManager.swift`
- **作用**: macOS 钥匙串安全存储
- **状态**: ✅ Git 凭据存储

### ResourceManager
- **文件**: `ResourceManager.swift`
- **作用**: 应用资源管理
- **状态**: ✅ 实际使用

### DataManager
- **文件**: `DataManager.swift`
- **作用**: 数据导入导出
- **状态**: ✅ 实际使用

### GeocoderService
- **文件**: `Geocoder.swift`
- **作用**: 地理位置解析和坐标转换
- **状态**: ✅ 地图功能必需

## 🎨 UI 组件管理器 (5个)

### NodeGraphWindowManager
- **文件**: `GraphView.swift`
- **作用**: 节点图谱窗口管理

### LayerGraphPresetManager  
- **文件**: `LayerGraphPresetManager.swift`
- **作用**: 层图谱预设管理

### NodeGraphPresetManager
- **文件**: `NodeGraphPresetManager.swift`
- **作用**: 节点图谱预设管理

### GlobalTagGraphWindowManager
- **文件**: `GlobalTagGraphView.swift`
- **作用**: 全局标签图谱窗口管理

### ContextMenuManager
- **文件**: `PerformanceOptimizations.swift`
- **作用**: 上下文菜单管理

## 📊 监控和追踪 (可选功能)

### TracingService
- **文件**: `TracingInfrastructure.swift`
- **作用**: 分布式追踪基础设施
- **状态**: 🟡 已实现但可选使用

### ServiceRegistry
- **文件**: `ServiceRegistry.swift`
- **作用**: 服务注册和健康监控
- **状态**: 🟡 已实现但可选使用

### ObservabilityDashboard
- **文件**: `ObservabilityDashboard.swift`
- **作用**: 可观测性监控面板
- **状态**: 🟡 已实现但可选使用

## 📝 服务使用指南

### 开发时重点关注
1. **NodeStore** - 核心数据操作
2. **ExternalDataService** - 数据持久化
3. **WindowFocusManager** - 多窗口协调

### 可选启用
- TracingService - 性能分析时启用
- ObservabilityDashboard - 调试时启用

### 服务总数统计
- **核心服务**: 5个 ✅
- **管理器**: 8个 ✅  
- **UI管理器**: 5个 ✅
- **监控组件**: 3个 🟡
- **总计**: 约21个实际服务/组件

*基于2025年9月17日实际代码分析*