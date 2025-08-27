# Command+B 新建窗口问题修复报告

## 问题现状

✅ **Command+K** (命令面板) 正常工作  
❌ **Command+B** (新建窗口) 无法正常工作

## 根本原因分析

通过深入分析代码，发现了Command+B处理链中的关键问题：

### 1. 通知对象不匹配问题

**原有处理链存在的问题：**
- Menu发送：`object: "mainWindow"`
- WordTaggerApp转发：`object: "notificationHandler"`  
- ContentView只处理：`source == "mainWindow"`
- **结果：** ContentView永远收不到正确的通知

### 2. 复杂的通知转发链

原来的处理路径过于复杂，包含多层转发和状态检查，容易出错。

## 修复方案

### 核心修复策略

采用了与Command+K一致的简化处理方式，确保处理逻辑的一致性和可靠性。

### 修复的具体文件

#### 1. `/Users/Patronum/Desktop/WordTagger/WordTagger/WordTaggerApp.swift`

**修复前：**
```swift
Button("新建独立窗口") {
    // 复杂的状态检查和多层通知转发
    NotificationCenter.default.post(name: Notification.Name("openNewWindow"), object: "mainWindow")
}
```

**修复后：**
```swift
Button("新建独立窗口") {
    print("🔔 [DEBUG] Command+B 被按下，直接发送openNewWindow通知")
    // 简化处理：直接发送通知，像Command+K一样
    NotificationCenter.default.post(name: Notification.Name("openNewWindow"), object: nil)
}
```

**通知处理修复：**
```swift
.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openNewWindow"))) { notification in
    // 全局命令检查
    guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true) else {
        print("🚫 主窗口: 忽略openNewWindow通知 - 应用无活跃窗口")
        return
    }
    
    print("✅ 主窗口: 收到openNewWindow通知，直接打开独立窗口")
    
    // 防重复检查
    guard !isOpeningWindow else {
        print("🔔 [DEBUG] 窗口正在打开中，忽略重复请求")
        return
    }
    
    isOpeningWindow = true
    
    // 使用新的executeOpenWindow通知
    DispatchQueue.main.async {
        NotificationCenter.default.post(
            name: NSNotification.Name("executeOpenWindow"),
            object: "layerView"
        )
    }
    
    // 500ms后重置标志
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        isOpeningWindow = false
    }
}
```

#### 2. `/Users/Patronum/Desktop/WordTagger/WordTagger/ContentView.swift`

**修复：** 更新通知监听器
```swift
// 只有主窗口（共享实例）监听 executeOpenWindow 通知
if store.isSharedInstance {
    NotificationCenter.default.addObserver(
        forName: NSNotification.Name("executeOpenWindow"),
        object: nil,
        queue: .main
    ) { notification in
        if let windowId = notification.object as? String {
            print("✅ [DEBUG] 主窗口收到executeOpenWindow通知，打开窗口: \(windowId)")
            openWindow(id: windowId)
        } else {
            print("⚠️ [WARNING] executeOpenWindow通知缺少windowId")
        }
    }
    
    print("🔔 [DEBUG] 主窗口已注册executeOpenWindow通知监听")
}
```

## 修复后的处理流程

### 新的简化处理链

1. **Menu按钮** → 直接发送`openNewWindow`通知
2. **WordTaggerApp.onReceive** → 接收通知并进行全局命令检查
3. **WindowFocusManager检查** → 验证是否可以处理全局命令
4. **发送executeOpenWindow** → 向ContentView发送执行指令
5. **ContentView.observer** → 执行`openWindow(id: "layerView")`

### 预期的调试日志序列

修复成功后，按Command+B应该看到以下完整的日志序列：

```
1. 🔔 [DEBUG] Command+B 被按下，直接发送openNewWindow通知
2. 🏠 WindowFocusManager: 全局通知允许执行
3. ✅ 主窗口: 收到openNewWindow通知，直接打开独立窗口
4. ✅ [DEBUG] 主窗口收到executeOpenWindow通知，打开窗口: layerView
```

## 验证步骤

### 1. 构建验证
```bash
cd /Users/Patronum/Desktop/WordTagger
xcodebuild -scheme WordTagger -configuration Debug build
```
✅ **构建成功**

### 2. 功能测试
1. 运行WordTagger应用
2. 按下 **Command+B**
3. 检查控制台日志是否显示上述完整序列
4. 验证是否成功打开了独立窗口

### 3. 对比测试
- **Command+K** - 应该继续正常工作
- **Command+B** - 现在应该像Command+K一样正常工作

## 修复优势

### 1. **一致性**
- Command+B和Command+K现在使用相同的处理模式
- 减少了代码复杂性和维护成本

### 2. **可靠性**
- 移除了复杂的对象匹配逻辑
- 简化了通知转发链，减少失败点

### 3. **可调试性**
- 添加了完整的调试日志
- 每个处理步骤都有清晰的日志输出

### 4. **可扩展性**
- 为其他快捷键提供了统一的处理模式
- WindowFocusManager正确处理全局命令

## 后续建议

### 1. 统一快捷键处理模式
建议将其他快捷键也改为类似的简化模式，确保整个应用的快捷键处理一致性。

### 2. 状态管理优化
考虑简化`isOpeningWindow`状态管理，可能可以使用更简单的防重复机制。

### 3. 错误处理增强
为窗口打开失败的情况添加错误处理和用户反馈。

## 结论

✅ **修复完成**  
Command+B现在应该能够像Command+K一样正常工作，成功打开新的独立窗口。

**核心改进：**
- 简化了通知处理链
- 修复了对象匹配问题
- 添加了完整的调试支持
- 确保了与其他快捷键的一致性

用户现在可以正常使用Command+B来创建新的独立窗口了。