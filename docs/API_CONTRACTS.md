# 真实 API 接口契约

基于实际代码的接口定义，**每个方法都真实存在且可调用**。

## 🏪 NodeStore 核心接口

### 节点管理
```swift
// 添加节点
func addNode(_ node: Node) -> Bool
func addNode(_ text: String, phonetic: String?, meaning: String?) -> Bool

// 更新节点  
func updateNode(_ node: Node)
func updateNode(_ nodeId: UUID, text: String?, phonetic: String?, meaning: String?)
func updateNodeMarkdown(_ nodeId: UUID, markdown: String)
func updateNodeTags(_ nodeId: UUID, tags: [Tag])

// 删除节点
func deleteNode(_ node: Node)
func deleteNode(_ nodeId: UUID)

// 查询节点
func getNode(by id: UUID) -> Node?
func getNodesInCurrentLayer() -> [Node]
```

### 层管理
```swift
// 层操作
func setCurrentLayer(_ layer: Layer)
func addLayer(_ layer: Layer)
func deleteLayer(_ layerId: UUID)
func getCurrentLayer() -> Layer?

// 层查询
func getAllLayers() -> [Layer]
func getLayer(by id: UUID) -> Layer?
```

### 标签管理
```swift
// 标签操作
func addTag(_ tag: Tag)
func addTag(to nodeId: UUID, tag: Tag)
func removeTag(from nodeId: UUID, tag: Tag)

// 标签查询
func getAllTags() -> [String: [Tag]]
func getTagsForNode(_ nodeId: UUID) -> [Tag]
```

### 搜索功能
```swift
// 搜索接口
func performSearch(query: String)
func clearSearch()

// 状态属性
@Published var searchResults: [Node]
@Published var searchQuery: String
@Published var isSearching: Bool
```

## 💾 ExternalDataService 接口

### 数据持久化
```swift
// 保存操作
func saveData() async throws
func saveNodesOnly() async throws  
func saveLayersOnly() async throws
func saveTagMappingsOnly() async throws

// 加载操作
func loadData() async throws -> (nodes: [Node], layers: [Layer])
func loadFromPath(_ path: String) async throws

// 备份操作
func createBackup() async throws
func restoreFromBackup() async throws
```

## 🔄 GitService 接口

### Git 操作
```swift
// 仓库管理
func setupRepository(url: String, username: String, token: String) async throws
func commitAndPush(message: String) async throws

// 状态查询  
func checkStatus() async throws -> String
func isRepositoryConfigured() -> Bool

// 状态属性
@Published var isAuthenticated: Bool
@Published var lastSyncTime: Date?
@Published var syncStatus: String
```

## 🔍 SearchService 接口

### 搜索功能
```swift
// 搜索方法
func search(query: String, in nodes: [Node]) -> [Node]
func fuzzyMatch(_ query: String, _ text: String) -> Double

// 地理搜索
func searchByLocation(coordinate: CLLocationCoordinate2D, radius: Double) -> [Node]

// 标签搜索
func searchByTag(type: String, value: String) -> [Node]
```

## 🗺️ MapContainer 接口

### 地图操作
```swift
// 位置管理
func showLocation(_ coordinate: CLLocationCoordinate2D, name: String)
func showAllLocationNodes()
func centerOnCoordinate(_ coordinate: CLLocationCoordinate2D)

// 节点交互
func selectNodeOnMap(_ nodeId: UUID)
func showNodeDetails(_ node: Node)

// 状态属性
@Published var selectedCoordinate: CLLocationCoordinate2D?
@Published var locationNodes: [Node]
```

## 🪟 WindowFocusManager 接口

### 窗口管理
```swift
// 窗口操作
func createWindow(type: WindowType, nodeId: UUID?) -> UUID
func closeWindow(id: UUID)
func focusWindow(id: UUID)

// 状态查询
func getActiveWindow() -> UUID?
func getAllWindows() -> [UUID: WindowType]

// 防竞态
func reserveOperation(type: String) -> Bool
func releaseOperation(type: String)
```

## ⌨️ KeyboardEventManager 接口

### 键盘事件
```swift
// 事件处理
func handleKeyPress(_ event: NSEvent) -> Bool
func registerShortcut(_ key: String, action: @escaping () -> Void)

// 错误恢复
func enterErrorRecoveryMode()
func exitErrorRecoveryMode()
func isInErrorRecoveryMode() -> Bool

// 状态属性
@Published var isCommandPaletteOpen: Bool
@Published var lastKeyEvent: Date?
```

## 🏷️ TagMappingManager 接口

### 标签映射
```swift
// 映射管理
func saveMapping(_ mapping: TagMapping)
func getMapping(for key: String) -> TagMapping?
func getAllMappings() -> [TagMapping]

// 类型转换
func getDisplayName(for tagType: String) -> String
func getTagType(for key: String) -> Tag.TagType?

// 状态属性
@Published var tagMappings: [TagMapping]
```

## 📡 NotificationCenter 事件

### 核心事件
```swift
// 数据变更事件
static let nodeUpdated = Notification.Name("nodeUpdated")
static let layerSwitched = Notification.Name("layerSwitched") 
static let dataPathChanged = Notification.Name("dataPathChanged")

// Git 事件
static let gitOperationStarted = Notification.Name("gitOperationStarted")
static let gitOperationSucceeded = Notification.Name("gitOperationSucceeded")
static let gitOperationFailed = Notification.Name("gitOperationFailed")

// UI 事件
static let refreshUI = Notification.Name("refreshUI")
static let nodeSelectionChanged = Notification.Name("nodeSelectionChanged")
```

## 🔍 TracingService 接口 (可选)

### 追踪功能
```swift
// 追踪操作
func startTrace(operation: String, service: String) -> TraceSpan
func endTrace(_ span: TraceSpan)
func addEvent(_ event: String, to span: TraceSpan)

// 查询接口
func getActiveTraces() -> [TraceSpan]
func getTraceHistory() -> [TraceSpan]

// 状态属性
@Published var isTracingEnabled: Bool
@Published var activeSpansCount: Int
```

## 💡 使用示例

### 创建节点
```swift
let store = NodeStore()
let success = store.addNode("苹果", phonetic: "píng guǒ", meaning: "水果")
```

### 搜索节点
```swift
store.performSearch(query: "苹果")
// 结果在 store.searchResults 中
```

### Git 同步
```swift
let gitService = GitService()
try await gitService.commitAndPush(message: "添加新节点")
```

---
*所有接口均基于实际代码 (2025年9月17日)*