# WordTagger Service Catalog Overview

This document provides a comprehensive overview of the WordTagger service catalog, including service inventory, architecture overview, integration instructions, and lessons learned from enterprise-level development challenges.

## 🎓 项目发展历程与技术挑战

### 关键里程碑
- **2025年7月28日**: 项目启动，基础功能实现
- **2025年8月**: 多窗口架构和服务契约系统构建
- **2025年8-9月**: WebView稳定性危机处理和重构  
- **2025年9月**: 分布式追踪系统完成，企业级工程治理框架建立

### 核心技术突破
1. **多窗口架构**: 通过WindowFocusManager原子性预留机制解决竞态条件
2. **WebView现代化**: 完全移除废弃API，重新设计安全策略
3. **分布式追踪**: 从零构建企业级TraceID传播系统
4. **状态管理**: 跨Store实例数据传递的ID化解决方案
5. **错误恢复**: KeyboardEventManager的智能错误恢复机制
6. **快捷键优化**: 解决Command+B与系统冲突，优化为Command+N新建窗口

## 📊 Service Inventory Summary

WordTagger consists of **23 services** organized into 5 categories:

### Core Services (3)
- **node-store** - Central data management and state synchronization
- **data-manager** - Data import/export and validation  
- **external-data-manager** - External storage path management

### Specialized Services (5)
- **search-service** - Advanced search with fuzzy matching and filters
- **graph-service** - Graph visualization and relationship management
- **git-service** - Git integration with automated commits
- **external-data-service** - Data persistence and backup management
- **geocoder-service** - Geographic data processing and coordinate conversion

### Infrastructure Services (9)
- **tag-mapping-manager** - Tag type definitions and mappings  
- **keychain-manager** - Secure credential storage
- **keyboard-event-manager** - Global keyboard event handling
- **window-focus-manager** - Multi-window focus management and coordination
- **performance-optimization-service** - Performance monitoring and optimization
- **location-manager** - Geographic location services
- **resource-manager** - System resource monitoring and management
- **memory-leak-detection** - Memory usage monitoring and leak prevention
- **service-registry** - Central service registration and health monitoring

### UI Services (4)
- **command-palette-service** - Keyboard-driven command interface
- **map-container-service** - Interactive map visualization
- **fullscreen-graph-window-manager** - Graph window management
- **global-tag-graph-window-manager** - Global tag visualization windows

### Observability & Tracing Services (3)
- **tracing-service** - Distributed tracing with span lifecycle management
- **structured-logger** - Context-aware structured logging
- **observability-dashboard** - Real-time monitoring and trace visualization

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                   Observability & Tracing Services                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────┐   │
│  │ Tracing     │  │ Structured  │  │ Observability               │   │
│  │ Service     │  │ Logger      │  │ Dashboard                   │   │
│  └─────────────┘  └─────────────┘  └─────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                    │
┌─────────────────────────────────────────────────────────────────────┐
│                            UI Services                               │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐ │
│  │ CommandPal  │  │ MapContainer│  │ FullscreenGr │  │ GlobalTag   │ │
│  │ etteService │  │ Service     │  │ aphWinMgr    │  │ GraphWinMgr │ │
│  └─────────────┘  └─────────────┘  └──────────────┘  └─────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                                    │
┌─────────────────────────────────────────────────────────────────────┐
│                       Specialized Services                           │
│  ┌──────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐ │
│  │ Search   │  │ Graph       │  │ Git         │  │ External        │ │
│  │ Service  │  │ Service     │  │ Service     │  │ DataService     │ │
│  └──────────┘  └─────────────┘  └─────────────┘  └─────────────────┘ │
│  ┌──────────────────────────────────────────┐                       │
│  │            Geocoder Service              │                       │
│  └──────────────────────────────────────────┘                       │
└─────────────────────────────────────────────────────────────────────┘
                                    │
┌─────────────────────────────────────────────────────────────────────┐
│                        Core Services                                 │
│  ┌──────────┐  ┌─────────────┐  ┌─────────────────────────────────┐  │
│  │ NodeStore│  │ DataManager │  │ ExternalDataManager             │  │
│  └──────────┘  └─────────────┘  └─────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                    │
┌─────────────────────────────────────────────────────────────────────┐
│                     Infrastructure Services                          │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐ │
│  │ TagMapping  │  │ Keychain    │  │ Keyboard     │  │ WindowFocus │ │
│  │ Manager     │  │ Manager     │  │ EventMgr     │  │ Manager     │ │
│  └─────────────┘  └─────────────┘  └──────────────┘  └─────────────┘ │
│  ┌─────────────────────────────┐  ┌─────────────────────────────────┐ │
│  │ PerformanceOptimization     │  │ Location Manager                │ │
│  │ Service                     │  │                                 │ │
│  └─────────────────────────────┘  └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

## 🔍 Service Details

### Core Services

#### NodeStore
- **Version**: 2.0.0
- **Purpose**: Central data store managing nodes, layers, tags and application state
- **Key Features**: Real-time sync, duplicate detection, auto-backup, corruption repair, multi-window support
- **Performance**: High memory usage, medium CPU usage, high I/O operations
- **Health Metrics**: node_count, layer_count, search_operations_per_second, tag_filter_operations

#### DataManager  
- **Version**: 1.9.0
- **Purpose**: Manages data import/export operations with validation
- **Key Features**: JSON import/export, data validation, backward compatibility
- **Performance**: Low memory usage, medium CPU during operations
- **APIs**: exportData, importData, validateImportedData

#### ExternalDataManager
- **Version**: 1.9.0  
- **Purpose**: Manages external storage paths and access permissions
- **Key Features**: Path validation, access control, sandboxed file access
- **Security**: macOS App Sandbox compliant, secure bookmark resolution

### Specialized Services

#### SearchService
- **Version**: 1.9.0
- **Purpose**: Advanced search engine with multi-field search and fuzzy matching
- **Key Features**: Multi-field search, fuzzy matching, location-based search, semantic similarity
- **Performance**: Search threshold 0.3, max 100 results, <100ms response time
- **Health Metrics**: search_requests_per_second, average_search_time_ms

#### GraphService
- **Version**: 1.9.0
- **Purpose**: Graph visualization and relationship management
- **Key Features**: Multiple layout algorithms, real-time updates, relationship discovery
- **Performance**: High memory usage, very high CPU usage, 15s timeout
- **Algorithms**: force_directed, hierarchical, circular

#### GitService
- **Version**: 1.9.0
- **Purpose**: Git repository integration with automated commits
- **Key Features**: Automated commits, credential management, retry mechanisms
- **Security**: Keychain credential storage, TLS 1.3 encryption
- **Resilience**: Exponential backoff, 3 max retries, 30s timeout

### Infrastructure Services

#### WindowFocusManager
- **Version**: 2.0.0
- **Purpose**: Multi-window focus management and coordination
- **Key Features**: Window state tracking, notification routing, atomic operations, race condition prevention
- **Performance**: Low memory usage, minimal CPU impact, sub-millisecond response times
- **Health Metrics**: active_window_count, notification_routing_accuracy, race_condition_prevention_success
- **Race Condition Fixes**: Layer graph window duplication prevention, Command+T keyboard event routing

#### KeyboardEventManager
- **Version**: 2.0.0
- **Purpose**: Global keyboard event handling with multi-window support
- **Key Features**: Command throttling, error recovery, focus tracking, conflict resolution, cross-window coordination
- **Performance**: Real-time response, command cooldown period 0.5s
- **Health Metrics**: command_execution_rate, error_recovery_success, window_focus_accuracy

#### KeychainManager
- **Version**: 1.9.0
- **Purpose**: Secure credential storage using macOS Keychain Services
- **Key Features**: Generic Codable storage, Git credential specialization, secure deletion
- **Security**: Hardware-backed encryption, kSecAttrAccessibleWhenUnlocked
- **Service ID**: com.wordtagger.git

#### PerformanceOptimizationService
- **Version**: 1.9.0
- **Purpose**: Performance monitoring and optimization utilities
- **Key Features**: Real-time monitoring, memory leak detection, automatic optimization
- **Monitoring**: Memory usage, CPU usage, UI responsiveness, operation execution times
- **Alerts**: memory_usage_critical, cpu_usage_sustained_high

#### LocationManager
- **Version**: 1.9.0
- **Purpose**: Geographic location services and coordinate management
- **Key Features**: GPS data access, permission management, coordinate validation
- **Security**: Location permission handling, privacy-compliant data usage
- **Health Metrics**: location_accuracy, permission_status, coordinate_validation_rate

### UI Services

#### CommandPaletteService
- **Version**: 2.0.0
- **Purpose**: Keyboard-driven command interface with fuzzy search
- **Key Features**: Fuzzy command search, context-aware commands, extensible command system, multi-window support
- **Performance**: <50ms response time target, command history, window-aware command routing
- **Dependencies**: node-store, search-service, keyboard-event-manager, window-focus-manager

#### MapContainerService
- **Version**: 2.0.0
- **Purpose**: Geographic visualization with interactive maps
- **Key Features**: Interactive visualization, node clustering, location tag navigation, cached tile management
- **Performance**: Supports 1000 concurrent nodes, cached tile support, real-time updates
- **Dependencies**: node-store, geocoder-service, location-manager

#### FullscreenGraphWindowManager
- **Version**: 2.0.0
- **Purpose**: Graph window management with multi-window coordination
- **Key Features**: Fullscreen management, window state tracking, multi-window coordination
- **Performance**: Low memory footprint, efficient window lifecycle management
- **Dependencies**: window-focus-manager, graph-service

#### GlobalTagGraphWindowManager
- **Version**: 2.0.0
- **Purpose**: Global tag visualization window management
- **Key Features**: Global tag visualization, window lifecycle management, state synchronization
- **Performance**: Real-time tag graph updates, efficient memory usage
- **Dependencies**: window-focus-manager, tag-mapping-manager

### Observability & Tracing Services

#### TracingService
- **Version**: 2.0.0
- **Purpose**: Distributed tracing with span lifecycle management
- **Key Features**: Span creation and management, performance metrics collection, error tracking, trace tree building
- **Performance**: Low overhead tracing, sub-microsecond span creation, efficient metric aggregation
- **Health Metrics**: active_spans, completed_spans, trace_throughput, error_rate
- **Trace Format**: 16-char hex traceId, 8-char hex spanId, hierarchical span relationships

#### StructuredLogger
- **Version**: 2.0.0
- **Purpose**: Context-aware structured logging with trace correlation
- **Key Features**: Structured log formatting, trace context injection, log aggregation, level-based filtering
- **Performance**: Async logging queue, 1000 recent logs buffer, minimal performance impact
- **Log Levels**: TRACE, DEBUG, INFO, WARN, ERROR
- **Output**: Console with structured format, trace correlation via traceId/spanId

#### ObservabilityDashboard
- **Version**: 2.0.0
- **Purpose**: Real-time monitoring and trace visualization UI
- **Key Features**: Real-time metrics visualization, trace timeline view, performance analysis, health monitoring
- **Performance**: Live dashboard updates, efficient chart rendering, interactive trace exploration
- **Dependencies**: tracing-service, structured-logger
- **Metrics Displayed**: Service health, response times, error rates, memory usage, trace flows

## 🚀 Integration Guide

### 1. Setting Up the Service Registry

Add the ServiceRegistry to your app initialization:

```swift
@main
struct WordTaggerApp: App {
    init() {
        // Initialize service registry
        setupServices()
    }
    
    private func setupServices() {
        let registry = ServiceRegistry.shared
        
        // Services are auto-registered, but you can customize:
        registry.enableHealthChecks()
        registry.forceHealthCheck() // Initial health check
        
        print("✅ Service registry initialized with \(registry.getAllServices().count) services")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ServiceRegistry.shared)
        }
        
        // Service Health Dashboard (optional)
        WindowGroup("Service Health") {
            ServiceHealthDashboard()
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "service-health"))
    }
}
```

### 2. Using Services in SwiftUI Views

Access services through the registry:

```swift
struct MyView: View {
    @EnvironmentObject var serviceRegistry: ServiceRegistry
    
    private var nodeStore: NodeStore {
        serviceRegistry.resolve(NodeStore.self)!
    }
    
    private var searchService: SearchService {
        serviceRegistry.resolve(SearchService.self)!
    }
    
    var body: some View {
        // Use services...
    }
}
```

### 3. Service Health Monitoring

Add the Service Health Dashboard to monitor system health:

```swift
// In your menu bar or toolbar
Button("Service Health") {
    if let url = URL(string: "wordtagger://service-health") {
        NSWorkspace.shared.open(url)
    }
}
```

### 4. Custom Service Registration

Register custom services:

```swift
class MyCustomService: ObservableObject, HealthCheckable {
    func checkHealth() async -> ServiceHealth {
        // Implement health check
        return ServiceHealth(status: .healthy)
    }
}

// Register the service
ServiceRegistry.shared.register(MyCustomService(), for: MyCustomService.self, name: "my-service")
```

## 📈 Monitoring and Observability

### Health Check Status

Services report health status in 4 levels:
- **Healthy** 🟢: Service operating normally
- **Warning** 🟡: Service has minor issues but still functional
- **Critical** 🔴: Service has serious issues affecting functionality  
- **Unknown** ⚪: Health status cannot be determined

### Performance Metrics

Key metrics tracked across services:
- **Memory Usage**: Current memory consumption in MB
- **CPU Usage**: CPU utilization percentage
- **Response Times**: API call latencies in milliseconds
- **Error Rates**: Success/failure ratios
- **Throughput**: Operations per second/minute

### Alerting

Automated alerts for:
- High memory usage (>500MB for individual services)
- Sustained high CPU usage (>70% for 30+ seconds)
- Service health degradation (healthy → warning/critical)
- Authentication failures
- Network connectivity issues

## 🛡️ Security Considerations

### Credential Management
- All credentials stored in macOS Keychain
- Hardware-backed encryption when available
- Service-specific access controls
- Automatic credential rotation support

### Data Protection
- App Sandbox compliance
- Secure file access through bookmarks
- Encrypted external data storage
- No secrets in source code or logs

### Network Security
- TLS 1.3 for all network communications
- Certificate pinning for Git operations
- Request/response validation
- Rate limiting and timeout protection

## 🔧 Troubleshooting

### Common Issues

#### Service Registry Issues
```bash
# Check service registration
print(ServiceRegistry.shared.getAllServices().map { $0.name })

# Force health check
ServiceRegistry.shared.forceHealthCheck()

# Check dependencies
let issues = ServiceRegistry.shared.validateDependencies()
print("Dependency issues: \(issues)")
```

#### Service Health Issues
```bash
# Check individual service health
let health = ServiceRegistry.shared.health(for: "node-store")
print("NodeStore health: \(health.status) - \(health.message ?? "")")

# Get metrics
if let metrics = health.metrics {
    for (key, value) in metrics {
        print("\(key): \(value)")
    }
}
```

#### Performance Issues
```bash
# Enable performance mode
if let perfService = ServiceRegistry.shared.resolve(PerformanceOptimizationService.self) {
    perfService.enablePerformanceMode(true)
    let report = perfService.generatePerformanceReport()
    print("Performance report: \(report)")
}
```

### Service Recovery

Services support automatic recovery:
```swift
// Manual recovery
let success = await ServiceRegistry.shared.recoverService("git-service")
if success {
    print("Service recovered successfully")
} else {
    print("Service recovery failed")
}

// Check recovery strategies
if let gitService = ServiceRegistry.shared.resolve(GitService.self) as? ServiceRecoveryProtocol {
    print("Recovery strategies: \(gitService.recoveryStrategies)")
}
```

## 📚 Additional Resources

### Documentation Structure
```
docs/
├── services/                 # Individual service YAML definitions
├── contracts/               # Service contracts and API specifications  
├── runbooks/               # Troubleshooting guides for each service
├── architecture/           # Architecture diagrams and analysis
└── service-lifecycle-management.md  # Lifecycle management guide
```

### Key Files
- **ServiceRegistry.swift**: Core service registry implementation
- **ServiceHealthDashboard.swift**: Health monitoring UI
- **service-contracts.md**: Comprehensive API contracts
- **service-lifecycle-management.md**: Lifecycle management processes

### Service YAML Files
Each service has a corresponding YAML file in `docs/services/` containing:
- Service metadata and configuration
- API definitions and parameters  
- Performance characteristics
- Monitoring and alerting configuration
- Dependencies and relationships

---

## 🎯 Next Steps

1. **Integration**: Add ServiceRegistry to your app initialization
2. **Monitoring**: Set up the Service Health Dashboard  
3. **Customization**: Register any custom services you need
4. **Testing**: Run integration tests to verify service interactions
5. **Production**: Monitor service health in production environments

This service catalog provides complete visibility into the WordTagger service ecosystem, enabling effective monitoring, troubleshooting, and maintenance of the application's service-oriented architecture.