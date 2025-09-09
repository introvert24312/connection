# WordTagger 分布式追踪系统完整指南

## 🎯 系统概述

WordTagger集成了完整的分布式追踪系统，基于OpenTelemetry标准，提供端到端的可观测性。该系统跨越所有20个服务，支持多窗口环境下的复杂操作追踪。

## 💡 构建历程与挑战解决

### 从零到企业级的追踪系统演进

#### 阶段一：基础需求识别 (2024年12月)
- **问题**: 复杂服务交互导致调试困难，无法定位性能瓶颈
- **目标**: 建立基础的操作追踪能力

#### 阶段二：核心基础设施构建 (2025年1月)
- **挑战**: SwiftUI环境下TraceContext传播的复杂性
- **解决方案**: 设计轻量级的TraceContext结构，实现NotificationCenter自动传播
- **成果**: 建立了16字符traceId + 8字符spanId的标识体系

#### 阶段三：多窗口环境适配 (2025年9月)
- **挑战**: 多窗口环境下trace上下文的正确传播和隔离
- **解决方案**: 实现窗口级trace隔离，通过WindowFocusManager协调trace传播
- **成果**: 支持独立窗口的完整trace链路

### 技术难点突破

1. **SwiftUI响应式环境下的追踪**
   - 挑战：@Published属性变更的自动追踪
   - 解决：通过TracedServices装饰器模式，无侵入式集成

2. **NotificationCenter事件追踪**
   - 挑战：异步事件的trace上下文传播
   - 解决：自定义NotificationCenter拦截器，自动注入TraceContext

3. **性能影响最小化**
   - 挑战：追踪系统不能显著影响应用性能
   - 解决：异步span收集，批量上报，智能采样策略

### 核心组件
- **TracingService**: 分布式追踪核心引擎
- **StructuredLogger**: 上下文感知的结构化日志系统  
- **ObservabilityDashboard**: 实时监控和可视化界面
- **TraceContext**: 跨服务传播的追踪上下文

## 🏗️ 追踪架构

### 分层架构
```
┌─────────────────────────────────────────────────────────────────┐
│                   Application Layer                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐   │
│  │ ContentView │  │ NodeManager │  │ LayerGraphWindow        │   │
│  │             │  │ View        │  │ View                    │   │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │ TraceContext传播
┌─────────────────────────────────────────────────────────────────┐
│                  Service Layer (20 Services)                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐   │
│  │ NodeStore   │  │ SearchSvc   │  │ WindowFocusManager      │   │
│  │ (traced)    │  │ (traced)    │  │ (traced)                │   │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │ Span收集
┌─────────────────────────────────────────────────────────────────┐
│                 Observability Infrastructure                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐   │
│  │ TracingSvc  │  │ Structured  │  │ Observability           │   │
│  │             │  │ Logger      │  │ Dashboard               │   │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## 🔍 TraceContext 详细规范

### 数据结构
```swift
public struct TraceContext {
    public let traceId: String        // 16字符十六进制全局追踪ID
    public let spanId: String         // 8字符十六进制当前span ID
    public let parentSpanId: String?  // 父span ID (可选)
    public let operationName: String  // 操作名称
    public let startTime: Date        // 开始时间
    public let tags: [String: String] // 标签元数据
    public let baggage: [String: String] // 跨服务传播数据
}
```

### ID生成规则
```swift
// TraceID: 16字符小写十六进制
// 示例: "a1b2c3d4e5f67890"
private static func generateTraceId() -> String {
    return UUID().uuidString
        .replacingOccurrences(of: "-", with: "")
        .prefix(16)
        .lowercased()
}

// SpanID: 8字符小写十六进制  
// 示例: "12345678"
private static func generateSpanId() -> String {
    return UUID().uuidString
        .replacingOccurrences(of: "-", with: "")
        .prefix(8)
        .lowercased()
}
```

## 📊 Span 生命周期管理

### Span状态转换
```
[创建] → [活跃] → [完成] → [收集]
  ↓        ↓        ↓        ↓
TraceContext → 添加日志/度量 → Span对象 → 性能分析
```

### 完整的Span结构
```swift
public struct Span: Identifiable {
    public let id = UUID()                    // 内部唯一标识
    public let context: TraceContext          // 追踪上下文
    public let endTime: Date                  // 结束时间
    public let duration: TimeInterval         // 执行时长
    public let outcome: SpanOutcome           // 执行结果
    public let logs: [SpanLog]               // 日志条目
    public let metrics: [String: Double]     // 性能指标
}

public enum SpanOutcome {
    case success                             // 成功完成
    case error(Error)                       // 异常终止
    case cancelled                          // 取消执行
}
```

## 🚀 实际使用示例

### 1. 节点创建操作追踪
```swift
// 开始追踪
let context = TracingService.shared.startSpan(
    "node.create",
    tags: [
        "service": "NodeStore",
        "layer_id": currentLayer.id.uuidString,
        "user_action": "manual_creation"
    ]
)

do {
    // 业务逻辑执行
    let newNode = Node(text: text, phonetic: phonetic, meaning: meaning, 
                      layerId: currentLayer.id, tags: tags)
    
    // 添加中间日志
    let logEntry = SpanLog(level: .info, message: "节点验证完成", fields: [
        "node_text": text,
        "tag_count": String(tags.count)
    ])
    
    let success = addNode(newNode)
    
    // 成功完成
    TracingService.shared.finishSpan(context, outcome: .success, logs: [logEntry], metrics: [
        "validation_time_ms": validationTime * 1000,
        "tag_processing_time_ms": tagProcessingTime * 1000
    ])
    
} catch {
    // 异常处理
    TracingService.shared.finishSpan(context, outcome: .error(error))
}
```

### 2. 跨服务调用追踪
```swift
// SearchService中的搜索操作
func performAdvancedSearch(query: String, parentContext: TraceContext?) -> [SearchResult] {
    // 创建子span
    let searchContext = TracingService.shared.startSpan(
        "search.advanced_query",
        parentContext: parentContext,
        tags: [
            "service": "SearchService", 
            "query_length": String(query.count),
            "search_type": "advanced"
        ]
    )
    
    // 执行搜索
    let results = performSearch(query)
    
    // 调用其他服务 - 传播追踪上下文
    if hasLocationQuery(query) {
        let geocodeContext = TracingService.shared.startSpan(
            "geocoder.location_search", 
            parentContext: searchContext,
            tags: ["service": "GeocoderService"]
        )
        
        let locationResults = GeocoderService.shared.searchLocations(query, context: geocodeContext)
        TracingService.shared.finishSpan(geocodeContext, outcome: .success)
        
        results.append(contentsOf: locationResults)
    }
    
    TracingService.shared.finishSpan(searchContext, outcome: .success, metrics: [
        "result_count": Double(results.count),
        "search_duration_ms": searchDuration * 1000
    ])
    
    return results
}
```

### 3. 自动追踪装饰器
```swift
// 使用便利方法进行自动追踪
func saveNode(_ node: Node) async throws {
    try await TracingService.shared.traced(
        "node.save",
        tags: [
            "service": "NodeStore",
            "node_id": node.id.uuidString,
            "layer_id": node.layerId.uuidString
        ]
    ) { context in
        // 业务逻辑 - 自动处理成功/失败
        await ExternalDataService.shared.saveNode(node, context: context)
        
        // 触发Git同步 - 传播上下文
        await GitService.shared.commitChanges(
            message: "更新节点: \\(node.text)", 
            context: context
        )
    }
}
```

## 🔗 跨窗口追踪

### 多窗口操作追踪
```swift
// 主窗口发起的跨窗口操作
func openLayerGraphWindow() {
    let context = TracingService.shared.startSpan(
        "window.open_layer_graph",
        tags: [
            "source_window": "main",
            "target_window": "layer_graph", 
            "user_action": "command_k"
        ]
    )
    
    // 窗口预留检查
    let reservationContext = TracingService.shared.startSpan(
        "window.reserve_layer_graph",
        parentContext: context,
        tags: ["service": "WindowFocusManager"]
    )
    
    let reserved = WindowFocusManager.shared.reserveLayerGraphWindow(for: windowId.uuidString)
    TracingService.shared.finishSpan(
        reservationContext, 
        outcome: reserved ? .success : .error(WindowError.alreadyExists)
    )
    
    if reserved {
        // 通知发送
        let notificationContext = TracingService.shared.startSpan(
            "notification.send_execute_open_window",
            parentContext: context,
            tags: ["notification": "executeOpenWindow"]
        )
        
        NotificationCenter.default.post(
            name: NSNotification.Name("executeOpenWindow"),
            object: "layerGraph",
            userInfo: ["trace_context": context.traceId],  // 传播追踪上下文
            context: notificationContext
        )
        
        TracingService.shared.finishSpan(notificationContext, outcome: .success)
    }
    
    TracingService.shared.finishSpan(context, outcome: reserved ? .success : .cancelled)
}
```

### NotificationCenter追踪集成
```swift
// 扩展NotificationCenter支持追踪
extension NotificationCenter {
    public func post(
        name: NSNotification.Name,
        object: Any?,
        userInfo: [AnyHashable: Any]? = nil,
        context: TraceContext
    ) {
        var enrichedUserInfo = userInfo ?? [:]
        enrichedUserInfo["trace_id"] = context.traceId
        enrichedUserInfo["span_id"] = context.spanId
        enrichedUserInfo["operation"] = context.operationName
        
        post(name: name, object: object, userInfo: enrichedUserInfo)
        
        StructuredLogger.shared.trace("发送通知并传播追踪上下文", context: context, fields: [
            "notification": name.rawValue,
            "object_type": String(describing: type(of: object))
        ])
    }
}
```

## 📈 性能监控和分析

### 关键性能指标
```swift
public struct PerformanceMetrics {
    public let operationName: String         // 操作名称
    public let duration: TimeInterval        // 执行时长
    public let success: Bool                 // 成功状态
    public let tags: [String: String]        // 标签元数据
    public let timestamp: Date               // 时间戳
    public let memoryUsageMB: Double?        // 内存使用(MB)
    public let cpuUsage: Double?             // CPU使用率
}
```

### 操作性能汇总
```swift
public struct OperationMetricsSummary {
    public let operationName: String         // 操作名称
    public let totalCalls: Int              // 调用总数
    public let successRate: Double          // 成功率 (0.0-1.0)
    public let avgDuration: TimeInterval    // 平均耗时
    public let p50Duration: TimeInterval    // 50分位数耗时
    public let p95Duration: TimeInterval    // 95分位数耗时
    public let p99Duration: TimeInterval    // 99分位数耗时
}

// 使用示例
let nodeCreateMetrics = TracingService.shared.getMetricsSummary(operationName: "node.create")
print("节点创建平均耗时: \\(nodeCreateMetrics.avgDuration * 1000)ms")
print("成功率: \\(nodeCreateMetrics.successRate * 100)%")
```

## 🔍 结构化日志系统

### 日志级别和格式
```swift
public enum LogLevel: String, CaseIterable {
    case trace = "TRACE"    // 详细追踪信息
    case debug = "DEBUG"    // 调试信息  
    case info = "INFO"      // 一般信息
    case warn = "WARN"      // 警告
    case error = "ERROR"    // 错误
}
```

### 完整日志条目结构
```swift
public struct SpanLog {
    public let timestamp: Date              // 时间戳
    public let level: LogLevel             // 日志级别
    public let message: String             // 日志消息
    public let fields: [String: String]    // 结构化字段
    
    // 自动注入的追踪字段
    // - trace_id: 追踪ID
    // - span_id: 当前span ID
    // - operation: 操作名称
    // - file: 源文件名
    // - function: 函数名
    // - line: 行号
}
```

### 实际日志输出示例
```
[2025-09-07T15:30:25.123Z] INFO  开始节点创建操作 | trace_id=a1b2c3d4e5f67890 span_id=12345678 operation=node.create service=NodeStore layer_id=abc123 node_text=example file=NodeStore.swift function=addNode line=627

[2025-09-07T15:30:25.145Z] DEBUG 节点验证通过 | trace_id=a1b2c3d4e5f67890 span_id=12345678 validation_time_ms=15.2 tag_count=3

[2025-09-07T15:30:25.167Z] INFO  节点创建完成 | trace_id=a1b2c3d4e5f67890 span_id=12345678 duration_ms=44.5 success=true total_nodes=1247
```

## 📊 ObservabilityDashboard 功能

### 实时监控界面
```swift
struct ObservabilityDashboard: View {
    @StateObject private var tracingService = TracingService.shared
    @StateObject private var logger = StructuredLogger.shared
    
    var body: some View {
        VStack {
            // 实时指标卡片
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ]) {
                MetricCard(title: "活跃Spans", value: "\\(tracingService.activeSpans.count)")
                MetricCard(title: "完成Spans", value: "\\(tracingService.completedSpans.count)")
                MetricCard(title: "日志条目", value: "\\(logger.recentLogs.count)")
            }
            
            // 追踪时间线
            TraceTimelineView(spans: tracingService.completedSpans.suffix(50))
            
            // 性能热点分析
            PerformanceHeatmapView(metrics: tracingService.metrics.suffix(100))
            
            // 错误趋势
            ErrorTrendView(spans: tracingService.completedSpans.filter { !$0.outcome.isSuccess })
        }
        .navigationTitle("可观测性仪表板")
        .toolbar {
            Button("导出追踪数据") {
                exportTraceData()
            }
        }
    }
}
```

### 追踪数据导出
```swift
func exportTraceData() {
    let traces = TracingService.shared.completedSpans
    let exportData = TraceExportData(
        spans: traces,
        timeRange: Date().addingTimeInterval(-3600)...Date(),
        format: .jaeger  // 支持Jaeger格式导出
    )
    
    do {
        let jsonData = try JSONEncoder().encode(exportData)
        // 保存到文件或发送到追踪系统
        saveTraceData(jsonData)
    } catch {
        print("追踪数据导出失败: \\(error)")
    }
}
```

## 🎯 最佳实践

### 1. Span命名规范
```swift
// 格式: <service>.<operation>
// 好的例子:
"node.create"           // NodeStore创建节点
"search.advanced_query" // SearchService高级搜索  
"git.commit_changes"    // GitService提交更改
"window.open_layer_graph" // WindowFocusManager打开窗口

// 避免的例子:
"createNode"           // 缺少服务前缀
"node.create.with.tags.and.validation" // 过于详细
```

### 2. 标签使用指导
```swift
// 标准标签
let standardTags = [
    "service": "NodeStore",           // 服务名称 (必需)
    "operation": "create",            // 操作类型
    "user_id": "user123",            // 用户标识 (如有)
    "session_id": "session456",       // 会话标识
    "window_type": "main"             // 窗口类型
]

// 业务标签
let businessTags = [
    "layer_id": layer.id.uuidString,  // 业务对象ID
    "node_count": String(nodes.count), // 数量统计
    "search_type": "fuzzy",           // 操作子类型
    "error_code": "validation_failed" // 错误代码 (失败时)
]
```

### 3. 性能优化建议
```swift
// ✅ 推荐: 异步处理追踪数据
TracingService.shared.traced("heavy.operation") { context in
    // 重计算操作
    await performHeavyComputation()
}

// ✅ 推荐: 合理的span粒度
let context = TracingService.shared.startSpan("node.batch_update")
for node in nodes {
    // 不要为每个节点创建单独的span
    updateNode(node)
}
TracingService.shared.finishSpan(context, outcome: .success)

// ❌ 避免: 过细粒度的span
for node in nodes {
    let nodeContext = TracingService.shared.startSpan("node.single_update") // 过细
    updateNode(node)  
    TracingService.shared.finishSpan(nodeContext, outcome: .success)
}
```

## 🚨 告警和监控

### 关键告警规则
```swift
// 性能告警
if avgDuration > 5.0 { // 平均响应时间超过5秒
    AlertManager.shared.sendAlert(.performance(.slowResponse(
        operation: operationName,
        duration: avgDuration
    )))
}

// 错误率告警  
if errorRate > 0.05 { // 错误率超过5%
    AlertManager.shared.sendAlert(.reliability(.highErrorRate(
        operation: operationName,
        rate: errorRate
    )))
}

// 内存使用告警
if memoryUsage > 500.0 { // 内存使用超过500MB
    AlertManager.shared.sendAlert(.resource(.highMemoryUsage(
        service: serviceName,
        usage: memoryUsage
    )))
}
```

### 健康检查集成
```swift
// 集成到服务健康检查
extension TracingService: HealthCheckable {
    func checkHealth() async -> ServiceHealth {
        let metrics = collectMetrics()
        
        var status = ServiceHealth.Status.healthy
        var issues: [String] = []
        
        // 检查追踪系统健康状态
        if activeSpans.count > 1000 {
            status = .warning
            issues.append("活跃span数量过多: \\(activeSpans.count)")
        }
        
        if completedSpans.count > maxCompletedSpans {
            status = .critical  
            issues.append("完成span缓冲区即将溢出")
        }
        
        return ServiceHealth(
            status: status,
            message: issues.joined(separator: "; "),
            metrics: [
                "active_spans": Double(activeSpans.count),
                "completed_spans": Double(completedSpans.count),
                "avg_span_duration": metrics.avgDuration
            ]
        )
    }
}
```

## 🔧 故障排除

### 常见问题和解决方案

#### 1. 追踪上下文丢失
**问题**: 跨异步边界时追踪上下文丢失
```swift
// ❌ 错误: 异步调用中追踪上下文丢失
func processAsync() {
    Task {
        // 这里没有父追踪上下文
        await performOperation()
    }
}

// ✅ 正确: 显式传播追踪上下文
func processAsync(context: TraceContext) {
    Task.traced(context) { traceContext in
        await performOperation(context: traceContext)
    }
}
```

#### 2. 内存泄漏
**问题**: span对象未正确释放导致内存泄漏
```swift
// ✅ 自动清理机制
func cleanupOldSpans() {
    if completedSpans.count > maxCompletedSpans {
        let excessCount = completedSpans.count - maxCompletedSpans
        completedSpans.removeFirst(excessCount)
        print("清理了 \\(excessCount) 个旧span")
    }
}
```

#### 3. 性能影响
**问题**: 追踪系统本身影响应用性能
```swift
// ✅ 性能优化配置
struct TracingConfiguration {
    let maxActiveSpans: Int = 1000
    let maxCompletedSpans: Int = 10000  
    let samplingRate: Double = 0.1      // 10% 采样率
    let enableVerboseLogging: Bool = false
    let asyncLoggingQueue: DispatchQueue = DispatchQueue(
        label: "com.wordtagger.tracing", 
        qos: .utility
    )
}
```

## 📚 扩展和集成

### 与外部追踪系统集成
```swift
// Jaeger集成示例
class JaegerExporter: TraceExporter {
    func export(_ spans: [Span]) async throws {
        let jaegerSpans = spans.map { convertToJaegerFormat($0) }
        try await jaegerClient.submit(jaegerSpans)
    }
    
    private func convertToJaegerFormat(_ span: Span) -> JaegerSpan {
        return JaegerSpan(
            traceID: span.context.traceId,
            spanID: span.context.spanId,
            parentSpanID: span.context.parentSpanId,
            operationName: span.context.operationName,
            startTime: span.context.startTime,
            duration: span.duration,
            tags: span.context.tags,
            logs: span.logs.map { convertToJaegerLog($0) }
        )
    }
}
```

### 自定义指标收集器
```swift
class CustomMetricsCollector: MetricsCollector {
    func collectMetrics(for span: Span) -> [String: Double] {
        var metrics: [String: Double] = [:]
        
        // UI相关指标
        if span.context.tags["service"] == "ContentView" {
            metrics["ui_responsiveness_score"] = calculateUIResponsiveness(span)
        }
        
        // 数据库相关指标  
        if span.context.operationName.contains("data") {
            metrics["data_throughput_mbps"] = calculateDataThroughput(span)
        }
        
        return metrics
    }
}
```

## 📖 变更日志

### v2.0.0 (2025-09-07)
- ✅ 完整的分布式追踪系统实现
- ✅ 多窗口环境追踪支持
- ✅ 实时可观测性仪表板
- ✅ 性能监控和告警系统
- ✅ 结构化日志集成
- ✅ 外部追踪系统集成接口

### v1.9.0 (2024-12-xx)
- ✅ 基础追踪框架
- ✅ 简单的span生命周期管理
- ✅ 基本日志记录

---

WordTagger的分布式追踪系统为复杂的多窗口、多服务应用提供了完整的可观测性解决方案，确保系统运行的透明度和可维护性。