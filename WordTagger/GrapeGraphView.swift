import SwiftUI
import Foundation

// MARK: - Grape Graph View

struct GrapeGraphView: View {
    @EnvironmentObject private var store: WordStore
    @StateObject private var grapeGraphService = GrapeGraphService.shared
    @State private var selectedNodeId: String? = nil
    
    var body: some View {
        ZStack {
            Color(NSColor.controlBackgroundColor)
            
            if grapeGraphService.nodes.isEmpty {
                VStack {
                    Text("图谱为空")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Button("重新构建") {
                        buildGraph()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                SimpleGraphView(
                    nodes: grapeGraphService.nodes,
                    edges: grapeGraphService.edges,
                    selectedNodeId: selectedNodeId,
                    onNodeSelect: { nodeId in
                        selectedNodeId = nodeId
                    }
                )
            }
        }
        .onAppear {
            buildGraph()
        }
        .onChange(of: store.words) { _, _ in
            buildGraph()
        }
    }
    
    
    private func buildGraph() {
        Task {
            await grapeGraphService.buildGraph(from: store.words)
        }
    }
}

// MARK: - Simple Graph View

struct SimpleGraphView: View {
    let nodes: [GrapeNode]
    let edges: [GrapeEdge]
    let selectedNodeId: String?
    let onNodeSelect: (String?) -> Void
    
    @State private var nodePositions: [String: CGPoint] = [:]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                edgesLayer
                nodesLayer(geometry)
            }
        }
        .onAppear { setupPositions() }
    }
    
    private var edgesLayer: some View {
        ForEach(edges, id: \.id) { edge in
            if let sourcePos = nodePositions[edge.source],
               let targetPos = nodePositions[edge.target] {
                Path { path in
                    path.move(to: sourcePos)
                    path.addLine(to: targetPos)
                }
                .stroke(edge.color, lineWidth: CGFloat(edge.width))
            }
        }
    }
    
    private func nodesLayer(_ geometry: GeometryProxy) -> some View {
        ForEach(nodes, id: \.id) { node in
            nodeView(node, geometry)
        }
    }
    
    private func nodeView(_ node: GrapeNode, _ geometry: GeometryProxy) -> some View {
        Circle()
            .fill(node.color)
            .frame(width: CGFloat(node.radius * 2), height: CGFloat(node.radius * 2))
            .overlay(
                Text(node.content)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
            )
            .overlay(
                Circle()
                    .stroke(selectedNodeId == node.id ? Color.blue : Color.clear, lineWidth: 3)
            )
            .position(nodePositions[node.id] ?? CGPoint(x: 100, y: 100))
            .onTapGesture {
                onNodeSelect(selectedNodeId == node.id ? nil : node.id)
            }
    }
    
    private func setupPositions() {
        guard !nodes.isEmpty else { return }
        let center = CGPoint(x: 400, y: 300)
        let radius: CGFloat = 150
        
        for (index, node) in nodes.enumerated() {
            let angle = (CGFloat(index) / CGFloat(nodes.count)) * 2 * .pi
            nodePositions[node.id] = CGPoint(
                x: center.x + radius * CoreGraphics.cos(angle),
                y: center.y + radius * CoreGraphics.sin(angle)
            )
        }
    }
}


// MARK: - Grape Graph Service

class GrapeGraphService: ObservableObject {
    static let shared = GrapeGraphService()
    
    @Published var nodes: [GrapeNode] = []
    @Published var edges: [GrapeEdge] = []
    
    private init() {}
    
    func buildGraph(from words: [Word]) async {
        await MainActor.run {
            buildNodes(from: words)
            buildEdges(from: words)
        }
    }
    
    private func buildNodes(from words: [Word]) {
        var newNodes: [GrapeNode] = []
        
        // 添加单词节点
        for word in words {
            newNodes.append(GrapeNode(
                id: word.id.uuidString,
                content: word.text,
                type: .word,
                tagType: nil,
                color: Color(.systemBlue),
                radius: 25,
                position: CGPoint.zero,
                velocity: CGVector.zero
            ))
        }
        
        // 添加标签节点
        let allTags = words.flatMap { $0.tags }.unique()
        for tag in allTags {
            newNodes.append(GrapeNode(
                id: tag.id.uuidString,
                content: tag.value,
                type: .tag,
                tagType: tag.type,
                color: Color.from(tagType: tag.type),
                radius: 20,
                position: CGPoint.zero,
                velocity: CGVector.zero
            ))
        }
        
        nodes = newNodes
    }
    
    private func buildEdges(from words: [Word]) {
        var newEdges: [GrapeEdge] = []
        
        // 单词-标签连接
        for word in words {
            for tag in word.tags {
                newEdges.append(GrapeEdge(
                    source: word.id.uuidString,
                    target: tag.id.uuidString,
                    color: Color(.systemBlue).opacity(0.6),
                    width: 2.0
                ))
            }
        }
        
        // 单词-单词连接（基于共同标签）
        for i in 0..<words.count {
            for j in (i+1)..<words.count {
                let word1 = words[i]
                let word2 = words[j]
                
                let commonTags = Set(word1.tags).intersection(Set(word2.tags))
                if !commonTags.isEmpty {
                    let weight = Double(commonTags.count) / Double(max(word1.tags.count, word2.tags.count))
                    newEdges.append(GrapeEdge(
                        source: word1.id.uuidString,
                        target: word2.id.uuidString,
                        color: Color(.systemGreen).opacity(0.5),
                        width: 1.5 * weight
                    ))
                }
            }
        }
        
        edges = newEdges
    }
}

// MARK: - Grape Data Models

struct GrapeNode: Identifiable, Equatable {
    let id: String
    let content: String
    let type: NodeDataType
    let tagType: Tag.TagType?
    let color: Color
    let radius: Double
    var position: CGPoint
    var velocity: CGVector
    
    enum NodeDataType {
        case word, tag
    }
    
    static func == (lhs: GrapeNode, rhs: GrapeNode) -> Bool {
        return lhs.id == rhs.id
    }
}

struct GrapeEdge: Identifiable {
    let source: String
    let target: String
    let color: Color
    let width: Double
    
    var id: String {
        return "\(source)-\(target)"
    }
}


#Preview {
    GrapeGraphView()
        .environmentObject(WordStore.shared)
}