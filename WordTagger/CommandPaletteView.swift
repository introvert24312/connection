import SwiftUI
import CoreLocation
import MapKit

struct CommandPaletteView: View {
    @EnvironmentObject private var store: NodeStore
    @Binding var isPresented: Bool
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @StateObject private var commandParser = CommandParser.shared
    @FocusState private var isTextFieldFocused: Bool
    @State private var shouldDismiss: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack {
                // 只显示命令按钮，移除图谱选项
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "command")
                        Text("命令")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.blue)
                    )
                    .foregroundColor(.white)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                
                Spacer()
                
                // 当前层信息
                if let currentLayer = store.currentLayer {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        Text(currentLayer.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 内容区域 - 直接显示命令视图内容
            HStack(spacing: 0) {
                    // 左侧：命令列表
                    VStack(spacing: 0) {
                        // 搜索输入框
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            
                            TextField("输入层名称...", text: $query, onCommit: {
                                    print("🔍 TextField onCommit 被触发")
                                    if isTextFieldFocused {
                                        executeSelectedCommand()
                                    }
                                })
                                .font(.title2)
                                .focused($isTextFieldFocused)
                                .onKeyPress(.upArrow) {
                                    selectedIndex = max(0, selectedIndex - 1)
                                    return .handled
                                }
                                .onKeyPress(.downArrow) {
                                    selectedIndex = min(availableCommands.count - 1, selectedIndex + 1)
                                    return .handled
                                }
                                .onKeyPress(.escape) {
                                    isTextFieldFocused = false
                                    shouldDismiss = true
                                    return .handled
                                }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(NSColor.textBackgroundColor))
                        
                        Divider()
                        
                        // 命令列表
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(availableCommands.enumerated()), id: \.offset) { index, command in
                                    NewCommandRowView(
                                        command: command,
                                        isSelected: index == selectedIndex
                                    ) {
                                        executeCommand(command)
                                    }
                                    .id(index)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .frame(minHeight: 400, maxHeight: .infinity)
                        
                        if availableCommands.isEmpty && !query.isEmpty {
                            VStack {
                                Text("未找到匹配的命令")
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 20)
                            }
                            .frame(maxHeight: 60)
                        }
                    }
                    .frame(width: 300)
                    
                    Divider()
                    
                    // 右侧：层关系图谱
                    VStack(spacing: 0) {
                        // 图谱标题
                        HStack {
                            Text("层结构图谱")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            Text("\(store.layers.count) 个层")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                        
                        Divider()
                        
                        // 层关系图谱
                        LayerStructureGraphView()
                            .environmentObject(store)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // 阻止点击事件穿透到父视图
                                print("🔍 LayerStructureGraphView容器被点击，阻止事件穿透")
                            }
                    }
                    .frame(minWidth: 500, maxWidth: .infinity)
                    .background(Color.clear)
                    .allowsHitTesting(true) // 确保可以接收点击事件
                    .onTapGesture {
                        // 右侧面板的点击事件处理
                        print("🔍 右侧面板被点击")
                    }
                }
        }
        .frame(minWidth: 900, idealWidth: 1200, maxWidth: min(NSScreen.main?.frame.width ?? 1440 * 0.9, 1400), minHeight: 600, idealHeight: 800, maxHeight: min(NSScreen.main?.frame.height ?? 900 * 0.8, 900))
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .onAppear {
            // 重置状态
            query = ""
            selectedIndex = 0
            updateAvailableCommands()
            
            // 立即聚焦到输入框
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
        .onChange(of: query) { _, newQuery in
            updateAvailableCommands()
            selectedIndex = 0
        }
        .background(
            Button("") {
                createNewLayer()
            }
            .keyboardShortcut("r", modifiers: .command)
            .hidden()
        )
        .onChange(of: shouldDismiss) { _, newValue in
            if newValue {
                print("🚨 CommandPaletteView: 延迟关闭面板")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPresented = false
                    shouldDismiss = false
                }
            }
        }
        .onChange(of: isPresented) { oldValue, newValue in
            if !newValue && !shouldDismiss {
                print("🚨 CommandPaletteView: isPresented changed from \(oldValue) to \(newValue)")
                print("🚨 Stack trace:")
                Thread.callStackSymbols.forEach { print("  \($0)") }
            }
        }
    }
    
    @State private var availableCommands: [Command] = []
    
    @MainActor
    private func updateAvailableCommands() {
        let context = CommandContext(
            store: store,
            currentNode: store.selectedNode,
            selectedTag: store.selectedTag
        )
        
        Task {
            availableCommands = await commandParser.parse(query, context: context)
        }
    }
    
    private func executeSelectedCommand() {
        guard !availableCommands.isEmpty, selectedIndex < availableCommands.count else { return }
        let command = availableCommands[selectedIndex]
        executeCommand(command)
    }
    
    private func executeCommand(_ command: Command) {
        print("🎯 CommandPaletteView: 执行命令 - \(command.title)")
        print("   命令类型: \(type(of: command))")
        print("   命令分类: \(command.category)")
        
        let context = CommandContext(
            store: store,
            currentNode: store.selectedNode,
            selectedTag: store.selectedTag
        )
        
        Task {
            do {
                let result = try await command.execute(with: context)
                await MainActor.run {
                    handleCommandResult(result)
                    
                    // 针对层切换操作使用快速关闭动画
                    if case .layerSwitched(_) = result {
                        print("🎯 CommandPaletteView: 层切换命令执行完成，准备关闭面板")
                        // 立即移除焦点，避免蓝框残留
                        isTextFieldFocused = false
                        withAnimation(.linear(duration: 0.05)) {
                            isPresented = false
                        }
                    } else {
                        // 其他命令使用正常关闭
                        isTextFieldFocused = false
                        isPresented = false
                    }
                }
            } catch {
                await MainActor.run {
                    // Handle error
                    print("Command execution error: \(error)")
                    isTextFieldFocused = false
                    isPresented = false
                }
            }
        }
    }
    
    private func handleCommandResult(_ result: CommandResult) {
        switch result {
        case .success(let message):
            print("Success: \(message)")
        case .nodeCreated(let node):
            store.selectNode(node)
        case .nodeSelected(let node):
            store.selectNode(node)
        case .tagAdded(_, let node):
            store.selectNode(node)
        case .searchPerformed(_):
            // Search results are already handled by the store
            break
        case .navigationRequested(let destination):
            handleNavigation(destination)
        case .layerSwitched(let layer):
            print("已切换到层: \(layer.displayName)")
        case .error(let message):
            print("Error: \(message)")
        }
    }
    
    private func handleNavigation(_ destination: NavigationDestination) {
        switch destination {
        case .map:
            NotificationCenter.default.post(name: .openMapWindow, object: nil)
        case .graph:
            NotificationCenter.default.post(name: .openGraphWindow, object: nil)
        case .settings:
            // Handle settings navigation - could open settings window
            break
        case .node(let id):
            if let node = store.nodes.first(where: { $0.id == id }) {
                store.selectNode(node)
            }
        }
    }
    
    private func createNewLayer() {
        guard !query.isEmpty else { return }
        
        let tokens = query.split(separator: " ").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        
        if tokens.count >= 2 {
            // 检测复合层创建语法: "层C 层A 层B"
            let compoundLayerName = tokens[0]
            let childLayerNames = Array(tokens[1...])
            
            print("🎯 CommandPalette: 检测到复合层创建 - 复合层: \(compoundLayerName), 子层: \(childLayerNames)")
            
            // 创建复合层命令并执行
            let compoundCommand = CreateCompoundLayerCommand(
                compoundLayerName: compoundLayerName, 
                childLayerNames: childLayerNames
            )
            
            let context = CommandContext(
                store: store,
                currentNode: store.selectedNode,
                selectedTag: store.selectedTag
            )
            
            Task {
                do {
                    let result = try await compoundCommand.execute(with: context)
                    await MainActor.run {
                        handleCommandResult(result)
                        // 复合层创建完成后关闭面板
                        isTextFieldFocused = false
                        withAnimation(.linear(duration: 0.05)) {
                            isPresented = false
                        }
                    }
                } catch {
                    await MainActor.run {
                        print("复合层创建失败: \(error)")
                        // 即使失败也关闭面板
                        isTextFieldFocused = false
                        isPresented = false
                    }
                }
            }
        } else {
            // 单个层名，创建普通层
            let layerName = tokens[0]
            
            // 检查是否已存在同名层
            let existingLayer = store.layers.first { 
                $0.name.lowercased() == layerName.lowercased() || 
                $0.displayName.lowercased() == layerName.lowercased() 
            }
            
            if existingLayer == nil {
                // 创建新层
                let newLayer = store.createLayer(name: layerName.lowercased(), displayName: layerName)
                
                // 切换到新层
                Task {
                    await store.switchToLayer(newLayer)
                    await MainActor.run {
                        print("已创建并切换到新层: \(newLayer.displayName)")
                        // 新建层完成后移除焦点并使用快速关闭动画
                        isTextFieldFocused = false
                        withAnimation(.linear(duration: 0.05)) {
                            isPresented = false
                        }
                    }
                }
            } else {
                print("层 '\(layerName)' 已存在")
                // 如果层已存在，切换到现有层
                Task {
                    await store.switchToLayer(existingLayer!)
                    await MainActor.run {
                        print("已切换到现有层: \(existingLayer!.displayName)")
                        isTextFieldFocused = false
                        withAnimation(.linear(duration: 0.05)) {
                            isPresented = false
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 新命令行视图

private struct NewCommandRowView: View {
    let command: Command
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: command.icon)
                    .font(.title2)
                    .foregroundColor(iconColor)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(command.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(command.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Category badge
                Text(command.category.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(iconColor.opacity(0.2))
                    )
                    .foregroundColor(iconColor)
                
                if isSelected {
                    Image(systemName: "return")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.15) : Color.clear)
        )
    }
    
    private var iconColor: Color {
        switch command.category {
        case .node: return .green
        case .tag: return .orange
        case .search: return .blue
        case .navigation: return .red
        case .system: return .gray
        case .layer: return .purple
        }
    }
}

// MARK: - 通知扩展

extension Notification.Name {
    static let openMapWindow = Notification.Name("openMapWindow")
    static let openGraphWindow = Notification.Name("openGraphWindow")
    static let addNewNode = Notification.Name("addNewNode")
    static let focusSearch = Notification.Name("focusSearch")
}


// MARK: - 层图谱视图

struct LayerGraphView: View {
    @EnvironmentObject private var store: NodeStore
    @State private var selectedLayerIds: Set<UUID> = []
    @State private var cachedNodes: [NodeGraphNode] = []
    @State private var cachedEdges: [NodeGraphEdge] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // 层选择器
            HStack {
                Text("层图谱")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // 快速选择按钮
                HStack(spacing: 8) {
                    Button("当前层") {
                        if let currentLayer = store.currentLayer {
                            selectedLayerIds = [currentLayer.id]
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("全部层") {
                        selectedLayerIds = Set(store.layers.map { $0.id })
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("清空") {
                        selectedLayerIds.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // 层列表
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.sortedLayers) { layer in
                        LayerToggleButton(
                            layer: layer,
                            isSelected: selectedLayerIds.contains(layer.id)
                        ) {
                            toggleLayer(layer)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 40)
            
            Divider()
            
            // 图谱内容
            if cachedNodes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "circle.hexagonpath")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
                    Text("选择层来显示图谱")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Text("使用上方按钮选择要显示的层")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                UniversalRelationshipGraphView(
                    nodes: cachedNodes,
                    edges: cachedEdges,
                    title: "层图谱",
                    initialScale: 0.8,
                    onNodeSelected: { nodeId in
                        // 当点击节点时，选择对应的节点
                        if let selectedGraphNode = cachedNodes.first(where: { $0.id == nodeId }),
                           let selectedNode = selectedGraphNode.node {
                            store.selectNode(selectedNode)
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            // 默认显示当前层
            if let currentLayer = store.currentLayer {
                selectedLayerIds = [currentLayer.id]
            }
            updateGraphData()
        }
        .onChange(of: selectedLayerIds) { _, _ in
            updateGraphData()
        }
        .onChange(of: store.nodes) { _, _ in
            updateGraphData()
        }
        .onChange(of: store.layers) { _, _ in
            updateGraphData()
        }
    }
    
    private func toggleLayer(_ layer: Layer) {
        if selectedLayerIds.contains(layer.id) {
            selectedLayerIds.remove(layer.id)
        } else {
            selectedLayerIds.insert(layer.id)
        }
    }
    
    private func updateGraphData() {
        let data = calculateLayerGraphData()
        cachedNodes = data.nodes
        cachedEdges = data.edges
    }
    
    private func calculateLayerGraphData() -> (nodes: [NodeGraphNode], edges: [NodeGraphEdge]) {
        var nodes: [NodeGraphNode] = []
        var edges: [NodeGraphEdge] = []
        var addedTagKeys: Set<String> = []
        var addedNodeIds: Set<UUID> = []
        
        // 获取选中层的节点（包括复合层的子层节点）
        var allSelectedNodes: [Node] = []
        
        for layerId in selectedLayerIds {
            if let layer = store.layers.first(where: { $0.id == layerId }) {
                if layer.isCompound {
                    // 如果是复合层，获取所有子层的节点
                    let compoundNodes = store.getNodesInCompoundLayer(layer)
                    allSelectedNodes.append(contentsOf: compoundNodes)
                } else {
                    // 如果是普通层，获取该层的节点
                    let layerNodes = store.nodes.filter { $0.layerId == layerId }
                    allSelectedNodes.append(contentsOf: layerNodes)
                }
            }
        }
        
        // 去重（避免同一个节点被多次添加）
        let uniqueNodes = Array(Set(allSelectedNodes))
        
        // 添加节点
        for node in uniqueNodes {
            nodes.append(NodeGraphNode(node: node))
            addedNodeIds.insert(node.id)
            
            // 如果是复合节点，递归添加其子节点结构
            if node.isCompound {
                addChildNodesForLayerGraph(
                    for: node,
                    nodes: &nodes,
                    addedTagKeys: &addedTagKeys,
                    addedNodeIds: &addedNodeIds,
                    depth: 1
                )
            }
        }
        
        // 添加标签节点
        let allAddedNodes = nodes.compactMap { $0.node }
        for node in allAddedNodes {
            for tag in node.tags {
                // 过滤掉复合节点的内部管理标签
                if case .custom(let key) = tag.type {
                    if key == "compound" || 
                       key == "child" ||
                       key.hasSuffix("复合节点") ||
                       key.hasSuffix("compound") {
                        continue
                    }
                }
                
                let tagKey = "\(tag.type.rawValue):\(tag.value)"
                if !addedTagKeys.contains(tagKey) {
                    nodes.append(NodeGraphNode(tag: tag))
                    addedTagKeys.insert(tagKey)
                }
            }
            
            // 添加位置标签
            for locationTag in node.locationTags {
                let locationTagKey = "\(locationTag.type.rawValue):\(locationTag.value)"
                if !addedTagKeys.contains(locationTagKey) {
                    nodes.append(NodeGraphNode(tag: locationTag))
                    addedTagKeys.insert(locationTagKey)
                }
            }
        }
        
        // 创建边
        for node in allAddedNodes {
            guard let nodeGraphNode = nodes.first(where: { $0.node?.id == node.id }) else { continue }
            
            // 如果是复合节点，创建到子节点的连接
            if node.isCompound {
                let childReferenceTags = node.tags.filter {
                    if case .custom(let key) = $0.type, key == "child" {
                        return true
                    }
                    return false
                }
                
                for childRefTag in childReferenceTags {
                    let childNodeName = childRefTag.value
                    if let childNodeGraphNode = nodes.first(where: { 
                        $0.node?.text.lowercased() == childNodeName.lowercased() 
                    }) {
                        edges.append(NodeGraphEdge(
                            from: nodeGraphNode,
                            to: childNodeGraphNode,
                            relationshipType: "子节点"
                        ))
                    }
                }
            }
            
            // 创建节点到标签的连接
            for tag in node.tags {
                // 过滤掉复合节点的内部管理标签
                if case .custom(let key) = tag.type {
                    if key == "compound" || 
                       key == "child" ||
                       key.hasSuffix("复合节点") ||
                       key.hasSuffix("compound") {
                        continue
                    }
                }
                
                if let tagNode = nodes.first(where: { 
                    $0.tag?.type.rawValue == tag.type.rawValue && $0.tag?.value == tag.value 
                }) {
                    edges.append(NodeGraphEdge(
                        from: nodeGraphNode,
                        to: tagNode,
                        relationshipType: tag.type.displayName
                    ))
                }
            }
            
            // 创建节点到位置标签的连接
            for locationTag in node.locationTags {
                if let tagNode = nodes.first(where: { 
                    $0.tag?.type.rawValue == locationTag.type.rawValue && $0.tag?.value == locationTag.value 
                }) {
                    edges.append(NodeGraphEdge(
                        from: nodeGraphNode,
                        to: tagNode,
                        relationshipType: locationTag.type.displayName
                    ))
                }
            }
        }
        
        return (nodes: nodes, edges: edges)
    }
    
    // 递归添加复合节点的子节点结构
    private func addChildNodesForLayerGraph(
        for node: Node, 
        nodes: inout [NodeGraphNode], 
        addedTagKeys: inout Set<String>, 
        addedNodeIds: inout Set<UUID>,
        depth: Int
    ) {
        // 防止无限递归
        guard depth <= 10 else { return }
        
        // 查找子节点引用标签
        let childReferenceTags = node.tags.filter {
            if case .custom(let key) = $0.type, key == "child" {
                return true
            }
            return false
        }
        
        for childRefTag in childReferenceTags {
            let childNodeName = childRefTag.value
            
            // 从store中查找实际的子节点
            if let childNode = store.nodes.first(where: { $0.text.lowercased() == childNodeName.lowercased() }) {
                // 如果子节点还没被添加，则添加它
                if !addedNodeIds.contains(childNode.id) {
                    nodes.append(NodeGraphNode(node: childNode))
                    addedNodeIds.insert(childNode.id)
                    
                    // 如果子节点也是复合节点，递归添加其子节点
                    if childNode.isCompound {
                        addChildNodesForLayerGraph(
                            for: childNode, 
                            nodes: &nodes, 
                            addedTagKeys: &addedTagKeys, 
                            addedNodeIds: &addedNodeIds,
                            depth: depth + 1
                        )
                    }
                }
            }
        }
    }
}

// MARK: - 层结构图谱视图

struct LayerStructureGraphView: View {
    @EnvironmentObject private var store: NodeStore
    @AppStorage("layerStructureGraphInitialScale") private var layerStructureGraphInitialScale: Double = 0.9
    @State private var cachedNodes: [LayerGraphNode] = []
    @State private var cachedEdges: [LayerGraphEdge] = []
    @State private var selectedLayerId: UUID?
    @State private var hoveredLayerId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部信息栏
            if let selectedLayerId = selectedLayerId,
               let selectedLayer = store.layers.first(where: { $0.id == selectedLayerId }) {
                HStack {
                    Text("选中层: \(selectedLayer.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("切换到此层") {
                        print("🔍 LayerStructureGraphView: 切换层按钮被点击")
                        Task {
                            await store.switchToLayer(selectedLayer)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
            }
            
            if cachedNodes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
                    Text("暂无层数据")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                UniversalRelationshipGraphView(
                    nodes: cachedNodes,
                    edges: cachedEdges,
                    title: "层结构图谱",
                    initialScale: layerStructureGraphInitialScale,
                    onNodeSelected: { nodeId in
                        // 当点击层节点时，直接切换到该层，使整个节点区域都可点击
                        print("🔍 LayerStructureGraphView: 层节点被点击, nodeId = \(nodeId)")
                        if let selectedGraphNode = cachedNodes.first(where: { $0.id == nodeId }),
                           let layerId = selectedGraphNode.layerId,
                           let targetLayer = store.layers.first(where: { $0.id == layerId }) {
                            print("🔍 LayerStructureGraphView: 找到层ID = \(layerId)，直接切换到层: \(targetLayer.displayName)")
                            selectedLayerId = layerId
                            Task {
                                await store.switchToLayer(targetLayer)
                            }
                        }
                    },
                    onNodeDeselected: {
                        // 点击空白处取消选中
                        selectedLayerId = nil
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            updateLayerGraphData()
            // 默认选中当前层
            selectedLayerId = store.currentLayer?.id
        }
        .onChange(of: store.layers) { _, _ in
            updateLayerGraphData()
        }
        .onChange(of: selectedLayerId) { _, _ in
            updateLayerGraphData()
        }
    }
    
    private func updateLayerGraphData() {
        let data = calculateLayerGraphData()
        cachedNodes = data.nodes
        cachedEdges = data.edges
    }
    
    private func calculateLayerGraphData() -> (nodes: [LayerGraphNode], edges: [LayerGraphEdge]) {
        var nodes: [LayerGraphNode] = []
        var edges: [LayerGraphEdge] = []
        
        // 添加所有层作为节点
        for layer in store.layers {
            let nodeCount = store.nodes.filter { $0.layerId == layer.id }.count
            let isSelected = layer.id == selectedLayerId
            nodes.append(LayerGraphNode(layer: layer, nodeCount: nodeCount, isSelected: isSelected, allLayers: store.layers))
        }
        
        // 创建复合层到子层的连接
        for layer in store.layers {
            if layer.isCompound {
                guard let parentNode = nodes.first(where: { $0.layerId == layer.id }) else { continue }
                
                for childLayerId in layer.childLayerIds {
                    if let childNode = nodes.first(where: { $0.layerId == childLayerId }) {
                        edges.append(LayerGraphEdge(
                            from: parentNode,
                            to: childNode,
                            relationshipType: "包含"
                        ))
                    }
                }
            }
        }
        
        return (nodes: nodes, edges: edges)
    }
}

// MARK: - 层图谱数据模型

struct LayerGraphNode: UniversalGraphNode {
    let id: Int
    let label: String
    let subtitle: String?
    let layerId: UUID?
    let layer: Layer?
    let nodeCount: Int
    let isCompound: Bool
    let isSelected: Bool
    
    init(layer: Layer, nodeCount: Int, isSelected: Bool = false, allLayers: [Layer] = []) {
        self.id = GraphNodeIDGenerator.shared.idForLayer(layer)
        self.label = layer.displayName
        self.layerId = layer.id
        self.layer = layer
        self.nodeCount = nodeCount
        self.isCompound = layer.isCompound
        self.isSelected = isSelected
        
        // 为复合层提供更详细的子层信息
        if self.isCompound && !layer.childLayerIds.isEmpty {
            // 从传入的层列表中获取子层名称
            let childLayerNames = allLayers
                .filter { childLayer in layer.childLayerIds.contains(childLayer.id) }
                .map { $0.displayName }
                .prefix(3) // 最多显示3个子层名称
            
            if childLayerNames.count > 0 {
                let namesText = Array(childLayerNames).joined(separator: "、")
                let moreText = layer.childLayerIds.count > 3 ? "等\(layer.childLayerIds.count)层" : ""
                self.subtitle = "包含: \(namesText)\(moreText)"
            } else {
                self.subtitle = "复合层 (\(layer.childLayerIds.count)个子层)"
            }
        } else if self.isCompound {
            self.subtitle = "复合层 (空)"
        } else {
            self.subtitle = "\(nodeCount) 个节点"
        }
    }
}

struct LayerGraphEdge: UniversalGraphEdge {
    let fromId: Int
    let toId: Int
    let label: String?
    
    init(from: LayerGraphNode, to: LayerGraphNode, relationshipType: String) {
        self.fromId = from.id
        self.toId = to.id
        self.label = relationshipType
    }
}

// MARK: - GraphNodeIDGenerator 扩展

extension GraphNodeIDGenerator {
    func idForLayer(_ layer: Layer) -> Int {
        let layerKey = "layer:\(layer.id.uuidString)"
        lock.lock()
        defer { lock.unlock() }
        
        if let existingID = tagIDMap[layerKey] {
            return existingID
        }
        
        currentID += 1
        tagIDMap[layerKey] = currentID
        return currentID
    }
}

// MARK: - 层切换按钮

struct LayerToggleButton: View {
    let layer: Layer
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                // 层类型指示器
                if layer.isCompound {
                    Image(systemName: "square.stack.3d.up")
                        .font(.caption2)
                        .foregroundColor(layerColor)
                } else {
                    Circle()
                        .fill(layerColor)
                        .frame(width: 8, height: 8)
                }
                
                Text(layer.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                // 复合层子层数量指示
                if layer.isCompound && !layer.childLayerIds.isEmpty {
                    Text("(\(layer.childLayerIds.count))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected ? Color.blue.opacity(0.2) : 
                        (layer.isCompound ? Color.purple.opacity(0.15) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                isSelected ? Color.blue : 
                                (layer.isCompound ? Color.purple : Color.secondary.opacity(0.3)), 
                                lineWidth: layer.isCompound ? 2 : 1
                            )
                    )
            )
            .foregroundColor(
                isSelected ? .blue : 
                (layer.isCompound ? .purple : .primary)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var layerColor: Color {
        switch layer.color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        default: return .blue
        }
    }
}

#Preview {
    CommandPaletteView(isPresented: .constant(true))
        .environmentObject(NodeStore.shared)
}
