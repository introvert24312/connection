import SwiftUI
import AppKit

// MARK: - 节点看板视图

struct NodeBoardView: View {
    // 🆕 支持关联数据管理器的初始化器
    private let associatedDataManager: NodeGraphDataManager?
    
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""           // 节点搜索
    @State private var layerSearchText = ""      // 层级搜索文本显示
    @State private var boardSelectedNodeIds: Set<UUID> = []  // 看板内部的选中状态
    @State private var boardSelectedLayerIds: Set<UUID> = [] // 看板内部的选中层级
    @State private var showingLayerSelector = false  // 是否显示层级选择器
    @State private var selectedLayers: Set<String> = []  // 选中的层级名称
    
    // 🆕 支持关联数据管理器的初始化器
    init(associatedDataManager: NodeGraphDataManager? = nil) {
        self.associatedDataManager = associatedDataManager
    }
    
    // 🆕 向后兼容的初始化器
    init(selectedNodeIds: Set<UUID>, selectedLayerIds: Set<UUID>) {
        self.associatedDataManager = nil
        // 忽略传入的参数，因为节点看板现在显示所有数据
    }
    
    private var filteredNodes: [Node] {
        var nodes = store.nodes
        
        // 1. 先应用层级筛选（基于选中的层级）
        if !selectedLayers.isEmpty {
            let matchingLayers = store.layers.filter { layer in
                selectedLayers.contains(layer.displayName) || selectedLayers.contains(layer.name)
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
        
        // 层级选择仅用于标记状态，不影响节点显示
        
        return nodes.sorted { $0.text < $1.text }
    }
    
    // 按层级分组的节点
    private var nodesByLayer: [(layer: Layer, nodes: [Node])] {
        let groupedNodes = Dictionary(grouping: filteredNodes) { node in
            node.layerId
        }
        
        // 🔍 智能显示逻辑：根据筛选状态决定显示哪些层级
        let layersToShow: [Layer]
        if !selectedLayers.isEmpty {
            // 如果有选中的层级，只显示选中的层级
            layersToShow = store.layers.filter { layer in
                selectedLayers.contains(layer.displayName) || selectedLayers.contains(layer.name)
            }
        } else {
            // 没有选中层级时显示所有层级
            layersToShow = store.layers
        }
        
        if selectedLayers.isEmpty && searchText.isEmpty {
            // 无筛选：显示所有层（包括空层）
            return layersToShow.map { layer in
                let nodes = groupedNodes[layer.id] ?? []
                return (layer: layer, nodes: nodes.sorted { $0.text < $1.text })
            }.sorted { $0.layer.displayName < $1.layer.displayName }
        } else {
            // 有筛选：只显示有内容的层级
            return layersToShow.compactMap { layer in
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
            // 标题栏
            HStack {
                Text("节点看板")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // 选中状态显示
                HStack(spacing: 12) {
                    if !boardSelectedNodeIds.isEmpty {
                        Text("\(boardSelectedNodeIds.count) 个节点已选中")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                    
                    if !boardSelectedLayerIds.isEmpty {
                        Text("\(boardSelectedLayerIds.count) 个层级已选中")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    }
                    
                    Text("\(filteredNodes.count) 个节点")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                // 清除选择按钮
                if !boardSelectedNodeIds.isEmpty || !boardSelectedLayerIds.isEmpty {
                    Button("清除选择") {
                        boardSelectedNodeIds.removeAll()
                        boardSelectedLayerIds.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 双搜索栏 - 一行布局
            VStack(spacing: 8) {
                // 搜索框一行排列
                HStack(spacing: 12) {
                    // 层级选择器（仿照标签看板）
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundColor(.blue)
                            .font(.system(size: 14))
                        
                        TextField("搜索层级...", text: $layerSearchText, onEditingChanged: { isEditing in
                            if isEditing {
                                showingLayerSelector = true
                            }
                        })
                            .textFieldStyle(.roundedBorder)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(layerSearchText.isEmpty ? Color.clear : Color.blue.opacity(0.5), lineWidth: 1)
                            )
                        
                        if !selectedLayers.isEmpty {
                            Button("×") {
                                selectedLayers.removeAll()
                                layerSearchText = ""
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                            .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // 分隔线
                    Divider()
                        .frame(height: 20)
                    
                    // 节点搜索栏  
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                        
                        TextField("搜索节点...", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(searchText.isEmpty ? Color.clear : Color.green.opacity(0.5), lineWidth: 1)
                            )
                        
                        if !searchText.isEmpty {
                            Button("×") {
                                searchText = ""
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.green)
                            .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // 清除所有按钮
                    if !selectedLayers.isEmpty || !searchText.isEmpty {
                        Button("全部清除") {
                            selectedLayers.removeAll()
                            layerSearchText = ""
                            searchText = ""
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    }
                }
                
                // 搜索状态显示
                if !selectedLayers.isEmpty || !searchText.isEmpty {
                    HStack(spacing: 8) {
                        if !selectedLayers.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 10))
                                Text(selectedLayers.count == 1 ? selectedLayers.first! : "\(selectedLayers.count) 个层级")
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
            
            // 节点列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                    if nodesByLayer.isEmpty {
                        EmptyNodeBoardView()
                            .frame(maxWidth: .infinity, minHeight: 400)
                    } else {
                        ForEach(nodesByLayer, id: \.layer.id) { layerGroup in
                            Section {
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 12) {
                                    ForEach(layerGroup.nodes) { node in
                                        NodeCard(
                                            node: node,
                                            layer: layerGroup.layer,
                                            isSelected: boardSelectedNodeIds.contains(node.id),
                                            onNodeTapped: { event in
                                                handleNodeSelection(node: node, event: event)
                                            }
                                        )
                                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.bottom)
                            } header: {
                                NodeBoardLayerHeader(
                                    layer: layerGroup.layer,
                                    nodeCount: layerGroup.nodes.count,
                                    isSelected: boardSelectedLayerIds.contains(layerGroup.layer.id),
                                    onLayerTapped: { event in
                                        handleLayerSelection(layer: layerGroup.layer, nodes: layerGroup.nodes, event: event)
                                    }
                                )
                            }
                        }
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
            selectedLayers.removeAll() // 清空层级选择
            layerSearchText = ""
        }
        .popover(isPresented: $showingLayerSelector) {
            LayerSelectorPopover(
                selectedLayers: $selectedLayers,
                layerSearchText: $layerSearchText,
                onDismiss: { showingLayerSelector = false }
            )
            .environmentObject(store)
        }
    }
    
    // MARK: - 选择处理函数
    
    private func handleNodeSelection(node: Node, event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            // Command+点击：多选切换
            if boardSelectedNodeIds.contains(node.id) {
                boardSelectedNodeIds.remove(node.id)
            } else {
                boardSelectedNodeIds.insert(node.id)
            }
        } else {
            // 普通点击：单选
            boardSelectedNodeIds = [node.id]
        }
        
        // 🆕 如果有关联的数据管理器，同步选中状态
        if let dataManager = associatedDataManager {
            // NodeGraphDataManager 没有这个方法，暂时注释掉
            // dataManager.handleNodeSelectionFromBoard(selectedNodeIds: boardSelectedNodeIds)
        }
    }
    
    private func handleLayerSelection(layer: Layer, nodes: [Node], event: NSEvent) {
        let nodeIds = Set(nodes.map { $0.id })
        
        if event.modifierFlags.contains(.command) {
            // Command+点击：多选切换
            if boardSelectedLayerIds.contains(layer.id) {
                boardSelectedLayerIds.remove(layer.id)
                // 取消选中该层的所有节点
                boardSelectedNodeIds.subtract(nodeIds)
            } else {
                boardSelectedLayerIds.insert(layer.id)
                // 选中该层的所有节点
                boardSelectedNodeIds.formUnion(nodeIds)
            }
        } else {
            // 普通点击：单选
            boardSelectedLayerIds = [layer.id]
            boardSelectedNodeIds = nodeIds
        }
        
        // 🆕 如果有关联的数据管理器，同步选中状态
        if let dataManager = associatedDataManager {
            // NodeGraphDataManager 没有这个方法，暂时注释掉
            // dataManager.handleNodeSelectionFromBoard(selectedNodeIds: boardSelectedNodeIds)
        }
    }
}

// MARK: - 空状态视图

struct EmptyNodeBoardView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("暂无节点")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Text("尝试调整搜索条件或创建新节点")
                .font(.caption)
                .foregroundColor(Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - 层级标题视图

struct NodeBoardLayerHeader: View {
    let layer: Layer
    let nodeCount: Int
    let isSelected: Bool
    let onLayerTapped: (NSEvent) -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            // 层级颜色指示器
            Circle()
                .fill(Color.from(layer.color))
                .frame(width: 14, height: 14)
                .shadow(radius: 1)
            
            // 层级名称
            Text(layer.displayName)
                .font(.headline)
                .foregroundColor(isSelected ? .blue : .primary)
            
            // 节点数量
            Text("(\(nodeCount))")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // 层级类型指示器
            if layer.isCompound {
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 12))
                        .foregroundColor(.purple)
                    Text("复合层")
                        .font(.caption)
                        .foregroundColor(.purple)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(4)
            }
            
            Spacer()
            
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            let currentEvent = NSApp.currentEvent ?? NSEvent()
            onLayerTapped(currentEvent)
        }
    }
}

// MARK: - 节点卡片视图

struct NodeCard: View {
    let node: Node
    let layer: Layer
    let isSelected: Bool
    let onNodeTapped: (NSEvent) -> Void
    
    @State private var isHovered = false
    @EnvironmentObject private var store: NodeStore
    
    private var formattedText: String {
        guard !node.text.isEmpty else { return "" }
        
        // 首先处理换行符，统一替换为空格
        var processedText = node.text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        
        // 移除多余的空格
        while processedText.contains("  ") {
            processedText = processedText.replacingOccurrences(of: "  ", with: " ")
        }
        
        // 处理长文本：智能截断
        let maxLength = 120
        if processedText.count > maxLength {
            // 找到合适的截断点（单词边界）
            let truncateIndex = processedText.index(processedText.startIndex, offsetBy: maxLength)
            let substring = String(processedText[..<truncateIndex])
            
            // 尝试在最后一个空格处截断
            if let lastSpace = substring.lastIndex(of: " ") {
                return String(processedText[..<lastSpace]) + "..."
            } else {
                return substring + "..."
            }
        }
        
        return processedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 顶部：节点文本
            Text(formattedText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // 含义（如果有）
            if let meaning = node.meaning, !meaning.isEmpty {
                Text(meaning)
                    .font(.system(size: 12))
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

// MARK: - 层级选择器弹出视图

struct LayerSelectorPopover: View {
    @Binding var selectedLayers: Set<String>
    @Binding var layerSearchText: String
    let onDismiss: () -> Void
    @EnvironmentObject private var store: NodeStore
    @State private var searchText = ""
    
    private var filteredLayers: [Layer] {
        if searchText.isEmpty {
            return store.layers.sorted(by: { $0.displayName < $1.displayName })
        }
        return store.layers.filter { layer in
            layer.displayName.localizedCaseInsensitiveContains(searchText) ||
            layer.name.localizedCaseInsensitiveContains(searchText)
        }.sorted(by: { $0.displayName < $1.displayName })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("选择层级（Command+点击多选）")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                
                TextField("搜索层级...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 14))
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 层级列表
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredLayers) { layer in
                        LayerSelectionRow(
                            layer: layer,
                            isSelected: selectedLayers.contains(layer.displayName),
                            onToggle: { isMultiSelect in
                                if isMultiSelect {
                                    // Command+点击：多选
                                    if selectedLayers.contains(layer.displayName) {
                                        selectedLayers.remove(layer.displayName)
                                    } else {
                                        selectedLayers.insert(layer.displayName)
                                    }
                                } else {
                                    // 普通点击：单选
                                    selectedLayers = [layer.displayName]
                                }
                                updateLayerSearchText()
                            }
                        )
                    }
                }
                .padding()
            }
            .frame(maxHeight: 300)
            
            // 底部已选择显示
            if !selectedLayers.isEmpty {
                Divider()
                
                HStack {
                    Text("已选择: ")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(selectedLayers.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Spacer()
                    
                    Button("清除") {
                        selectedLayers.removeAll()
                        layerSearchText = ""
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding()
            }
        }
        .frame(width: 400)
        .onAppear {
            // 如果外部已经有搜索文本，同步到内部
            if !layerSearchText.isEmpty && !layerSearchText.contains("个层级") {
                searchText = layerSearchText
            }
        }
    }
    
    private func updateLayerSearchText() {
        if selectedLayers.count == 1 {
            layerSearchText = selectedLayers.first!
        } else if selectedLayers.count > 1 {
            layerSearchText = "\(selectedLayers.count) 个层级"
        } else {
            layerSearchText = ""
        }
    }
}

// MARK: - 层级选择行

struct LayerSelectionRow: View {
    let layer: Layer
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack {
            // 层级颜色指示器
            Circle()
                .fill(Color.from(layer.color))
                .frame(width: 12, height: 12)
            
            // 层级名称
            Text(layer.displayName)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .blue : .primary)
            
            Spacer()
            
            // 选中状态
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue.opacity(0.1) : (isHovered ? Color.gray.opacity(0.05) : Color.clear))
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture { location in
            // 检查是否按下了 Command 键
            let isMultiSelect = NSEvent.modifierFlags.contains(.command)
            onToggle(isMultiSelect)
        }
    }
}