# WordTagger Architecture Documentation

## Overview

This directory contains comprehensive architecture documentation for the WordTagger application, including service mappings, dependency relationships, data flow patterns, and runtime visualization tools. This documentation reflects lessons learned from solving complex enterprise-level challenges in multi-window SwiftUI applications.

## 🎯 架构演进历程

### 第一阶段：基础架构 (2024年10月)
- 建立MVVM + Service Layer基础架构
- 实现NotificationCenter事件系统
- 解决多窗口状态同步基础问题

### 第二阶段：稳定性危机处理 (2024年11月)  
- **挑战**: WebView废弃API导致应用崩溃
- **解决**: 完全重构WebView安全策略，移除`allowUniversalAccessFromFileURLs`等废弃API
- **收获**: 建立了现代化的WebView最佳实践

### 第三阶段：企业级可观测性 (2024年12月-2025年1月)
- **挑战**: 复杂服务交互难以调试和监控
- **解决**: 构建完整的分布式追踪系统，实现TraceID传播
- **收获**: 20个服务的全链路可观测性

### 第四阶段：多窗口架构复杂性 (2025年9月)
- **挑战**: 窗口焦点管理竞态条件，快捷键冲突
- **解决**: WindowFocusManager原子性预留，KeyboardEventManager错误恢复
- **收获**: 企业级多窗口协调机制

## Documentation Files

### Core Architecture Diagrams

#### `wordtagger-complete-architecture.mmd`
**Complete system architecture diagram showing all services and their relationships.**
- 🎯 Core Layer: NodeStore, DataManager, ExternalDataManager
- ⚡ Service Layer: ExternalDataService, SearchService, GraphService, GitService
- 🛠️ Infrastructure Layer: TagMappingManager, KeyboardEventManager, KeychainManager
- 🎨 Presentation Layer: All SwiftUI views and UI components
- 📡 Communication System: NotificationCenter-based event coordination
- 💾 External Dependencies: File system, Git repositories, macOS services

#### `l2.mmd` (Updated)
**Enhanced L2 service catalog diagram with current implementation details.**
- Updated to reflect actual service implementations
- Includes notification system relationships
- Shows external dependency integrations
- Color-coded by service type and responsibility

#### `data-flow-patterns.mmd`
**Data flow visualization showing notification-based communication.**
- User action → State change → Persistence → Sync workflows
- Tag system modification flows
- Error recovery patterns
- Search and filter operations

### Documentation

#### `service-dependency-mapping.md`
**Detailed service dependency analysis and communication patterns.**
- Complete service breakdown with dependencies and consumers
- Communication protocols (direct calls, notifications, async operations)
- Service initialization order and lifecycle management
- Error handling and recovery mechanisms

#### `ArchitectureVisualization.swift` (Optional)
**Runtime architecture visualization and monitoring dashboard.**
- SwiftUI-based architecture inspector
- Real-time service health monitoring
- Interactive dependency visualization
- Service detail views and metrics

## Architecture Principles

### MVVM + Service Layer Pattern
- **Model**: Node, Layer, Tag data structures
- **ViewModel**: NodeStore (central state management)
- **View**: SwiftUI components with reactive @Published bindings
- **Services**: Specialized business logic and infrastructure

### Notification-Based Communication
- **Decoupled services**: No direct dependencies between most services
- **Event-driven updates**: NotificationCenter coordinates state changes
- **Async operations**: Non-blocking data persistence and Git operations
- **Error recovery**: Automatic state correction and user feedback

### Key Services Architecture

#### Core Services (Central State & Persistence)
1. **NodeStore** - Central state management with @Published properties
2. **ExternalDataService** - Async persistence with backup and recovery
3. **DataManager** - Import/export operations with validation
4. **ExternalDataManager** - Storage path management and security

#### Specialized Services (Business Logic)
1. **SearchService** - Advanced multi-field search with semantic matching
2. **GraphService** - Node relationship analysis and clustering
3. **GitService** - Version control with auto-sync and credential management

#### Infrastructure Services (Support & Monitoring)
1. **TagMappingManager** - Tag type system with custom definitions
2. **KeyboardEventManager** - Input handling with error recovery
3. **KeychainManager** - Secure credential storage
4. **MemoryLeakDetection** - Performance monitoring

### Communication Patterns

#### Primary Data Flow
```
UI Action → NodeStore → ExternalDataService → File System
                    ↓
              NotificationCenter → GitService → Git Repository
                    ↓
              @Published Update → UI Refresh
```

#### Tag System Flow
```
Tag Modification → TagMappingManager → NotificationCenter
                                             ↓
                                        NodeStore → UI Update
                                             ↓
                                    ExternalDataService → Persistence
```

#### Error Recovery Flow
```
Error Detection → KeyboardEventManager → Error Recovery Mode
                                              ↓
                  State Cleanup → Normal Operation → Recovery Exit
```

## Integration Guidelines

### Adding New Services
1. Define service interface and dependencies
2. Implement with appropriate service layer (Core/Specialized/Infrastructure)
3. Add notification events if cross-service communication needed
4. Update architecture documentation
5. Add health monitoring if applicable

### Modifying Existing Services
1. Check dependency mappings to understand impact
2. Maintain backward compatibility for @Published properties
3. Update notification payloads if event structure changes
4. Test error recovery and state management
5. Update documentation and diagrams

### Notification System Usage
```swift
// Posting notifications
NotificationCenter.default.post(
    name: .dataPathChanged,
    object: self,
    userInfo: ["newPath": newDataPath]
)

// Listening for notifications
NotificationCenter.default.addObserver(
    forName: .nodeUpdated,
    object: nil,
    queue: .main
) { notification in
    // Handle event
}
```

### Service Initialization
Services should be initialized in dependency order:
1. Foundation services (TagMappingManager, KeychainManager)
2. Storage services (ExternalDataManager, ExternalDataService)
3. Core services (NodeStore)
4. Specialized services (SearchService, GraphService, GitService)
5. UI components

## Best Practices

### State Management
- Use @MainActor for UI-bound services
- Implement @Published properties for reactive updates
- Avoid direct state mutation from multiple threads
- Use async/await for long-running operations

### Error Handling
- Implement graceful degradation for service failures
- Use notification system for error propagation
- Provide user-friendly error messages
- Implement automatic recovery where possible

### Performance
- Use background queues for heavy operations
- Implement caching strategies for expensive computations
- Monitor memory usage and implement cleanup
- Use debouncing for rapid user actions

### Security
- Store sensitive data in Keychain
- Validate external input and file paths
- Use app sandbox security properly
- Implement proper access control

## Viewing Architecture Diagrams

### Using Mermaid CLI
```bash
# Install mermaid-cli
npm install -g @mermaid-js/mermaid-cli

# Generate PNG diagrams
mmdc -i wordtagger-complete-architecture.mmd -o architecture-complete.png
mmdc -i l2.mmd -o architecture-l2.png  
mmdc -i data-flow-patterns.mmd -o data-flow.png
```

### Online Mermaid Editor
Visit [mermaid.live](https://mermaid.live) and paste any `.mmd` file content for interactive viewing.

### In-App Visualization
The optional `ArchitectureVisualization.swift` provides a runtime SwiftUI dashboard for monitoring service health and dependencies.

## Maintenance

This architecture documentation should be updated whenever:
- New services are added or removed
- Service dependencies change
- Communication patterns are modified
- New notification events are introduced
- Error handling strategies are updated

Regular architecture reviews should validate that the implementation matches the documented design and identify areas for improvement or refactoring.