import SwiftUI
import AppKit

struct GraphView: View {
    @EnvironmentObject private var store: NodeStore
    @AppStorage("globalGraphInitialScale") private var globalGraphInitialScale: Double = 1.0
    @AppStorage("globalGraphSelectedNodeIds") private var selectedNodeIdsData: Data = Data()
    @State private var searchQuery: String = ""
    @State private var displayedNodes: [Node] = []
    @State private var cachedNodes: [NodeGraphNode] = []
    @State private var cachedEdges: [NodeGraphEdge] = []
    @State private var showingNodeSelector = false
    @State private var selectedNodeIds: Set<UUID> = []
    
    // 层级筛选状态
    @State private var selectedLayerIds: Set<UUID> = [] // 空集表示显示所有层
    @State private var showingLayerSelector = false
    
    // 预设和看板状态
    @State private var showingPresetManager = false
    @State private var showingSavePresetDialog = false
    @State private var newPresetName = ""
    @State private var newPresetDescription = ""
    
    // 🔒 全局图谱锁定状态 - 锁定后不再接收数据更新
    @State private var isLocked = false
    @State private var lockedNodes: [Node]? // 锁定时保存的节点数据
    
    // 生成所有节点的图谱数据 - 统一计算节点和边
    private func calculateGraphData() -> (nodes: [NodeGraphNode], edges: [NodeGraphEdge]) {
        @AppStorage("enableGraphDebug") var enableGraphDebug: Bool = false
        
        var nodes: [NodeGraphNode] = []
        var edges: [NodeGraphEdge] = []
        var addedTagKeys: Set<String> = []
        
        // 🔒 根据锁定状态选择数据源
        let sourceNodes: [Node]
        if isLocked, let lockedData = lockedNodes {
            sourceNodes = lockedData
        } else {
            sourceNodes = store.nodes
        }
        
        // 首先根据层级筛选进行过滤
        let layerFilteredNodes: [Node]
        if selectedLayerIds.isEmpty {
            // 显示所有层的节点
            layerFilteredNodes = sourceNodes
        } else {
            // 只显示选中层的节点
            layerFilteredNodes = sourceNodes.filter { selectedLayerIds.contains($0.layerId) }
        }
        
        // 根据选择的节点ID和标签筛选来确定要显示的节点
        let nodesToShow: [Node]
        if !selectedNodeIds.isEmpty {
            nodesToShow = layerFilteredNodes.filter { selectedNodeIds.contains($0.id) }
        } else if !displayedNodes.isEmpty {
            // 搜索结果也需要应用层级筛选
            nodesToShow = displayedNodes.filter { selectedLayerIds.isEmpty || selectedLayerIds.contains($0.layerId) }
        } else if let selectedTag = store.selectedTag {
            // 🏷️ 标签筛选逻辑
            if store.showAllTagTypeNodes {
                // 显示该标签类型下的所有节点
                if store.expandedTagTypes.count > 1 {
                    nodesToShow = layerFilteredNodes.filter { node in
                        node.tags.contains { tag in store.expandedTagTypes.contains(tag.type) }
                    }
                } else {
                    nodesToShow = layerFilteredNodes.filter { node in
                        node.tags.contains { $0.type == selectedTag.type }
                    }
                }
            } else {
                // 显示该具体标签的节点
                nodesToShow = layerFilteredNodes.filter { $0.hasTag(selectedTag) }
            }
        } else {
            nodesToShow = layerFilteredNodes
        }
        
        var addedNodeIds: Set<UUID> = []
        
        // 首先添加所有顶级节点
        for node in nodesToShow {
            nodes.append(NodeGraphNode(node: node))
            addedNodeIds.insert(node.id)
            
            // 如果是复合节点，递归添加其子节点结构
            if node.isCompound {
                addChildNodesForGlobalGraph(
                    for: node, 
                    nodes: &nodes, 
                    addedTagKeys: &addedTagKeys, 
                    addedNodeIds: &addedNodeIds,
                    depth: 1
                )
            }
        }
        
        // 添加所有已添加节点的标签（去重），但过滤掉复合节点的管理标签
        let allAddedNodes = nodes.compactMap { $0.node }
        for node in allAddedNodes {
            for tag in node.tags {
                // 过滤掉复合节点的内部管理标签
                if case .custom(let key) = tag.type {
                    // 过滤掉复合节点管理标签
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
        
        // 现在使用同一批节点创建边
        
        #if DEBUG
        if enableGraphDebug {
            print("🔍 调试信息:")
            print("🔹 总节点数: \(nodes.count)")
            print("🔹 节点数: \(nodesToShow.count)")
            print("🔹 节点节点数: \(nodes.filter { $0.node != nil }.count)")
            print("🔹 标签节点数: \(nodes.filter { $0.tag != nil }.count)")
        }
        #endif
        
        // 为所有节点与其标签和子节点创建连接
        let allProcessedNodes = nodes.compactMap { $0.node }
        for node in allProcessedNodes {
            guard let nodeGraphNode = nodes.first(where: { $0.node?.id == node.id }) else { 
                #if DEBUG
                if enableGraphDebug {
                    print("❌ 找不到节点节点: \(node.text)")
                }
                #endif
                continue 
            }
            
            #if DEBUG
            if enableGraphDebug {
                print("🔹 处理节点: \(node.text), 标签数: \(node.tags.count), 是否复合: \(node.isCompound)")
            }
            #endif
            
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
                        #if DEBUG
                        if enableGraphDebug {
                            print("✅ 创建子节点连接: \(node.text) -> \(childNodeName)")
                        }
                        #endif
                    }
                }
            }
            
            // 创建节点到标签的连接
            for tag in node.tags {
                // 过滤掉复合节点的内部管理标签，不创建连接
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
                    #if DEBUG
                    if enableGraphDebug {
                        print("✅ 创建标签连接: \(node.text) -> \(tag.value)")
                    }
                    #endif
                } else {
                    #if DEBUG
                    if enableGraphDebug {
                        print("❌ 找不到标签节点: \(tag.type.rawValue):\(tag.value)")
                    }
                    #endif
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
                    #if DEBUG
                    if enableGraphDebug {
                        print("✅ 创建位置标签连接: \(node.text) -> \(locationTag.value)")
                    }
                    #endif
                }
            }
        }
        
        #if DEBUG
        if enableGraphDebug {
            print("🔹 节点-标签连接数: \(edges.count)")
            print("🔹 总连接数: \(edges.count)")
        }
        #endif
        
        // 移除节点间连接逻辑 - 只保留节点与标签之间的连接
        
        return (nodes: nodes, edges: edges)
    }
    
    // 保存选择状态到持久化存储
    private func saveSelectedNodeIds() {
        do {
            let data = try JSONEncoder().encode(Array(selectedNodeIds))
            selectedNodeIdsData = data
            print("🔄 GraphView: 保存选择状态 - \(selectedNodeIds.count) 个节点")
        } catch {
            print("❌ GraphView: 保存选择状态失败 - \(error)")
        }
    }
    
    // 从持久化存储加载选择状态
    private func loadSelectedNodeIds() {
        guard !selectedNodeIdsData.isEmpty else { return }
        
        // 尝试解码为UUID数组
        if let nodeIds = try? JSONDecoder().decode([UUID].self, from: selectedNodeIdsData) {
            selectedNodeIds = Set(nodeIds)
            print("🔄 GraphView: 加载选择状态 - \(selectedNodeIds.count) 个节点")
            return
        }
        
        // 如果失败，尝试解码为字符串数组（兼容旧格式）
        if let nodeIdStrings = try? JSONDecoder().decode([String].self, from: selectedNodeIdsData) {
            let nodeIds = nodeIdStrings.compactMap { UUID(uuidString: $0) }
            selectedNodeIds = Set(nodeIds)
            print("🔄 GraphView: 从字符串格式加载选择状态 - \(selectedNodeIds.count) 个节点")
            
            // 更新为新格式
            saveSelectedNodeIds()
            return
        }
        
        print("⚠️ GraphView: 无法解析选择状态数据，清空数据")
        selectedNodeIdsData = Data()
    }
    
    // 更新缓存的图数据
    private func updateGraphData() {
        let data = calculateGraphData()
        cachedNodes = data.nodes
        cachedEdges = data.edges
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                // 左侧：过滤信息显示
                buildFilterInfoView()
                
                Spacer()
                
                // 图谱预设按钮
                Button("图谱预设") {
                    showingPresetManager = true
                    print("📚 [全局节点图谱] 打开预设管理")
                }
                .buttonStyle(.bordered)
                .help("管理图谱预设")
                
                // 保存为预设按钮
                Button("保存为预设") {
                    showingSavePresetDialog = true
                    print("💾 [全局节点图谱] 保存当前状态为预设")
                }
                .buttonStyle(.bordered)
                .help("保存当前状态为预设")
                .disabled(selectedNodeIds.isEmpty && selectedLayerIds.isEmpty)
                
                // 🔒 锁定/解锁按钮
                Button(isLocked ? "🔓 解锁" : "🔒 锁定") {
                    toggleLockState()
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isLocked ? Color.orange.opacity(0.2) : Color.blue.opacity(0.1))
                .foregroundColor(isLocked ? .orange : .blue)
                .cornerRadius(6)
                .help(isLocked ? "解锁图谱以接收数据更新" : "锁定图谱以固定当前显示内容")
                
                // 节点看板按钮
                Button("节点看板") {
                    showNodeBoardWindow()
                    print("📋 [全局节点图谱] 打开节点看板")
                }
                .buttonStyle(.borderedProminent)
                .help("打开节点看板")
                
                // 重置按钮
                if !displayedNodes.isEmpty || !selectedNodeIds.isEmpty || !selectedLayerIds.isEmpty {
                    Button("显示全部") {
                        displayedNodes = []
                        selectedNodeIds = []
                        selectedLayerIds = []
                        searchQuery = ""
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 图谱内容
            if cachedNodes.isEmpty {
                EmptyGraphView()
            } else {
                NodeContextGraphView(
                    nodes: cachedNodes,
                    edges: cachedEdges,
                    title: "全局节点图谱",
                    initialScale: globalGraphInitialScale,
                    onNodeSelected: { nodeId, commandPressed in
                        // 当点击节点时，选择对应的节点（只有节点才会触发选择）
                        if let selectedGraphNode = cachedNodes.first(where: { $0.id == nodeId }),
                           let selectedNode = selectedGraphNode.node {
                            store.selectNode(selectedNode)
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environmentObject(store)
            }
        }
        .sheet(isPresented: $showingNodeSelector) {
            NodeSelectorView(selectedNodeIds: $selectedNodeIds)
                .environmentObject(store)
                .frame(width: 700, height: 600)
                .background(WindowAccessor())
        }
        .sheet(isPresented: $showingLayerSelector) {
            LayerSelectorView(selectedLayerIds: $selectedLayerIds)
                .environmentObject(store)
                .frame(width: 600, height: 500)
                .background(LayerWindowAccessor())
        }
        .sheet(isPresented: $showingPresetManager) {
            NodeGraphPresetManagerView(
                selectedNodeIds: $selectedNodeIds,
                selectedLayerIds: $selectedLayerIds
            )
            .environmentObject(store)
            .frame(width: 800, height: 600)
        }
        .alert("保存节点图谱预设", isPresented: $showingSavePresetDialog) {
            TextField("预设名称", text: $newPresetName)
            TextField("描述（可选）", text: $newPresetDescription)
            
            Button("保存") {
                if !newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    saveCurrentAsPreset()
                    newPresetName = ""
                    newPresetDescription = ""
                }
            }
            .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            
            Button("取消", role: .cancel) {
                newPresetName = ""
                newPresetDescription = ""
            }
        } message: {
            Text("为当前的节点和层级筛选状态创建一个预设，以便后续快速加载。")
        }
        .onKeyPress(.init("k"), phases: .down) { _ in
            NotificationCenter.default.post(name: Notification.Name("fitGraph"), object: nil)
            return .handled
        }
        .onAppear {
            // 加载持久化的选择状态
            loadSelectedNodeIds()
            
            // 初始显示所有节点
            if displayedNodes.isEmpty && selectedNodeIds.isEmpty && !store.nodes.isEmpty {
                displayedNodes = Array(store.nodes.prefix(20)) // 限制初始显示数量
            }
            updateGraphData()
        }
        .onChange(of: store.nodes) {
            updateGraphData()
        }
        .onChange(of: displayedNodes) {
            updateGraphData()
        }
        .onChange(of: selectedNodeIds) {
            updateGraphData()
            saveSelectedNodeIds()
        }
        .onChange(of: selectedLayerIds) {
            updateGraphData()
        }
        .onChange(of: store.selectedTag) {
            updateGraphData()
        }
        .onChange(of: store.showAllTagTypeNodes) {
            updateGraphData()
        }
        .onChange(of: store.expandedTagTypes) {
            updateGraphData()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NodeBoardSelectionChanged"))) { notification in
            if let userInfo = notification.userInfo,
               let nodeIds = userInfo["selectedNodeIds"] as? [UUID],
               let layerIds = userInfo["selectedLayerIds"] as? [UUID] {
                
                print("🔄 GraphView: 收到节点看板选择变化通知")
                print("   - 节点: \(nodeIds.count) 个")
                print("   - 层级: \(layerIds.count) 个")
                
                // 更新主界面的选择状态
                selectedNodeIds = Set(nodeIds)
                selectedLayerIds = Set(layerIds)
                
                // 强制更新图谱数据
                updateGraphData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("compoundNodeRefreshed"))) { notification in
            print("📨 [GraphView] 收到复合节点刷新通知！")
            
            if let userInfo = notification.userInfo {
                print("   - 通知数据: \(userInfo)")
                if let compoundNodeId = userInfo["compoundNodeId"] as? UUID,
                   let compoundNodeName = userInfo["compoundNodeName"] as? String,
                   let childNodeName = userInfo["childNodeName"] as? String {
                    print("   - 复合节点: \(compoundNodeName) (ID: \(compoundNodeId))")
                    print("   - 子节点: \(childNodeName)")
                }
            }
            
            // 如果图谱被锁定，不进行更新
            if !isLocked {
                print("🔄 GraphView: 开始更新图谱数据...")
                // 强制更新图谱数据以反映复合节点的最新状态
                updateGraphData()
                print("✅ GraphView: 图谱已更新以反映复合节点变化")
            } else {
                print("🔒 GraphView: 图谱已锁定，跳过更新")
            }
        }
        .navigationTitle("全局节点图谱")
    }
    
    private func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            displayedNodes = []
            return
        }
        
        // 清空节点选择，使用搜索模式
        selectedNodeIds = []
        
        // 搜索匹配的节点
        let matchedNodes = store.nodes.filter { node in
            node.text.localizedCaseInsensitiveContains(query) ||
            node.meaning?.localizedCaseInsensitiveContains(query) == true ||
            node.tags.contains { tag in
                tag.value.localizedCaseInsensitiveContains(query)
            }
        }
        
        // 获取相关节点（有共同标签的）
        var relatedNodes = Set<Node>()
        for matchedNode in matchedNodes {
            let nodeTags = Set(matchedNode.tags)
            let related = store.nodes.filter { otherNode in
                otherNode.id != matchedNode.id && !Set(otherNode.tags).isDisjoint(with: nodeTags)
            }
            relatedNodes.formUnion(related)
        }
        
        // 组合结果
        var finalNodes = Set(matchedNodes)
        finalNodes.formUnion(relatedNodes)
        
        displayedNodes = Array(finalNodes).sorted { $0.text < $1.text }
    }
    
    // MARK: - 过滤信息显示
    
    @ViewBuilder
    private func buildFilterInfoView() -> some View {
        if isLocked {
            // 🔒 锁定状态显示
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                
                Text("图谱已锁定")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fontWeight(.medium)
                
                Text("(\(lockedNodes?.count ?? 0) 个节点)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if !selectedNodeIds.isEmpty || !selectedLayerIds.isEmpty || !displayedNodes.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                Text(buildFilterText())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "circle.hexagonpath")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                Text("节点: \(store.nodes.count) | 层级: \(store.layers.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func buildFilterText() -> String {
        var parts: [String] = []
        
        if !selectedLayerIds.isEmpty {
            let layerNames = store.layers
                .filter { selectedLayerIds.contains($0.id) }
                .map { $0.displayName }
            parts.append("层级: \(layerNames.joined(separator: ", "))")
        }
        
        if !selectedNodeIds.isEmpty {
            parts.append("节点: \(selectedNodeIds.count)个")
        }
        
        if !displayedNodes.isEmpty {
            parts.append("搜索结果: \(displayedNodes.count)个")
        }
        
        return parts.joined(separator: " | ")
    }
    
    // MARK: - 预设和看板功能
    
    private func showNodeBoardWindow() {
        // 节点看板永远显示所有数据，不受任何筛选限制
        let nodeBoardView = NodeBoardView(
            selectedNodeIds: Set<UUID>(), // 清空节点筛选
            selectedLayerIds: Set<UUID>() // 清空层级筛选
        )
        .environmentObject(store)
        
        let hostingView = NSHostingView(rootView: nodeBoardView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.contentView = hostingView
        newWindow.title = "节点看板"
        newWindow.setFrameAutosaveName("NodeBoardWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        
        print("🪟 [节点看板] 窗口已创建")
    }
    
    private func saveCurrentAsPreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = newPresetDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !name.isEmpty else { return }
        
        // 创建并保存节点图谱预设
        let preset = NodeGraphPreset(
            name: name,
            description: description.isEmpty ? nil : description,
            selectedNodeIds: selectedNodeIds,
            selectedLayerIds: selectedLayerIds,
            createdAt: Date(),
            lastUsed: Date()
        )
        
        NodeGraphPresetManager.shared.savePreset(preset)
        
        print("💾 保存节点图谱预设: \(name)")
        print("   - 选中节点数: \(selectedNodeIds.count)")
        print("   - 选中层数: \(selectedLayerIds.count)")
        print("   - 描述: \(description.isEmpty ? "无" : description)")
    }
    
    // 递归添加复合节点的子节点结构（类似DetailPanel的逻辑）
    private func addChildNodesForGlobalGraph(
        for node: Node, 
        nodes: inout [NodeGraphNode], 
        addedTagKeys: inout Set<String>, 
        addedNodeIds: inout Set<UUID>,
        depth: Int
    ) {
        // 防止无限递归
        guard depth <= 10 else { return }
        
        #if DEBUG
        @AppStorage("enableGraphDebug") var enableGraphDebug: Bool = false
        if enableGraphDebug {
            let indentPrefix = String(repeating: "  ", count: depth)
            print("\(indentPrefix)🏗️ 全局节点图谱添加子节点结构: \(node.text) (深度: \(depth))")
        }
        #endif
        
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
                    
                    #if DEBUG
                    if enableGraphDebug {
                        let indentPrefix = String(repeating: "  ", count: depth)
                        print("\(indentPrefix)  ↳ 添加子节点: \(childNode.text)")
                    }
                    #endif
                    
                    // 如果子节点也是复合节点，递归添加其子节点
                    if childNode.isCompound {
                        addChildNodesForGlobalGraph(
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
    
    // 🔒 锁定/解锁切换函数
    private func toggleLockState() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if isLocked {
                // 解锁：清除锁定的数据，恢复正常数据流
                print("🔓 [全局节点图谱] 解锁图谱，恢复数据更新")
                isLocked = false
                lockedNodes = nil
                
                // 解锁后立即重新计算图谱数据
                updateGraphData()
            } else {
                // 锁定：保存当前数据状态
                print("🔒 [全局节点图谱] 锁定图谱，冻结当前显示内容")
                isLocked = true
                lockedNodes = store.nodes
                
                // 打印锁定的数据信息
                print("🔒 锁定数据: \(lockedNodes?.count ?? 0)个节点")
            }
        }
    }
}

// MARK: - Empty Graph View

struct EmptyGraphView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "circle.hexagonpath")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("暂无图谱数据")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("添加一些节点来生成全局节点图谱")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 节点选择器视图

struct NodeSelectorView: View {
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedNodeIds: Set<UUID>
    @State private var tempSelectedIds: Set<UUID> = []
    @State private var searchQuery: String = ""
    
    private var filteredNodes: [Node] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return store.nodes.sorted { $0.text < $1.text }
        }
        
        return store.nodes.filter { node in
            node.text.localizedCaseInsensitiveContains(searchQuery) ||
            node.meaning?.localizedCaseInsensitiveContains(searchQuery) == true
        }.sorted { $0.text < $1.text }
    }
    
    private var regularNodes: [Node] {
        filteredNodes.filter { !$0.isCompound }
    }
    
    private var compoundNodes: [Node] {
        filteredNodes.filter { $0.isCompound }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("选择要显示的节点")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("完成") {
                    selectedNodeIds = tempSelectedIds
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 搜索栏
            HStack {
                TextField("搜索节点...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                
                if !searchQuery.isEmpty {
                    Button("清除") {
                        searchQuery = ""
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 快速选择按钮
            HStack {
                Button("全选") {
                    tempSelectedIds = Set(store.nodes.map { $0.id })
                }
                .buttonStyle(.bordered)
                
                Button("全不选") {
                    tempSelectedIds.removeAll()
                }
                .buttonStyle(.bordered)
                
                Button("仅复合节点") {
                    tempSelectedIds = Set(store.nodes.filter { $0.isCompound }.map { $0.id })
                }
                .buttonStyle(.bordered)
                
                Button("仅普通节点") {
                    tempSelectedIds = Set(store.nodes.filter { !$0.isCompound }.map { $0.id })
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // 节点列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // 复合节点部分
                    if !compoundNodes.isEmpty {
                        SectionHeaderView(title: "复合节点", count: compoundNodes.count)
                        
                        ForEach(compoundNodes, id: \.id) { node in
                            NodeSelectorRow(
                                node: node,
                                isSelected: tempSelectedIds.contains(node.id),
                                isCompound: true
                            ) {
                                toggleNode(node)
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 8)
                    }
                    
                    // 普通节点部分
                    if !regularNodes.isEmpty {
                        SectionHeaderView(title: "普通节点", count: regularNodes.count)
                        
                        ForEach(regularNodes, id: \.id) { node in
                            NodeSelectorRow(
                                node: node,
                                isSelected: tempSelectedIds.contains(node.id),
                                isCompound: false
                            ) {
                                toggleNode(node)
                            }
                        }
                    }
                    
                    // 空状态
                    if filteredNodes.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            
                            Text("没有找到匹配的节点")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            tempSelectedIds = selectedNodeIds
        }
    }
    
    private func toggleNode(_ node: Node) {
        if tempSelectedIds.contains(node.id) {
            tempSelectedIds.remove(node.id)
        } else {
            tempSelectedIds.insert(node.id)
        }
    }
}

// MARK: - 节点选择器行视图

struct NodeSelectorRow: View {
    let node: Node
    let isSelected: Bool
    let isCompound: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 复选框
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            
            // 节点类型指示器
            Circle()
                .fill(isCompound ? Color.purple : Color.blue)
                .frame(width: 8, height: 8)
            
            // 节点信息
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(node.text)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    if isCompound {
                        Text("复合")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    // 标签数量
                    Text("\(node.tags.count)个标签")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let meaning = node.meaning {
                    Text(meaning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        )
        .onTapGesture {
            onToggle()
        }
    }
}

// MARK: - 分组标题视图

struct SectionHeaderView: View {
    let title: String
    let count: Int
    
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("(\(count))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

// MARK: - Window Accessor for fixing sheet window size

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.findAndConfigureWindow()
        }
        
        // 多次延迟尝试，确保能找到并配置窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.findAndConfigureWindow()
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.findAndConfigureWindow()
        }
    }
    
    private func findAndConfigureWindow() {
        // 查找所有Sheet类型的窗口
        for window in NSApp.windows {
            // 检查是否是Sheet窗口并且包含我们的内容
            if window.isSheet || window.title.contains("选择要显示的节点") || window.level == NSWindow.Level.modalPanel {
                self.configureWindow(window)
            }
        }
        
        // 如果找不到特定窗口，尝试最新的非主窗口
        if let latestWindow = NSApp.windows.filter({ !$0.isMainWindow && $0.isVisible }).first {
            self.configureWindow(latestWindow)
        }
    }
    
    private func configureWindow(_ window: NSWindow) {
        // 完全禁用窗口大小调整
        window.styleMask.remove(.resizable)
        
        // 设置固定尺寸约束
        let targetSize = NSSize(width: 700, height: 600)
        window.minSize = targetSize
        window.maxSize = targetSize
        
        // 强制设置窗口尺寸
        if window.frame.size != targetSize {
            let currentFrame = window.frame
            let newFrame = NSRect(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y,
                width: targetSize.width,
                height: targetSize.height
            )
            window.setFrame(newFrame, display: true, animate: false)
        }
        
        // 设置窗口不可移动（如果需要的话）
        window.isMovable = true // 保持可移动，但不可调整大小
        
        // 确保内容视图也不能调整大小
        if let contentView = window.contentView {
            contentView.autoresizingMask = []
        }
    }
}

// MARK: - 层级选择器视图

struct LayerSelectorView: View {
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLayerIds: Set<UUID>
    @State private var tempSelectedIds: Set<UUID> = []
    @State private var searchQuery: String = ""
    
    private var filteredLayers: [Layer] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return store.layers.sorted { $0.displayName < $1.displayName }
        }
        
        return store.layers.filter { layer in
            layer.displayName.localizedCaseInsensitiveContains(searchQuery) ||
            layer.name.localizedCaseInsensitiveContains(searchQuery)
        }.sorted { $0.displayName < $1.displayName }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("选择要显示的层")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("完成") {
                    selectedLayerIds = tempSelectedIds
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 搜索栏
            HStack {
                TextField("搜索层...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                
                if !searchQuery.isEmpty {
                    Button("清除") {
                        searchQuery = ""
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 快速选择按钮
            HStack {
                Button("全选") {
                    tempSelectedIds = Set(store.layers.map { $0.id })
                }
                .buttonStyle(.bordered)
                
                Button("全不选") {
                    tempSelectedIds.removeAll()
                }
                .buttonStyle(.bordered)
                
                Button("显示所有层") {
                    tempSelectedIds.removeAll() // 空集表示显示所有层
                }
                .buttonStyle(.bordered)
                
                if let currentLayer = store.currentLayer {
                    Button("仅当前层") {
                        tempSelectedIds = Set([currentLayer.id])
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // 层列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredLayers, id: \.id) { layer in
                        LayerSelectorRow(
                            layer: layer,
                            isSelected: tempSelectedIds.contains(layer.id),
                            isCurrentLayer: store.currentLayer?.id == layer.id
                        ) {
                            toggleLayer(layer)
                        }
                    }
                    
                    // 空状态
                    if filteredLayers.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            
                            Text("没有找到匹配的层")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            tempSelectedIds = selectedLayerIds
        }
    }
    
    private func toggleLayer(_ layer: Layer) {
        if tempSelectedIds.contains(layer.id) {
            tempSelectedIds.remove(layer.id)
        } else {
            tempSelectedIds.insert(layer.id)
        }
    }
}

// MARK: - 层级选择器行视图

struct LayerSelectorRow: View {
    @EnvironmentObject private var store: NodeStore
    let layer: Layer
    let isSelected: Bool
    let isCurrentLayer: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 复选框
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            
            // 层级颜色指示器
            Circle()
                .fill(Color.from(layer.color))
                .frame(width: 12, height: 12)
            
            // 层级信息
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(layer.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    if isCurrentLayer {
                        Text("当前层")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                    
                    if layer.isCompound {
                        Text("复合")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    // 节点数量
                    let nodeCount = store.nodes.filter { $0.layerId == layer.id }.count
                    Text("\(nodeCount)个节点")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("(\(layer.name))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        )
        .onTapGesture {
            onToggle()
        }
    }
}

// MARK: - Layer Window Accessor for fixing layer selector sheet window size

struct LayerWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.findAndConfigureWindow()
        }
        
        // 多次延迟尝试，确保能找到并配置窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.findAndConfigureWindow()
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.findAndConfigureWindow()
        }
    }
    
    private func findAndConfigureWindow() {
        // 查找所有Sheet类型的窗口
        for window in NSApp.windows {
            // 检查是否是Sheet窗口并且包含层级选择相关内容
            if window.isSheet || window.title.contains("选择要显示的层") || window.level == NSWindow.Level.modalPanel {
                self.configureWindow(window)
            }
        }
        
        // 如果找不到特定窗口，尝试最新的非主窗口
        if let latestWindow = NSApp.windows.filter({ !$0.isMainWindow && $0.isVisible }).first {
            self.configureWindow(latestWindow)
        }
    }
    
    private func configureWindow(_ window: NSWindow) {
        // 完全禁用窗口大小调整
        window.styleMask.remove(.resizable)
        
        // 设置层级选择器的固定尺寸约束
        let targetSize = NSSize(width: 600, height: 500)
        window.minSize = targetSize
        window.maxSize = targetSize
        
        // 强制设置窗口尺寸
        if window.frame.size != targetSize {
            let currentFrame = window.frame
            let newFrame = NSRect(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y,
                width: targetSize.width,
                height: targetSize.height
            )
            window.setFrame(newFrame, display: true, animate: false)
        }
        
        // 设置窗口不可移动（如果需要的话）
        window.isMovable = true // 保持可移动，但不可调整大小
        
        // 确保内容视图也不能调整大小
        if let contentView = window.contentView {
            contentView.autoresizingMask = []
        }
    }
}

// MARK: - 节点看板视图

struct NodeBoardView: View {
    let selectedNodeIds: Set<UUID>
    let selectedLayerIds: Set<UUID>
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""           // 节点搜索
    @State private var layerSearchText = ""      // 层级搜索
    @State private var boardSelectedNodeIds: Set<UUID> = []  // 看板内部的选中状态
    @State private var boardSelectedLayerIds: Set<UUID> = [] // 看板内部的选中层级
    
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
        
        // 层级选择仅用于标记状态，不影响节点显示
        
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
                
                Button("关闭") {
                    // Close the current window
                    if let window = NSApplication.shared.keyWindow {
                        window.close()
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 双搜索栏 - 一行布局
            VStack(spacing: 8) {
                // 搜索框一行排列
                HStack(spacing: 12) {
                    // 层级搜索栏
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundColor(.blue)
                            .font(.system(size: 14))
                        
                        TextField("搜索层级...", text: $layerSearchText)
                            .textFieldStyle(.roundedBorder)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(layerSearchText.isEmpty ? Color.clear : Color.blue.opacity(0.5), lineWidth: 1)
                            )
                        
                        if !layerSearchText.isEmpty {
                            Button("×") {
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
                            
                            if !selectedNodeIds.isEmpty || !selectedLayerIds.isEmpty {
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
        .frame(minWidth: 800, minHeight: 600)
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
        // 这里可以通知主界面更新选中状态，或者发送通知
        print("📤 节点看板选择状态变化:")
        print("   - 选中节点: \(boardSelectedNodeIds.count) 个")
        print("   - 选中层级: \(boardSelectedLayerIds.count) 个")
        
        // 发送通知给主界面的GraphView更新选择状态
        NotificationCenter.default.post(
            name: Notification.Name("NodeBoardSelectionChanged"),
            object: nil,
            userInfo: [
                "selectedNodeIds": Array(boardSelectedNodeIds),
                "selectedLayerIds": Array(boardSelectedLayerIds)
            ]
        )
        
        // 直接更新主界面的显示状态（如果可能）
        DispatchQueue.main.async {
            // 这里可以通过更多方式同步状态
        }
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
            
            // 提示文字
            if isHovered {
                Text("点击选择整个层级 • ⌘+点击多选")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }
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
        .help("点击选择整个层级，Command+点击进行多选")
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

// MARK: - 节点图谱预设管理视图

struct NodeGraphPresetManagerView: View {
    @Binding var selectedNodeIds: Set<UUID>
    @Binding var selectedLayerIds: Set<UUID>
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var presetManager = NodeGraphPresetManager.shared
    
    @State private var searchText = ""
    @State private var showingDeleteAlert = false
    @State private var presetToDelete: NodeGraphPreset?
    
    private var filteredPresets: [NodeGraphPreset] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return presetManager.presetsSortedByLastUsed
        }
        
        return presetManager.presets.filter { preset in
            preset.name.localizedCaseInsensitiveContains(searchText) ||
            preset.description?.localizedCaseInsensitiveContains(searchText) == true
        }.sorted { $0.lastUsed > $1.lastUsed }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("节点图谱预设管理")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("(\(presetManager.presets.count) 个预设)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
            
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索预设...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // 预设列表
            if filteredPresets.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: searchText.isEmpty ? "bookmark.slash" : "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text(searchText.isEmpty ? "暂无保存的节点图谱预设" : "没有找到匹配的预设")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if searchText.isEmpty {
                        Text("在全局节点图谱中选择节点和层级后，点击\"保存为预设\"来创建您的第一个预设。")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredPresets) { preset in
                            PresetRowView(
                                preset: preset,
                                isCurrentPreset: presetManager.currentPreset?.id == preset.id,
                                store: store,
                                onLoad: {
                                    let result = presetManager.loadPreset(preset)
                                    selectedNodeIds = result.selectedNodeIds
                                    selectedLayerIds = result.selectedLayerIds
                                    dismiss()
                                },
                                onDelete: {
                                    presetToDelete = preset
                                    showingDeleteAlert = true
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .padding()
        .frame(width: 800, height: 600)
        .alert("删除预设", isPresented: $showingDeleteAlert, presenting: presetToDelete) { preset in
            Button("删除", role: .destructive) {
                presetManager.deletePreset(preset)
                presetToDelete = nil
            }
            Button("取消", role: .cancel) {
                presetToDelete = nil
            }
        } message: { preset in
            Text("确定要删除预设 \"\(preset.name)\" 吗？此操作无法撤销。")
        }
    }
}

// MARK: - 预设行视图

struct PresetRowView: View {
    let preset: NodeGraphPreset
    let isCurrentPreset: Bool
    let store: NodeStore
    let onLoad: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    private func getNodeNames(for nodeIds: Set<UUID>) -> [String] {
        return store.nodes
            .filter { nodeIds.contains($0.id) }
            .map { $0.text }
            .sorted()
    }
    
    private func getLayerNames(for layerIds: Set<UUID>) -> [String] {
        return store.layers
            .filter { layerIds.contains($0.id) }
            .map { $0.displayName }
            .sorted()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 预设标题行
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(preset.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if isCurrentPreset {
                            Text("当前")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                    }
                    
                    if let description = preset.description {
                        Text(description)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                // 操作按钮
                HStack(spacing: 8) {
                    Button("加载") {
                        onLoad()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    if isHovered {
                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("删除预设")
                    }
                }
            }
            
            // 预设内容概览
            HStack(spacing: 20) {
                // 节点信息
                if !preset.selectedNodeIds.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "circle")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            Text("节点 (\(preset.selectedNodeIds.count))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        
                        let nodeNames = getNodeNames(for: preset.selectedNodeIds)
                        Text(nodeNames.prefix(3).joined(separator: ", ") + (nodeNames.count > 3 ? "..." : ""))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                // 层级信息
                if !preset.selectedLayerIds.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "square.stack")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                            Text("层级 (\(preset.selectedLayerIds.count))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                        }
                        
                        let layerNames = getLayerNames(for: preset.selectedLayerIds)
                        Text(layerNames.prefix(3).joined(separator: ", ") + (layerNames.count > 3 ? "..." : ""))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // 时间信息
                VStack(alignment: .trailing, spacing: 2) {
                    Text("创建: \(preset.createdAt, formatter: dateFormatter)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Text("使用: \(preset.lastUsed, formatter: dateFormatter)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrentPreset ? Color.green.opacity(0.05) : Color(NSColor.controlBackgroundColor))
                .stroke(
                    isCurrentPreset ? Color.green.opacity(0.3) : (isHovered ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2)),
                    lineWidth: isCurrentPreset ? 2 : (isHovered ? 1.5 : 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            // 单击加载预设
            onLoad()
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}


#Preview {
    GraphView()
        .environmentObject(NodeStore.shared)
}