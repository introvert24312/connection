# 🚀 WordTagger 项目快速交接摘要

## 📋 项目基本信息
- **应用名称**: WordTagger (智能节点标签管理系统)
- **技术栈**: Swift/SwiftUI + macOS + Git集成
- **架构模式**: 微服务 + 事件驱动 + 分布式追踪
- **服务数量**: 16个服务 (Core: 3, Specialized: 6, Infrastructure: 4, UI: 3)
- **当前版本**: 1.9.0

## 📖 关键文档清单

| 文档类型 | 文件路径 | 用途 |
|---------|----------|------|
| **🏗️ 完整架构图** | `docs/architecture/wordtagger-complete-architecture.mmd` | 系统全貌 |
| **📋 服务清单** | `docs/SERVICE_CATALOG_OVERVIEW.md` | 服务详情 |
| **📡 接口契约** | `docs/contracts/service-contracts.md` | API规范 |
| **🔍 TraceID追踪** | `WordTagger/TracingInfrastructure.swift` | 分布式追踪 |
| **📱 完整交接文档** | `PROJECT_HANDOVER_DOCUMENTATION.md` | 详细交接 |

## 🎯 核心服务快速索引

### 🏪 数据核心
- **NodeStore.swift** - 中央状态管理，所有UI数据的唯一来源
- **ExternalDataService.swift** - 数据持久化，支持备份恢复
- **DataManager.swift** - 导入导出，JSON格式处理

### ⚡ 业务服务  
- **SearchService.swift** - 高级搜索，支持模糊匹配和语义搜索
- **GraphService.swift** - 图可视化，节点关系分析
- **GitService.swift** - Git集成，自动提交和同步

### 🛠️ 基础设施
- **WindowFocusManager.swift** - 多窗口焦点管理 ⚠️ *最近修复*
- **KeychainManager.swift** - 安全凭据存储
- **TracingInfrastructure.swift** - 分布式追踪系统

## 🔥 最近重要修复

### ✅ 层图谱窗口重复创建问题 (2025-01-07)
**问题**: Command+K时创建多个层图谱窗口
**原因**: 竞态条件，多个通知接收器同时处理
**解决**: 原子性预留机制
```swift
// 关键修复 - WindowFocusManager.swift
func reserveLayerGraphWindow(for mainWindowId: String) -> Bool {
    if layerGraphWindows[mainWindowId] != nil {
        return false  // 已存在，拒绝
    }
    layerGraphWindows[mainWindowId] = "RESERVED"  // 预留位置
    return true
}
```

## 🕵️ TraceID 系统核心

### 追踪流程
```
用户操作 → TraceContext生成 → 跨服务传播 → Span收集 → 可视化分析
```

### 关键结构
```swift
struct TraceContext {
    let traceId: String        // 16位十六进制全局标识
    let spanId: String         // 8位当前操作标识  
    let parentSpanId: String?  // 父操作关联
    let operationName: String  // 操作名称
    // ... 更多元数据
}
```

## 🔧 快速启动指南

### 1. 开发环境
```bash
# 克隆并进入项目
cd WordTagger

# 启动应用 (两种方式)
./启动WordTagger.command        # 快速启动
open WordTagger.xcodeproj      # Xcode开发

# 验证契约 (可选)
cd docs/contracts/tools && npm test
```

### 2. 关键快捷键
- **⌘K** - 命令面板/层图谱 (核心功能)
- **⌘N** - 清除标签筛选
- **⌘T** - 恢复标签筛选
- **⌘M** - 地图窗口
- **⌘G** - 全局图谱

### 3. 调试工具
```swift
// 强制刷新窗口状态
WindowFocusManager.shared.forceRefreshWindowState()

// 查看追踪数据
TracingCollector.shared.getTraces(timeRange: .lastHour)

// 服务健康检查
ServiceRegistry.shared.forceHealthCheck()
```

## ⚠️ 已知问题和限制

### 解决的问题
- ✅ 层图谱窗口重复创建 (已修复)
- ✅ SwiftUI Publishing changes警告 (已修复)
- ✅ 多窗口焦点管理 (已优化)

### 需要注意的点
- **内存管理**: 图可视化组件占用较高内存，有自动清理机制
- **Git集成**: 需要正确配置凭据，支持SSH和HTTPS
- **多窗口**: 复杂的窗口映射逻辑，修改时需谨慎测试

## 🔍 故障排除快速参考

### 常见问题
1. **窗口焦点异常** → 检查 `WindowFocusManager.shared.getDebugInfo()`
2. **服务无响应** → 运行 `ServiceRegistry.shared.forceHealthCheck()`
3. **Git操作失败** → 检查凭据存储和网络连接
4. **搜索性能慢** → 查看 `SearchService` 性能指标

### 日志关键字
```bash
# 窗口管理
grep "WindowFocusManager" app_output.log

# 追踪信息  
grep "TraceContext\|trace_id" app_output.log

# 服务健康
grep "ServiceHealth\|HealthCheck" app_output.log
```

## 📞 支持资源

### 文档体系
- **架构**: `docs/architecture/` - 系统设计和依赖关系
- **服务**: `docs/services/` - 每个服务的YAML定义  
- **契约**: `docs/contracts/` - API规范和验证
- **运维**: `docs/runbooks/` - 故障排除手册

### 自助工具
- **架构图查看**: [mermaid.live](https://mermaid.live) 
- **契约验证**: `cd docs/contracts/tools && npm test`
- **性能分析**: ServiceHealthDashboard (内置)
- **追踪可视化**: ObservabilityDashboard (内置)

---

## 🎯 交接确认清单

接收方请确认以下项目完成：

### 技术理解
- [ ] 能够启动和运行应用
- [ ] 理解16个核心服务的职责
- [ ] 掌握TraceID追踪系统使用
- [ ] 熟悉最近的重要修复

### 开发能力  
- [ ] 能够查看和理解架构图
- [ ] 会使用契约验证工具
- [ ] 掌握常见问题排查方法
- [ ] 了解性能监控和健康检查

### 运维知识
- [ ] 知道关键日志位置和关键字
- [ ] 能够处理多窗口焦点问题
- [ ] 理解Git集成的配置要求
- [ ] 掌握服务注册中心的使用

**这份摘要提供了快速上手所需的核心信息。更详细的技术细节请参考 `PROJECT_HANDOVER_DOCUMENTATION.md`。**