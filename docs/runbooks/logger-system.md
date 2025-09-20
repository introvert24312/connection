# Logger System Runbook

## Service Overview

**Name:** Logger System  
**Purpose:** 提供统一的日志管理，支持Debug/Release模式自动切换  
**Owner:** WordTagger Team @wordtagger-oncall  
**Features:** 自动构建模式检测、分类日志、性能友好的生产环境禁用  

## 设计理念

### 构建模式感知
- **Debug模式**: 启用详细日志输出，便于开发调试
- **Release模式**: 完全禁用日志输出，确保生产性能
- **自动检测**: 基于编译时标志自动切换模式

### 日志分类
- **搜索**: `Logger.search()` - 搜索相关操作
- **层管理**: `Logger.layer()` - 层操作和管理
- **窗口**: `Logger.window()` - 窗口管理和切换
- **图谱**: `Logger.graph()` - 图谱渲染和交互
- **键盘**: `Logger.keyboard()` - 键盘事件和快捷键
- **错误**: `Logger.error()` - 错误和异常
- **警告**: `Logger.warning()` - 警告信息
- **成功**: `Logger.success()` - 成功操作
- **调试**: `Logger.debug()` - 一般调试信息

## API Reference

### 基本用法
```swift
// 分类日志
Logger.search("缓存搜索结果 - 'hello' (15 结果)")
Logger.layer("创建新层: MyLayer")
Logger.window("窗口切换 - ContentView -> GraphView")
Logger.error("网络连接失败")

// 通用日志
Logger.log("自定义消息", category: .general)

// 兼容性方法（用于替换现有print语句）
Logger.print("调试信息")
```

### 日志格式
```
[HH:mm:ss.SSS] 🔍 Search: 缓存搜索结果 - 'hello' (15 结果) (SearchService.swift:37)
[HH:mm:ss.SSS] 📁 Layer: 创建新层: MyLayer (Store.swift:123)
[HH:mm:ss.SSS] ❌ Error: 网络连接失败 (NetworkService.swift:45)
```

### 构建配置
```swift
// 自动根据构建模式设置
#if DEBUG
private static let isLoggingEnabled = true   // 开发环境
#else
private static let isLoggingEnabled = false  // 生产环境
#endif
```

## Migration Guide

### 替换现有print语句

**原有代码:**
```swift
print("🔍 SearchService: 使用缓存结果 - '\(query)' (\(results.count) 结果)")
print("✅ 创建新层: \(layerName)")
print("❌ 搜索失败: \(error)")
```

**新代码:**
```swift
Logger.search("使用缓存结果 - '\(query)' (\(results.count) 结果)")
Logger.success("创建新层: \(layerName)")
Logger.error("搜索失败: \(error)")
```

### 批量替换策略

1. **搜索相关**: `print("🔍` → `Logger.search("`
2. **层管理**: `print("📁` 或 `print("✅` → `Logger.layer(`
3. **错误信息**: `print("❌` → `Logger.error(`
4. **成功操作**: `print("✅` → `Logger.success(`
5. **一般调试**: `print("` → `Logger.debug(`

## Performance Impact

### Debug模式
- **日志开销**: 最小化，仅包含字符串格式化
- **文件信息**: 自动包含文件名和行号
- **时间戳**: 精确到毫秒的时间记录

### Release模式
- **性能开销**: 零开销，编译时完全移除
- **代码大小**: 不影响最终应用大小
- **运行时**: 无任何日志相关的运行时开销

## Best Practices

### 日志内容
- **简洁明确**: 避免冗长的日志消息
- **包含关键信息**: 操作结果、数量、标识符
- **避免敏感信息**: 不记录密码、令牌等敏感数据

### 使用场景
- **操作确认**: 重要操作的成功/失败状态
- **性能监控**: 缓存命中、搜索时间等指标
- **错误追踪**: 异常情况和错误信息
- **调试辅助**: 开发期间的状态追踪

### 不推荐的用法
```swift
// ❌ 避免：过于详细的日志
Logger.debug("进入函数 \(#function)")
Logger.debug("退出函数 \(#function)")

// ❌ 避免：记录敏感信息
Logger.debug("用户密码: \(password)")

// ❌ 避免：高频率日志
for item in items {
    Logger.debug("处理项目: \(item)")  // 可能产生大量日志
}
```

## Implementation Details

### 文件结构
```
WordTagger/
├── Logger.swift           # 主要日志系统实现
├── SearchService.swift    # 已更新使用Logger.search()
├── Store.swift           # 部分更新使用分类日志
└── ...                   # 其他文件待更新
```

### 类型定义
```swift
public enum LogCategory: String, CaseIterable {
    case general = "General"
    case search = "Search"
    case layer = "Layer"
    case window = "Window"
    case graph = "Graph"
    case keyboard = "Keyboard"
    case error = "Error"
    case warning = "Warning"
    case success = "Success"
    case debug = "Debug"
}
```

## Monitoring

### 日志统计
- **Debug构建**: 监控日志输出频率和内容
- **Release构建**: 验证日志完全禁用
- **性能测试**: 确认Release模式无日志开销

### 验证方法
```bash
# 检查Release构建中是否包含日志代码
otool -t YourApp.app/Contents/MacOS/YourApp | grep -i "logger"
# 应该没有输出，表示日志代码已被移除
```

## Recent Changes

### 2025-01-15: 初始实现
- ✅ 创建Logger系统基础架构
- ✅ 实现Debug/Release模式自动切换
- ✅ 定义日志分类和格式标准
- ✅ 更新SearchService使用新日志系统
- ✅ 提供Legacy兼容性方法

### Next Steps
- 🔄 更新所有服务使用Logger系统
- 🔄 完善日志分类和最佳实践
- 🔄 添加日志配置选项

---
*Last updated: 2025-01-15*
*Created for unified logging system*