# WordTagger Service Dependency Mapping

## Overview
This document provides detailed dependency mappings for all services in the WordTagger application architecture. Each service's dependencies, consumers, and communication patterns are documented.

## Architecture Layers

### Core Services Layer
The foundational services that manage the primary application state and data operations.

#### NodeStore (Central State Management)
```swift
@MainActor public final class NodeStore: ObservableObject
```

**Dependencies:**
- `ExternalDataService` - For data persistence
- `TagMappingManager` - For tag type resolution
- `ExternalDataManager` - For path validation

**Consumers:**
- All SwiftUI views (ContentView, WordManagerView, TagSidebarView, etc.)
- SearchService (for data queries)
- GraphService (for relationship building)

**Communication:**
- **Publishes:** Node/Layer state changes via `@Published` properties
- **Receives:** Via NotificationCenter:
  - `.dataPathChanged` - Reloads data from new path
  - `.saveCurrentDataBeforeSwitch` - Saves before path change
  - `.tagTypeNameChanged` - Updates tag type names
  - `.clearTagFilter` - Clears tag filtering state

**Key Responsibilities:**
- Maintains @Published arrays of Nodes and Layers
- Handles CRUD operations with automatic persistence
- Manages search state and results
- Coordinates tag filtering and selection

---

#### ExternalDataService (Persistence Engine)
```swift
@MainActor public class ExternalDataService: ObservableObject
```

**Dependencies:**
- `ExternalDataManager` - For file path management
- `TagMappingManager` - For tag mapping persistence
- `JSONEncoder/JSONDecoder` - For serialization

**Consumers:**
- `NodeStore` - Primary consumer for all persistence operations

**Communication:**
- **Publishes:** Save/load state via `@Published` properties (`isSaving`, `isLoading`)
- **Emits:** Completion callbacks for async operations

**Key Responsibilities:**
- Async JSON serialization/deserialization
- Backup management with cleanup
- Data corruption detection and recovery
- Auto-sync coordination

---

#### DataManager (Import/Export Service)
```swift
class DataManager: ObservableObject
```

**Dependencies:**
- `FileManager` - For file I/O operations
- `NSSavePanel/NSOpenPanel` - For user file selection

**Consumers:**
- SwiftUI views requiring import/export functionality

**Communication:**
- **Async callbacks:** Completion handlers for file operations

**Key Responsibilities:**
- JSON import/export with validation
- Legacy data format support
- User-initiated file operations

---

### Specialized Services Layer

#### SearchService (Advanced Search Engine)
```swift
public final class SearchService: ObservableObject
```

**Dependencies:**
- `CoreLocation` - For location-based queries
- Node array (passed as parameter)

**Consumers:**
- `NodeStore` - Uses for search operations
- Search UI components

**Communication:**
- **Async operations:** Returns search results via async methods
- **Published state:** Search progress and metrics

**Key Responsibilities:**
- Multi-field fuzzy search
- Semantic similarity matching
- Location proximity search
- Performance optimization

---

#### GraphService (Relationship Analysis)
```swift
public final class GraphService: ObservableObject
```

**Dependencies:**
- Node arrays (for graph building)
- `CoreLocation` - For location proximity calculations

**Consumers:**
- Graph visualization components
- Relationship analysis features

**Communication:**
- **Published properties:** Graph state and build progress
- **Async methods:** Graph construction operations

**Key Responsibilities:**
- Node relationship detection
- Similarity scoring algorithms
- Graph clustering analysis
- Export for visualization

---

#### GitService (Version Control)
```swift
@MainActor class GitService: ObservableObject
```

**Dependencies:**
- `KeychainManager` - For credential storage
- `GitOperations` - For Git command execution
- `UserDefaults` - For configuration persistence

**Consumers:**
- Git-related UI components
- Auto-sync workflows

**Communication:**
- **Published properties:** Connection status, sync progress
- **NotificationCenter:** Emits Git operation events
- **Async operations:** Commit/push/pull operations

**Key Responsibilities:**
- Repository connection management
- Auto-commit on data changes
- Credential management with retry logic
- Branch and conflict handling

---

### Infrastructure Services Layer

#### TagMappingManager (Tag System Manager)
```swift
class TagMappingManager: ObservableObject
```

**Dependencies:**
- `UserDefaults` - For persistent storage
- Built-in tag type definitions

**Consumers:**
- `NodeStore` - For tag type resolution
- Tag-related UI components
- `ExternalDataService` - For tag mapping persistence

**Communication:**
- **NotificationCenter:** 
  - Emits: `.tagTypeNameChanged` when mappings change
  - Receives: External update events
- **Singleton access:** Direct method calls

**Key Responsibilities:**
- Tag type to display name mapping
- Custom tag type management
- Built-in tag type definitions
- Real-time mapping updates

---

#### KeyboardEventManager (Input Event Handler)
```swift
class KeyboardEventManager: ObservableObject
```

**Dependencies:**
- `DispatchQueue` - For thread management
- `Timer` - For cooldown and cleanup
- `NotificationCenter` - For app lifecycle events

**Consumers:**
- Command palette systems
- Keyboard shortcut handlers

**Communication:**
- **Published properties:** Error recovery state
- **Synchronous methods:** Command execution validation
- **App lifecycle:** Monitors focus changes

**Key Responsibilities:**
- Command execution throttling
- Error recovery mechanisms
- Focus state management
- Conflict resolution

---

#### KeychainManager (Security Service)
```swift
class KeychainManager
```

**Dependencies:**
- macOS Security framework
- Keychain Services API

**Consumers:**
- `GitService` - For credential storage/retrieval

**Communication:**
- **Direct method calls:** Synchronous credential operations
- **Error handling:** Throws on security failures

**Key Responsibilities:**
- Secure credential storage
- Git token management
- Access control enforcement

---

#### MemoryLeakDetection (Performance Monitor)
```swift
class MemoryLeakDetection
```

**Dependencies:**
- System memory APIs
- Performance monitoring frameworks

**Consumers:**
- Development and debugging tools

**Communication:**
- **Monitoring callbacks:** Memory usage reports
- **Debug output:** Leak detection alerts

**Key Responsibilities:**
- Memory usage tracking
- Leak detection algorithms
- Performance metrics collection

---

### Communication Infrastructure

#### NotificationCenter (Event Coordination)
```
NSNotificationCenter.default
```

**Key Event Types:**

1. **Data Management Events:**
   - `.dataPathChanged` → Triggers data reload in NodeStore
   - `.saveCurrentDataBeforeSwitch` → Forces immediate save

2. **Node/Tag Events:**
   - `"nodeUpdated"` → Triggers Git auto-sync and UI refresh
   - `.tagTypeNameChanged` → Updates tag display names
   - `"clearTagFilter"` → Resets tag filtering state

3. **Git Events:**
   - `.gitAuthenticationRequired` → Prompts for credentials
   - `.gitOperationFailed/.gitOperationSucceeded` → Status updates

4. **UI Events:**
   - `"compoundNodeRefreshed"` → Refreshes compound node displays

**Communication Patterns:**
- **Decoupled messaging:** Services don't directly reference each other
- **Async event handling:** Non-blocking event processing
- **User info payloads:** Additional context data with notifications

---

### External Dependencies

#### File System Integration
- **JSON persistence:** Structured data storage
- **Backup management:** Automatic backup creation and cleanup
- **Configuration files:** User preferences and settings

#### Git Repository Integration
- **Remote sync:** GitHub/GitLab integration
- **Version control:** History tracking and branch management
- **Conflict resolution:** Merge conflict handling

#### macOS Keychain Integration
- **Encrypted storage:** Secure credential management
- **Access control:** User authentication requirements
- **Token management:** Git personal access tokens

#### Core Location Integration
- **GPS services:** Location coordinate management
- **Geocoding:** Address to coordinate conversion
- **Permission management:** Location access authorization

---

## Service Initialization Order

1. **Foundation Services:** TagMappingManager, KeychainManager
2. **Storage Services:** ExternalDataManager, ExternalDataService
3. **Core Services:** NodeStore (depends on storage services)
4. **Specialized Services:** SearchService, GraphService, GitService
5. **Infrastructure Services:** KeyboardEventManager, MemoryLeakDetection
6. **UI Components:** All SwiftUI views (depend on NodeStore)

---

## Communication Flow Patterns

### Data Modification Flow
1. **UI Action** → NodeStore method call
2. **NodeStore** → Updates internal state
3. **NodeStore** → Calls ExternalDataService.saveAllData()
4. **NodeStore** → Posts "nodeUpdated" notification
5. **GitService** → Receives notification → Auto-commit
6. **UI Components** → Receive @Published updates → Refresh

### Tag System Flow
1. **User modifies tag type** → TagMappingManager
2. **TagMappingManager** → Posts .tagTypeNameChanged notification  
3. **NodeStore** → Receives notification → Updates affected nodes
4. **ExternalDataService** → Saves updated tag mappings
5. **UI** → Refreshes with new tag display names

### Error Recovery Flow
1. **Service encounters error** → KeyboardEventManager.markCommandFailed()
2. **KeyboardEventManager** → Enters error recovery mode
3. **Active commands cleared** → UI state normalized
4. **Recovery timeout** → Automatic state reset
5. **Normal operation resumed** → Error recovery exit

This dependency mapping ensures clear separation of concerns while enabling efficient communication between services through the notification system and direct method calls where appropriate.