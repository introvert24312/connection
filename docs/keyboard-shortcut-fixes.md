# 键盘快捷键修复方案

## 问题描述

Command+F 和 Command+E 在多窗口环境下出现问题：
1. **Command+F (标签搜索)** - 所有窗口都接收到通知，导致全局传播
2. **Command+E (切换侧边栏)** - 被冷却机制卡住，应用失去焦点后无法正常工作

## 解决方案

### 核心思路：模仿 Command+I 的工作原理

经过分析发现 Command+I (addNewNode) 工作正常，因此我们采用相同的架构：
- 使用 SwiftUI 的 FocusedValue 系统
- 避免全局通知广播
- 实现窗口特定的通知过滤

### 修复方法

#### 1. Command+F (标签搜索)

**问题**：直接发送全局通知，所有窗口都响应

**解决方案**：
1. 在菜单中使用 FocusedValue：`openTagSearch?()`
2. 在通知中包含 windowId 信息
3. TagSidebarView 过滤通知，只处理匹配的窗口

**修改文件**：
- `WordTaggerApp.swift` - 菜单项使用 FocusedValue
- `ContentView.swift` - 添加 focusedSceneValue 处理
- `TagSidebarView.swift` - 添加 windowId 参数和通知过滤

#### 2. Command+E (切换侧边栏)

**问题**：被冷却机制卡住，传递了不必要的 `commandName` 参数

**解决方案**：
1. 移除 `commandName: "toggleSidebar"` 参数
2. 对于独立窗口，发送窗口特定的 `executeToggleSidebar` 通知
3. ContentView 过滤通知，只处理匹配的窗口

**修改文件**：
- `WordTaggerApp.swift` - 移除冷却机制参数，添加窗口特定通知
- `ContentView.swift` - 添加 executeToggleSidebar 通知处理和窗口过滤

## 实现细节

### 窗口特定通知模式

```swift
// 发送端
NotificationCenter.default.post(
    name: NSNotification.Name("notificationName"), 
    object: nil,
    userInfo: ["windowId": windowId.uuidString]
)

// 接收端
.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("notificationName"))) { notification in
    if let userInfo = notification.userInfo,
       let targetWindowId = userInfo["windowId"] as? String {
        if targetWindowId == windowId.uuidString {
            // 只有匹配的窗口才处理
            handleNotification()
        }
    }
}
```

### FocusedValue 系统

```swift
// 定义 FocusedValue
extension FocusedValues {
    var commandName: ShowCardAction? {
        get { self[CommandNameKey.self] }
        set { self[CommandNameKey.self] = newValue }
    }
}

// 设置 FocusedValue
.focusedSceneValue(\.commandName, ShowCardAction {
    // 直接在当前窗口执行操作
})

// 菜单中调用
Button("Command") {
    commandName?()
}
```

## 测试验证

修复后的行为：
1. **Command+F** - 只有当前聚焦窗口的标签搜索被触发
2. **Command+E** - 只有当前聚焦窗口的侧边栏被切换
3. 不再有全局传播问题
4. 不再被冷却机制卡住

## 关键学习点

1. **分析正常工作的快捷键**：Command+I 的实现为我们提供了正确的模板
2. **窗口特定通知**：通过 userInfo 传递 windowId 实现精确路由
3. **避免过度工程化**：移除不必要的冷却机制参数
4. **SwiftUI FocusedValue 系统**：是处理跨窗口命令的推荐方式

## 修改文件列表

- `/WordTagger/WordTaggerApp.swift` - 快捷键路由和菜单处理
- `/WordTagger/ContentView.swift` - FocusedValue 处理和通知过滤
- `/WordTagger/TagSidebarView.swift` - 窗口参数和通知过滤

## 提交信息

```
🔧 修复Command+F和Command+E多窗口传播问题

- Command+F: 使用窗口特定通知替代全局广播
- Command+E: 移除冷却机制，使用FocusedValue系统
- 参考Command+I的成功模式实现窗口隔离
- 添加windowId过滤机制防止跨窗口干扰

修复了多窗口环境下快捷键的全局传播和卡住问题
```

这次修复展示了通过分析现有正常工作的组件来解决类似问题的有效方法。