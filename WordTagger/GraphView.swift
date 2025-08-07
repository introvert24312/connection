import SwiftUI

struct GraphView: View {
    @EnvironmentObject private var store: NodeStore
    @AppStorage("globalGraphInitialScale") private var globalGraphInitialScale: Double = 1.0
    @State private var searchQuery: String = ""
    @State private var displayedNodes: [Node] = []
    @State private var cachedNodes: [NodeGraphNode] = []
    @State private var cachedEdges: [NodeGraphEdge] = []
    @State private var showingNodeSelector = false
    @State private var selectedNodeIds: Set<UUID> = []
    
    // 生成所有节点的图谱数据 - 统一计算节点和边
    private func calculateGraphData() -> (nodes: [NodeGraphNode], edges: [NodeGraphEdge]) {
        @AppStorage("enableGraphDebug") var enableGraphDebug: Bool = false
        
        var nodes: [NodeGraphNode] = []
        var edges: [NodeGraphEdge] = []
        var addedTagKeys: Set<String> = []
        
        // 根据选择的节点ID来确定要显示的节点
        let nodesToShow: [Node]
        if !selectedNodeIds.isEmpty {
            nodesToShow = store.nodes.filter { selectedNodeIds.contains($0.id) }
        } else if !displayedNodes.isEmpty {
            nodesToShow = displayedNodes
        } else {
            nodesToShow = store.nodes
        }
        
        // 首先添加所有节点
        for node in nodesToShow {
            nodes.append(NodeGraphNode(node: node))
        }
        
        // 然后添加所有标签节点（去重），但过滤掉复合节点的管理标签
        for node in nodesToShow {
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
        
        // 为每个节点与其标签创建连接
        for node in nodesToShow {
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
                print("🔹 处理节点: \(node.text), 标签数: \(node.tags.count)")
            }
            #endif
            
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
                        print("✅ 创建连接: \(node.text) -> \(tag.value)")
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
                Text("全局图谱")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
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
                
                // 重置按钮
                if !displayedNodes.isEmpty || !selectedNodeIds.isEmpty {
                    Button("显示全部") {
                        displayedNodes = []
                        selectedNodeIds = []
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
                UniversalRelationshipGraphView(
                    nodes: cachedNodes,
                    edges: cachedEdges,
                    title: "全局图谱",
                    initialScale: globalGraphInitialScale,
                    onNodeSelected: { nodeId in
                        // 当点击节点时，选择对应的节点（只有节点才会触发选择）
                        if let selectedGraphNode = cachedNodes.first(where: { $0.id == nodeId }),
                           let selectedNode = selectedGraphNode.node {
                            store.selectNode(selectedNode)
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingNodeSelector) {
            NodeSelectorView(selectedNodeIds: $selectedNodeIds)
                .environmentObject(store)
        }
        .onKeyPress(.init("k"), phases: .down) { _ in
            NotificationCenter.default.post(name: Notification.Name("fitGraph"), object: nil)
            return .handled
        }
        .onAppear {
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
            
            Text("添加一些节点来生成全局图谱")
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
        NavigationView {
            VStack(spacing: 0) {
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
            .navigationTitle("选择要显示的节点")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        selectedNodeIds = tempSelectedIds
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 700, height: 600)
        .fixedSize()
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

#Preview {
    GraphView()
        .environmentObject(NodeStore.shared)
}