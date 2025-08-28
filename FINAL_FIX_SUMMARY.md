# 最终修复总结 - 窗口通知路由问题

## 问题诊断

通过日志分析发现了根本问题：
```
📍 QuickAddSheetView: 确定源窗口ID: 220239D9  // 这是主窗口ID，不是独立窗口ID BEF33E1D
🚫 主窗口: 忽略发给其他窗口的openMapWindow通知 - 目标: 220239D9
🚫 独立窗口: 忽略发给其他窗口的openMapWindow通知 - 目标: 220239D9, 当前: BEF33E1D
```

**根本原因**: `WindowFocusManager.shared.getActiveWindowId()` 返回的是全局活跃窗口ID，而不是包含QuickAddSheetView的实际窗口ID。

## 最终修复方案

### 1. 改变通知机制
不再让QuickAddSheetView直接确定窗口ID，而是让它发送请求给父窗口处理：

**QuickAddSheetView变更**:
```swift
// 修复前：尝试自己确定窗口ID（会出错）
let sourceWindowId = store.isSharedInstance ? "MAIN_WINDOW" : WindowFocusManager.shared.getActiveWindowId()?.uuidString

// 修复后：发送请求让父窗口处理
NotificationCenter.default.post(
    name: NSNotification.Name("requestMapForLocationSelection"), 
    object: store.isSharedInstance ? "MAIN_WINDOW" : "INDEPENDENT_WINDOW"
)
```

### 2. 父窗口响应机制
主窗口和独立窗口各自处理对应的请求：

**主窗口**:
```swift
.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("requestMapForLocationSelection"))) { notification in
    if let requestSource = notification.object as? String {
        if requestSource == "MAIN_WINDOW" {
            print("📍 主窗口: 处理位置选择请求，打开地图")
            NotificationCenter.default.post(name: NSNotification.Name("executeOpenMapWindow"), object: ["sourceWindowId": "MAIN_WINDOW"])
        } else {
            print("📍 主窗口: 忽略独立窗口的位置选择请求")
        }
    }
}
```

**独立窗口**:
```swift
.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("requestMapForLocationSelection"))) { notification in
    if let requestSource = notification.object as? String {
        if requestSource == "INDEPENDENT_WINDOW" {
            print("📍 独立窗口: 处理位置选择请求，打开地图")
            NotificationCenter.default.post(name: NSNotification.Name("executeOpenMapWindow"), object: ["sourceWindowId": windowId.uuidString])
        } else {
            print("📍 独立窗口: 忽略主窗口的位置选择请求")
        }
    }
}
```

## 技术优势

1. **精确的窗口识别**: 每个窗口明确知道自己应该处理哪些请求
2. **清晰的职责分离**: QuickAddSheetView负责发送请求，父窗口负责窗口管理
3. **可靠的路由机制**: 基于window store类型而不是动态获取的窗口ID

## 预期修复效果

现在测试日志应该显示：

**独立窗口中按Command+P**:
```
📍 QuickAddSheetView: 发送请求让父窗口打开地图
📍 独立窗口: 处理位置选择请求，打开地图
✅ MapWindow: 立即设置窗口映射 - 源窗口: [独立窗口ID]
```

**主窗口中按Command+P**:
```
📍 QuickAddSheetView: 发送请求让父窗口打开地图
📍 主窗口: 处理位置选择请求，打开地图
✅ MapWindow: 立即设置窗口映射 - 源窗口: MAIN_WINDOW
```

## 修改的文件

1. **WordTaggerApp.swift**:
   - QuickAddSheetView的`openMapForLocationSelection()`方法：改为发送`requestMapForLocationSelection`通知
   - 主窗口：添加`requestMapForLocationSelection`通知处理
   - 独立窗口：添加`requestMapForLocationSelection`通知处理

2. **保持不变的修复**:
   - MapContainer.swift：继续使用ID传递而不是对象传递
   - 地图点击处理逻辑：继续从ID查找节点和层

现在Command+P功能应该在两种窗口中都能正常工作了！