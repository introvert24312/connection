# L2 Architecture Diagram Validation Report

Generated: 2025-08-20T04:00:51.143Z

## Statistics
- Total Services: 16
- Services with Dependencies: 6
- Total Dependencies: 10
- Orphaned Services: 8
- Missing Services: 5

## Validation Status
Status: ❌ ISSUES FOUND

## Issues
- Orphaned services (no connections): context-menu-manager, data-manager, fullscreen-graph-window-manager, geocoder-service, governance-validation, graph-manager, keyboard-event-manager, tag-mapping-manager
- Missing service definitions: database, cache, file-manager, keychain-manager, cllocation-manager

## Service List
- **context-menu-manager**: / Optimized context menu manager that handles creation and disposal efficiently class ContextMenuManager
- **data-manager**: DataManager - Manages and coordinates system resources
- **example-service**: Example service for testing governance framework
  - Dependencies: database, cache
- **external-data-manager**: ExternalDataManager - Manages and coordinates system resources
  - Dependencies: file-manager
- **external-data-service**: ExternalDataService - Provides core business logic and functionality
  - Dependencies: external-data-manager
- **fullscreen-graph-window-manager**: MARK - SwiftUI原生全屏图谱管理器 class FullscreenGraphWindowManager
- **geocoder-service**: GeocoderService - Provides core business logic and functionality
- **git-service**: GitService - Provides core business logic and functionality
  - Dependencies: keychain-manager
- **governance-validation**: Engineering governance framework validation and compliance checking
- **graph-manager**: MARK - 全局图谱管理器 class GraphManager
- **graph-service**: GraphService - Provides core business logic and functionality
- **keyboard-event-manager**: / Manages keyboard event state and prevents rapid-fire command execution class KeyboardEventManager
- **location-manager**: MARK - Location Manager class LocationManager
  - Dependencies: cllocation-manager
- **search-service**: SearchService - Provides core business logic and functionality
- **tag-mapping-manager**: TagMappingManager - Manages and coordinates system resources
- **wordtagger-app**: Main WordTagger macOS application for word and node management
  - Dependencies: external-data-service, git-service, graph-service, search-service