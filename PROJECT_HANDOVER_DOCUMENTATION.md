# WordTagger 项目交接文档

## 📋 项目概述

**WordTagger** 是一个基于 Swift/SwiftUI 的智能节点标签管理应用，采用现代化的微服务架构和分布式追踪系统，支持多窗口环境和复杂的数据可视化。

### 基本信息
- **平台**: macOS (SwiftUI + AppKit)
- **架构**: 微服务 + MVVM + 事件驱动
- **语言**: Swift 5.9+, JavaScript (工具链), Mermaid (架构图)
- **依赖**: Git集成, MapKit, Combine, 分布式追踪
- **版本**: 2.0.0

## 🏗️ 系统架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                        UI Services                               │
│  ┌─────────────┐  ┌─────────────────┐  ┌────────────────────┐   │
│  │ CommandPal  │  │ MapContainer    │  │ FullscreenGraph    │   │
│  │ etteService │  │ Service         │  │ WindowManager      │   │
│  └─────────────┘  └─────────────────┘  └────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────────┐
│                   Specialized Services                           │
│  ┌──────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │ Search   │  │ Graph       │  │ Git         │  │ External    │ │
│  │ Service  │  │ Service     │  │ Service     │  │ DataService │ │
│  └──────────┘  └─────────────┘  └─────────────┘  └─────────────┘ │
│  ┌──────────┐  ┌─────────────┐                                   │
│  │ Geocoder │  │ TagMapping  │                                   │
│  │ Service  │  │ Manager     │                                   │
│  └──────────┘  └─────────────┘                                   │
└─────────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────────┐
│                    Core Services                                 │
│  ┌──────────┐  ┌─────────────┐  ┌─────────────────────────────┐  │
│  │ NodeStore│  │ DataManager │  │ ExternalDataManager         │  │
│  └──────────┘  └─────────────┘  └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────────┐
│                 Infrastructure Services                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐   │
│  │ Keychain    │  │ Keyboard    │  │ PerformanceOptimization │   │
│  │ Manager     │  │ EventMgr    │  │ Service                 │   │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘   │
│  ┌─────────────┐                                                 │
│  │ Location    │                                                 │
│  │ Manager     │                                                 │
│  └─────────────┘                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 🔧 服务清单 (20个服务)

### 🎯 Core Services (3个)
| 服务名 | 版本 | 职责 | 关键特性 |
|--------|------|------|----------|
| **NodeStore** | 1.9.0 | 中央数据状态管理 | @Published响应式属性、层/节点管理、搜索协调、标签过滤 |
| **DataManager** | 1.9.0 | 数据导入导出管理 | JSON处理、数据验证、向后兼容性 |
| **ExternalDataManager** | 1.9.0 | 外部存储路径管理 | 路径验证、访问控制、沙盒文件访问 |

### ⚡ Specialized Services (5个)  
| 服务名 | 版本 | 职责 | 关键特性 |
|--------|------|------|----------|
| **SearchService** | 1.9.0 | 高级搜索引擎 | 多字段搜索、模糊匹配、位置搜索、语义相似性 |
| **GraphService** | 1.9.0 | 图可视化和关系管理 | 多种布局算法、实时更新、关系发现 |
| **GitService** | 1.9.0 | Git集成自动提交 | 凭据管理、重试机制、进度报告 |
| **ExternalDataService** | 1.9.0 | 数据持久化和备份 | 异步保存/加载、备份管理、损坏恢复 |
| **GeocoderService** | 1.9.0 | 地理数据处理 | 地址解析、坐标转换、位置验证 |

### 🛠️ Infrastructure Services (6个)
| 服务名 | 版本 | 职责 | 关键特性 |
|--------|------|------|----------|
| **TagMappingManager** | 1.9.0 | 标签类型定义映射 | 类型映射、显示名称、自定义标签 |
| **KeychainManager** | 1.9.0 | 安全凭据存储 | macOS Keychain、Git凭据、安全删除 |
| **KeyboardEventManager** | 2.0.0 | 全局键盘事件处理 | 命令限流、错误恢复、焦点跟踪、多窗口协调 |
| **WindowFocusManager** | 2.0.0 | 多窗口焦点管理协调 | 窗口状态跟踪、通知路由、原子操作、竞态防护 |
| **PerformanceOptimizationService** | 1.9.0 | 性能监控优化 | 实时监控、内存泄漏检测、自动优化 |
| **LocationManager** | 1.9.0 | 地理位置服务 | 位置获取、权限管理、精度控制 |

### 🎨 UI Services (4个)
| 服务名 | 版本 | 职责 | 关键特性 |
|--------|------|------|----------|
| **CommandPaletteService** | 2.0.0 | 键盘驱动命令界面 | 模糊命令搜索、上下文感知、可扩展命令、多窗口支持 |
| **MapContainerService** | 2.0.0 | 交互式地图可视化 | 节点聚类、位置标签导航、缓存瓦片、实时更新 |
| **FullscreenGraphWindowManager** | 2.0.0 | 图形窗口管理 | 全屏图形、窗口状态、多窗口协调 |
| **GlobalTagGraphWindowManager** | 2.0.0 | 全局标签可视化窗口管理 | 全局标签图谱、窗口生命周期、状态同步 |

### 📊 Observability & Tracing Services (3个)
| 服务名 | 版本 | 职责 | 关键特性 |
|--------|------|------|----------|
| **TracingService** | 2.0.0 | 分布式追踪核心引擎 | TraceID生成、Span管理、性能指标、错误追踪 |
| **StructuredLogger** | 2.0.0 | 上下文感知结构化日志 | 追踪关联、日志聚合、级别过滤、异步处理 |
| **ObservabilityDashboard** | 2.0.0 | 实时监控可视化 | 追踪时间线、性能分析、健康监控、交互式探索 |

## 📡 接口契约系统

### 契约类型
1. **Swift Protocol Contracts** - 编译时类型安全
2. **AsyncAPI Event Contracts** - NotificationCenter事件规范  
3. **JSON Schema Data Contracts** - 运行时数据验证
4. **Validation Tools** - 自动化契约测试

### 关键契约文件
```
docs/contracts/
├── swift/service-protocols.swift         # Swift接口定义
├── events/wordtagger-events.asyncapi.yaml # 事件规范
├── schemas/                               # 数据契约
│   ├── node.schema.json                  # 节点数据验证
│   ├── layer.schema.json                 # 层数据验证  
│   ├── search-result.schema.json         # 搜索结果格式
│   ├── git-credentials.schema.json       # Git认证格式
│   └── external-data-format.schema.json  # 外部存储格式
└── tools/                                # 验证工具
    ├── contract-validator.swift          # Swift运行时验证
    └── contract-test-suite.js            # JavaScript验证工具
```

### 通信模式
1. **@Published 响应式绑定** - UI状态同步
2. **NotificationCenter 事件** - 解耦服务通信
3. **Async/Await 操作** - 结构化并发
4. **进度回调** - 长期运行操作追踪

## 🕵️ TraceID 分布式追踪系统

### 追踪基础设施
```swift
// 追踪上下文结构
public struct TraceContext {
    public let traceId: String      // 16字符十六进制唯一标识
    public let spanId: String       // 8字符十六进制当前span标识  
    public let parentSpanId: String? // 父span标识
    public let operationName: String // 操作名称
    public let startTime: Date      // 开始时间
    public let tags: [String: String] // 标签元数据
    public let baggage: [String: String] // 传播数据
}
```

### 关键组件
| 组件 | 文件 | 功能 |
|------|------|------|
| **TracingInfrastructure.swift** | 核心基础设施 | TraceContext、Span、追踪生命周期管理 |
| **TracingIntegration.swift** | 集成层 | NotificationCenter追踪传播、自动上下文注入 |
| **TracedServices.swift** | 服务装饰器 | 自动为服务添加追踪能力 |
| **ObservabilityDashboard.swift** | 监控仪表板 | 实时追踪可视化、性能分析 |

### 追踪数据流
```
用户操作 → TraceContext生成 → 服务调用链 → Span收集 → 
性能分析 → 错误追踪 → 可观测性仪表板
```

### 追踪示例
```swift
// 自动追踪的服务操作
let context = TraceContext(operationName: "node.create")
let tracedNodeStore = TracedNodeStore(nodeStore, tracer: tracer)
await tracedNodeStore.addNode(newNode, context: context)

// 生成的trace数据
{
  "trace_id": "a1b2c3d4e5f67890", 
  "spans": [
    {
      "span_id": "12345678",
      "operation": "node.create",
      "duration_ms": 45,
      "status": "success",
      "tags": {
        "service": "NodeStore",
        "layer_id": "layer_abc",
        "node_type": "compound"
      }
    }
  ]
}
```

## 🔄 数据流架构

### 主要数据流
```
UI Action → NodeStore → ExternalDataService → File System
              ↓
        NotificationCenter → GitService → Git Repository  
              ↓
        @Published Update → UI Refresh
```

### 标签系统流
```
Tag Modification → TagMappingManager → NotificationCenter
                                           ↓
                                      NodeStore → UI Update
                                           ↓  
                                  ExternalDataService → Persistence
```

### 错误恢复流
```
Error Detection → KeyboardEventManager → Error Recovery Mode
                                              ↓
                  State Cleanup → Normal Operation → Recovery Exit
```

## 🗂️ 关键文件结构

### 核心代码文件
```
WordTagger/
├── WordTaggerApp.swift           # 应用入口和配置
├── ContentView.swift             # 主界面视图
├── NodeStore.swift               # 中央数据存储
├── WindowFocusManager.swift      # 多窗口焦点管理 
├── LayerGraphWindowView.swift    # 层图谱窗口
├── TracingInfrastructure.swift   # 分布式追踪基础
├── TracingIntegration.swift      # 追踪集成层
├── ObservabilityDashboard.swift  # 可观测性仪表板
└── Services/                     # 各种业务服务
    ├── SearchService.swift
    ├── GitService.swift
    ├── GraphService.swift
    └── ...
```

### 文档文件
```
docs/
├── architecture/                 # 架构文档
│   ├── README.md                # 架构概述
│   ├── wordtagger-complete-architecture.mmd # 完整架构图
│   ├── l2.mmd                   # L2服务目录图
│   └── data-flow-patterns.mmd   # 数据流模式
├── services/                    # 服务定义（YAML格式）
├── contracts/                   # 接口契约
├── runbooks/                    # 故障排除指南
└── SERVICE_CATALOG_OVERVIEW.md  # 服务目录概述
```

## 🚀 开发和部署

### 开发环境设置
```bash
# 克隆仓库
git clone <repository-url>
cd WordTagger

# 安装依赖
npm install  # JavaScript工具链依赖

# 打开Xcode项目
open WordTagger.xcodeproj

# 运行契约验证
cd docs/contracts/tools
npm test
```

### 构建配置
- **开发**: Debug模式，完整追踪，详细日志
- **生产**: Release模式，优化追踪，必要日志
- **测试**: 专用追踪配置，模拟数据

### 关键快捷键
| 快捷键 | 功能 |
|--------|------|
| ⌘K | 命令面板/层图谱窗口 |
| ⌘N | 清除标签筛选 |
| ⌘T | 恢复标签筛选状态 |
| ⌘M | 地图窗口 |
| ⌘G | 全局节点图谱 |
| ⌘E | 切换侧边栏 |

## 📊 性能指标和监控

### 关键性能指标 (KPI)
- **搜索响应时间**: <100ms
- **UI更新延迟**: <16ms (60fps)
- **内存使用**: <500MB per service
- **CPU使用**: <70% sustained
- **数据同步**: <5s for full sync

### 监控工具
1. **ServiceHealthDashboard.swift** - 服务健康监控
2. **PerformanceOptimizationService** - 性能监控
3. **ObservabilityDashboard.swift** - 追踪可视化
4. **内存泄漏检测** - 自动检测和报告

## 🔒 安全考虑

### 数据保护
- App Sandbox合规
- 通过书签的安全文件访问
- 加密外部数据存储
- 源码和日志中无秘密信息

### 凭据管理
- macOS Keychain存储所有凭据
- 硬件支持的加密
- 服务特定的访问控制
- 自动凭据轮换支持

### 网络安全
- 所有网络通信使用TLS 1.3
- Git操作的证书锁定
- 请求/响应验证
- 限流和超时保护

## 🛠️ 故障排除

### 常见问题

#### 1. 服务注册问题
```swift
// 检查服务注册
print(ServiceRegistry.shared.getAllServices().map { $0.name })

// 强制健康检查
ServiceRegistry.shared.forceHealthCheck()
```

#### 2. 窗口焦点问题
```swift  
// 强制刷新窗口状态
WindowFocusManager.shared.forceRefreshWindowState()

// 检查窗口映射
let debugInfo = WindowFocusManager.shared.getDebugInfo()
```

#### 3. 层图谱重复窗口问题
- **已修复**: 使用原子性预留机制防止竞态条件
- **监控**: 通过日志确认只创建一个窗口

### 日志和调试
```swift
// 启用详细追踪日志
TracingConfiguration.shared.enableVerboseLogging = true

// 查看追踪数据
let traces = TracingCollector.shared.getTraces(timeRange: lastHour)
traces.forEach { trace in
    print("Trace: \(trace.traceId), Duration: \(trace.totalDuration)ms")
}
```

## 📞 联系信息和资源

### 项目资源
- **架构图**: `docs/architecture/*.mmd` (使用 [mermaid.live](https://mermaid.live) 查看)
- **API文档**: `docs/contracts/service-contracts.md`
- **服务目录**: `docs/SERVICE_CATALOG_OVERVIEW.md`
- **故障排除**: `docs/runbooks/`

### 开发工具
- **Xcode** 15.0+
- **Swift** 5.9+  
- **Mermaid CLI**: `npm install -g @mermaid-js/mermaid-cli`
- **契约验证**: `cd docs/contracts/tools && npm test`

### 最近更新
- ✅ **2025-09-07**: 修复主窗口Command+T键盘快捷键不响应问题 (ContentView.swift:188-193)
- ✅ **2025-09-07**: 实现WindowFocusManager原子性预留机制防止层图谱窗口重复创建
- ✅ **2025-09-07**: 完整分布式追踪系统升级 (20个服务，TraceID + Span管理)
- ✅ **2025-09-07**: 更新架构文档、服务清单、接口契约和项目交接文档
- ✅ **2024-12**: 基础分布式追踪系统实现
- ✅ **2024-11**: 完善服务契约系统
- ✅ **2024-10**: 多窗口焦点管理优化

---

## 📋 交接检查清单

### 接收方需要确认的项目
- [ ] 开发环境设置完成
- [ ] 项目能正常编译运行
- [ ] 理解架构图和服务关系  
- [ ] 熟悉追踪系统和调试方法
- [ ] 了解常见问题和解决方案
- [ ] 掌握性能监控和健康检查
- [ ] 能够修改契约和验证测试

### 权限和访问
- [ ] Git仓库访问权限
- [ ] 开发者证书和签名配置
- [ ] 第三方服务账户(如果有)
- [ ] 测试设备和环境访问

这份文档提供了WordTagger项目的完整技术架构概览，包含所有必要的技术细节和运维知识，确保项目能够顺利交接给新的维护团队。