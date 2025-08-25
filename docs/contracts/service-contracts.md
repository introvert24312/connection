# WordTagger Service Contracts

This document serves as the comprehensive reference for WordTagger's service interface contracts, defining clear boundaries between all services and communication patterns.

## Table of Contents

1. [Overview](#overview)
2. [Contract Specifications](#contract-specifications)
3. [Communication Patterns](#communication-patterns)
4. [Service Interfaces](#service-interfaces)
5. [Data Contracts](#data-contracts)
6. [Event Contracts](#event-contracts)
7. [Validation and Testing](#validation-and-testing)
8. [Integration Guide](#integration-guide)

## Overview

WordTagger implements a sophisticated service-oriented architecture with multiple interface contract types that define clear service boundaries and enable reliable inter-service communication.

### Contract Types

WordTagger uses four primary contract specification formats:

1. **Swift Protocol Contracts** ([service-protocols.swift](swift/service-protocols.swift))
   - Native Swift interface definitions
   - Compile-time contract enforcement
   - Type-safe service boundaries

2. **AsyncAPI Event Contracts** ([wordtagger-events.asyncapi.yaml](events/wordtagger-events.asyncapi.yaml))
   - NotificationCenter-based event specifications
   - Reactive communication patterns
   - Event payload and metadata definitions

3. **JSON Schema Data Contracts** ([schemas/](schemas/))
   - Data structure validation rules
   - Runtime data integrity enforcement
   - Cross-platform data compatibility

4. **Validation Tools** ([tools/](tools/))
   - Automated contract testing
   - Runtime compliance validation
   - Continuous integration support

### Architecture Principles

WordTagger's contract system is built on these core principles:

1. **Type Safety**: All APIs leverage Swift's strong type system with compile-time validation
2. **Event-Driven Communication**: Decoupled services communicate via NotificationCenter and @Published properties
3. **Data Integrity**: Comprehensive validation ensures data consistency across all service boundaries
4. **Observable State**: Services expose reactive state through Combine publishers
5. **Error Transparency**: Structured error handling with actionable error information
6. **Performance Accountability**: Services define and adhere to performance contracts
7. **Testability**: All contracts include validation tools and test suites

### Service Communication Patterns

WordTagger implements multiple communication patterns optimized for different use cases:

#### 1. Reactive State Binding
```swift
// @Published properties for automatic UI updates
@Published public private(set) var nodes: [Node] = []
@Published public private(set) var isLoading: Bool = false
```

#### 2. NotificationCenter Events
```swift
// Decoupled service communication
NotificationCenter.default.post(
    name: .nodeUpdated,
    object: updatedNode
)
```

#### 3. Async/Await Operations  
```swift
// Structured concurrency for data operations
func saveAllData(store: NodeStore) async throws
```

#### 4. Delegate/Closure Progress Reporting
```swift
// Progress tracking for long-running operations
func commitChanges(progressHandler: @escaping (GitOperationProgress) -> Void) async throws
```

### Contract Versioning Strategy

- **Semantic Versioning**: All contracts use major.minor.patch versioning
- **Breaking Change Management**: Major version increments for breaking changes
- **Deprecation Path**: Swift @available annotations with migration guides
- **Backward Compatibility**: One major version compatibility window

## Contract Specifications

### File Organization

```
docs/contracts/
├── swift/
│   └── service-protocols.swift      # Complete Swift protocol definitions
├── events/
│   └── wordtagger-events.asyncapi.yaml # Event-driven communication specs
├── schemas/
│   ├── node.schema.json            # Node data validation
│   ├── layer.schema.json           # Layer data validation
│   ├── search-result.schema.json   # Search result format
│   ├── git-credentials.schema.json # Git authentication format
│   └── external-data-format.schema.json # External storage format
├── http/
│   └── *.openapi.yaml              # HTTP API specifications (future)
└── tools/
    ├── contract-validator.swift    # Swift runtime validation
    ├── contract-test-suite.js      # JavaScript validation tools
    └── README.md                   # Validation tool documentation
```

### Contract Validation

All contracts include comprehensive validation:
- **Syntax validation** for JSON Schema, AsyncAPI, and OpenAPI formats
- **Example validation** ensuring examples conform to their schemas
- **Cross-contract consistency** checking for schema references and data alignment
- **Runtime compliance** testing for Swift protocol conformance

Run validation tests:
```bash
cd docs/contracts/tools
npm install
npm test
```

## Communication Patterns

WordTagger implements sophisticated communication patterns that enable decoupled, reactive, and performant service interactions.

### Pattern Overview

| Pattern | Use Case | Implementation | Example |
|---------|----------|----------------|---------|
| **@Published Binding** | UI state synchronization | Combine publishers | `@Published var nodes: [Node]` |
| **NotificationCenter Events** | Decoupled service communication | Event broadcasting | `nodeUpdated` notification |
| **Async/Await Operations** | Data persistence & network | Structured concurrency | `saveAllData() async throws` |
| **Progress Callbacks** | Long-running operations | Closure-based reporting | Git operations with progress |
| **Protocol Delegation** | Service configuration | Swift protocols | Service health monitoring |

### Reactive State Management

WordTagger uses Combine's @Published properties for automatic UI synchronization:

```swift
@MainActor
public final class NodeStore: ObservableObject {
    @Published public private(set) var nodes: [Node] = []
    @Published public private(set) var layers: [Layer] = []
    @Published public private(set) var selectedNode: Node?
    @Published public private(set) var isLoading: Bool = false
}
```

**Benefits:**
- Automatic UI updates when data changes
- Thread-safe main actor isolation
- Elimination of manual view refresh calls
- Declarative data binding in SwiftUI

### Event-Driven Architecture

NotificationCenter provides decoupled communication between services:

```swift
// Service publishes events
NotificationCenter.default.post(
    name: .nodeUpdated,
    object: updatedNode,
    userInfo: ["action": "content_changed"]
)

// Other services subscribe to events  
NotificationCenter.default.addObserver(
    forName: .nodeUpdated,
    object: nil,
    queue: .main
) { notification in
    // Handle node update
}
```

**Event Categories:**
- **Data Events**: Node/layer creation, updates, deletion
- **UI State Events**: Selection changes, filter updates
- **System Events**: Git operations, data synchronization
- **Performance Events**: Memory warnings, optimization triggers

### Structured Concurrency

All async operations use Swift's structured concurrency:

```swift
// Data service operations
@MainActor
func saveAllData(store: NodeStore) async throws {
    // Concurrent operations with proper error propagation
    async let layersSave = saveLayers(store.layers)
    async let nodesSave = saveNodes(store.nodes)
    
    try await layersSave
    try await nodesSave
}
```

**Advantages:**
- Automatic task cancellation and cleanup
- Structured error propagation
- Resource leak prevention
- Predictable execution order

## Service Interfaces

### Core Service Contracts

WordTagger defines comprehensive Swift protocols for all major services. See [service-protocols.swift](swift/service-protocols.swift) for complete definitions.

#### NodeStore - Central Data Management
```swift
@MainActor
public protocol NodeStoreProtocol: ObservableObject {
    // Observable state
    var nodes: [Node] { get }
    var layers: [Layer] { get }
    var selectedNode: Node? { get }
    
    // Data operations
    func addNode(_ node: Node) -> Bool
    func updateNode(_ nodeId: UUID, text: String?, phonetic: String?, meaning: String?)
    func deleteNode(_ nodeId: UUID)
    
    // Layer management
    func addLayer(_ layer: Layer)
    func setCurrentLayer(_ layer: Layer)
    func createCompoundLayer(name: String, displayName: String, childLayerIds: [UUID]) -> Layer
    
    // Search operations
    func performSearch(query: String)
    func searchTags(query: String) -> [Tag]
}
```

**Key Responsibilities:**
- Central repository for all nodes and layers
- Reactive state management with @Published properties
- Search operations with debounced queries
- Compound layer support for hierarchical organization
- Data integrity and corruption detection/repair

#### SearchService - Advanced Search Engine
```swift
public protocol SearchServiceProtocol: ObservableObject {
    var isSearching: Bool { get }
    var searchMetrics: SearchMetrics { get }
    
    func search(_ query: String, in nodes: [Node], filter: SearchFilter) async -> [SearchResult]
    func searchByTag(_ tagType: Tag.TagType, in nodes: [Node]) -> [Node]
    func searchByLocation(near coordinate: CLLocationCoordinate2D, radius: Double, in nodes: [Node]) -> [Node]
    func findSimilarNodes(_ node: Node, in nodes: [Node], threshold: Double) -> [Node]
}
```

**Search Capabilities:**
- Multi-field text search (text, meaning, phonetic, tags)
- Fuzzy matching with configurable thresholds
- Location-based proximity search
- Semantic similarity detection
- Performance monitoring and metrics

#### GitService - Version Control Integration
```swift
@MainActor
public protocol GitServiceProtocol: ObservableObject {
    var connectionStatus: GitConnectionStatus { get }
    var isOperationInProgress: Bool { get }
    var lastError: GitError? { get }
    
    func configureRepository(url: String, credentials: GitCredentials) async throws
    func commitChanges(message: String) async throws
    func pushToRemote() async throws
    func refreshRepositoryStatus() async
}
```

**Git Integration Features:**
- Secure credential management via Keychain
- Automatic retry with exponential backoff
- Progress reporting for long-running operations
- Comprehensive error handling with suggested actions
- Repository health monitoring

#### ExternalDataService - Data Persistence
```swift
@MainActor
public protocol ExternalDataServiceProtocol: ObservableObject {
    var isSaving: Bool { get }
    var isLoading: Bool { get }
    var syncStatus: SyncStatus { get }
    
    func saveAllData(store: NodeStore) async throws
    func loadAllData() async throws -> (layers: [Layer], nodes: [Node])
    func clearAllExternalData() async throws
}
```

**Data Management:**
- JSON-based external storage with backup/restore
- Data integrity verification with SHA-256 hashing
- Automatic corruption detection and repair
- Incremental and full backup strategies

### Service Health and Monitoring

All services implement health checking and performance monitoring:

```swift
public protocol HealthCheckable {
    func checkHealth() async -> ServiceHealth
}

public struct ServiceHealth {
    public let isHealthy: Bool
    public let status: HealthStatus
    public let message: String
    public let metrics: [String: Any]
}
```

## Data Contracts

WordTagger uses JSON Schema to define comprehensive data validation rules. All schemas include:
- Strict type validation with format constraints
- Required field enforcement
- Business logic validation rules
- Comprehensive examples with edge cases

### Node Data Contract ([node.schema.json](schemas/node.schema.json))

```json
{
  "type": "object",
  "required": ["id", "text", "layerId", "tags", "isCompound", "createdAt", "updatedAt"],
  "properties": {
    "id": { "type": "string", "format": "uuid" },
    "text": { 
      "type": "string", 
      "minLength": 1, 
      "maxLength": 500,
      "pattern": "^(?!.*[\\x00-\\x1F\\x7F-\\x9F]).*$"
    },
    "tags": {
      "type": "array",
      "maxItems": 50,
      "items": { "$ref": "#/$defs/Tag" }
    }
  }
}
```

**Validation Rules:**
- Text content must be non-empty and exclude control characters
- Maximum 50 tags per node to prevent performance issues
- UUID format validation for all identifier fields
- Location tags must have both latitude and longitude coordinates

### Layer Data Contract ([layer.schema.json](schemas/layer.schema.json))

Defines validation for both simple and compound layers:
```json
{
  "allOf": [
    {
      "if": { "properties": { "isCompound": { "const": true } } },
      "then": { 
        "properties": { "childLayerIds": { "minItems": 1 } },
        "required": ["childLayerIds"] 
      }
    }
  ]
}
```

**Business Logic Validation:**
- Compound layers must have at least one child layer
- Non-compound layers cannot have child layer references
- Layer names must be unique within the application
- Color values must be valid CSS colors or predefined names

### External Data Format ([external-data-format.schema.json](schemas/external-data-format.schema.json))

Complete validation for external storage including:
- Data format versioning and migration support
- Integrity verification with SHA-256 hashes
- Comprehensive metadata and statistics
- Backup and restore information

## Event Contracts

WordTagger's event-driven architecture is documented using AsyncAPI specifications. See [wordtagger-events.asyncapi.yaml](events/wordtagger-events.asyncapi.yaml) for complete event definitions.

### Event Categories

#### Node Management Events
- `node.created` - New node creation
- `node.updated` - Node content or metadata changes  
- `node.deleted` - Node removal
- `node.selected` - Selection state changes

#### Layer Management Events
- `layer.created` - New layer creation
- `layer.updated` - Layer property changes
- `layer.deleted` - Layer removal
- `layer.switched` - Active layer changes

#### Search Events
- `search.started` - Search operation initiation
- `search.completed` - Search results available
- `search.query.changed` - Search query updates (debounced)

#### Git Integration Events
- `git.connection.established` - Repository connection success
- `git.operation.started` - Git operation beginning
- `git.operation.completed` - Git operation success
- `git.operation.failed` - Git operation failure with retry information

#### External Data Events  
- `data.save.started` / `data.save.completed` - Data persistence operations
- `data.load.started` / `data.load.completed` - Data loading operations
- `data.path.changed` - External storage path modifications

#### Map Integration Events
- `map.location.selected` - Geographic location selection
- `map.node.clicked` - Node annotation interaction
- `map.preview.location` - Location preview requests

### Event Structure

All events follow a consistent structure with required metadata:

```yaml
EventMetadata:
  type: object
  required: [eventId, eventType, timestamp, version, source]
  properties:
    eventId: { type: string, format: uuid }
    eventType: { type: string }
    timestamp: { type: string, format: date-time }
    version: { type: string }
    source: { type: string }
    correlationId: { type: string, format: uuid }
```

### Event Examples

Node creation event:
```json
{
  "eventId": "evt_123e4567-e89b-12d3-a456-426614174000",
  "eventType": "node.created", 
  "timestamp": "2024-01-01T10:00:00Z",
  "version": "1.0",
  "source": "NodeStore",
  "data": {
    "nodeId": "node_123e4567-e89b-12d3-a456-426614174001",
    "layerId": "layer_123e4567-e89b-12d3-a456-426614174002",
    "text": "visible",
    "phonetic": "/ˈvɪzəbəl/",
    "meaning": "可见的",
    "tags": [
      {
        "type": "custom(root)",
        "value": "vis"
      }
    ]
  }
}
```

## Validation and Testing

WordTagger provides comprehensive contract validation tools to ensure interface compliance and data integrity.

### Validation Tools

1. **JavaScript Contract Test Suite** ([contract-test-suite.js](tools/contract-test-suite.js))
   - JSON Schema syntax and example validation
   - AsyncAPI specification structure verification
   - Cross-contract consistency checking
   - Automated CI/CD integration

2. **Swift Runtime Validator** ([contract-validator.swift](tools/contract-validator.swift))
   - Protocol conformance verification
   - Data structure compliance testing
   - Event publishing validation
   - Performance contract monitoring

### Running Validation Tests

```bash
# Install dependencies
cd docs/contracts/tools
npm install

# Run all contract tests
npm test

# Run specific test categories
node contract-test-suite.js --schemas-only
node contract-test-suite.js --events-only
node contract-test-suite.js --consistency-only
```

### Swift Integration

```swift
// Runtime contract validation
let validator = ContractValidator.shared
let report = validator.validateService(
    nodeStore, 
    conformingTo: [NodeStoreProtocol.self],
    withName: "NodeStore"
)

if !report.isValid {
    report.violations.forEach { violation in
        print("Contract violation: \(violation.description)")
    }
}
```

### Continuous Integration

Integration with CI/CD pipelines:

```yaml
# GitHub Actions example
- name: Validate Service Contracts
  run: |
    cd docs/contracts/tools
    npm install
    npm test
    
- name: Swift Contract Tests
  run: |
    swift test --filter ContractValidationTests
```

## Integration Guide

### For Service Developers

1. **Define Protocol Contract**: Start with Swift protocol definition in `service-protocols.swift`
2. **Add Data Schemas**: Create JSON Schema files for all data structures
3. **Document Events**: Add AsyncAPI specifications for all published events
4. **Implement Validation**: Use provided tools to validate compliance
5. **Add Tests**: Include contract tests in your service test suite

### For API Consumers

1. **Review Protocol**: Check Swift protocol for available methods and properties
2. **Understand Events**: Review AsyncAPI specs for event subscriptions
3. **Validate Data**: Use JSON schemas to validate input/output data
4. **Handle Errors**: Implement proper error handling per contract specifications

### Best Practices

#### Contract Design
- Use semantic versioning for all changes
- Provide comprehensive examples and documentation
- Include performance characteristics and constraints
- Define clear error handling contracts

#### Implementation
- Always validate input data against schemas
- Implement proper error propagation
- Use structured concurrency for async operations
- Provide observable state through @Published properties

#### Testing
- Run contract validation tests before committing
- Include integration tests for service interactions
- Test error scenarios and edge cases
- Monitor performance against contract specifications

### Migration Guidelines

When updating contracts:

1. **Breaking Changes**: Increment major version, provide migration guide
2. **New Features**: Increment minor version, ensure backward compatibility  
3. **Bug Fixes**: Increment patch version, maintain existing behavior
4. **Deprecation**: Use @available annotations with clear migration paths

---

This comprehensive contract documentation ensures reliable, maintainable, and well-tested service interactions throughout the WordTagger application. All services must adhere to these contracts to maintain system integrity and enable seamless integration.
