import SwiftUI
import WebKit

struct GraphView: View {
    @EnvironmentObject private var store: WordStore
    @StateObject private var graphService = GraphService.shared
    @State private var selectedNodeType: NodeType = .all
    @State private var selectedTagType: Tag.TagType? = nil
    @State private var searchQuery: String = ""
    @State private var showingFilters = true
    @State private var nodeSize: Double = 20
    @State private var isBuilding = false
    @State private var focusedNodeId: String? = nil // 聚焦的节点ID
    @State private var selectedNodeId: String? = nil // 选中的节点ID
    @State private var nodeClusters: [NodeCluster] = [] // 节点簇列表
    @State private var selectedClusterIds: Set<String> = [] // 选中的节点簇ID
    @State private var addedWordIds: Set<String> = [] // 通过搜索添加的单词ID
    
    enum NodeType: String, CaseIterable {
        case all = "全部"
        case wordsOnly = "仅单词"
        case tagsOnly = "仅标签"
        case connected = "有连接"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                HStack {
                    Text("节点关系图谱")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    // 聚焦模式指示器和返回按钮
                    if let focusedId = focusedNodeId,
                       let focusedNode = createNodes().first(where: { $0.id == focusedId }) {
                        Text("→")
                            .foregroundColor(.secondary)
                        
                        Text("\(focusedNode.label)")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                        
                        Button(action: { 
                            withAnimation(.easeInOut(duration: 0.3)) {
                                focusedNodeId = nil 
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .help("返回全图")
                    }
                }
                
                // 节点簇统计信息
                if !nodeClusters.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("节点簇统计")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            Text("总计: \(nodeClusters.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("显示: \(selectedClusterIds.count)")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text("节点: \(filteredNodes.count)")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.1))
                    )
                }
                
                Spacer()
                
                // 搜索框和添加功能
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("搜索单词或标签...", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .frame(width: 200)
                            .onSubmit {
                                if !searchQuery.isEmpty {
                                    addWordsToGraph(searchQuery)
                                }
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    
                    // 添加到图谱按钮
                    if !searchQuery.isEmpty {
                        Button(action: {
                            addWordsToGraph(searchQuery)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                Text("添加")
                            }
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.blue)
                            )
                        }
                        .help("将搜索结果添加到图谱中显示")
                    }
                }
                
                // 简单的节点类型过滤器
                Menu {
                    ForEach(NodeType.allCases, id: \.self) { type in
                        Button(action: {
                            selectedNodeType = type
                        }) {
                            HStack {
                                Text(type.rawValue)
                                if selectedNodeType == type {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(selectedNodeType.rawValue)
                    }
                    .foregroundColor(.blue)
                }
                .help("节点类型过滤")
                
                // 节点簇过滤器
                Menu {
                    Button(action: {
                        selectedClusterIds = Set(nodeClusters.map { $0.id })
                    }) {
                        HStack {
                            Text("全部显示")
                            if selectedClusterIds.count == nodeClusters.count {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Button(action: {
                        selectedClusterIds.removeAll()
                    }) {
                        HStack {
                            Text("全部隐藏")
                            if selectedClusterIds.isEmpty {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Divider()
                    
                    ForEach(Array(nodeClusters.enumerated()), id: \.element.id) { index, cluster in
                        Button(action: {
                            if selectedClusterIds.contains(cluster.id) {
                                selectedClusterIds.remove(cluster.id)
                            } else {
                                selectedClusterIds.insert(cluster.id)
                            }
                        }) {
                            HStack {
                                Circle()
                                    .fill(cluster.color)
                                    .frame(width: 12, height: 12)
                                Text("节点簇 \(index + 1) (\(cluster.nodeIds.count)个节点)")
                                if selectedClusterIds.contains(cluster.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "circle.grid.3x3")
                        Text("节点簇 (\(selectedClusterIds.count)/\(nodeClusters.count))")
                    }
                    .foregroundColor(.blue)
                }
                .help("节点簇过滤")
                
                // 清空添加的单词按钮
                if !addedWordIds.isEmpty {
                    Button(action: clearAddedWords) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("清空(\(addedWordIds.count))")
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                    .help("清空通过搜索添加的单词")
                }
                
                Button(action: buildGraph) {
                    if isBuilding {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                    }
                }
                .help("重新构建图谱")
                .disabled(isBuilding)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 图谱主体
            VStack {
                ZStack {
                    if filteredNodes.isEmpty {
                        EmptyGraphView()
                    } else {
                        // 使用新的通用关系图组件
                        UniversalRelationshipGraphView(
                            nodes: filteredNodes.map { node in
                                let clusterColor = node.clusterId.flatMap { clusterId in
                                    nodeClusters.first { $0.id == clusterId }?.color
                                }
                                return GraphNodeAdapter(
                                    id: node.id.hashValue,
                                    label: node.label,
                                    subtitle: node.subtitle.isEmpty ? nil : node.subtitle,
                                    clusterId: node.clusterId,
                                    clusterColor: clusterColor?.toHexString()
                                )
                            },
                            edges: filteredEdges.map { edge in
                                GraphEdgeAdapter(
                                    fromId: edge.source.hashValue,
                                    toId: edge.target.hashValue,
                                    label: edge.type.rawValue
                                )
                            },
                            title: "节点关系图谱",
                            onNodeSelected: { nodeId in
                                // 通过hashValue找到对应的原始节点ID
                                if let selectedNode = createNodes().first(where: { $0.id.hashValue == nodeId }) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        focusedNodeId = selectedNode.id
                                    }
                                }
                            },
                            onNodeDeselected: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    focusedNodeId = nil
                                }
                            }
                        )
                    }
                }
            }
        }
        .onAppear {
            buildGraph()
        }
        .onChange(of: store.words) { _, _ in
            buildGraph()
        }
        .onKeyPress(.escape) {
            if focusedNodeId != nil {
                withAnimation(.easeInOut(duration: 0.3)) {
                    focusedNodeId = nil
                }
                return .handled
            }
            return .ignored
        }
    }
    
    private var filteredNodes: [UIGraphNode] {
        let allNodes = createNodes()
        
        var filtered = allNodes
        
        // 如果有聚焦节点，只显示1级链接
        if let focusedId = focusedNodeId {
            let allEdges = createEdges()
            let connectedNodeIds = Set(allEdges.filter { edge in
                edge.source == focusedId || edge.target == focusedId
            }.flatMap { edge in
                [edge.source, edge.target]
            })
            
            // 包含聚焦节点本身和所有1级连接的节点
            filtered = filtered.filter { node in
                connectedNodeIds.contains(node.id)
            }
            
            return filtered
        }
        
        // 按节点类型过滤
        switch selectedNodeType {
        case .all:
            break
        case .wordsOnly:
            filtered = filtered.filter { $0.type == .word }
        case .tagsOnly:
            filtered = filtered.filter { $0.type == .tag }
        case .connected:
            let connectedIds = Set(filteredEdges.flatMap { [$0.source, $0.target] })
            filtered = filtered.filter { connectedIds.contains($0.id) }
        }
        
        // 按标签类型过滤
        if let tagType = selectedTagType {
            filtered = filtered.filter { node in
                if node.type == .tag {
                    return node.tagType == tagType
                } else {
                    // 对于单词节点，检查是否有指定类型的标签
                    return store.words.first { $0.id.uuidString == node.id }?.tags.contains { $0.type == tagType } ?? false
                }
            }
        }
        
        // 按搜索查询过滤
        if !searchQuery.isEmpty {
            filtered = filtered.filter { node in
                node.label.localizedCaseInsensitiveContains(searchQuery) ||
                node.subtitle.localizedCaseInsensitiveContains(searchQuery)
            }
        }
        
        // 如果有通过搜索添加的单词，确保它们总是包含在结果中
        if !addedWordIds.isEmpty {
            let addedNodes = allNodes.filter { node in
                addedWordIds.contains(node.id)
            }
            
            // 合并添加的节点和过滤后的节点，去重
            let combinedNodeIds = Set(filtered.map { $0.id }).union(Set(addedNodes.map { $0.id }))
            filtered = allNodes.filter { combinedNodeIds.contains($0.id) }
        }
        
        // 按节点簇过滤
        if !selectedClusterIds.isEmpty {
            filtered = filtered.filter { node in
                if let clusterId = node.clusterId {
                    return selectedClusterIds.contains(clusterId)
                }
                // 对于没有节点簇的节点，如果没有选中任何节点簇则显示，否则隐藏
                return selectedClusterIds.isEmpty
            }
        }
        
        return filtered
    }
    
    private var filteredEdges: [UIGraphEdge] {
        let nodeIds = Set(filteredNodes.map { $0.id })
        return createEdges().filter { edge in
            nodeIds.contains(edge.source) && nodeIds.contains(edge.target)
        }
    }
    
    private func createNodes() -> [UIGraphNode] {
        var nodes: [UIGraphNode] = []
        
        // 添加单词节点
        for word in store.words {
            let clusterId = getClusterIdForNode(word.id.uuidString)
            nodes.append(UIGraphNode(
                id: word.id.uuidString,
                label: word.text,
                subtitle: word.meaning ?? "",
                type: .word,
                tagType: nil,
                color: .blue,
                clusterId: clusterId
            ))
        }
        
        // 添加标签节点
        let allTags = store.allTags
        for tag in allTags {
            let clusterId = getClusterIdForNode(tag.id.uuidString)
            nodes.append(UIGraphNode(
                id: tag.id.uuidString,
                label: tag.value,
                subtitle: tag.type.displayName,
                type: .tag,
                tagType: tag.type,
                color: Color.from(tagType: tag.type),
                clusterId: clusterId
            ))
        }
        
        return nodes
    }
    
    private func getClusterIdForNode(_ nodeId: String) -> String? {
        return nodeClusters.first { cluster in
            cluster.nodeIds.contains(nodeId)
        }?.id
    }
    
    private func createEdges() -> [UIGraphEdge] {
        var edges: [UIGraphEdge] = []
        
        // 单词-标签连接
        for word in store.words {
            for tag in word.tags {
                edges.append(UIGraphEdge(
                    source: word.id.uuidString,
                    target: tag.id.uuidString,
                    type: .wordTag,
                    weight: 1.0
                ))
            }
        }
        
        // 单词-单词连接（基于共同标签）
        for i in 0..<store.words.count {
            for j in (i+1)..<store.words.count {
                let word1 = store.words[i]
                let word2 = store.words[j]
                
                let commonTags = Set(word1.tags).intersection(Set(word2.tags))
                if !commonTags.isEmpty {
                    let weight = Double(commonTags.count) / Double(max(word1.tags.count, word2.tags.count))
                    edges.append(UIGraphEdge(
                        source: word1.id.uuidString,
                        target: word2.id.uuidString,
                        type: .wordWord,
                        weight: weight
                    ))
                }
            }
        }
        
        return edges
    }
    
    private func buildGraph() {
        isBuilding = true
        
        Task {
            await graphService.buildGraph(from: store.words)
            
            await MainActor.run {
                detectNodeClusters()
                isBuilding = false
            }
        }
    }
    
    // MARK: - Node Cluster Detection
    
    private func detectNodeClusters() {
        let nodes = createNodes()
        let edges = createEdges()
        
        // 构建邻接表
        var adjacencyList: [String: Set<String>] = [:]
        for node in nodes {
            adjacencyList[node.id] = Set<String>()
        }
        
        for edge in edges {
            adjacencyList[edge.source]?.insert(edge.target)
            adjacencyList[edge.target]?.insert(edge.source)
        }
        
        // 使用DFS检测连通分量
        var visited: Set<String> = Set()
        var clusters: [NodeCluster] = []
        let clusterColors: [Color] = [
            Color(red: 0.0, green: 0.48, blue: 1.0),      // 系统蓝色 #007AFF
            Color(red: 1.0, green: 0.23, blue: 0.19),     // 系统红色 #FF3B30
            Color(red: 0.20, green: 0.78, blue: 0.35),    // 系统绿色 #34C759
            Color(red: 1.0, green: 0.58, blue: 0.0),      // 系统橙色 #FF9500
            Color(red: 0.69, green: 0.32, blue: 0.87),    // 系统紫色 #AF52DE
            Color(red: 1.0, green: 0.18, blue: 0.33),     // 系统粉红 #FF2D55
            Color(red: 1.0, green: 0.80, blue: 0.0),      // 系统黄色 #FFCC00
            Color(red: 0.32, green: 0.78, blue: 0.98)     // 系统青色 #50C8F5
        ]
        
        for node in nodes {
            if !visited.contains(node.id) {
                let clusterNodes = dfs(startNode: node.id, adjacencyList: adjacencyList, visited: &visited)
                
                if !clusterNodes.isEmpty {
                    let clusterId = UUID().uuidString
                    let clusterColor = clusterColors[clusters.count % clusterColors.count]
                    
                    let cluster = NodeCluster(
                        id: clusterId,
                        nodeIds: clusterNodes,
                        color: clusterColor
                    )
                    clusters.append(cluster)
                }
            }
        }
        
        nodeClusters = clusters
        // 默认选中所有节点簇
        selectedClusterIds = Set(clusters.map { $0.id })
    }
    
    private func dfs(startNode: String, adjacencyList: [String: Set<String>], visited: inout Set<String>) -> Set<String> {
        var clusterNodes: Set<String> = Set()
        var stack: [String] = [startNode]
        
        while !stack.isEmpty {
            let currentNode = stack.removeLast()
            
            if !visited.contains(currentNode) {
                visited.insert(currentNode)
                clusterNodes.insert(currentNode)
                
                if let neighbors = adjacencyList[currentNode] {
                    for neighbor in neighbors {
                        if !visited.contains(neighbor) {
                            stack.append(neighbor)
                        }
                    }
                }
            }
        }
        
        return clusterNodes
    }
    
    // MARK: - Enhanced Search and Add Functionality
    
    private func addWordsToGraph(_ searchText: String) {
        // 搜索匹配的单词
        let matchingWords = store.words.filter { word in
            word.text.localizedCaseInsensitiveContains(searchText) ||
            (word.meaning?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            word.tags.contains { tag in
                tag.value.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // 将匹配的单词ID添加到已添加列表中
        for word in matchingWords {
            addedWordIds.insert(word.id.uuidString)
        }
        
        // 清空搜索框并重新构建图谱
        withAnimation(.easeInOut(duration: 0.3)) {
            searchQuery = ""
            // 聚焦到第一个匹配的单词（如果有的话）
            if let firstWord = matchingWords.first {
                focusedNodeId = firstWord.id.uuidString
            }
        }
        
        // 重新构建图谱以反映新添加的节点
        detectNodeClusters()
    }
    
    private func clearAddedWords() {
        withAnimation(.easeInOut(duration: 0.3)) {
            addedWordIds.removeAll()
            focusedNodeId = nil
        }
        detectNodeClusters()
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
                .font(.title3)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("• 添加更多单词和标签")
                Text("• 调整过滤器设置")
                Text("• 点击刷新按钮重新构建图谱")
            }
            .font(.body)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Node Cluster Model

struct NodeCluster: Identifiable, Equatable {
    let id: String
    let nodeIds: Set<String>
    let color: Color
    
    static func == (lhs: NodeCluster, rhs: NodeCluster) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - UI Data Models

struct UIGraphNode: Equatable {
    let id: String
    let label: String
    let subtitle: String
    let type: UINodeType
    let tagType: Tag.TagType?
    let color: Color
    let clusterId: String?
    
    enum UINodeType: Equatable {
        case word, tag
    }
    
    static func == (lhs: UIGraphNode, rhs: UIGraphNode) -> Bool {
        return lhs.id == rhs.id
    }
}

struct UIGraphEdge {
    let source: String
    let target: String
    let type: UIEdgeType
    let weight: Double
    
    var id: String {
        return "\(source)-\(target)-\(type.rawValue)"
    }
}

enum UIEdgeType: String {
    case wordTag = "word_tag"
    case wordWord = "word_word"
    case tagTag = "tag_tag"
}

// MARK: - Color Extensions

extension Color {
    func toHexString() -> String {
        // 将SwiftUI Color转换为十六进制字符串
        let nsColor = NSColor(self)
        
        // 如果是目录颜色（catalog color），需要先转换颜色空间
        let rgbColor: NSColor
        if nsColor.colorSpace.colorSpaceModel != .rgb {
            rgbColor = nsColor.usingColorSpace(.sRGB) ?? nsColor
        } else {
            rgbColor = nsColor
        }
        
        // 安全地获取RGB组件
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let redInt = Int(red * 255)
        let greenInt = Int(green * 255)
        let blueInt = Int(blue * 255)
        
        return String(format: "#%02X%02X%02X", redInt, greenInt, blueInt)
    }
}

// MARK: - Vector Extensions

extension CGVector {
    static let zero = CGVector(dx: 0, dy: 0)
    
    static func + (lhs: CGVector, rhs: CGVector) -> CGVector {
        return CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
    }
    
    static func * (vector: CGVector, scalar: Double) -> CGVector {
        return CGVector(dx: vector.dx * scalar, dy: vector.dy * scalar)
    }
    
    static func * (vector: CGVector, scalar: CGFloat) -> CGVector {
        return CGVector(dx: vector.dx * scalar, dy: vector.dy * scalar)
    }
}

#Preview {
    GraphView()
        .environmentObject(WordStore.shared)
}
