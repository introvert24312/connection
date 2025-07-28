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
                    Text("关系图谱")
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
                
                Spacer()
                
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("搜索单词或标签...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .frame(width: 200)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                
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
                                GraphNodeAdapter(
                                    id: node.id.hashValue,
                                    label: node.label,
                                    subtitle: node.subtitle.isEmpty ? nil : node.subtitle
                                )
                            },
                            edges: filteredEdges.map { edge in
                                GraphEdgeAdapter(
                                    fromId: edge.source.hashValue,
                                    toId: edge.target.hashValue,
                                    label: edge.type.rawValue
                                )
                            },
                            title: "单词关系图谱"
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
            nodes.append(UIGraphNode(
                id: word.id.uuidString,
                label: word.text,
                subtitle: word.meaning ?? "",
                type: .word,
                tagType: nil,
                color: .blue
            ))
        }
        
        // 添加标签节点
        let allTags = store.allTags
        for tag in allTags {
            nodes.append(UIGraphNode(
                id: tag.id.uuidString,
                label: tag.value,
                subtitle: tag.type.displayName,
                type: .tag,
                tagType: tag.type,
                color: Color.from(tagType: tag.type)
            ))
        }
        
        return nodes
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
                isBuilding = false
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

// MARK: - UI Data Models

struct UIGraphNode: Equatable {
    let id: String
    let label: String
    let subtitle: String
    let type: UINodeType
    let tagType: Tag.TagType?
    let color: Color
    
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
