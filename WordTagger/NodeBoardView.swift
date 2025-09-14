import SwiftUI
import AppKit

// MARK: - 节点看板视图

struct NodeBoardView: View {
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""           // 节点搜索
    @State private var layerSearchText = ""      // 层级搜索
    @State private var boardSelectedNodeIds: Set<UUID> = []  // 看板内部的选中状态
    @State private var boardSelectedLayerIds: Set<UUID> = [] // 看板内部的选中层级
    
    init() {
        // 默认初始化器
    }
    
    private var filteredNodes: [Node] {
        var nodes = store.nodes
        
        // 1. 先应用层级搜索筛选
        if !layerSearchText.isEmpty {
            let matchingLayers = store.layers.filter { layer in
                layer.displayName.localizedCaseInsensitiveContains(layerSearchText) ||
                layer.name.localizedCaseInsensitiveContains(layerSearchText)
            }
            let matchingLayerIds = Set(matchingLayers.map { $0.id })
            nodes = nodes.filter { matchingLayerIds.contains($0.layerId) }
        }
        
        // 2. 再应用节点搜索筛选
        if !searchText.isEmpty {
            nodes = nodes.filter { node in
                node.text.localizedCaseInsensitiveContains(searchText) ||
                node.meaning?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        
        return nodes.sorted { $0.text < $1.text }
    }
    
    // 按层级分组的节点
    private var nodesByLayer: [(layer: Layer, nodes: [Node])] {
        let groupedNodes = Dictionary(grouping: filteredNodes) { node in
            node.layerId
        }
        
        // 🔍 智能显示逻辑：根据搜索状态决定显示哪些层级
        if layerSearchText.isEmpty && searchText.isEmpty {
            // 无搜索：显示所有层（包括空层）
            return store.layers.map { layer in
                let nodes = groupedNodes[layer.id] ?? []
                return (layer: layer, nodes: nodes.sorted { $0.text < $1.text })
            }.sorted { $0.layer.displayName < $1.layer.displayName }
        } else {
            // 有搜索：只显示有内容的层级
            return store.layers.compactMap { layer in
                let nodes = groupedNodes[layer.id] ?? []
                // 只有当层级有节点时才显示
                if !nodes.isEmpty {
                    return (layer: layer, nodes: nodes.sorted { $0.text < $1.text })
                }
                return nil
            }.sorted { $0.layer.displayName < $1.layer.displayName }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // 双搜索栏 - 一行布局
            VStack(spacing: 8) {
                // 搜索框一行排列
                HStack(spacing: 12) {
                    // 层级搜索栏
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundColor(.blue)
                            .font(.system(size: 16))
                        
                        TextField("搜索层级...", text: $layerSearchText)
                            .font(.system(size: 16))
                            .textFieldStyle(.plain)
                            .frame(height: 36)
                            .padding(.horizontal, 12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(layerSearchText.isEmpty ? Color.gray.opacity(0.3) : Color.blue.opacity(0.8), lineWidth: 1.5)
                            )
                            .cornerRadius(8)
                        
                        if !layerSearchText.isEmpty {
                            Button("×") {
                                layerSearchText = ""
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                            .font(.system(size: 16, weight: .medium))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // 分隔线
                    Divider()
                        .frame(height: 20)
                    
                    // 节点搜索栏  
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.green)
                            .font(.system(size: 16))
                        
                        TextField("搜索节点...", text: $searchText)
                            .font(.system(size: 16))
                            .textFieldStyle(.plain)
                            .frame(height: 36)
                            .padding(.horizontal, 12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(searchText.isEmpty ? Color.gray.opacity(0.3) : Color.green.opacity(0.8), lineWidth: 1.5)
                            )
                            .cornerRadius(8)
                        
                        if !searchText.isEmpty {
                            Button("×") {
                                searchText = ""
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.green)
                            .font(.system(size: 16, weight: .medium))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // 清除所有按钮
                    if !layerSearchText.isEmpty || !searchText.isEmpty {
                        Button("全部清除") {
                            layerSearchText = ""
                            searchText = ""
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    }
                }
                
                // 搜索状态显示
                if !layerSearchText.isEmpty || !searchText.isEmpty {
                    HStack(spacing: 8) {
                        if !layerSearchText.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 10))
                                Text("\(layerSearchText)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.blue)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                        }
                        
                        if !searchText.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 10))
                                Text("\(searchText)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                    .transition(.opacity)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 按层级分组的节点列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(nodesByLayer, id: \.layer.id) { layerGroup in
                        VStack(alignment: .leading, spacing: 12) {
                            // 层级标题 - 支持点击选择
                            LayerSectionHeader(
                                layer: layerGroup.layer, 
                                nodeCount: layerGroup.nodes.count,
                                isSelected: boardSelectedLayerIds.contains(layerGroup.layer.id),
                                onLayerTapped: { event in
                                    handleLayerSelection(layer: layerGroup.layer, nodes: layerGroup.nodes, commandPressed: event.modifierFlags.contains(.command))
                                }
                            )
                            
                            // 节点网格
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ], spacing: 12) {
                                ForEach(layerGroup.nodes, id: \.id) { node in
                                    CompactNodeCard(
                                        node: node, 
                                        layer: layerGroup.layer,
                                        isSelected: boardSelectedNodeIds.contains(node.id),
                                        onNodeTapped: { event in
                                            handleNodeSelection(node: node, commandPressed: event.modifierFlags.contains(.command))
                                        }
                                    )
                                }
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .stroke(
                                    boardSelectedLayerIds.contains(layerGroup.layer.id) 
                                        ? Color.blue.opacity(0.5)
                                        : Color.gray.opacity(0.2), 
                                    lineWidth: boardSelectedLayerIds.contains(layerGroup.layer.id) ? 2 : 1
                                )
                        )
                    }
                    
                    if nodesByLayer.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            
                            Text("没有找到匹配的节点")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            
                            if !boardSelectedNodeIds.isEmpty || !boardSelectedLayerIds.isEmpty {
                                Text("当前筛选条件下没有节点")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding()
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear {
            // 节点看板永远显示所有数据，清空所有筛选状态
            boardSelectedNodeIds.removeAll() // 不应用任何节点筛选
            boardSelectedLayerIds.removeAll() // 不应用任何层级筛选
            searchText = "" // 清空节点搜索
            layerSearchText = "" // 清空层级搜索
        }
    }
    
    // MARK: - 选择处理函数
    
    private func handleLayerSelection(layer: Layer, nodes: [Node], commandPressed: Bool) {
        let layerId = layer.id
        let nodeIds = Set(nodes.map { $0.id })
        
        if commandPressed {
            // Command+点击：多选层级
            if boardSelectedLayerIds.contains(layerId) {
                // 取消选择该层级和其所有节点
                boardSelectedLayerIds.remove(layerId)
                boardSelectedNodeIds.subtract(nodeIds)
                print("🔄 取消选择层级: \(layer.displayName) (\(nodes.count)个节点)")
            } else {
                // 添加选择该层级和其所有节点
                boardSelectedLayerIds.insert(layerId)
                boardSelectedNodeIds.formUnion(nodeIds)
                print("✅ 多选添加层级: \(layer.displayName) (\(nodes.count)个节点)")
            }
        } else {
            // 普通点击：单选层级
            boardSelectedLayerIds.removeAll()
            boardSelectedNodeIds.removeAll()
            boardSelectedLayerIds.insert(layerId)
            boardSelectedNodeIds.formUnion(nodeIds)
            print("🎯 单选层级: \(layer.displayName) (\(nodes.count)个节点)")
        }
        
        // 通知主应用选择状态变化
        notifySelectionChange()
    }
    
    private func handleNodeSelection(node: Node, commandPressed: Bool) {
        let nodeId = node.id
        
        if commandPressed {
            // Command+点击：多选节点
            if boardSelectedNodeIds.contains(nodeId) {
                boardSelectedNodeIds.remove(nodeId)
                print("🔄 取消选择节点: \(node.text)")
            } else {
                boardSelectedNodeIds.insert(nodeId)
                print("✅ 多选添加节点: \(node.text)")
            }
        } else {
            // 普通点击：单选节点并选中主应用中的节点
            store.selectNode(node)
            boardSelectedNodeIds.removeAll()
            boardSelectedNodeIds.insert(nodeId)
            print("🎯 单选节点: \(node.text)")
        }
        
        // 通知主应用选择状态变化
        notifySelectionChange()
    }
    
    private func notifySelectionChange() {
        print("📤 节点看板选择状态变化:")
        print("   - 选中节点: \(boardSelectedNodeIds.count) 个")
        print("   - 选中层级: \(boardSelectedLayerIds.count) 个")
        
        print("📤 [节点看板] 发送全局选择变化通知")
        // 向后兼容：发送通知给主界面的GraphView更新选择状态
        NotificationCenter.default.post(
            name: Notification.Name("NodeBoardSelectionChanged"),
            object: nil,
            userInfo: [
                "selectedNodeIds": Array(boardSelectedNodeIds),
                "selectedLayerIds": Array(boardSelectedLayerIds)
            ]
        )
    }
}

// MARK: - 层级分组标题
struct LayerSectionHeader: View {
    let layer: Layer
    let nodeCount: Int
    let isSelected: Bool
    let onLayerTapped: (NSEvent) -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            // 选中状态指示器
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundColor(isSelected ? .blue : .secondary)
            
            // 层级颜色指示器
            Circle()
                .fill(Color.from(layer.color))
                .frame(width: 16, height: 16)
                .shadow(radius: 1)
            
            Text(layer.displayName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isSelected ? .blue : .primary)
            
            Text("(\(nodeCount))")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            
            if layer.isCompound {
                Image(systemName: "square.stack.3d.up")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            // 由于无法直接获取NSEvent，我们创建一个模拟事件
            let currentEvent = NSApp.currentEvent ?? NSEvent()
            onLayerTapped(currentEvent)
        }
    }
}

// MARK: - 紧凑节点卡片
struct CompactNodeCard: View {
    let node: Node
    let layer: Layer
    let isSelected: Bool
    let onNodeTapped: (NSEvent) -> Void
    @EnvironmentObject private var store: NodeStore
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 节点名称和选中状态
            HStack {
                Text(node.text)
                    .font(.system(size: 16, weight: .medium))  // 增大字体从13到16
                    .foregroundColor(isSelected ? .blue : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                // 选中状态指示器
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))  // 增大图标
                        .foregroundColor(.blue)
                }
            }
            
            // 节点含义
            if let meaning = node.meaning {
                Text(meaning)
                    .font(.system(size: 14))  // 增大字体从12到14
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            
            // 显示主要标签
            if !node.tags.isEmpty {
                let displayTags = Array(node.tags.prefix(3))  // 显示前3个标签
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 4) {
                    ForEach(displayTags.indices, id: \.self) { index in
                        let tag = displayTags[index]
                        HStack(spacing: 2) {
                            Text(tag.type.displayName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.blue)
                                .lineLimit(1)
                            Text(tag.value)
                                .font(.system(size: 11))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
                }
            }
            
            Spacer()
            
            // 底部信息栏
            HStack {
                // 标签总数指示器
                if !node.tags.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .font(.system(size: 12))  // 增大图标
                            .foregroundColor(.blue)
                        Text("\(node.tags.count)")
                            .font(.system(size: 12))  // 增大字体从10到12
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // 节点类型指示器
                if node.isCompound {
                    HStack(spacing: 2) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 12))  // 增大图标
                            .foregroundColor(.purple)
                        Text("复合")
                            .font(.system(size: 11))
                            .foregroundColor(.purple)
                    }
                }
            }
        }
        .padding(14)  // 增大内边距
        .frame(minHeight: 140, maxHeight: 160)  // 增大卡片高度
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.blue.opacity(0.1) : (isHovered ? Color.blue.opacity(0.05) : Color(NSColor.controlBackgroundColor)))
                .stroke(
                    isSelected ? Color.blue : (isHovered ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2)),
                    lineWidth: isSelected ? 2 : (isHovered ? 1.5 : 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            let currentEvent = NSApp.currentEvent ?? NSEvent()
            onNodeTapped(currentEvent)
        }
        .help(buildTooltipWithSelection())
    }
    
    private func buildTooltipWithSelection() -> String {
        var tooltip = node.text
        if let meaning = node.meaning {
            tooltip += "\n\n\(meaning)"
        }
        tooltip += "\n\n层级: \(layer.displayName)"
        if !node.tags.isEmpty {
            tooltip += "\n标签数量: \(node.tags.count)"
        }
        tooltip += "\n\n点击选择节点 • ⌘+点击多选"
        if isSelected {
            tooltip += "\n✅ 当前已选中"
        }
        return tooltip
    }
}