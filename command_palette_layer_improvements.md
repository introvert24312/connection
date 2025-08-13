# 命令面板层管理改进

## 改进内容

### ✅ 1. 复合层显示子层信息
**复合层现在会显示其包含的子层**

#### 显示格式
- 普通层：`英语节点`
- 复合层：`语言学 (英语节点, 法语节点, 德语节点)`

#### 悬停提示
- 普通层：`普通层: 英语节点`
- 复合层：`复合层: 语言学\n包含子层: 英语节点, 法语节点, 德语节点`

### ✅ 2. 键盘快捷键层过滤
**在搜索框中输入层名，使用快捷键操作层过滤器**

#### ⌘J - 添加层到过滤器
```
1. 在搜索框输入层名（如："英语"）
2. 按 ⌘J
3. 匹配的层会被添加到图谱过滤器中
4. 如果是复合层，其子层也会同时添加
```

#### ⌘⇧J - 从过滤器移除层
```
1. 在搜索框输入层名（如："英语"）
2. 按 ⌘⇧J
3. 匹配的层会从图谱过滤器中移除
4. 如果是复合层，其子层也会同时移除
```

### ✅ 3. 移除层切换命令
**清理了命令列表，移除了所有层切换相关的命令**

#### 移除的命令类型
- `统计学 - 切换到统计学学科层`
- `教育心理学 - 切换到教育心理学学科层`
- 所有类似的层切换命令

#### 保留的命令类型
- 添加节点
- 搜索节点
- 添加标签
- 导航命令（地图、图谱）

### ✅ 4. 修复焦点残留问题
**解决了关闭命令面板时搜索框蓝色边框残留的问题**

#### 修复机制
```swift
private func dismissView() {
    // 清除搜索框焦点，防止残留蓝色边框
    isTextFieldFocused = false
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        isPresented = false
        shouldDismiss = false
    }
}
```

## 技术实现

### 复合层子层显示
```swift
// 获取复合层的子层名称
private var childLayerNames: [String] {
    guard layer.isCompound else { return [] }
    return layer.childLayerIds.compactMap { childId in
        store.layers.first(where: { $0.id == childId })?.displayName
    }
}

// 生成显示文本
private var displayText: String {
    if layer.isCompound && !childLayerNames.isEmpty {
        let childText = childLayerNames.joined(separator: ", ")
        return "\(layer.displayName) (\(childText))"
    } else {
        return layer.displayName
    }
}
```

### 键盘快捷键处理
```swift
.onKeyPress(.init("j"), phases: .down) { keyPress in
    if keyPress.modifiers.contains(.command) {
        if keyPress.modifiers.contains(.shift) {
            // ⌘⇧J: 从过滤器中移除层
            handleRemoveLayerFromFilter()
        } else {
            // ⌘J: 添加层到过滤器
            handleAddLayerToFilter()
        }
        return .handled
    }
    return .ignored
}
```

### 智能层匹配
```swift
// 查找匹配的层
let matchingLayers = store.layers.filter { layer in
    layer.displayName.lowercased().contains(trimmedQuery) ||
    layer.name.lowercased().contains(trimmedQuery)
}

// 如果是复合层，也处理其子层
if firstMatch.isCompound {
    for childLayerId in firstMatch.childLayerIds {
        filteredLayerIds.insert(childLayerId)
        // 记录操作日志
    }
}
```

### 命令清理
```swift
public func getDefaultCommands(context: CommandContext? = nil) async -> [Command] {
    // 移除所有层切换命令，只返回基本的节点和标签操作命令
    return [
        AddNodeCommand(),
        SearchNodesCommand(),
        AddTagCommand(nodeId: UUID()),
        NavigationCommand(destination: .map),
        NavigationCommand(destination: .graph)
    ]
}
```

## 用户体验改进

### 更清晰的层信息
- 复合层现在显示其包含的子层，用户一眼就能看到层的结构
- 悬停提示提供了详细的层信息

### 高效的层管理
- 通过键盘快捷键快速添加/移除层过滤器
- 支持模糊匹配，输入部分层名即可操作
- 复合层操作会自动处理其子层

### 简洁的命令界面
- 移除了冗余的层切换命令
- 命令列表更加专注于核心功能
- 减少了界面混乱

### 完善的视觉反馈
- 解决了焦点残留问题
- 操作有清晰的控制台日志反馈
- 层过滤器状态实时更新

## 使用示例

### 添加复合层到过滤器
```
1. 打开命令面板 (⌘K)
2. 输入 "语言" (匹配复合层"语言学")
3. 按 ⌘J
4. "语言学"及其所有子层都会被添加到图谱过滤器
5. 层标签会显示为 "语言学 (英语节点, 法语节点, 德语节点)"
```

### 移除特定层
```
1. 在搜索框输入 "英语"
2. 按 ⌘⇧J
3. "英语节点"层会从过滤器中移除
4. 图谱会实时更新，不再显示该层的内容
```

这些改进让层管理更加直观和高效，用户可以通过简单的键盘操作快速管理图谱中显示的层，同时获得更清晰的层结构信息。