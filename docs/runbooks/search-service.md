# search-service Runbook

## Service Overview

**Name:** search-service  
**Purpose:** 提供高性能的本地搜索功能，支持缓存和即时响应  
**Owner:** WordTagger Team @wordtagger-oncall  
**Features:** 搜索结果缓存、即时搜索、多字段匹配、性能监控  

## Dependencies

- NodeStore: 节点数据存储
- Logger: 日志系统（生产环境自动禁用）

## Performance Optimizations

### 搜索结果缓存
- **缓存大小**: 最多50个查询结果
- **过期时间**: 5分钟自动失效
- **清理机制**: 每60秒自动清理过期条目
- **内存管理**: 自动移除最旧条目防止内存泄漏

### 即时搜索
- **响应模式**: 每次输入立即搜索，无防抖延迟
- **适用场景**: 本地数据库，数据量适中
- **用户体验**: 实时反馈，搜索结果随输入变化

### 搜索算法
- **多字段匹配**: 文本、含义、Markdown、音标、标签
- **权重系统**: 不同字段采用不同权重计算相关性
- **模糊匹配**: 支持相似度匹配和部分匹配
- **结果限制**: 最多返回100个结果

## Common Issues

### 搜索性能缓慢

**症状:**
- 搜索响应时间超过预期
- 用户输入时有明显延迟

**故障排除步骤:**
1. 检查缓存命中率：`SearchService.shared.searchMetrics.cacheHitRate`
2. 清空搜索缓存：`SearchService.shared.clearSearchCache()`
3. 检查数据量是否过大
4. 验证搜索查询复杂度

### 内存使用过高

**症状:**
- 应用内存占用持续增长
- 搜索缓存占用大量内存

**故障排除步骤:**
1. 检查缓存大小：`SearchService.shared.searchMetrics.cacheSize`
2. 手动清理缓存：`SearchService.shared.clearSearchCache()`
3. 检查缓存过期清理是否正常工作
4. 考虑减少缓存大小限制

### 缓存未命中

**症状:**
- 相同查询重复计算
- 缓存效果不明显

**故障排除步骤:**
1. 检查查询字符串格式是否一致
2. 验证过滤器参数是否相同
3. 检查缓存是否被意外清空
4. 确认缓存键生成逻辑

## Monitoring

### 性能指标
```swift
let metrics = SearchService.shared.searchMetrics
print("搜索时间: \(metrics.lastSearchTimeFormatted)")
print("缓存大小: \(metrics.cacheSize)")
print("缓存命中率: \(metrics.cacheHitRateFormatted)")
print("搜索状态: \(metrics.isSearching ? "搜索中" : "空闲")")
```

### 日志监控
- **Debug模式**: 详细日志输出，包括缓存操作
- **Release模式**: 自动禁用所有日志输出
- **日志类别**: 搜索操作使用 `Logger.search()` 记录

### 关键指标
- **搜索响应时间**: 应小于50ms（本地数据）
- **缓存命中率**: 建议大于30%
- **缓存大小**: 监控是否接近50个上限
- **内存使用**: 定期检查缓存内存占用

## API Reference

### 主要方法
```swift
// 执行搜索（已集成缓存）
func search(_ query: String, in nodes: [Node], filter: SearchFilter = SearchFilter()) async -> [SearchResult]

// 缓存管理
func clearSearchCache()

// 性能监控
var searchMetrics: SearchMetrics { get }
```

### 搜索过滤器
```swift
SearchFilter(
    tagType: Tag.TagType?,      // 按标签类型过滤
    hasLocation: Bool?          // 按位置信息过滤
)
```

## Recent Changes

### 2025-01-15: 搜索优化重构
- ✅ 移除防抖机制，实现即时搜索
- ✅ 集成搜索结果缓存系统
- ✅ 添加Logger系统支持Debug/Release模式
- ✅ 优化缓存键生成和内存管理
- ✅ 扩展性能监控指标

### 2025-01-14: 性能基础优化
- ✅ 添加搜索防抖功能（已移除）
- ✅ 实现基础缓存机制
- ✅ 添加搜索时间统计

---
*Last updated: 2025-01-15*
*Updated for search optimization and logging system*
