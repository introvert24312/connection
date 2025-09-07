# 多窗口管理契约文档

## 概述
此文档定义了WordTagger应用中多窗口环境下的管理契约，包括窗口焦点管理、状态同步、原子性操作和竞态条件防护。

## 🪟 窗口类型定义

### 支持的窗口类型
| 窗口类型 | 类名 | 窗口ID | NodeStore类型 | 描述 |
|----------|------|--------|---------------|------|
| **主窗口** | `ContentView` | 动态UUID | 共享实例 | 应用主界面，使用NodeStore.shared |
| **独立窗口** | `IndependentWindow` | 动态UUID | 独立实例 | 独立的节点管理界面，独立NodeStore |
| **层图谱窗口** | `LayerGraphWindowView` | `layerGraph` | 共享实例 | 层关系可视化，每个主窗口最多一个 |
| **地图窗口** | `MapWindow` | `map` | 共享实例 | 地理位置可视化 |
| **节点图谱窗口** | `GraphWindow` | `graph` | 共享实例 | 节点关系图谱 |
| **节点管理窗口** | `NodeManagerWindow` | `nodeManager` | 共享实例 | 批量节点管理工具 |

## 🎯 WindowFocusManager 核心契约

### 接口定义
```swift
@MainActor
class WindowFocusManager: ObservableObject {
    static let shared = WindowFocusManager()
    
    // MARK: - 核心接口契约
    
    /// 原子性预留层图谱窗口 (防止竞态条件)
    func reserveLayerGraphWindow(for mainWindowId: String) -> Bool
    
    /// 检查窗口是否应该处理通知
    func shouldHandleNotification(
        for windowId: UUID, 
        isGlobalCommand: Bool, 
        commandName: String? = nil
    ) -> Bool
    
    /// 强制刷新窗口状态 (错误恢复)
    func forceRefreshWindowState()
    
    /// 获取调试信息
    func getDebugInfo() -> [String: Any]
    
    // MARK: - 窗口映射管理
    
    /// 建立地图窗口映射
    func establishMapWindowMapping(sourceWindowId: String, mapWindow: NSWindow)
    
    /// 清理窗口映射
    func cleanupWindowMapping(for windowId: String)
    
    // MARK: - 状态查询
    
    /// 获取活跃窗口数量
    var activeWindowCount: Int { get }
    
    /// 检查特定窗口类型是否已存在
    func hasWindow(type: String, for sourceWindowId: String) -> Bool
}
```

### 预留机制契约
```swift
// 层图谱窗口原子性预留
private var layerGraphWindows: [String: String] = [:]  // mainWindowId -> windowState

func reserveLayerGraphWindow(for mainWindowId: String) -> Bool {
    // 检查是否已存在
    if layerGraphWindows[mainWindowId] != nil {
        print("⚠️ 主窗口 \\(mainWindowId.prefix(8)) 已有层图谱窗口")
        return false
    }
    
    // 原子性预留
    layerGraphWindows[mainWindowId] = "RESERVED"
    print("✅ 为主窗口 \\(mainWindowId.prefix(8)) 预留层图谱窗口")
    return true
}

// 窗口创建完成后更新状态
func confirmLayerGraphWindow(for mainWindowId: String, windowInstance: NSWindow) {
    layerGraphWindows[mainWindowId] = "ACTIVE:\\(windowInstance.identifier?.rawValue ?? "unknown")"
}
```

## 🔄 状态同步契约

### NodeStore实例管理
```swift
// 主窗口和层图谱窗口 - 使用共享实例
@EnvironmentObject private var store: NodeStore  // NodeStore.shared

// 独立窗口 - 使用独立实例  
@StateObject private var store: NodeStore = NodeStore.createIndependentInstance()
```

### 跨窗口状态同步
```swift
// 标签筛选状态同步
protocol TagFilterStateSyncProtocol {
    // 保存当前状态
    func saveCurrentTagFilterState()
    
    // 恢复之前状态
    func restorePreviousTagFilterState()
    
    // 清除所有筛选状态
    func clearTagFilter()
    
    // 检查是否有保存的状态
    func hasSavedTagFilterState() -> Bool
}

// 节点选择状态同步
extension NodeStore {
    // 跨层选择节点 (支持自动层切换)
    @MainActor
    func selectNodeAcrossLayers(_ node: Node) {
        // 检查节点所属层
        if node.layerId != currentLayer?.id {
            if let nodeLayer = layers.first(where: { $0.id == node.layerId }) {
                print("🔄 自动切换到节点所属层: \\(nodeLayer.displayName)")
                setCurrentLayer(nodeLayer)
            }
        }
        
        // 选择节点
        selectNode(node)
        
        // 清除标签筛选以确保节点可见
        clearTagFilter()
    }
}
```

## 🚦 通知路由契约

### 窗口特定通知路由
```swift
// 通知接收窗口验证
.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("executeOpenWindow"))) { notification in
    // 1. 源窗口ID验证
    if let sourceWindowId = notification.userInfo?["sourceWindowId"] as? String {
        guard sourceWindowId == self.windowId.uuidString else {
            print("🚫 源窗口ID不匹配，忽略通知")
            return
        }
    }
    
    // 2. 窗口焦点状态检查
    guard WindowFocusManager.shared.shouldHandleNotification(
        for: windowId, 
        isGlobalCommand: false, 
        commandName: "executeOpenWindow"
    ) else {
        print("🚫 窗口焦点检查失败，忽略通知")
        return
    }
    
    // 3. 执行操作
    handleWindowOpenRequest(notification)
}
```

### 全局命令路由
```swift
// 全局命令 (如Command+T) 路由到所有相关窗口
.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("clearTagFilterFromKeyboard"))) { _ in
    // 全局命令不需要窗口ID验证，但需要焦点检查
    guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true) else {
        return
    }
    
    print("🔑 \\(windowType): 收到键盘清除标签筛选通知")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
        store.clearTagFilter()
    }
}
```

## 🛡️ 竞态条件防护

### 层图谱窗口重复防护
```swift
// 问题: 多个通知接收器同时处理executeOpenWindow
// 解决: 原子性预留机制

// 发送方
NotificationCenter.default.post(
    name: NSNotification.Name("executeOpenWindow"),
    object: "layerGraph",
    userInfo: ["sourceWindowId": windowId.uuidString]
)

// 接收方
.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("executeOpenWindow"))) { notification in
    if let windowType = notification.object as? String, windowType == "layerGraph" {
        // 原子性检查和预留
        let currentWindowId = windowId.uuidString
        guard WindowFocusManager.shared.reserveLayerGraphWindow(for: currentWindowId) else {
            print("⚠️ 层图谱窗口已存在，忽略重复请求")
            return
        }
        
        // 只有预留成功的接收器才会执行窗口创建
        openWindow(id: windowType)
    }
}
```

### 命令防抖机制
```swift
// ContentView中的命令冷却期
private var commandCooldowns: [String: Date] = [:]
private let cooldownPeriod: TimeInterval = 0.5

private func shouldExecuteCommand(_ commandName: String) -> Bool {
    let now = Date()
    if let lastExecution = commandCooldowns[commandName] {
        let timeSinceLastExecution = now.timeIntervalSince(lastExecution)
        if timeSinceLastExecution < cooldownPeriod {
            print("🚫 命令'\\(commandName)'仍在冷却期 (剩余: \\(String(format: "%.3f", cooldownPeriod - timeSinceLastExecution))s)")
            return false
        }
    }
    commandCooldowns[commandName] = now
    return true
}
```

## 🔌 窗口生命周期契约

### 窗口创建流程
```swift
// 1. 检查权限和状态
func canCreateWindow(type: String, sourceWindowId: String) -> Bool {
    switch type {
    case "layerGraph":
        return WindowFocusManager.shared.reserveLayerGraphWindow(for: sourceWindowId)
    case "map":
        return !WindowFocusManager.shared.hasWindow(type: "map", for: sourceWindowId)
    default:
        return true
    }
}

// 2. 创建窗口
func createWindow(type: String, sourceWindowId: String) {
    guard canCreateWindow(type: type, sourceWindowId: sourceWindowId) else {
        return
    }
    
    openWindow(id: type)
    
    // 3. 建立映射关系
    if type == "map" {
        // 延迟建立映射，确保窗口已创建
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let sourceInfo = ["sourceWindowId": sourceWindowId]
            NotificationCenter.default.post(
                name: NSNotification.Name("setupMapWindowMapping"),
                object: sourceInfo
            )
        }
    }
}
```

### 窗口销毁清理
```swift
// 窗口销毁时清理映射
.onDisappear {
    WindowFocusManager.shared.cleanupWindowMapping(for: windowId.uuidString)
}

// WindowFocusManager清理方法
func cleanupWindowMapping(for windowId: String) {
    // 清理层图谱窗口映射
    layerGraphWindows.removeValue(forKey: windowId)
    
    // 清理地图窗口映射
    mapWindowMappings.removeValue(forKey: windowId)
    
    // 清理其他相关映射
    print("🧹 已清理窗口 \\(windowId.prefix(8)) 的所有映射")
}
```

## 🎨 UI状态管理契约

### 窗口焦点指示
```swift
// 窗口标题栏指示活跃状态
var windowTitle: String {
    let baseTitle = "WordTagger"
    let isActive = WindowFocusManager.shared.isWindowActive(windowId)
    return isActive ? "● \\(baseTitle)" : baseTitle
}
```

### 多窗口间UI同步
```swift
// 层切换同步
@Published private var currentLayerSync: Layer? {
    didSet {
        // 同步到其他使用共享NodeStore的窗口
        if isSharedInstance {
            NotificationCenter.default.post(
                name: NSNotification.Name("layerChanged"),
                object: currentLayerSync,
                userInfo: ["sourceWindowId": windowId?.uuidString ?? "unknown"]
            )
        }
    }
}
```

## ⚠️ 错误处理契约

### 窗口管理错误类型
```swift
enum WindowManagementError: Error, LocalizedError {
    case windowAlreadyExists(type: String, sourceId: String)
    case invalidWindowId(String)
    case focusManagerUnavailable
    case reservationFailed(reason: String)
    
    var errorDescription: String? {
        switch self {
        case .windowAlreadyExists(let type, let sourceId):
            return "窗口类型'\\(type)'已存在于源窗口\\(sourceId)"
        case .invalidWindowId(let id):
            return "无效的窗口ID: \\(id)"
        case .focusManagerUnavailable:
            return "WindowFocusManager不可用"
        case .reservationFailed(let reason):
            return "窗口预留失败: \\(reason)"
        }
    }
}
```

### 错误恢复策略
```swift
// 窗口状态异常恢复
func recoverFromWindowStateError() {
    print("🔄 开始窗口状态错误恢复...")
    
    // 1. 强制刷新窗口状态
    WindowFocusManager.shared.forceRefreshWindowState()
    
    // 2. 清理无效映射
    WindowFocusManager.shared.cleanupInvalidMappings()
    
    // 3. 重新建立必要的映射
    establishEssentialMappings()
    
    print("✅ 窗口状态错误恢复完成")
}

// 映射一致性检查
func validateMappingConsistency() -> [String] {
    var issues: [String] = []
    
    // 检查层图谱窗口映射
    for (sourceId, windowState) in layerGraphWindows {
        if windowState == "RESERVED" {
            // 检查预留时间是否过长
            issues.append("层图谱窗口预留超时: \\(sourceId)")
        }
    }
    
    return issues
}
```

## 📊 性能监控契约

### 关键性能指标
```swift
struct WindowManagementMetrics {
    let activeWindowCount: Int
    let reservationSuccessRate: Double
    let averageWindowCreationTime: TimeInterval
    let notificationRoutingAccuracy: Double
    let mappingConsistencyScore: Double
}

// 性能监控方法
func collectWindowManagementMetrics() -> WindowManagementMetrics {
    return WindowManagementMetrics(
        activeWindowCount: WindowFocusManager.shared.activeWindowCount,
        reservationSuccessRate: calculateReservationSuccessRate(),
        averageWindowCreationTime: calculateAverageCreationTime(),
        notificationRoutingAccuracy: calculateNotificationAccuracy(),
        mappingConsistencyScore: calculateMappingConsistency()
    )
}
```

### 健康检查
```swift
// 定期健康检查
func performWindowHealthCheck() -> HealthStatus {
    let metrics = collectWindowManagementMetrics()
    
    var status = HealthStatus.healthy
    var issues: [String] = []
    
    // 检查活跃窗口数量
    if metrics.activeWindowCount > 20 {
        status = .warning
        issues.append("活跃窗口数量过多: \\(metrics.activeWindowCount)")
    }
    
    // 检查预留成功率
    if metrics.reservationSuccessRate < 0.95 {
        status = .critical
        issues.append("窗口预留成功率过低: \\(metrics.reservationSuccessRate)")
    }
    
    return HealthStatus(status: status, issues: issues)
}
```

## 🧪 测试契约

### 单元测试要求
```swift
class WindowFocusManagerTests: XCTestCase {
    
    func testLayerGraphWindowReservation() {
        let manager = WindowFocusManager()
        let windowId = "test-window-1"
        
        // 首次预留应该成功
        XCTAssertTrue(manager.reserveLayerGraphWindow(for: windowId))
        
        // 重复预留应该失败
        XCTAssertFalse(manager.reserveLayerGraphWindow(for: windowId))
        
        // 清理后应该可以再次预留
        manager.cleanupWindowMapping(for: windowId)
        XCTAssertTrue(manager.reserveLayerGraphWindow(for: windowId))
    }
    
    func testNotificationRouting() {
        // 测试通知路由的窗口ID验证
        // 测试全局命令的广播机制
        // 测试焦点状态检查
    }
    
    func testRaceConditionPrevention() {
        // 并发测试：多个线程同时尝试预留窗口
        // 确保只有一个成功
    }
}
```

### 集成测试场景
1. **多窗口协作**: 同时打开所有类型的窗口，验证状态同步
2. **竞态条件**: 快速连续触发窗口创建操作
3. **错误恢复**: 模拟窗口异常关闭，验证状态清理
4. **内存泄漏**: 长时间运行，验证窗口映射是否正确清理
5. **焦点管理**: 窗口之间切换焦点，验证通知路由准确性

## 📝 变更日志

### v2.0.0 (2025-09-07)
- ✅ 实现WindowFocusManager原子性预留机制
- ✅ 修复层图谱窗口重复创建问题
- ✅ 完善多窗口通知路由系统
- ✅ 添加竞态条件防护机制
- ✅ 实现窗口生命周期管理

### v1.9.0 (2024-12-xx)  
- ✅ 基础多窗口支持
- ✅ 初始窗口焦点管理
- ✅ 简单状态同步机制

---

此契约确保WordTagger应用中多窗口环境的稳定性、一致性和高性能运行。所有窗口管理相关组件都必须严格遵循这些契约规范。