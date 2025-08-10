# 快捷键解决方案实现总结（简化版）

## 问题描述
在DetailPanel中，当焦点在VditorWebView（基于WKWebView）内时，SwiftUI的`onKeyPress`无法响应Command+O/L快捷键，导致无法切换标签页。

## 解决方案

### 1. 两层事件处理机制

#### 层级1：JavaScript拦截（VditorWebView）
```javascript
document.addEventListener('keydown', function(e) {
    if (e.metaKey && (e.key === 'o' || e.key === 'O')) {
        e.preventDefault();
        window.webkit?.messageHandlers?.bridge?.postMessage({ type: 'commandO' });
        return false;
    }
    if (e.metaKey && (e.key === 'l' || e.key === 'L')) {
        e.preventDefault();
        window.webkit?.messageHandlers?.bridge?.postMessage({ type: 'commandL' });
        return false;
    }
}, true);
```

#### 层级2：Swift Coordinator转发
```swift
func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    switch type {
    case "commandO":
        NotificationCenter.default.post(name: NSNotification.Name("switchToDetailTab"), object: nil)
    case "commandL":
        NotificationCenter.default.post(name: NSNotification.Name("switchToGraphTab"), object: nil)
    }
}
```


### 2. DetailPanel优化
- 添加`@FocusState`和`.focusable()`使视图可获得焦点
- 统一处理通知和直接按键事件
- 使用`handleSwitchToDetail()`和`handleSwitchToGraph()`方法集中处理逻辑

## 测试要点

1. **WebView有焦点时**：JavaScript拦截 → Coordinator转发 → DetailPanel响应
2. **DetailPanel有焦点时**：SwiftUI onKeyPress直接响应

## 优势

1. **可靠性**：两层保障机制，WebView内外都能响应
2. **简单性**：不需要额外的全局监听器或焦点管理器
3. **用户体验**：快捷键响应及时
4. **可维护性**：代码简洁，易于理解

## 注意事项

1. 使用`DispatchQueue.main.async`避免在视图更新期间修改状态
2. JavaScript事件拦截要使用`preventDefault()`阻止默认行为
3. 通过NotificationCenter统一处理来自不同源的快捷键事件