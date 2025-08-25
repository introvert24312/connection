import Foundation
import Combine
import SwiftUI

// MARK: - Service Registry Protocol

protocol ServiceRegistryProtocol {
    func register<T>(_ service: T, for type: T.Type, name: String?)
    func resolve<T>(_ type: T.Type, name: String?) -> T?
    func resolveAll<T>(_ type: T.Type) -> [T]
    func health(for name: String) -> ServiceHealth
    func getAllServices() -> [ServiceDescriptor]
}

// MARK: - Service Health Status

public enum ServiceHealthStatus: String, Codable, CaseIterable {
    case healthy = "healthy"
    case warning = "warning" 
    case critical = "critical"
    case unknown = "unknown"
    
    var color: Color {
        switch self {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        case .unknown: return .gray
        }
    }
    
    var icon: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

public struct ServiceHealth: Codable {
    let status: ServiceHealthStatus
    let message: String?
    let timestamp: Date
    let metrics: [String: Double]?
    
    public init(status: ServiceHealthStatus, message: String? = nil, metrics: [String: Double]? = nil) {
        self.status = status
        self.message = message
        self.timestamp = Date()
        self.metrics = metrics
    }
    
    static var healthy: ServiceHealth {
        ServiceHealth(status: .healthy)
    }
    
    static var unknown: ServiceHealth {
        ServiceHealth(status: .unknown, message: "Health check not implemented")
    }
}

// MARK: - Service Descriptor

public struct ServiceDescriptor: Codable, Identifiable, Hashable {
    public let id = UUID()
    let name: String
    let version: String
    let type: ServiceType
    let purpose: String
    let owner: String
    let status: ServiceStatus
    let dependencies: [String]
    let apis: [ServiceAPI]?
    let performance: ServicePerformance?
    let monitoring: ServiceMonitoring?
    let features: [String]?
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(version)
    }
    
    public static func == (lhs: ServiceDescriptor, rhs: ServiceDescriptor) -> Bool {
        lhs.name == rhs.name && lhs.version == rhs.version
    }
}

public enum ServiceType: String, Codable, CaseIterable {
    case coreService = "core-service"
    case specializedService = "specialized-service"
    case infrastructureService = "infrastructure-service" 
    case uiService = "ui-service"
    
    var displayName: String {
        switch self {
        case .coreService: return "Core Service"
        case .specializedService: return "Specialized Service"
        case .infrastructureService: return "Infrastructure Service"
        case .uiService: return "UI Service"
        }
    }
    
    var color: Color {
        switch self {
        case .coreService: return .blue
        case .specializedService: return .purple
        case .infrastructureService: return .gray
        case .uiService: return .green
        }
    }
}

public enum ServiceStatus: String, Codable, CaseIterable {
    case active = "active"
    case inactive = "inactive"
    case maintenance = "maintenance"
    case deprecated = "deprecated"
    
    var color: Color {
        switch self {
        case .active: return .green
        case .inactive: return .gray
        case .maintenance: return .orange
        case .deprecated: return .red
        }
    }
}

public struct ServiceAPI: Codable {
    let method: String
    let description: String
    let parameters: [String]
    let returns: String
}

public struct ServicePerformance: Codable {
    let memoryUsage: String
    let cpuUsage: String
    let ioOperations: String
    let customMetrics: [String: String]?
}

public struct ServiceMonitoring: Codable {
    let metrics: [String]
    let alerts: [String]
}

// MARK: - Service Registry Implementation

@MainActor
public class ServiceRegistry: ObservableObject, ServiceRegistryProtocol {
    public static let shared = ServiceRegistry()
    
    @Published public private(set) var services: [String: Any] = [:]
    @Published public private(set) var serviceDescriptors: [String: ServiceDescriptor] = [:]
    @Published public private(set) var serviceHealth: [String: ServiceHealth] = [:]
    @Published public private(set) var isHealthCheckEnabled: Bool = true
    
    private var healthCheckTimer: Timer?
    private let healthCheckInterval: TimeInterval = 30.0 // 30 seconds
    
    private init() {
        loadServiceDescriptors()
        startHealthMonitoring()
        registerBuiltInServices()
    }
    
    deinit {
        healthCheckTimer?.invalidate()
    }
    
    // MARK: - Service Registration
    
    public func register<T>(_ service: T, for type: T.Type, name: String? = nil) {
        let serviceName = name ?? String(describing: type)
        services[serviceName] = service
        
        print("🔧 ServiceRegistry: Registered service '\(serviceName)'")
        
        // Initialize health status
        if serviceHealth[serviceName] == nil {
            serviceHealth[serviceName] = .unknown
        }
        
        // Trigger health check for the new service
        checkServiceHealth(serviceName)
    }
    
    public func resolve<T>(_ type: T.Type, name: String? = nil) -> T? {
        let serviceName = name ?? String(describing: type)
        return services[serviceName] as? T
    }
    
    public func resolveAll<T>(_ type: T.Type) -> [T] {
        return services.values.compactMap { $0 as? T }
    }
    
    // MARK: - Health Monitoring
    
    public func health(for name: String) -> ServiceHealth {
        return serviceHealth[name] ?? .unknown
    }
    
    public func getAllServices() -> [ServiceDescriptor] {
        return Array(serviceDescriptors.values).sorted { $0.name < $1.name }
    }
    
    private func startHealthMonitoring() {
        guard isHealthCheckEnabled else { return }
        
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: healthCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performHealthChecks()
            }
        }
        
        print("🏥 ServiceRegistry: Health monitoring started (interval: \(healthCheckInterval)s)")
    }
    
    private func performHealthChecks() {
        for serviceName in services.keys {
            checkServiceHealth(serviceName)
        }
    }
    
    private func checkServiceHealth(_ serviceName: String) {
        // Default health check implementation
        guard let service = services[serviceName] else {
            serviceHealth[serviceName] = ServiceHealth(status: .critical, message: "Service not found")
            return
        }
        
        // Check if service conforms to HealthCheckable protocol
        if let healthCheckable = service as? HealthCheckable {
            Task {
                let health = await healthCheckable.checkHealth()
                await MainActor.run {
                    self.serviceHealth[serviceName] = health
                }
            }
        } else {
            // Basic health check - service is registered and available
            serviceHealth[serviceName] = ServiceHealth(status: .healthy, message: "Service is registered and available")
        }
    }
    
    // MARK: - Service Descriptor Loading
    
    private func loadServiceDescriptors() {
        // Load service descriptors from YAML files
        let serviceDocsURL = Bundle.main.url(forResource: "docs", withExtension: nil)?
            .appendingPathComponent("services")
        
        guard let docsURL = serviceDocsURL,
              let serviceFiles = try? FileManager.default.contentsOfDirectory(at: docsURL, 
                                                                             includingPropertiesForKeys: nil) else {
            print("⚠️ ServiceRegistry: Could not load service descriptors from docs/services")
            return
        }
        
        for file in serviceFiles where file.pathExtension == "yaml" {
            loadServiceDescriptor(from: file)
        }
        
        print("📚 ServiceRegistry: Loaded \(serviceDescriptors.count) service descriptors")
    }
    
    private func loadServiceDescriptor(from url: URL) {
        do {
            let yamlData = try Data(contentsOf: url)
            
            // Note: In a real implementation, you'd use a YAML parser like Yams
            // For now, we'll create descriptors programmatically based on the files we created
            let serviceName = url.deletingPathExtension().lastPathComponent
            let descriptor = createServiceDescriptor(for: serviceName)
            serviceDescriptors[serviceName] = descriptor
            
        } catch {
            print("❌ ServiceRegistry: Failed to load service descriptor from \(url.lastPathComponent): \(error)")
        }
    }
    
    private func createServiceDescriptor(for serviceName: String) -> ServiceDescriptor {
        // Create service descriptors based on our YAML definitions
        switch serviceName {
        case "node-store":
            return ServiceDescriptor(
                name: "node-store",
                version: "1.9.0", 
                type: .coreService,
                purpose: "Central data store managing nodes, layers, tags and application state",
                owner: "WordTagger Team @wordtagger-oncall",
                status: .active,
                dependencies: ["external-data-service", "external-data-manager", "tag-mapping-manager"],
                apis: [
                    ServiceAPI(method: "addNode", description: "Add new node to current layer", parameters: ["Node"], returns: "Bool"),
                    ServiceAPI(method: "updateNode", description: "Update existing node properties", parameters: ["UUID", "String?"], returns: "Void"),
                    ServiceAPI(method: "deleteNode", description: "Remove node from store", parameters: ["UUID"], returns: "Void")
                ],
                performance: ServicePerformance(memoryUsage: "High", cpuUsage: "Medium", ioOperations: "High", customMetrics: nil),
                monitoring: ServiceMonitoring(metrics: ["nodes_count", "search_operations_per_second"], alerts: ["memory_usage_high", "sync_failures"]),
                features: ["real_time_sync", "duplicate_detection", "auto_backup", "corruption_repair"]
            )
        case "search-service":
            return ServiceDescriptor(
                name: "search-service",
                version: "1.9.0",
                type: .specializedService,
                purpose: "Advanced search engine with fuzzy matching and location-based search",
                owner: "WordTagger Team @wordtagger-oncall",
                status: .active,
                dependencies: ["node-store"],
                apis: [
                    ServiceAPI(method: "search", description: "Perform advanced search with filters", parameters: ["String", "[Node]"], returns: "[SearchResult]"),
                    ServiceAPI(method: "searchByTag", description: "Search nodes by specific tag type", parameters: ["Tag.TagType"], returns: "[Node]")
                ],
                performance: ServicePerformance(memoryUsage: "Low", cpuUsage: "High", ioOperations: "None", customMetrics: ["search_threshold": "0.3"]),
                monitoring: ServiceMonitoring(metrics: ["search_requests_per_second", "average_search_time_ms"], alerts: ["search_time_exceeded_threshold"]),
                features: ["multi_field_search", "fuzzy_matching", "location_based_search", "semantic_similarity"]
            )
        case "git-service":
            return ServiceDescriptor(
                name: "git-service",
                version: "1.9.0",
                type: .specializedService,
                purpose: "Git repository integration with automated commits and credential management",
                owner: "WordTagger Team @wordtagger-oncall", 
                status: .active,
                dependencies: ["keychain-manager", "external-data-service"],
                apis: [
                    ServiceAPI(method: "connect", description: "Connect to Git repository", parameters: ["String", "GitCredentials"], returns: "Result<Void, GitError>"),
                    ServiceAPI(method: "commitAndPush", description: "Commit and push changes", parameters: ["String"], returns: "Result<Void, GitError>")
                ],
                performance: ServicePerformance(memoryUsage: "Low", cpuUsage: "Low", ioOperations: "High", customMetrics: nil),
                monitoring: ServiceMonitoring(metrics: ["commit_operations_per_hour", "push_success_rate"], alerts: ["authentication_failures", "push_operation_failures"]),
                features: ["automated_commits", "credential_management", "error_handling", "retry_mechanisms"]
            )
        case "keychain-manager":
            return ServiceDescriptor(
                name: "keychain-manager",
                version: "1.9.0",
                type: .infrastructureService,
                purpose: "Secure credential storage using macOS Keychain Services",
                owner: "WordTagger Team @wordtagger-oncall",
                status: .active,
                dependencies: [],
                apis: [
                    ServiceAPI(method: "save", description: "Store item securely", parameters: ["T: Codable", "String"], returns: "throws Void"),
                    ServiceAPI(method: "load", description: "Retrieve item from keychain", parameters: ["T.Type", "String"], returns: "throws T?")
                ],
                performance: ServicePerformance(memoryUsage: "Very Low", cpuUsage: "Very Low", ioOperations: "Low", customMetrics: nil),
                monitoring: ServiceMonitoring(metrics: ["keychain_operations_per_minute"], alerts: ["keychain_access_denied"]),
                features: ["generic_codable_storage", "git_credential_specialization", "secure_deletion"]
            )
        default:
            return ServiceDescriptor(
                name: serviceName,
                version: "1.9.0",
                type: .specializedService,
                purpose: "Service loaded from YAML configuration",
                owner: "WordTagger Team @wordtagger-oncall",
                status: .active,
                dependencies: [],
                apis: nil,
                performance: nil,
                monitoring: nil,
                features: nil
            )
        }
    }
    
    // MARK: - Built-in Service Registration
    
    private func registerBuiltInServices() {
        // Register core services that are always available
        register(NodeStore.shared, for: NodeStore.self, name: "node-store")
        register(SearchService.shared, for: SearchService.self, name: "search-service")
        register(KeychainManager.shared, for: KeychainManager.self, name: "keychain-manager")
        register(ExternalDataService.shared, for: ExternalDataService.self, name: "external-data-service")
        register(ExternalDataManager.shared, for: ExternalDataManager.self, name: "external-data-manager")
        
        print("🔧 ServiceRegistry: Registered \(services.count) built-in services")
    }
    
    // MARK: - Service Management
    
    public func enableHealthChecks() {
        isHealthCheckEnabled = true
        startHealthMonitoring()
    }
    
    public func disableHealthChecks() {
        isHealthCheckEnabled = false
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }
    
    public func forceHealthCheck(for serviceName: String? = nil) {
        if let serviceName = serviceName {
            checkServiceHealth(serviceName)
        } else {
            performHealthChecks()
        }
    }
    
    public func getServicesByType(_ type: ServiceType) -> [ServiceDescriptor] {
        return serviceDescriptors.values.filter { $0.type == type }.sorted { $0.name < $1.name }
    }
    
    public func getServicesByStatus(_ status: ServiceStatus) -> [ServiceDescriptor] {
        return serviceDescriptors.values.filter { $0.status == status }.sorted { $0.name < $1.name }
    }
    
    public func getDependencyGraph() -> [String: [String]] {
        var graph: [String: [String]] = [:]
        
        for (name, descriptor) in serviceDescriptors {
            graph[name] = descriptor.dependencies
        }
        
        return graph
    }
}

// MARK: - Health Check Protocol

public protocol HealthCheckable {
    func checkHealth() async -> ServiceHealth
}

// MARK: - Service Health Extensions

extension NodeStore: HealthCheckable {
    public func checkHealth() async -> ServiceHealth {
        let nodeCount = await MainActor.run { nodes.count }
        let layerCount = await MainActor.run { layers.count }
        let isLoading = await MainActor.run { self.isLoading }
        
        var metrics: [String: Double] = [
            "node_count": Double(nodeCount),
            "layer_count": Double(layerCount)
        ]
        
        if isLoading {
            return ServiceHealth(status: .warning, message: "Service is currently loading data", metrics: metrics)
        }
        
        if nodeCount == 0 && layerCount == 0 {
            return ServiceHealth(status: .warning, message: "No data loaded", metrics: metrics)
        }
        
        return ServiceHealth(status: .healthy, message: "Service is operating normally", metrics: metrics)
    }
}

extension SearchService: HealthCheckable {
    public func checkHealth() async -> ServiceHealth {
        let isSearching = await MainActor.run { self.isSearching }
        let lastSearchTime = await MainActor.run { self.lastSearchTime }
        
        let metrics: [String: Double] = [
            "last_search_time_ms": lastSearchTime * 1000,
            "is_searching": isSearching ? 1.0 : 0.0
        ]
        
        return ServiceHealth(status: .healthy, message: "Search service is operational", metrics: metrics)
    }
}

extension KeychainManager: HealthCheckable {
    public func checkHealth() async -> ServiceHealth {
        // Test keychain access by attempting to read a test value
        do {
            _ = try loadData(for: "health_check_test")
            return ServiceHealth(status: .healthy, message: "Keychain access is working")
        } catch {
            return ServiceHealth(status: .warning, message: "Keychain access issue: \(error.localizedDescription)")
        }
    }
}

extension ExternalDataService: HealthCheckable {
    public func checkHealth() async -> ServiceHealth {
        let isSaving = await MainActor.run { self.isSaving }
        let isLoading = await MainActor.run { self.isLoading }
        let lastSyncTime = await MainActor.run { self.lastSyncTime }
        let syncStatus = await MainActor.run { self.syncStatus }
        
        var metrics: [String: Double] = [
            "is_saving": isSaving ? 1.0 : 0.0,
            "is_loading": isLoading ? 1.0 : 0.0
        ]
        
        if let lastSync = lastSyncTime {
            metrics["last_sync_seconds_ago"] = Date().timeIntervalSince(lastSync)
        }
        
        switch syncStatus {
        case .idle:
            return ServiceHealth(status: .healthy, message: "External data service is idle", metrics: metrics)
        case .syncing:
            return ServiceHealth(status: .warning, message: "External data service is syncing", metrics: metrics)
        case .error(let error):
            return ServiceHealth(status: .critical, message: "Sync error: \(error)", metrics: metrics)
        }
    }
}

// MARK: - Convenience Extensions

extension ServiceRegistry {
    public var coreServices: [ServiceDescriptor] {
        getServicesByType(.coreService)
    }
    
    public var specializedServices: [ServiceDescriptor] {
        getServicesByType(.specializedService)
    }
    
    public var infrastructureServices: [ServiceDescriptor] {
        getServicesByType(.infrastructureService)
    }
    
    public var uiServices: [ServiceDescriptor] {
        getServicesByType(.uiService)
    }
    
    public var healthyServices: [ServiceDescriptor] {
        serviceDescriptors.values.filter { 
            health(for: $0.name).status == .healthy 
        }.sorted { $0.name < $1.name }
    }
    
    public var unhealthyServices: [ServiceDescriptor] {
        serviceDescriptors.values.filter { 
            health(for: $0.name).status != .healthy 
        }.sorted { $0.name < $1.name }
    }
}