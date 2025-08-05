import SwiftUI

struct GraphView: View {
    @EnvironmentObject private var store: NodeStore
    @AppStorage("globalGraphInitialScale") private var globalGraphInitialScale: Double = 1.0
    @State private var searchQuery: String = ""
    @State private var displayedNodes: [Node] = []
    @State private var cachedNodes: [NodeGraphNode] = []
    @State private var cachedEdges: [NodeGraphEdge] = []
    
    // 生成所有节点的图谱数据 - 统一计算节点和边
    private func calculateGraphData() -> (nodes: [NodeGraphNode], edges: [NodeGraphEdge]) {
        @AppStorage("enableGraphDebug") var enableGraphDebug: Bool = false
        
        var nodes: [NodeGraphNode] = []
        var edges: [NodeGraphEdge] = []
        var addedTagKeys: Set<String> = []
        
        let nodesToShow = displayedNodes.isEmpty ? store.nodes : displayedNodes
        
        // 首先添加所有节点
        for node in nodesToShow {
            nodes.append(NodeGraphNode(node: node))
        }
        
        // 然后添加所有标签节点（去重）
        for node in nodesToShow {
            for tag in node.tags {
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
                
                // 搜索框
                TextField("搜索节点或标签...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit {
                        performSearch()
                    }
                
                // 搜索按钮
                Button("搜索") {
                    performSearch()
                }
                .disabled(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                
                // 重置按钮
                if !displayedNodes.isEmpty {
                    Button("显示全部") {
                        displayedNodes = []
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
        .onKeyPress(.init("k"), phases: .down) { _ in
            NotificationCenter.default.post(name: Notification.Name("fitGraph"), object: nil)
            return .handled
        }
        .onAppear {
            // 初始显示所有节点
            if displayedNodes.isEmpty && !store.nodes.isEmpty {
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
    }
    
    private func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            displayedNodes = []
            return
        }
        
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

#Preview {
    GraphView()
        .environmentObject(NodeStore.shared)
}