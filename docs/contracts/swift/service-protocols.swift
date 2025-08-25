import Foundation
import Combine
import CoreLocation
import SwiftUI

// MARK: - WordTagger Service Interface Contracts
// This file defines the comprehensive interface contracts for all WordTagger services
// These protocols serve as the definitive API specifications for service boundaries

// MARK: - Core Data Store Protocol

/// Central data management service contract
/// Manages nodes, layers, search state, and reactive UI bindings
@MainActor
public protocol NodeStoreProtocol: ObservableObject {
    // MARK: - Observable State Properties
    var nodes: [Node] { get }
    var layers: [Layer] { get }
    var sortedLayers: [Layer] { get }
    var currentLayer: Layer? { get }
    var selectedNode: Node? { get }
    var selectedTag: Tag? { get }
    var showAllTagTypeNodes: Bool { get }
    var expandedTagTypes: Set<Tag.TagType> { get }
    var searchQuery: String { get set }
    var searchResults: [Node] { get }
    var isLoading: Bool { get }
    var isExporting: Bool { get }
    var isImporting: Bool { get }
    var duplicateNodeAlert: DuplicateNodeAlert? { get }
    
    // MARK: - Computed Properties
    var allTags: [Tag] { get }
    var currentLayerTags: [Tag] { get }
    
    // MARK: - Node Management
    func addNode(_ node: Node) -> Bool
    func addNode(_ text: String, phonetic: String?, meaning: String?) -> Bool
    func updateNode(_ node: Node)
    func updateNode(_ nodeId: UUID, text: String?, phonetic: String?, meaning: String?)
    func updateNodeMarkdown(_ nodeId: UUID, markdown: String)
    func updateNodeTags(_ nodeId: UUID, tags: [Tag])
    func deleteNode(_ node: Node)
    func deleteNode(_ nodeId: UUID)
    func setSelectedNode(_ node: Node?)
    func selectNode(_ node: Node?)
    
    // MARK: - Layer Management
    func addLayer(_ layer: Layer)
    func updateLayer(_ layer: Layer)
    func updateLayerDisplayName(layer: Layer, newDisplayName: String, newColor: String?)
    func deleteLayer(_ layer: Layer)
    func setCurrentLayer(_ layer: Layer)
    func createLayer(name: String, displayName: String, color: String) -> Layer
    func switchToLayer(_ layer: Layer) async
    func switchToLayer(named name: String) async
    
    // MARK: - Compound Layer Management
    func createCompoundLayer(name: String, displayName: String, childLayerIds: [UUID], color: String) -> Layer
    func updateCompoundLayer(_ layer: Layer, childLayerIds: [UUID])
    func getNodesInCompoundLayer(_ layer: Layer) -> [Node]
    func getChildLayers(of compoundLayer: Layer) -> [Layer]
    func isLayerUsedInCompound(_ layer: Layer) -> Bool
    
    // MARK: - Search Operations
    func performSearch(query: String)
    func searchTags(query: String) -> [Tag]
    func getRelevantTags(for query: String) -> [Tag]
    
    // MARK: - Tag Management
    func setSelectedTag(_ tag: Tag?)
    func setSelectedTagWithTypeMode(_ tag: Tag?)
    func selectTag(_ tag: Tag?)
    func selectTagType(_ tagType: Tag.TagType)
    func selectTagWithFocus(_ tag: Tag)
    func addTag(to nodeId: UUID, tag: Tag)
    func removeTag(from nodeId: UUID, tagId: UUID)
    func nodesInCurrentLayer(withTag tag: Tag) -> [Node]
    func nodesInCurrentLayer(withTagType tagType: Tag.TagType) -> [Node]
    func nodesInCurrentLayer(withTagTypes tagTypes: Set<Tag.TagType>) -> [Node]
    func getNodesInCurrentLayer() -> [Node]
    func nodes(withTag tag: Tag) -> [Node]
    func nodesCount(forTagType type: Tag.TagType) -> Int
    
    // MARK: - Tag Type Expansion State
    func setExpandedTagTypes(_ tagTypes: Set<Tag.TagType>)
    func addExpandedTagType(_ tagType: Tag.TagType)
    func removeExpandedTagType(_ tagType: Tag.TagType)
    func toggleExpandedTagType(_ tagType: Tag.TagType)
    func clearTagFilter()
    
    // MARK: - Map Integration
    func expandLocationTagAndSelect(_ node: Node)
    func findLocationTagByName(_ name: String) -> Tag?
    
    // MARK: - Data Operations
    func clearAllData()
    func clearAllDataWithoutSample()
    func resetToSampleData()
    func clearAllDataIncludingExternal() async
    func replaceAllData(layers: [Layer], nodes: [Node]) async
    func forceSaveToExternalStorage() async
    func forceRefreshUI()
    
    // MARK: - Data Integrity
    func cleanupDataConsistency()
    func fixOrphanNodes()
    func detectAndFixCorruptedNodes() -> Int
    
    // MARK: - Utilities
    func createTag(type: Tag.TagType, value: String, latitude: Double?, longitude: Double?, isShortcutType: Bool) -> Tag
}

// MARK: - Search Service Protocol

/// Advanced search service contract
/// Provides multi-field search, fuzzy matching, and performance monitoring
public protocol SearchServiceProtocol: ObservableObject {
    // MARK: - State Properties
    var isSearching: Bool { get }
    var lastSearchTime: TimeInterval { get }
    var searchMetrics: SearchMetrics { get }
    
    // MARK: - Core Search Operations
    func search(_ query: String, in nodes: [Node], filter: SearchFilter) async -> [SearchResult]
    func searchByTag(_ tagType: Tag.TagType, in nodes: [Node]) -> [Node]
    func searchByLocation(near coordinate: CLLocationCoordinate2D, radius: Double, in nodes: [Node]) -> [Node]
    func findSimilarNodes(_ node: Node, in nodes: [Node], threshold: Double) -> [Node]
}

// MARK: - Git Service Protocol

/// Git repository integration contract
/// Handles version control operations with secure credential management
@MainActor
public protocol GitServiceProtocol: ObservableObject {
    // MARK: - State Properties
    var connectionStatus: GitConnectionStatus { get }
    var lastSyncDate: Date? { get }
    var pendingChanges: Int { get }
    var isOperationInProgress: Bool { get }
    var operationProgress: GitOperationProgress? { get }
    var repositoryStatus: GitRepositoryStatus { get }
    var lastError: GitError? { get }
    var retryCount: Int { get }
    var isRetrying: Bool { get }
    
    // MARK: - Connection Management
    func configureRepository(url: String, credentials: GitCredentials) async throws
    func disconnect()
    func refreshCredentials(_ newCredentials: GitCredentials) async throws
    func validateCredentials(_ credentials: GitCredentials, for repositoryURL: String) async throws -> Bool
    
    // MARK: - Git Operations
    func commitChanges(message: String) async throws
    func pushToRemote() async throws
    func refreshRepositoryStatus() async
    func checkPendingChanges() async
    func initializeLocalRepository() async throws
    func addRemoteRepository(url: String, name: String) async throws
    
    // MARK: - Credential Management
    func getAllStoredCredentials(for repositoryURL: String) throws -> [GitCredentials]
    func deleteStoredCredentials(for repositoryURL: String, username: String) throws
    func deleteAllStoredCredentials(for repositoryURL: String) throws
    func refreshStoredCredentials(for repositoryURL: String, username: String, newToken: String) async throws
    func hasStoredCredentials(for repositoryURL: String, username: String) -> Bool
    func getStoredCredentials(for repositoryURL: String, username: String) throws -> GitCredentials?
    
    // MARK: - Error Handling
    func getDetailedErrorMessage(_ error: GitError) -> (title: String, message: String, action: String)
    func handleAuthenticationError() async throws
    func retryLastOperation() async throws
    
    // MARK: - Monitoring
    func startPeriodicStatusCheck(interval: TimeInterval)
}

// MARK: - External Data Service Protocol

/// External data persistence contract
/// Manages data synchronization with external storage systems
@MainActor  
public protocol ExternalDataServiceProtocol: ObservableObject {
    // MARK: - State Properties
    var isSaving: Bool { get }
    var isLoading: Bool { get }
    var lastSyncTime: Date? { get }
    var syncStatus: SyncStatus { get }
    
    // MARK: - Data Operations
    func saveAllData(store: NodeStore) async throws
    func loadAllData() async throws -> (layers: [Layer], nodes: [Node])
    func clearAllExternalData() async throws
    func saveTagMappingsOnly() async throws
    
    // MARK: - Backup Operations
    func initializeDataFolder() async throws
    func startAutoSync(store: NodeStore)
}

// MARK: - Keychain Manager Protocol

/// Secure credential storage contract
/// Provides encrypted storage using macOS Keychain Services
public protocol KeychainManagerProtocol {
    // MARK: - Generic Operations
    func save<T: Codable>(_ item: T, for key: String) throws
    func load<T: Codable>(_ type: T.Type, for key: String) throws -> T?
    func delete(for key: String) throws
    
    // MARK: - Git-Specific Operations
    func saveGitCredentials(_ credentials: GitCredentials, for repositoryURL: String) throws
    func loadGitCredentials(for repositoryURL: String, username: String) throws -> GitCredentials?
    func loadAllGitCredentials(for repositoryURL: String) throws -> [GitCredentials]
    func deleteGitCredentials(for repositoryURL: String, username: String) throws
    func deleteAllGitCredentials(for repositoryURL: String) throws
}

// MARK: - Graph Service Protocol

/// Node relationship graph contract
/// Builds and queries semantic relationships between nodes
public protocol GraphServiceProtocol: ObservableObject {
    // MARK: - State Properties
    var graph: NodeGraph { get }
    var isBuilding: Bool { get }
    var lastBuildTime: TimeInterval { get }
    var graphStats: GraphStatistics { get }
    
    // MARK: - Graph Building
    func buildGraph(from words: [Node]) async
    
    // MARK: - Graph Query Methods
    func neighbors(of wordId: UUID) -> [Node]
    func connectedNodes(to wordId: UUID, maxDepth: Int) -> [Node]
    func findPath(from: UUID, to: UUID) -> [Node]?
    func strongestConnections(for wordId: UUID, limit: Int) -> [(Node, Double)]
    func clusterNodes(minClusterSize: Int) -> [[Node]]
    
    // MARK: - Visualization Export
    func exportForVisualization(includeEdgeTypes: Set<EdgeType>) -> GraphVisualizationData
}

// MARK: - Map Container Protocol

/// Geographic visualization contract
/// Handles location-based node display and interaction
public protocol MapContainerProtocol: ObservableObject {
    // MARK: - State Properties
    var displayedNodes: [Node] { get }
    var mapRegion: MKCoordinateRegion { get }
    var isLoading: Bool { get }
    
    // MARK: - Map Operations
    func displayNodes(_ nodes: [Node])
    func centerOnLocation(_ coordinate: CLLocationCoordinate2D)
    func centerOnNode(_ node: Node)
    func selectNode(_ nodeId: UUID)
    func updateNodePosition(_ nodeId: UUID, coordinate: CLLocationCoordinate2D)
    
    // MARK: - Map Configuration
    func setMapType(_ mapType: MKMapType)
    func enableClustering(_ enabled: Bool)
    func setZoomLevel(_ level: Double)
}

// MARK: - Command Palette Protocol

/// Keyboard-driven command interface contract
/// Provides fuzzy search and command execution
public protocol CommandPaletteProtocol: ObservableObject {
    // MARK: - State Properties
    var isVisible: Bool { get }
    var availableCommands: [Command] { get }
    var filteredCommands: [Command] { get }
    var selectedCommandIndex: Int { get }
    
    // MARK: - Command Management
    func showPalette(with context: CommandContext?)
    func hidePalette()
    func executeCommand(_ command: Command, with parameters: [Any]) -> CommandResult
    func filterCommands(query: String)
    func selectNextCommand()
    func selectPreviousCommand()
    
    // MARK: - Command Registration
    func registerCommand(_ command: Command)
    func unregisterCommand(withIdentifier identifier: String)
}

// MARK: - Performance Optimization Protocol

/// Performance monitoring and optimization contract
/// Tracks resource usage and provides optimization recommendations
public protocol PerformanceOptimizationProtocol {
    // MARK: - Monitoring
    func measurePerformance<T>(of operation: String, _ block: () throws -> T) rethrows -> T
    func monitorMemoryUsage() -> MemoryUsage
    func detectMemoryLeaks() -> [MemoryLeak]
    
    // MARK: - Optimization
    func optimizeForLowMemory()
    func clearCaches()
    func enablePerformanceMode(_ enabled: Bool)
    
    // MARK: - Reporting
    func generatePerformanceReport() -> PerformanceReport
    func getMetrics(for timeRange: ClosedRange<Date>) -> [PerformanceMetric]
}

// MARK: - Health Check Protocol

/// Service health monitoring contract
/// Provides health status and diagnostics for all services
public protocol HealthCheckable {
    func checkHealth() async -> ServiceHealth
}

// MARK: - Service Registry Protocol

/// Service discovery and dependency injection contract
/// Manages service lifecycle and dependencies
public protocol ServiceRegistryProtocol {
    func register<T>(_ service: T, for type: T.Type)
    func resolve<T>(_ type: T.Type) -> T?
    func resolveRequired<T>(_ type: T.Type) throws -> T
    func registerSingleton<T>(_ service: T, for type: T.Type)
    func getAllServices() -> [String: Any]
    func getServiceHealth() async -> [String: ServiceHealth]
}

// MARK: - Supporting Data Structures

public struct DuplicateNodeAlert {
    public let message: String
    public let isDuplicate: Bool
    public let existingNode: Node?
    public let newNode: Node
}

public struct SearchFilter {
    public let tagType: Tag.TagType?
    public let hasLocation: Bool?
    public let layerId: UUID?
    public let dateRange: ClosedRange<Date>?
    
    public static let empty = SearchFilter(tagType: nil, hasLocation: nil, layerId: nil, dateRange: nil)
    
    public init(tagType: Tag.TagType? = nil, hasLocation: Bool? = nil, layerId: UUID? = nil, dateRange: ClosedRange<Date>? = nil) {
        self.tagType = tagType
        self.hasLocation = hasLocation
        self.layerId = layerId
        self.dateRange = dateRange
    }
}

public struct SearchResult: Identifiable {
    public let id = UUID()
    public let node: Node
    public let score: Double // 0.0 to 1.0 relevance score
    public let matchedFields: Set<MatchField>
    
    public enum MatchField: String, CaseIterable {
        case text, meaning, phonetic, tagValue
    }
    
    // Contract: score must be between 0.0 and 1.0
    // Contract: matchedFields cannot be empty
    public init(node: Node, score: Double, matchedFields: Set<MatchField>) {
        precondition(score >= 0.0 && score <= 1.0, "Score must be between 0.0 and 1.0")
        precondition(!matchedFields.isEmpty, "MatchedFields cannot be empty")
        
        self.node = node
        self.score = score
        self.matchedFields = matchedFields
    }
}

public struct Command: Identifiable {
    public let id: String
    public let title: String
    public let description: String?
    public let category: CommandCategory
    public let shortcut: KeyboardShortcut?
    public let handler: CommandHandler
    public let isEnabled: (CommandContext?) -> Bool
    
    // Contract: id must be unique across all commands
    // Contract: handler must be thread-safe
    // Contract: isEnabled function must be pure (no side effects)
    public init(id: String, title: String, description: String?, category: CommandCategory, shortcut: KeyboardShortcut?, handler: @escaping CommandHandler, isEnabled: @escaping (CommandContext?) -> Bool) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.shortcut = shortcut
        self.handler = handler
        self.isEnabled = isEnabled
    }
}

public enum CommandResult {
    case success(message: String?)
    case failure(error: Error)
    case cancelled
}

public enum CommandCategory: String, CaseIterable {
    case node = "node"
    case layer = "layer" 
    case search = "search"
    case navigation = "navigation"
    case git = "git"
    case system = "system"
}

public struct CommandContext {
    public let selectedNode: Node?
    public let currentLayer: Layer?
    public let searchQuery: String?
    public let selectedTags: [Tag]
    
    public init(selectedNode: Node?, currentLayer: Layer?, searchQuery: String?, selectedTags: [Tag]) {
        self.selectedNode = selectedNode
        self.currentLayer = currentLayer
        self.searchQuery = searchQuery
        self.selectedTags = selectedTags
    }
}

public typealias CommandHandler = (CommandContext?) -> CommandResult
public typealias KeyboardShortcut = String // Simplified for now

public struct ServiceHealth {
    public let isHealthy: Bool
    public let status: HealthStatus
    public let message: String
    public let lastChecked: Date
    public let metrics: [String: Any]
    
    public enum HealthStatus: String, CaseIterable {
        case healthy = "healthy"
        case degraded = "degraded"
        case unhealthy = "unhealthy"
        case unknown = "unknown"
    }
    
    public init(isHealthy: Bool, status: HealthStatus, message: String, metrics: [String: Any] = [:]) {
        self.isHealthy = isHealthy
        self.status = status
        self.message = message
        self.lastChecked = Date()
        self.metrics = metrics
    }
}

public struct MemoryUsage {
    public let totalMemory: UInt64
    public let usedMemory: UInt64 
    public let availableMemory: UInt64
    public let memoryPressure: MemoryPressureLevel
    
    public enum MemoryPressureLevel: String, CaseIterable {
        case normal = "normal"
        case warning = "warning"
        case critical = "critical"
    }
    
    public init(totalMemory: UInt64, usedMemory: UInt64, availableMemory: UInt64, memoryPressure: MemoryPressureLevel) {
        self.totalMemory = totalMemory
        self.usedMemory = usedMemory
        self.availableMemory = availableMemory
        self.memoryPressure = memoryPressure
    }
}

public struct MemoryLeak {
    public let identifier: String
    public let description: String
    public let severity: Severity
    public let detectedAt: Date
    
    public enum Severity: String, CaseIterable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
    }
    
    public init(identifier: String, description: String, severity: Severity) {
        self.identifier = identifier
        self.description = description
        self.severity = severity
        self.detectedAt = Date()
    }
}

public struct PerformanceReport {
    public let generatedAt: Date
    public let overallScore: Double // 0.0 to 100.0
    public let metrics: [PerformanceMetric]
    public let recommendations: [String]
    public let issues: [PerformanceIssue]
    
    public init(overallScore: Double, metrics: [PerformanceMetric], recommendations: [String], issues: [PerformanceIssue]) {
        self.generatedAt = Date()
        self.overallScore = overallScore
        self.metrics = metrics
        self.recommendations = recommendations
        self.issues = issues
    }
}

public struct PerformanceMetric {
    public let name: String
    public let value: Double
    public let unit: String
    public let timestamp: Date
    public let category: MetricCategory
    
    public enum MetricCategory: String, CaseIterable {
        case memory = "memory"
        case cpu = "cpu"
        case disk = "disk"
        case network = "network"
        case ui = "ui"
        case database = "database"
    }
    
    public init(name: String, value: Double, unit: String, category: MetricCategory) {
        self.name = name
        self.value = value
        self.unit = unit
        self.timestamp = Date()
        self.category = category
    }
}

public struct PerformanceIssue {
    public let description: String
    public let severity: Severity
    public let suggestion: String
    public let detectedAt: Date
    
    public enum Severity: String, CaseIterable {
        case low = "low"
        case medium = "medium" 
        case high = "high"
        case critical = "critical"
    }
    
    public init(description: String, severity: Severity, suggestion: String) {
        self.description = description
        self.severity = severity
        self.suggestion = suggestion
        self.detectedAt = Date()
    }
}

// MARK: - Git Supporting Structures

public struct GitOperationProgress {
    public let phase: String
    public let progress: Double // 0.0 to 1.0
    public let message: String?
    
    public init(phase: String, progress: Double, message: String? = nil) {
        self.phase = phase
        self.progress = progress
        self.message = message
    }
}

public struct GitRepositoryStatus {
    public let branch: String
    public let uncommittedFiles: [String]
    public let unpushedCommits: Int
    public let isClean: Bool
    
    public init(branch: String = "main", uncommittedFiles: [String] = [], unpushedCommits: Int = 0, isClean: Bool = true) {
        self.branch = branch
        self.uncommittedFiles = uncommittedFiles
        self.unpushedCommits = unpushedCommits
        self.isClean = isClean
    }
}

// MARK: - Contract Validation

/// Protocol for validating service contracts at runtime
public protocol ContractValidatable {
    func validateContract() throws -> ContractValidationResult
}

public struct ContractValidationResult {
    public let isValid: Bool
    public let violations: [ContractViolation]
    public let warnings: [String]
    public let validatedAt: Date
    
    public init(isValid: Bool, violations: [ContractViolation], warnings: [String]) {
        self.isValid = isValid
        self.violations = violations
        self.warnings = warnings
        self.validatedAt = Date()
    }
}

public struct ContractViolation {
    public let rule: String
    public let description: String
    public let severity: Severity
    
    public enum Severity: String, CaseIterable {
        case warning = "warning"
        case error = "error"
        case critical = "critical"
    }
    
    public init(rule: String, description: String, severity: Severity) {
        self.rule = rule
        self.description = description
        self.severity = severity
    }
}

// MARK: - Error Handling Contracts

/// Standard error handling contract for all services
public protocol ServiceError: LocalizedError {
    var errorCode: String { get }
    var isRetryable: Bool { get }
    var suggestedAction: String { get }
    var userInfo: [String: Any] { get }
}

/// Standard result type for service operations
public enum ServiceResult<Success, Failure: ServiceError> {
    case success(Success)
    case failure(Failure)
    
    public var isSuccess: Bool {
        switch self {
        case .success: return true
        case .failure: return false
        }
    }
    
    public var isFailure: Bool {
        return !isSuccess
    }
}

// MARK: - Event Publishing Contract

/// Standard event publishing contract for all services
public protocol EventPublisher {
    func publish<T>(_ event: T, to channel: String) where T: Codable
    func subscribe<T>(to channel: String, type: T.Type, handler: @escaping (T) -> Void) where T: Codable
    func unsubscribe(from channel: String)
}

/// Standard event structure
public struct ServiceEvent<Payload: Codable>: Codable {
    public let id: UUID
    public let type: String
    public let source: String
    public let timestamp: Date
    public let version: String
    public let correlationId: UUID?
    public let payload: Payload
    
    public init(type: String, source: String, payload: Payload, correlationId: UUID? = nil) {
        self.id = UUID()
        self.type = type
        self.source = source
        self.timestamp = Date()
        self.version = "1.0"
        self.correlationId = correlationId
        self.payload = payload
    }
}