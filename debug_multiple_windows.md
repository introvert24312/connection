# Debug: 独立窗口Command+P打开多个地图窗口问题

## 问题描述
在独立窗口中使用Command+P时，出现了5个地图窗口同时打开的问题。

## 可能原因分析

### 1. 多个openWindow调用点
```swift
// ContentView.swift 中有2个调用点:
openWindow(id: "map")  // line 164
openWindow(id: "map")  // line 320

// WordTaggerApp.swift 中有3个调用点:
openWindow(id: "map")  // line 3707 (独立窗口focusedSceneValue)
openWindow(id: "map")  // line 3980 (独立窗口executeOpenMapWindow处理器)
openWindow(id: "map")  // line 3992 (独立窗口executeOpenMapWindow处理器备用)
```

### 2. 通知链路过复杂
当前通知流程:
1. Command+P → `openMapForLocationSelection()`
2. 发送 `requestMapForLocationSelection` 通知
3. 独立窗口处理，发送 `executeOpenMapWindow` 通知
4. 独立窗口的 `executeOpenMapWindow` 处理器响应
5. 可能还有其他路径同时响应

### 3. 重复的通知监听器
独立窗口可能同时监听了多个相关通知，导致重复处理。

## 修复策略

### 方案1: 简化通知链
直接在独立窗口的 `requestMapForLocationSelection` 处理器中调用 `openWindow`，
而不是再发送 `executeOpenMapWindow` 通知。

### 方案2: 防重复机制
添加防重复打开的标志，确保短时间内不会重复打开地图窗口。

### 方案3: 统一通知处理
清理重复的通知监听器，确保每个通知只有一个处理器。

## 下一步
1. 先尝试方案1，简化通知链
2. 如果不行，实施方案2的防重复机制