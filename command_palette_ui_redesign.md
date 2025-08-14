# 命令面板UI重新设计

## 设计目标

最大化图谱显示空间，简化界面，提供更好的用户体验。

## 主要改进

### ✅ 1. 搜索框移至顶部
**将搜索框从左侧移到UI顶部，节省水平空间**

#### 新的顶部布局
```
┌─────────────────────────────────────────────────────────┐
│ [层管理]     🔍 搜索层名...     当前层: 英语节点        │
├─────────────────────────────────────────────────────────┤
│ 搜索结果: [英语节点✓] [统计学] [语言学(复合)]          │ ← 只在有搜索结果时显示
├─────────────────────────────────────────────────────────┤
│                                                         │
│                    图谱区域                             │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

#### 特点
- **紧凑搜索框**：200px宽度，不占用过多空间
- **实时搜索结果**：只在有结果时展开显示
- **水平滚动**：搜索结果以芯片形式水平排列
- **状态指示**：显示层是否已添加到过滤器（✓标记）

### ✅ 2. 删除左侧区域
**完全移除左侧的层管理说明区域**

#### 移除的内容
- ❌ 层管理说明文字
- ❌ 快捷键帮助信息
- ❌ 详细的搜索结果列表
- ❌ 300px宽度的固定侧边栏

#### 节省的空间
- **水平空间**：节省300px + 分隔线
- **垂直空间**：移除了大量说明文字
- **图谱区域**：现在占用全部可用空间

### ✅ 3. 可折叠的层过滤器
**参考全局图谱设计，将层过滤器做成可折叠的**

#### 折叠状态（默认）
```
┌─────────────────────────────────────────────────────────┐
│ 层结构图谱    已过滤 3/4    [过滤器 ▼]                 │
├─────────────────────────────────────────────────────────┤
│                                                         │
│                    图谱区域                             │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

#### 展开状态
```
┌─────────────────────────────────────────────────────────┐
│ 层结构图谱    已过滤 3/4    [过滤器 ▲]                 │
├─────────────────────────────────────────────────────────┤
│ 🔍搜索层名  [快速选择▼]              [重置]            │
│ [英语节点✓] [统计学] [语言学(复合)✓] [教育心理学]      │
├─────────────────────────────────────────────────────────┤
│                    图谱区域                             │
└─────────────────────────────────────────────────────────┘
```

#### 功能特点
- **默认折叠**：最大化图谱显示空间
- **状态显示**：显示当前过滤状态（已过滤 3/4）
- **动画切换**：平滑的展开/折叠动画
- **快速操作**：展开后提供完整的过滤功能

### ✅ 4. 搜索结果优化
**搜索结果只在有内容时显示，采用紧凑的芯片设计**

#### 搜索结果芯片
```swift
HStack(spacing: 4) {
    Circle()
        .fill(layer.isCompound ? Color.purple : Color.blue)
        .frame(width: 6, height: 6)
    
    Text(layer.displayName)
        .font(.caption)
    
    if layer.isCompound {
        Text("(复合)")
            .font(.caption2)
            .foregroundColor(.secondary)
    }
    
    if filteredLayerIds.contains(layer.id) {
        Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green)
            .font(.caption2)
    }
}
.background(Capsule().fill(isSelected ? Color.green.opacity(0.2) : Color.gray.opacity(0.1)))
```

#### 特点
- **紧凑设计**：芯片式布局，节省空间
- **颜色区分**：蓝点=普通层，紫点=复合层
- **状态指示**：绿色✓表示已添加到过滤器
- **水平滚动**：支持大量搜索结果
- **智能截断**：超过10个结果显示省略号

## 技术实现

### 顶部搜索栏
```swift
VStack(spacing: 0) {
    HStack {
        // 标题标签
        HStack(spacing: 4) {
            Image(systemName: "command")
            Text("层管理")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue))
        .foregroundColor(.white)
        
        Spacer()
        
        // 搜索框
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("搜索层名...", text: $query)
                .font(.body)
                .focused($isTextFieldFocused)
                // 键盘事件处理...
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .frame(width: 200)
        
        // 当前层指示
        if let currentLayer = store.currentLayer {
            HStack(spacing: 4) {
                Circle().fill(Color.blue).frame(width: 8, height: 8)
                Text(currentLayer.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(Color(NSColor.controlBackgroundColor))
    
    // 可折叠的搜索结果
    if !query.isEmpty {
        // 搜索结果展示...
    }
}
```

### 可折叠过滤器
```swift
// 简化的工具栏
HStack {
    Text("层结构图谱")
        .font(.headline)
        .fontWeight(.semibold)
    
    Spacer()
    
    // 过滤状态指示
    if filteredLayerIds.count != store.layers.count {
        Text("已过滤 \(filteredLayerIds.count)/\(store.layers.count)")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    
    // 过滤器切换按钮
    Button(action: {
        withAnimation(.easeInOut(duration: 0.2)) {
            showLayerFilter.toggle()
        }
    }) {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal.decrease.circle")
            Text("过滤器")
            Image(systemName: showLayerFilter ? "chevron.up" : "chevron.down")
        }
    }
}

// 可折叠的过滤器内容
if showLayerFilter {
    // 过滤器控制和层标签...
}
```

### 图谱区域最大化
```swift
// 图谱区域（占用全部剩余空间）
LayerStructureGraphViewSimple(
    filteredLayerIds: $filteredLayerIds,
    isPresented: $isPresented
)
.environmentObject(store)
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

## 用户体验改进

### 空间利用最大化
- **图谱区域**：现在占用90%以上的界面空间
- **紧凑控件**：所有控制元素都采用紧凑设计
- **智能折叠**：非必要元素默认隐藏

### 操作流程优化
1. **搜索层**：在顶部搜索框输入层名
2. **查看结果**：搜索结果自动展开显示
3. **快速操作**：使用⌘J/⌘⇧J添加/移除层
4. **精细控制**：需要时展开过滤器进行详细操作

### 视觉层次清晰
- **顶部**：搜索和基本信息
- **中间**：可选的搜索结果和过滤器
- **主体**：图谱显示区域

### 响应式设计
- **搜索结果**：只在有内容时显示
- **过滤器**：默认折叠，需要时展开
- **状态指示**：实时显示过滤状态

## 对比效果

### 修改前
```
┌─────────────┬─────────────────────────────────┐
│             │ 层结构图谱                      │
│   层管理    ├─────────────────────────────────┤
│   说明区    │ 选中层: XX  [切换到此层]        │
│   (300px)   ├─────────────────────────────────┤
│             │                                 │
│   搜索结果  │           图谱区域              │
│             │                                 │
└─────────────┴─────────────────────────────────┘
```

### 修改后
```
┌─────────────────────────────────────────────────┐
│ [层管理] 🔍搜索框  当前层                       │
├─────────────────────────────────────────────────┤
│ 搜索结果 (可隐藏)                               │
├─────────────────────────────────────────────────┤
│ 层结构图谱  [过滤器▼] (可折叠)                 │
├─────────────────────────────────────────────────┤
│                                                 │
│                图谱区域                         │
│              (最大化显示)                       │
│                                                 │
└─────────────────────────────────────────────────┘
```

这次重新设计大幅提升了图谱的显示空间，同时保持了所有必要的功能，提供了更好的用户体验。