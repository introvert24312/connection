# 修复总结 - 独立窗口通知路由问题

## 修复的问题

### 1. Command+P 位置选择器在独立窗口失效

**问题根源**:
- 独立窗口的 QuickAddSheetView 发送 `openMapWindow` 通知
- 主窗口和独立窗口都接收到同一个通知
- 主窗口先处理通知，导致地图窗口被错误映射到主窗口

**修复方案**:
1. 在 `openMapForLocationSelection()` 中发送带源窗口信息的通知
2. 更新主窗口和独立窗口的通知处理逻辑，只处理匹配的源窗口通知
3. MapWindow 直接从 `openMapWindow` 通知中获取源窗口信息

**修改的文件**:
- `WordTaggerApp.swift`: QuickAddSheetView 的 `openMapForLocationSelection()` 方法
- `WordTaggerApp.swift`: 主窗口和独立窗口的 `openMapWindow` 通知处理逻辑
- `MapWindow.swift`: 添加从通知中直接获取源窗口信息的逻辑

### 2. 地图点击后精确定位失败

**问题根源**:
- MapContainer 传递 Node 和 Layer 对象
- 独立窗口有独立的 store 实例，传递的对象在目标 store 中不存在
- `expandLocationTagAndSelect` 无法找到对应的节点

**修复方案**:
1. MapContainer 传递节点ID和层ID而不是对象
2. 目标窗口从自己的 store 实例中查找对应的节点和层
3. 确保跨 store 实例的数据一致性

**修改的文件**:
- `MapContainer.swift`: 修改通知传递格式，使用 ID 而不是对象
- `WordTaggerApp.swift`: 更新主窗口和独立窗口的 `handleMapPinTap` 通知处理逻辑

## 技术细节

### 通知路由修复
```swift
// 修复前：发送无源窗口信息的通知
NotificationCenter.default.post(name: NSNotification.Name("openMapWindow"), object: nil)

// 修复后：发送带源窗口信息的通知
let sourceWindowId = store.isSharedInstance ? "MAIN_WINDOW" : WindowFocusManager.shared.getActiveWindowId()?.uuidString ?? "UNKNOWN_WINDOW"
NotificationCenter.default.post(
    name: NSNotification.Name("openMapWindow"), 
    object: ["sourceWindowId": sourceWindowId]
)
```

### 跨Store实例数据传递修复
```swift
// 修复前：传递对象（会导致跨store实例问题）
let userInfo: [String: Any] = [
    "targetNode": node,
    "targetLayer": targetLayer
]

// 修复后：传递ID，在目标窗口查找对应对象
let userInfo: [String: Any] = [
    "targetNodeId": node.id.uuidString,
    "targetLayerId": targetLayer.id.uuidString,
    "targetNodeText": node.text,
    "targetLayerName": targetLayer.displayName
]
```

## 预期效果

1. **Command+P 在独立窗口正常工作**:
   - 独立窗口按 Command+I 打开快速添加
   - 在输入框中按 Command+P 正确打开地图
   - 地图窗口正确映射到独立窗口

2. **地图点击精确定位正常工作**:
   - 点击地图标注后正确切换到目标层
   - 正确展开地点标签类型
   - 正确选中具体的地点标签值和节点

## 测试建议

### 测试 Command+P 功能
1. 打开主窗口 → Command+I → Command+P (应该正常工作)
2. 打开独立窗口 → Command+I → Command+P (现在应该也正常工作)

### 测试地图点击定位功能
1. 主窗口：点击地图标注 → 检查是否精确定位到节点
2. 独立窗口：点击地图标注 → 检查是否精确定位到节点

## 关键改进

1. **窗口通知路由系统**: 通过源窗口ID确保通知被正确的窗口处理
2. **跨Store实例数据传递**: 使用ID而不是对象引用，避免实例不匹配问题
3. **向后兼容性**: 保留原有的全局命令逻辑作为回退机制