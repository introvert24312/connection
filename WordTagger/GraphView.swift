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
    
    // 生成所有节点的图谱数据 - 统一计算节点和边
    private func calculateGraphData() -> (nodes: [NodeGraphNode], edges: [NodeGraphEdge]) {
        @AppStorage("enableGraphDebug") var enableGraphDebug: Bool = false
        
        var nodes: [NodeGraphNode] = []
        var edges: [NodeGraphEdge] = []
        var addedTagKeys: Set<String> = []
        
        // 首先根据层级筛选进行过滤
        let layerFilteredNodes: [Node]
        if selectedLayerIds.isEmpty {
            // 显示所有层的节点
            layerFilteredNodes = store.nodes
        } else {
            // 只显示选中层的节点
            layerFilteredNodes = store.nodes.filter { selectedLayerIds.contains($0.layerId) }
        }
        
        // 根据选择的节点ID来确定要显示的节点
        let nodesToShow: [Node]
        if !selectedNodeIds.isEmpty {
            nodesToShow = layerFilteredNodes.filter { selectedNodeIds.contains($0.id) }
        } else if !displayedNodes.isEmpty {
            // 搜索结果也需要应用层级筛选
            nodesToShow = displayedNodes.filter { selectedLayerIds.isEmpty || selectedLayerIds.contains($0.layerId) }
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
                Text("全局节点图谱")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // 层级选择器按钮
                Button(action: {
                    showingLayerSelector = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "layer.fill")
                        if selectedLayerIds.isEmpty {
                            Text("所有层")
                        } else {
                            Text("筛选层(\(selectedLayerIds.count))")
                        }
                    }
                }
                .buttonStyle(.bordered)
                .help("选择要显示的层")
                
                // 节点选择器按钮
                Button(action: {
                    showingNodeSelector = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                        Text("选择节点")
                        if !selectedNodeIds.isEmpty {
                            Text("(\(selectedNodeIds.count))")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .help("选择要显示的节点")
                
                // 搜索框
                TextField("搜索节点或标签...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit {
                        performSearch()
                    }
                
                // 搜索按钮
                Button("搜索") {
                    performSearch()
                }
                .disabled(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                
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
            .frame(width: 500, height: 400)
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
    
    // MARK: - 预设和看板功能
    
    private func showNodeBoardWindow() {
        let nodeBoardView = NodeBoardView(
            selectedNodeIds: selectedNodeIds,
            selectedLayerIds: selectedLayerIds
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
        
        // 这里应该保存预设到某个管理器中
        print("💾 保存节点图谱预设: \(name)")
        print("   - 选中节点数: \(selectedNodeIds.count)")
        print("   - 选中层数: \(selectedLayerIds.count)")
        print("   - 描述: \(description.isEmpty ? "无" : description)")
        
        // TODO: 实现实际的预设保存逻辑
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
    
    @State private var searchText = ""
    
    private var filteredNodes: [Node] {
        var nodes = store.nodes
        
        // 应用节点筛选
        if !selectedNodeIds.isEmpty {
            nodes = nodes.filter { selectedNodeIds.contains($0.id) }
        }
        
        // 应用层级筛选
        if !selectedLayerIds.isEmpty {
            nodes = nodes.filter { selectedLayerIds.contains($0.layerId) }
        }
        
        // 应用搜索筛选
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
        
        return store.layers.compactMap { layer in
            if let nodes = groupedNodes[layer.id], !nodes.isEmpty {
                return (layer: layer, nodes: nodes.sorted { $0.text < $1.text })
            }
            return nil
        }.sorted { $0.layer.displayName < $1.layer.displayName }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("节点看板")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(filteredNodes.count) 个节点")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
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
            
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索节点...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                
                if !searchText.isEmpty {
                    Button("清除") {
                        searchText = ""
                    }
                    .buttonStyle(.plain)
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
                            // 层级标题
                            LayerSectionHeader(layer: layerGroup.layer, nodeCount: layerGroup.nodes.count)
                            
                            // 节点网格
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ], spacing: 12) {
                                ForEach(layerGroup.nodes, id: \.id) { node in
                                    CompactNodeCard(node: node, layer: layerGroup.layer)
                                }
                            }
                        }
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
    }
}

// MARK: - 层级分组标题
struct LayerSectionHeader: View {
    let layer: Layer
    let nodeCount: Int
    
    var body: some View {
        HStack(spacing: 8) {
            // 层级颜色指示器
            Circle()
                .fill(Color.from(layer.color))
                .frame(width: 16, height: 16)
                .shadow(radius: 1)
            
            Text(layer.displayName)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("(\(nodeCount))")
                .font(.body)
                .foregroundColor(.secondary)
            
            if layer.isCompound {
                Image(systemName: "square.stack.3d.up")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - 紧凑节点卡片
struct CompactNodeCard: View {
    let node: Node
    let layer: Layer
    @EnvironmentObject private var store: NodeStore
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 节点名称
            Text(node.text)
                .font(.headline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            // 节点含义
            if let meaning = node.meaning {
                Text(meaning)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            // 标签数量指示器
            HStack {
                if !node.tags.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text("\(node.tags.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // 节点类型指示器
                if node.isCompound {
                    Image(systemName: "square.stack.3d.up")
                        .font(.caption)
                        .foregroundColor(.purple)
                }
            }
        }
        .padding(12)
        .frame(minHeight: 100, maxHeight: 120)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.blue.opacity(0.05) : Color(NSColor.controlBackgroundColor))
                .stroke(
                    isHovered ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2),
                    lineWidth: isHovered ? 1.5 : 1
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            store.selectNode(node)
            print("📄 选中节点: \(node.text)")
        }
        .help(buildTooltip())
    }
    
    private func buildTooltip() -> String {
        var tooltip = node.text
        if let meaning = node.meaning {
            tooltip += "\n\n\(meaning)"
        }
        tooltip += "\n\n层级: \(layer.displayName)"
        if !node.tags.isEmpty {
            tooltip += "\n标签数量: \(node.tags.count)"
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
    
    @State private var searchText = ""
    @State private var savedPresets: [NodeGraphPreset] = []
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("节点图谱预设管理")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
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
            
            // 预设列表占位
            VStack(spacing: 16) {
                Image(systemName: "bookmark.slash")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                
                Text("暂无保存的节点图谱预设")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("在全局节点图谱中选择节点和层级后，点击\"保存为预设\"来创建您的第一个预设。")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}

// MARK: - 节点图谱预设数据模型

struct NodeGraphPreset: Identifiable {
    let id = UUID()
    let name: String
    let description: String?
    let selectedNodeIds: Set<UUID>
    let selectedLayerIds: Set<UUID>
    let createdAt: Date
    var lastUsed: Date
}

#Preview {
    GraphView()
        .environmentObject(NodeStore.shared)
}