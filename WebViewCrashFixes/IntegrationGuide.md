# WebView闪退问题修复 - 集成指南

## 🎯 集成步骤

### 1. 替换现有组件

#### 替换 DetailPanel
```swift
// 在使用 DetailPanel 的地方，替换为：
StableDetailPanel(node: selectedNode)
    .environmentObject(store)
```

#### 替换 VditorWebView  
```swift
// 将 VditorWebView 替换为：
EnhancedVditorWebView(
    markdown: markdownText,
    nodeId: node.id.uuidString,
    onChange: { newValue in
        handleContentChange(newValue)
    },
    coordinatorBinding: $vditorCoordinator
)
```

#### 升级 NodeStore
```swift
// 如果需要更好的状态管理，可以选择性使用：
@StateObject private var enhancedStore = EnhancedNodeStore()

// 或者继续使用原有 NodeStore，新组件会兼容
```

### 2. 添加健康监控

```swift
// 在开发模式下启用监控
#if DEBUG
import SwiftUI

struct ContentView: View {
    @State private var showHealthPanel = false
    
    var body: some View {
        YourMainView()
        .toolbar {
            ToolbarItem {
                Button("监控") {
                    showHealthPanel.toggle()
                }
            }
        }
        .sheet(isPresented: $showHealthPanel) {
            WebViewHealthPanel()
                .frame(minWidth: 600, minHeight: 400)
        }
    }
}
#endif
```

### 3. 配置监控（可选）

```swift
// 在 App 启动时
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // 仅在调试模式下启用监控
        Task { @MainActor in
            WebViewHealthMonitor.shared.startMonitoring()
        }
        #endif
    }
}
```

## 🔧 配置选项

### WebViewUpdateManager 配置
```swift
// 调整更新频率
let updateManager = WebViewUpdateManager()
// 默认最小间隔为 500ms，可以根据需要调整
```

### 内容保护级别
```swift
// 在 EnhancedVditorWebView.swift 中调整保护阈值：
// 第100-110行的 shouldUpdateContent 方法
```

## 🚨 故障排除

### 常见问题

#### 1. WebView 仍然闪退
**检查项：**
- 确认已替换所有相关组件
- 查看控制台是否有内存警告
- 检查是否有递归调用

**解决方案：**
```swift
// 启用详细日志
#if DEBUG
print("🔄 WebView更新: \(详细信息)")
#endif
```

#### 2. 内容更新延迟
**原因：** 防抖机制生效
**调整：**
```swift
// 在 WebViewUpdateManager 中调整间隔
private let minimumUpdateInterval: TimeInterval = 0.3 // 减少到300ms
```

#### 3. 内存使用增高
**监控：** 使用 WebViewHealthPanel 观察内存趋势
**优化：**
```swift
// 定期清理WebView
if memoryUsage > threshold {
    // 重建WebView实例
    webViewGeneration = UUID()
}
```

## 📊 性能优化建议

### 1. 开发阶段
- 启用健康监控面板
- 定期检查内存使用情况  
- 监控WebView创建/销毁频率

### 2. 生产环境
- 禁用调试日志
- 使用轻量级错误收集
- 定期检查崩溃报告

### 3. 内容管理
- 避免频繁的小幅内容更改
- 使用批量更新机制
- 实施合理的防抖策略

## 🔍 调试技巧

### 1. 启用详细日志
```swift
#if DEBUG
let enableVerboseLogging = true
#else
let enableVerboseLogging = false
#endif
```

### 2. 监控状态变化
```swift
// 添加状态变化监听
store.$selectedNode
    .sink { newNode in
        print("🔄 节点变化: \(newNode?.text ?? "nil")")
    }
    .store(in: &cancellables)
```

### 3. WebView生命周期跟踪
```swift
// 在 Coordinator 中添加
override init() {
    super.init()
    print("🟢 WebView Coordinator 创建")
}

deinit {
    print("🔴 WebView Coordinator 销毁")
}
```

## ⚠️ 注意事项

### 1. 向后兼容性
- 新组件完全兼容现有API
- 可以渐进式替换
- 不会影响现有数据

### 2. 性能影响
- 健康监控有轻微性能开销
- 生产环境建议禁用详细监控
- 内存使用会略有增加（用于状态缓存）

### 3. 测试建议
- 在不同节点类型上测试
- 验证长时间运行稳定性
- 测试快速切换场景

## 🎉 预期改进

实施这些修复后，您应该看到：

✅ **WebView闪退大幅减少**  
✅ **内容更新更加稳定**  
✅ **性能监控可见性提升**  
✅ **开发调试体验改善**  
✅ **长期运行稳定性提高**

---

## 📞 支持

如果在集成过程中遇到问题：

1. 检查控制台日志中的错误信息
2. 使用健康监控面板观察指标
3. 确认所有依赖组件已正确替换
4. 验证WebView创建/销毁频率是否合理

这套解决方案经过精心设计，采用现代Swift并发模式和企业级稳定性保护机制，应该能显著改善WordTagger应用的WebView稳定性。