# 键盘事件和通知契约文档

## 概述
此文档定义了WordTagger应用中键盘事件处理和NotificationCenter通知的契约规范，确保多窗口环境下的一致性和可靠性。

## 📋 键盘快捷键契约

### 全局键盘快捷键
| 快捷键 | 功能 | 通知名称 | 处理方式 |
|--------|------|----------|----------|
| ⌘K | 层图谱窗口/命令面板 | `showCommandPalette` | 全局菜单 → 通知 |
| ⌘T | 清除标签筛选 | `clearTagFilterFromKeyboard` | 全局菜单 → 通知 |
| ⌘⇧T | 恢复标签筛选状态 | `restorePreviousTagFilterState` | 全局菜单 → 直接调用 |
| ⌘N | 添加新节点 | `addNewNode` | 全局菜单 → 通知 |
| ⌘F | 标签搜索 | `openTagSearch` | 全局菜单 → 通知 |
| ⌘⇧F | 快速搜索 | `openQuickSearch` | 全局菜单 → 通知 |
| ⌘M | 地图窗口 | `openMapWindow` | 全局菜单 → 通知 |
| ⌘G | 全局节点图谱 | `openGraphWindow` | 全局菜单 → 通知 |
| ⌘B | 新建独立窗口 | `openNewWindow` | 全局菜单 → 直接调用 |

## 📡 NotificationCenter 通知契约

### 核心通知规范

#### `clearTagFilterFromKeyboard`
**用途**: 从键盘快捷键触发的标签筛选清除操作
```swift
// 发送
NotificationCenter.default.post(
    name: NSNotification.Name("clearTagFilterFromKeyboard"), 
    object: nil
)

// 接收 (主窗口和独立窗口)
.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("clearTagFilterFromKeyboard"))) { _ in
    print("🔑 收到键盘清除标签筛选通知")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
        store.clearTagFilter()
    }
}
```

#### `executeOpenWindow`
**用途**: 统一的窗口打开请求
```swift
// 发送 (带源窗口ID)
NotificationCenter.default.post(
    name: NSNotification.Name("executeOpenWindow"), 
    object: windowType, // "layerGraph", "map", "graph" 等
    userInfo: ["sourceWindowId": windowId.uuidString]
)

// 接收
.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("executeOpenWindow"))) { notification in
    // 窗口ID验证
    if let sourceWindowId = notification.userInfo?["sourceWindowId"] as? String {
        guard sourceWindowId == windowId.uuidString else { return }
    }
    
    if let windowType = notification.object as? String {
        // 层图谱窗口需要原子性检查
        if windowType == "layerGraph" {
            guard WindowFocusManager.shared.reserveLayerGraphWindow(for: windowId.uuidString) else {
                return // 防止重复创建
            }
        }
        openWindow(id: windowType)
    }
}
```

#### `restorePreviousTagFilterState`
**用途**: 恢复之前保存的标签筛选状态
```swift
// 发送
NotificationCenter.default.post(
    name: NSNotification.Name("restorePreviousTagFilterState"), 
    object: nil
)

// 接收
.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("restorePreviousTagFilterState"))) { _ in
    store.restorePreviousTagFilterState()
}
```

### 窗口管理通知

#### `setupMapWindowMapping`
**用途**: 建立地图窗口与主窗口的映射关系
```swift
// 发送
let sourceInfo = ["sourceWindowId": windowId.uuidString]
NotificationCenter.default.post(
    name: NSNotification.Name("setupMapWindowMapping"), 
    object: sourceInfo
)
```

#### `selectNodeFromCommandClick`
**用途**: 通过Command+点击选择节点
```swift
// 发送
NotificationCenter.default.post(
    name: NSNotification.Name("selectNodeFromCommandClick"),
    object: contentNode // Node类型
)

// 接收 - 支持跨层选择和窗口切换
.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("selectNodeFromCommandClick"))) { notification in
    guard let contentNode = notification.object as? Node else { return }
    
    // 检查是否需要切换层
    if contentNode.layerId != currentLayer?.id {
        if let nodeLayer = layers.first(where: { $0.id == contentNode.layerId }) {
            setCurrentLayer(nodeLayer)
        }
    }
    
    // 选择节点并清除标签筛选
    selectNode(contentNode)
    clearTagFilter()
}
```

## 🪟 多窗口管理契约

### WindowFocusManager 接口
```swift
protocol WindowFocusManagerProtocol {
    // 原子性窗口预留 (防止竞态条件)
    func reserveLayerGraphWindow(for mainWindowId: String) -> Bool
    
    // 窗口焦点状态检查
    func shouldHandleNotification(for windowId: UUID, isGlobalCommand: Bool, commandName: String?) -> Bool
    
    // 强制刷新窗口状态
    func forceRefreshWindowState()
    
    // 调试信息获取
    func getDebugInfo() -> [String: Any]
}
```

### 窗口类型标识符
| 窗口类型 | 标识符 | 描述 |
|----------|--------|------|
| 主界面 | `main` | ContentView主窗口 |
| 独立窗口 | `layerView` | IndependentWindow |
| 层图谱 | `layerGraph` | LayerGraphWindowView |
| 地图 | `map` | MapWindow |
| 节点图谱 | `graph` | UniversalRelationshipGraphView |
| 节点管理 | `nodeManager` | NodeManagerView |

## 🔄 事件处理流程

### Command+T 处理流程
```
1. 用户按下 Command+T
2. 全局菜单拦截 (优先级最高)
3. 发送 clearTagFilterFromKeyboard 通知
4. 主窗口和独立窗口同时监听
5. 各窗口执行 store.clearTagFilter()
6. UI状态同步更新
```

### 层图谱窗口打开流程
```
1. 用户触发 Command+K 或点击按钮
2. 发送 executeOpenWindow 通知 (object: "layerGraph")
3. 目标窗口检查源窗口ID匹配
4. 调用 WindowFocusManager.reserveLayerGraphWindow()
5. 如果返回 true，执行 openWindow(id: "layerGraph")
6. 如果返回 false，忽略请求 (防止重复)
```

### 跨窗口节点选择流程
```
1. 用户在图谱中 Command+点击节点
2. 发送 selectNodeFromCommandClick 通知
3. 接收窗口检查节点所属层
4. 如需要，切换到节点所属层
5. 选择节点并清除标签筛选状态
6. UI更新完成
```

## ⚠️ 错误处理和容错

### 通知处理错误恢复
```swift
.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("clearTagFilterFromKeyboard"))) { _ in
    do {
        // 使用延迟确保脱离视图更新周期
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
            store.clearTagFilter()
        }
    } catch {
        print("❌ 标签筛选清除失败: \\(error)")
        // 错误恢复逻辑
    }
}
```

### 窗口管理错误处理
```swift
// 检查窗口管理器状态
guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true) else {
    print("🚫 窗口焦点检查失败，忽略通知")
    return
}

// 原子性操作失败处理
if windowType == "layerGraph" {
    if !WindowFocusManager.shared.reserveLayerGraphWindow(for: windowId.uuidString) {
        print("⚠️ 层图谱窗口已存在，忽略重复请求")
        return
    }
}
```

### 命令冷却期机制
```swift
private var commandCooldowns: [String: Date] = [:]
private let cooldownPeriod: TimeInterval = 0.5

private func shouldExecuteCommand(_ commandName: String) -> Bool {
    let now = Date()
    if let lastExecution = commandCooldowns[commandName] {
        let timeSinceLastExecution = now.timeIntervalSince(lastExecution)
        if timeSinceLastExecution < cooldownPeriod {
            return false // 仍在冷却期内
        }
    }
    commandCooldowns[commandName] = now
    return true
}
```

## 🧪 测试和验证

### 单元测试契约
```swift
func testKeyboardEventContract() {
    // 测试通知发送和接收
    let expectation = XCTestExpectation(description: "clearTagFilterFromKeyboard")
    
    let observer = NotificationCenter.default.addObserver(
        forName: NSNotification.Name("clearTagFilterFromKeyboard"),
        object: nil,
        queue: .main
    ) { _ in
        expectation.fulfill()
    }
    
    // 触发通知
    NotificationCenter.default.post(name: NSNotification.Name("clearTagFilterFromKeyboard"), object: nil)
    
    wait(for: [expectation], timeout: 1.0)
    NotificationCenter.default.removeObserver(observer)
}
```

### 集成测试场景
1. **多窗口键盘事件**: 确保Command+T在所有窗口类型中工作
2. **竞态条件防护**: 快速连续打开层图谱窗口
3. **跨层节点选择**: Command+点击不同层的节点
4. **错误恢复**: 网络中断时的通知处理
5. **状态同步**: 标签筛选状态的跨窗口同步

## 📝 变更日志

### v2.0.0 (2025-09-07)
- ✅ 修复主窗口Command+T不响应问题
- ✅ 统一键盘事件处理机制 (全局菜单 + 通知)
- ✅ 添加WindowFocusManager原子性操作
- ✅ 实现层图谱窗口重复防护
- ✅ 完善跨窗口通信契约

### v1.9.0 (2024-12-xx)
- ✅ 初始键盘事件处理
- ✅ 基础NotificationCenter通知系统
- ✅ 多窗口支持框架

---

此契约文档确保WordTagger应用中键盘事件和通知系统的一致性、可靠性和可维护性。所有相关组件都必须遵循这些契约规范。