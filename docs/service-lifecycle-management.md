# Service Lifecycle Management

This document defines the lifecycle management processes for WordTagger services, including initialization, dependency management, health monitoring, and graceful shutdown.

## Overview

WordTagger services follow a well-defined lifecycle that ensures proper initialization order, dependency resolution, health monitoring, and clean shutdown. The ServiceRegistry manages these lifecycles automatically while providing hooks for manual intervention when needed.

## Service Lifecycle Phases

### 1. Registration Phase

Services are registered with the ServiceRegistry during app initialization:

```swift
// Automatic registration during app startup
@main
struct WordTaggerApp: App {
    init() {
        // Services are automatically registered by ServiceRegistry.shared
        setupServiceRegistry()
    }
    
    private func setupServiceRegistry() {
        let registry = ServiceRegistry.shared
        
        // Core services (registered first)
        registry.register(NodeStore.shared, for: NodeStore.self, name: "node-store")
        registry.register(KeychainManager.shared, for: KeychainManager.self, name: "keychain-manager")
        
        // Infrastructure services  
        registry.register(ExternalDataManager.shared, for: ExternalDataManager.self, name: "external-data-manager")
        registry.register(ExternalDataService.shared, for: ExternalDataService.self, name: "external-data-service")
        
        // Specialized services (depend on core services)
        registry.register(SearchService.shared, for: SearchService.self, name: "search-service")
        registry.register(GitService.shared, for: GitService.self, name: "git-service")
        
        print("✅ All services registered successfully")
    }
}
```

### 2. Initialization Phase

Services initialize in dependency order:

#### Core Services First
1. **KeychainManager** - No dependencies
2. **NodeStore** - Depends on ExternalDataService, ExternalDataManager
3. **PerformanceOptimizationService** - No dependencies

#### Infrastructure Services  
1. **ExternalDataManager** - No dependencies
2. **ExternalDataService** - Depends on ExternalDataManager
3. **TagMappingManager** - No dependencies

#### Specialized Services
1. **SearchService** - Depends on NodeStore
2. **GitService** - Depends on KeychainManager, ExternalDataService  
3. **GraphService** - Depends on NodeStore, SearchService

#### UI Services (Last)
1. **CommandPaletteService** - Depends on NodeStore, SearchService
2. **MapContainerService** - Depends on NodeStore, GeocoderService

### 3. Health Monitoring Phase

Services enter continuous health monitoring after successful initialization:

```swift
// Health monitoring configuration
private func configureHealthMonitoring() {
    let registry = ServiceRegistry.shared
    
    // Enable health checks with 30-second interval
    registry.enableHealthChecks()
    
    // Configure service-specific health check parameters
    configureServiceHealth("node-store", alertThreshold: 0.8)
    configureServiceHealth("search-service", alertThreshold: 0.9)
    configureServiceHealth("git-service", alertThreshold: 0.7)
}

private func configureServiceHealth(_ serviceName: String, alertThreshold: Double) {
    // Service-specific health monitoring configuration
    switch serviceName {
    case "node-store":
        // Monitor memory usage, sync operations, data integrity
        break
    case "search-service":
        // Monitor search performance, CPU usage
        break
    case "git-service":
        // Monitor network connectivity, authentication status
        break
    default:
        break
    }
}
```

### 4. Runtime Phase

During normal operation, services:
- Respond to API calls
- Publish state changes via @Published properties
- Participate in health checks
- Log operations and metrics
- Handle errors gracefully

### 5. Shutdown Phase

Services shutdown in reverse dependency order:

```swift
class ServiceRegistry {
    func gracefulShutdown() async {
        print("🛑 Initiating graceful service shutdown...")
        
        // Stop health monitoring
        disableHealthChecks()
        
        // Shutdown in reverse dependency order
        await shutdownUIServices()
        await shutdownSpecializedServices()  
        await shutdownInfrastructureServices()
        await shutdownCoreServices()
        
        print("✅ All services shutdown complete")
    }
    
    private func shutdownUIServices() async {
        // CommandPaletteService, MapContainerService
        await shutdownService("command-palette-service")
        await shutdownService("map-container-service")
    }
    
    private func shutdownSpecializedServices() async {
        // GraphService, GitService, SearchService  
        await shutdownService("graph-service")
        await shutdownService("git-service")
        await shutdownService("search-service")
    }
    
    private func shutdownInfrastructureServices() async {
        // ExternalDataService, ExternalDataManager
        await shutdownService("external-data-service")
        await shutdownService("external-data-manager") 
        await shutdownService("tag-mapping-manager")
    }
    
    private func shutdownCoreServices() async {
        // NodeStore, KeychainManager, PerformanceOptimizationService
        await shutdownService("node-store")
        await shutdownService("keychain-manager")
        await shutdownService("performance-optimization-service")
    }
    
    private func shutdownService(_ serviceName: String) async {
        guard let service = services[serviceName] else { return }
        
        print("🛑 Shutting down service: \(serviceName)")
        
        // Call shutdown method if service implements ShutdownProtocol
        if let shutdownService = service as? ServiceShutdownProtocol {
            do {
                await shutdownService.shutdown()
                print("✅ \(serviceName) shutdown complete")
            } catch {
                print("❌ \(serviceName) shutdown failed: \(error)")
            }
        }
        
        // Remove from registry
        services.removeValue(forKey: serviceName)
        serviceHealth.removeValue(forKey: serviceName)
    }
}
```

## Dependency Management

### Dependency Resolution

The ServiceRegistry maintains a dependency graph and resolves dependencies automatically:

```swift
class ServiceRegistry {
    func getDependencyGraph() -> [String: [String]] {
        // Returns service dependency mappings
        return [
            "node-store": ["external-data-service", "external-data-manager", "tag-mapping-manager"],
            "search-service": ["node-store"],
            "git-service": ["keychain-manager", "external-data-service"],
            "graph-service": ["node-store", "search-service"],
            "command-palette-service": ["node-store", "search-service", "keyboard-event-manager"],
            "map-container-service": ["node-store", "geocoder-service"],
            "external-data-service": ["external-data-manager"]
        ]
    }
    
    func validateDependencies() -> [String] {
        var issues: [String] = []
        let graph = getDependencyGraph()
        
        for (service, dependencies) in graph {
            for dependency in dependencies {
                if services[dependency] == nil {
                    issues.append("Service '\(service)' depends on missing service '\(dependency)'")
                }
            }
        }
        
        return issues
    }
    
    func checkCircularDependencies() -> [String] {
        // Implement topological sort to detect circular dependencies
        var visited: Set<String> = []
        var recursionStack: Set<String> = []
        var cycles: [String] = []
        
        func dfs(_ service: String) {
            visited.insert(service)
            recursionStack.insert(service)
            
            let dependencies = getDependencyGraph()[service] ?? []
            for dependency in dependencies {
                if !visited.contains(dependency) {
                    dfs(dependency)
                } else if recursionStack.contains(dependency) {
                    cycles.append("Circular dependency detected: \(service) -> \(dependency)")
                }
            }
            
            recursionStack.remove(service)
        }
        
        for service in services.keys {
            if !visited.contains(service) {
                dfs(service)
            }
        }
        
        return cycles
    }
}
```

### Service Injection

Services can access dependencies through the registry:

```swift
// Good: Dependency injection in initializer
class SearchService: ObservableObject {
    private let nodeStore: NodeStore
    
    init(nodeStore: NodeStore = ServiceRegistry.shared.resolve(NodeStore.self)!) {
        self.nodeStore = nodeStore
    }
}

// Better: Protocol-based injection for testability  
class SearchService: ObservableObject {
    private let nodeStore: NodeStoreProtocol
    
    init(nodeStore: NodeStoreProtocol) {
        self.nodeStore = nodeStore
    }
}
```

## Health Monitoring

### Health Check Implementation

Services implement the `HealthCheckable` protocol:

```swift
public protocol HealthCheckable {
    func checkHealth() async -> ServiceHealth
}

// Example implementation
extension NodeStore: HealthCheckable {
    public func checkHealth() async -> ServiceHealth {
        let nodeCount = await MainActor.run { nodes.count }
        let layerCount = await MainActor.run { layers.count }
        let isLoading = await MainActor.run { self.isLoading }
        
        var metrics: [String: Double] = [
            "node_count": Double(nodeCount),
            "layer_count": Double(layerCount),
            "memory_usage_mb": getMemoryUsage()
        ]
        
        // Check for critical conditions
        if isLoading && Date().timeIntervalSince(loadingStartTime) > 30 {
            return ServiceHealth(
                status: .critical,
                message: "Loading operation stuck for over 30 seconds",
                metrics: metrics
            )
        }
        
        // Check for warning conditions
        if nodeCount == 0 && layerCount == 0 {
            return ServiceHealth(
                status: .warning,
                message: "No data loaded",
                metrics: metrics
            )
        }
        
        // Check memory usage
        let memoryUsageMB = getMemoryUsage()
        if memoryUsageMB > 500 {
            return ServiceHealth(
                status: .warning,
                message: "High memory usage: \(Int(memoryUsageMB))MB",
                metrics: metrics
            )
        }
        
        return ServiceHealth(
            status: .healthy,
            message: "Service is operating normally",
            metrics: metrics
        )
    }
    
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0
        }
        return 0.0
    }
}
```

### Health Check Scheduling

Health checks run on a configurable schedule:

```swift
class ServiceRegistry {
    private var healthCheckTimer: Timer?
    private let healthCheckInterval: TimeInterval = 30.0
    
    func startHealthMonitoring() {
        guard isHealthCheckEnabled else { return }
        
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: healthCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performHealthChecks()
            }
        }
    }
    
    private func performHealthChecks() async {
        let startTime = CFAbsoluteTimeGetCurrent()
        var healthResults: [String: ServiceHealth] = [:]
        
        // Perform health checks concurrently
        await withTaskGroup(of: (String, ServiceHealth).self) { group in
            for (serviceName, service) in services {
                group.addTask {
                    let health: ServiceHealth
                    if let healthCheckable = service as? HealthCheckable {
                        health = await healthCheckable.checkHealth()
                    } else {
                        health = ServiceHealth(status: .unknown, message: "Health check not implemented")
                    }
                    return (serviceName, health)
                }
            }
            
            for await (serviceName, health) in group {
                healthResults[serviceName] = health
            }
        }
        
        // Update health status and trigger alerts
        for (serviceName, health) in healthResults {
            let previousHealth = serviceHealth[serviceName]
            serviceHealth[serviceName] = health
            
            // Check for status changes and trigger alerts
            if let previous = previousHealth, previous.status != health.status {
                handleHealthStatusChange(serviceName: serviceName, from: previous.status, to: health.status)
            }
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        print("🏥 Health check cycle completed in \(String(format: "%.2f", duration))s")
    }
    
    private func handleHealthStatusChange(serviceName: String, from: ServiceHealthStatus, to: ServiceHealthStatus) {
        let message = "Service '\(serviceName)' status changed: \(from.rawValue) -> \(to.rawValue)"
        
        switch to {
        case .critical:
            print("🚨 CRITICAL: \(message)")
            // Could trigger notifications, alerts, etc.
        case .warning:
            print("⚠️ WARNING: \(message)")
        case .healthy:
            if from != .healthy {
                print("✅ RECOVERED: \(message)")
            }
        case .unknown:
            print("❓ UNKNOWN: \(message)")
        }
        
        // Notify observers of health status change
        NotificationCenter.default.post(
            name: .serviceHealthChanged,
            object: nil,
            userInfo: [
                "serviceName": serviceName,
                "previousStatus": from,
                "currentStatus": to
            ]
        )
    }
}

// Notification names
extension Notification.Name {
    static let serviceHealthChanged = Notification.Name("serviceHealthChanged")
}
```

## Service Recovery

### Automatic Recovery

Services implement automatic recovery strategies:

```swift
public protocol ServiceRecoveryProtocol {
    func attemptRecovery() async -> Bool
    var recoveryStrategies: [RecoveryStrategy] { get }
}

public enum RecoveryStrategy {
    case restart
    case clearCache
    case resetToDefaults
    case recreateConnections
    case freeMemory
}

// Example recovery implementation
extension ExternalDataService: ServiceRecoveryProtocol {
    public func attemptRecovery() async -> Bool {
        print("🔧 Attempting recovery for ExternalDataService")
        
        // Strategy 1: Reset sync status
        await MainActor.run {
            self.syncStatus = .idle
            self.isSaving = false
            self.isLoading = false
        }
        
        // Strategy 2: Verify data path access
        if !dataManager.ensureAccess() {
            print("❌ Recovery failed: Cannot access data path")
            return false
        }
        
        // Strategy 3: Test basic operations
        do {
            let testData = "recovery_test"
            let testURL = dataManager.currentDataPath?.appendingPathComponent("recovery_test.txt")
            try testData.write(to: testURL!, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testURL!)
            
            print("✅ ExternalDataService recovery successful")
            return true
        } catch {
            print("❌ Recovery failed: \(error)")
            return false
        }
    }
    
    public var recoveryStrategies: [RecoveryStrategy] {
        [.clearCache, .resetToDefaults, .recreateConnections]
    }
}
```

### Manual Recovery

The ServiceRegistry provides manual recovery options:

```swift
extension ServiceRegistry {
    public func recoverService(_ serviceName: String) async -> Bool {
        guard let service = services[serviceName] else {
            print("❌ Cannot recover unknown service: \(serviceName)")
            return false
        }
        
        print("🔧 Initiating manual recovery for service: \(serviceName)")
        
        // Attempt automatic recovery if supported
        if let recoverable = service as? ServiceRecoveryProtocol {
            let success = await recoverable.attemptRecovery()
            if success {
                // Update health status
                serviceHealth[serviceName] = ServiceHealth(
                    status: .healthy,
                    message: "Service recovered successfully"
                )
                return true
            }
        }
        
        // Fallback: Restart service
        return await restartService(serviceName)
    }
    
    private func restartService(_ serviceName: String) async -> Bool {
        print("🔄 Restarting service: \(serviceName)")
        
        // Store current service instance
        guard let currentService = services[serviceName] else { return false }
        
        // Shutdown current instance
        if let shutdownService = currentService as? ServiceShutdownProtocol {
            do {
                await shutdownService.shutdown()
            } catch {
                print("⚠️ Error during service shutdown: \(error)")
            }
        }
        
        // Create new instance based on service type
        let newService = createServiceInstance(serviceName)
        guard let newService = newService else {
            print("❌ Failed to create new instance of service: \(serviceName)")
            return false
        }
        
        // Register new instance
        services[serviceName] = newService
        serviceHealth[serviceName] = ServiceHealth(
            status: .healthy,
            message: "Service restarted successfully"
        )
        
        print("✅ Service restart successful: \(serviceName)")
        return true
    }
    
    private func createServiceInstance(_ serviceName: String) -> Any? {
        // Factory method to create new service instances
        switch serviceName {
        case "search-service":
            return SearchService()
        case "git-service":
            return GitService()
        case "external-data-service":
            return ExternalDataService()
        // Add other services as needed
        default:
            return nil
        }
    }
}
```

## Service Shutdown

### Graceful Shutdown Protocol

Services implement graceful shutdown:

```swift
public protocol ServiceShutdownProtocol {
    func shutdown() async throws
}

// Example implementation
extension NodeStore: ServiceShutdownProtocol {
    public func shutdown() async throws {
        print("🛑 NodeStore shutdown initiated")
        
        // 1. Stop accepting new operations
        isShuttingDown = true
        
        // 2. Wait for current operations to complete
        while isSaving || isLoading {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        // 3. Save current state
        if externalDataManager.isDataPathSelected && !nodes.isEmpty {
            try await forceSaveToExternalStorage()
            print("💾 Final data save completed")
        }
        
        // 4. Cancel subscriptions and timers
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
        
        // 5. Clear caches and temporary data
        searchResults.removeAll()
        
        print("✅ NodeStore shutdown complete")
    }
}

extension ExternalDataService: ServiceShutdownProtocol {
    public func shutdown() async throws {
        print("🛑 ExternalDataService shutdown initiated")
        
        // Wait for current save/load operations
        while isSaving || isLoading {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // Cancel any pending operations
        // (Implementation would cancel ongoing tasks)
        
        print("✅ ExternalDataService shutdown complete")
    }
}
```

### Shutdown Timeout Handling

Services must shutdown within reasonable time limits:

```swift
extension ServiceRegistry {
    private func shutdownService(_ serviceName: String, timeout: TimeInterval = 10.0) async {
        guard let service = services[serviceName] else { return }
        
        print("🛑 Shutting down service: \(serviceName) (timeout: \(timeout)s)")
        
        if let shutdownService = service as? ServiceShutdownProtocol {
            do {
                // Use timeout to prevent hanging
                try await withTimeout(timeout) {
                    try await shutdownService.shutdown()
                }
                print("✅ \(serviceName) shutdown complete")
            } catch {
                if error is TimeoutError {
                    print("⚠️ \(serviceName) shutdown timed out after \(timeout)s")
                } else {
                    print("❌ \(serviceName) shutdown failed: \(error)")
                }
                // Force removal even on timeout/error
            }
        }
        
        // Remove from registry regardless of shutdown success
        services.removeValue(forKey: serviceName)
        serviceHealth.removeValue(forKey: serviceName)
    }
}

// Timeout utility
func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw TimeoutError()
        }
        
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

struct TimeoutError: Error {}
```

## Lifecycle Events

### Event Notifications

Services can listen for lifecycle events:

```swift
extension Notification.Name {
    static let serviceRegistered = Notification.Name("serviceRegistered")
    static let serviceShutdown = Notification.Name("serviceShutdown")
    static let serviceHealthChanged = Notification.Name("serviceHealthChanged")
    static let applicationWillTerminate = Notification.Name("applicationWillTerminate")
}

// Example listener
class ServiceLifecycleMonitor {
    init() {
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleServiceRegistered),
            name: .serviceRegistered,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationWillTerminate),
            name: .applicationWillTerminate,
            object: nil
        )
    }
    
    @objc private func handleServiceRegistered(_ notification: Notification) {
        if let serviceName = notification.userInfo?["serviceName"] as? String {
            print("📝 Service registered: \(serviceName)")
        }
    }
    
    @objc private func handleApplicationWillTerminate(_ notification: Notification) {
        Task {
            await ServiceRegistry.shared.gracefulShutdown()
        }
    }
}
```

## Best Practices

### Service Design

1. **Single Responsibility**: Each service has one clear purpose
2. **Dependency Injection**: Services receive dependencies via initializers
3. **Protocol-Based**: Services implement protocols for testability
4. **Thread Safety**: Services use proper concurrency controls
5. **Error Handling**: Comprehensive error types and recovery strategies

### Lifecycle Management

1. **Proper Ordering**: Services initialize in dependency order
2. **Health Monitoring**: All services implement health checks
3. **Graceful Shutdown**: Services clean up resources properly
4. **Recovery Strategies**: Services can recover from failures
5. **Timeout Handling**: Operations have reasonable time limits

### Performance

1. **Lazy Loading**: Services initialize only when needed
2. **Resource Management**: Services release resources promptly
3. **Monitoring**: Services expose performance metrics
4. **Optimization**: Services respond to resource pressure
5. **Caching**: Services cache appropriately and clear caches during shutdown

---

This service lifecycle management system ensures WordTagger services are reliable, maintainable, and properly integrated throughout their entire lifecycle from registration to shutdown.