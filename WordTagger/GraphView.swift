import SwiftUI

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
                
                Button(action: { showingFilters.toggle() }) {
                    Image(systemName: showingFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .foregroundColor(.blue)
                }
                .help("切换过滤器")
                
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
            
            HStack(spacing: 0) {
                // 过滤侧栏
                if showingFilters {
                    FilterSidebar(
                        selectedNodeType: $selectedNodeType,
                        selectedTagType: $selectedTagType,
                        nodeSize: $nodeSize
                    )
                    .frame(width: 250)
                    
                    Divider()
                }
                
                // 图谱主体
                VStack {
                    ZStack {
                        if filteredNodes.isEmpty {
                            EmptyGraphView()
                        } else {
                            GraphCanvas(
                                nodes: filteredNodes,
                                edges: filteredEdges,
                                nodeSize: nodeSize,
                                searchQuery: searchQuery,
                                selectedNodeId: selectedNodeId,
                                onNodeSelect: { nodeId in
                                    selectedNodeId = nodeId
                                },
                                onNodeFocus: { nodeId in
                                    focusedNodeId = nodeId
                                }
                            )
                        }
                    }
                    
                    // 操作提示
                    if focusedNodeId == nil {
                        HStack {
                            Text("💡 点击选中节点，再次点击进入1级链接视图")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
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

// MARK: - Filter Sidebar

struct FilterSidebar: View {
    @Binding var selectedNodeType: GraphView.NodeType
    @Binding var selectedTagType: Tag.TagType?
    @Binding var nodeSize: Double
    @EnvironmentObject private var store: WordStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("过滤器")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("节点类型")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ForEach(GraphView.NodeType.allCases, id: \.self) { type in
                    HStack {
                        Button(action: {
                            selectedNodeType = type
                        }) {
                            HStack {
                                Image(systemName: selectedNodeType == type ? "circle.fill" : "circle")
                                    .foregroundColor(.blue)
                                Text(type.rawValue)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("标签类型")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if selectedTagType != nil {
                        Button("清除") {
                            selectedTagType = nil
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                
                ForEach(Tag.TagType.allCases, id: \.self) { type in
                    HStack {
                        Button(action: {
                            selectedTagType = selectedTagType == type ? nil : type
                        }) {
                            HStack {
                                Circle()
                                    .fill(Color.from(tagType: type))
                                    .frame(width: 12, height: 12)
                                
                                Text(type.displayName)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Text("\(store.wordsCount(forTagType: type))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color.gray.opacity(0.15))
                                    )
                                
                                if selectedTagType == type {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("视图设置")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Image(systemName: "circle.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("极简模式")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("简洁的球形节点，直线连接")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("手势操作")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "hand.draw")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text("拖拽平移")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text("捏合缩放")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding(.vertical)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Graph Canvas

struct GraphCanvas: View {
    let nodes: [UIGraphNode]
    let edges: [UIGraphEdge]
    let nodeSize: Double
    let searchQuery: String
    let selectedNodeId: String?
    let onNodeSelect: (String?) -> Void
    let onNodeFocus: (String) -> Void
    
    @State private var nodePositions: [String: CGPoint] = [:]
    @State private var nodeVelocities: [String: CGVector] = [:]
    @State private var canvasSize: CGSize = .zero
    @State private var draggedNode: String?
    @State private var dragStartPositions: [String: CGPoint] = [:]
    @State private var animationTimer: Timer?
    
    // 缩放和平移状态
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    private let springForce: Double = 0.08
    private let repulsionForce: Double = 8000
    private let damping: Double = 0.85
    private let centerForce: Double = 0.005
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景 - 使用系统适应性颜色
                Rectangle()
                    .fill(Color(NSColor.controlBackgroundColor))
                
                ZStack {
                    // 弹性实时连接线
                    ForEach(edges, id: \.id) { edge in
                        if let sourcePos = nodePositions[edge.source],
                           let targetPos = nodePositions[edge.target] {
                            ElasticConnectionView(
                                from: sourcePos,
                                to: targetPos,
                                type: edge.type,
                                weight: edge.weight,
                                nodeSize: nodeSize,
                                isDragging: draggedNode == edge.source || draggedNode == edge.target
                            )
                        }
                    }
                    
                    // 节点
                    ForEach(nodes, id: \.id) { node in
                        if let position = nodePositions[node.id] {
                            self.createNodeView(
                                node: node,
                                position: position,
                                geometry: geometry
                            )
                        }
                    }
                }
                .scaleEffect(scale)
                .offset(offset)
            }
            .clipped()
            .gesture(
                SimultaneousGesture(
                    // 缩放手势
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(0.5, min(3.0, lastScale * value))
                        }
                        .onEnded { value in
                            lastScale = max(0.5, min(3.0, lastScale * value))
                            scale = lastScale
                        },
                    // 平移手势
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
            )
            .onAppear {
                setupInitialPositions(in: geometry.size)
                startAnimation()
            }
            .onDisappear {
                stopAnimation()
            }
            .onChange(of: nodes) { _, _ in
                setupInitialPositions(in: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                if canvasSize != newSize {
                    canvasSize = newSize
                    updatePositionsForNewSize(newSize)
                }
            }
        }
    }
    
    private func setupInitialPositions(in size: CGSize) {
        guard !nodes.isEmpty else { return }
        
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.3
        
        // 随机初始位置，但保持在合理范围内
        var positions: [String: CGPoint] = [:]
        var velocities: [String: CGVector] = [:]
        
        for (index, node) in nodes.enumerated() {
            let angle = Double(index) * 2 * .pi / Double(nodes.count)
            let x = center.x + CGFloat(cos(angle)) * radius * CGFloat.random(in: 0.5...1.5)
            let y = center.y + CGFloat(sin(angle)) * radius * CGFloat.random(in: 0.5...1.5)
            
            positions[node.id] = constrainToBounds(CGPoint(x: x, y: y), in: size)
            velocities[node.id] = CGVector.zero
        }
        
        nodePositions = positions
        nodeVelocities = velocities
        canvasSize = size
    }
    
    private func updatePositionsForNewSize(_ size: CGSize) {
        let oldSize = canvasSize
        guard oldSize.width > 0 && oldSize.height > 0 else {
            setupInitialPositions(in: size)
            return
        }
        
        let scaleX = size.width / oldSize.width
        let scaleY = size.height / oldSize.height
        
        for (nodeId, position) in nodePositions {
            let newPosition = CGPoint(
                x: position.x * scaleX,
                y: position.y * scaleY
            )
            nodePositions[nodeId] = constrainToBounds(newPosition, in: size)
        }
        
        canvasSize = size
    }
    
    private func createNodeView(node: UIGraphNode, position: CGPoint, geometry: GeometryProxy) -> some View {
        let isHighlighted = !searchQuery.isEmpty && 
            (node.label.localizedCaseInsensitiveContains(searchQuery) || 
             node.subtitle.localizedCaseInsensitiveContains(searchQuery))
        
        return MinimalNodeView(
            node: node,
            size: nodeSize,
            isSelected: selectedNodeId == node.id,
            isHighlighted: isHighlighted,
            isDragging: draggedNode == node.id,
            onTap: {
                // 双击功能：聚焦到该节点的1级链接
                if selectedNodeId == node.id {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        onNodeFocus(node.id)
                        onNodeSelect(nil)
                    }
                } else {
                    onNodeSelect(node.id)
                }
            },
            onDragStart: {
                draggedNode = node.id
                dragStartPositions[node.id] = nodePositions[node.id]
            },
            onDragChange: { translation in
                if let startPosition = dragStartPositions[node.id] {
                    let newPosition = CGPoint(
                        x: startPosition.x + translation.width,
                        y: startPosition.y + translation.height
                    )
                    // 实时更新位置以确保连接线跟随
                    nodePositions[node.id] = constrainToBounds(newPosition, in: geometry.size)
                }
            },
            onDragEnd: { translation in
                draggedNode = nil
                dragStartPositions.removeValue(forKey: node.id)
            }
        )
        .position(position)
    }
    
    private func constrainToBounds(_ position: CGPoint, in size: CGSize) -> CGPoint {
        let radius = nodeSize / 2
        let padding: CGFloat = 20
        
        return CGPoint(
            x: max(radius + padding, min(size.width - radius - padding, position.x)),
            y: max(radius + padding, min(size.height - radius - padding, position.y))
        )
    }
    
    private func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) { _ in
            updatePhysics()
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    private func updatePhysics() {
        guard !nodes.isEmpty && canvasSize != .zero else { return }
        
        var newPositions = nodePositions
        var newVelocities = nodeVelocities
        
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        
        for node in nodes {
            guard let currentPos = nodePositions[node.id],
                  let currentVel = nodeVelocities[node.id],
                  draggedNode != node.id else { continue }
            
            var force = CGVector.zero
            
            // 中心引力
            let centerVector = CGVector(
                dx: center.x - currentPos.x,
                dy: center.y - currentPos.y
            )
            force = force + centerVector * centerForce
            
            // 节点间斥力
            for otherNode in nodes {
                guard otherNode.id != node.id,
                      let otherPos = nodePositions[otherNode.id] else { continue }
                
                let dx = currentPos.x - otherPos.x
                let dy = currentPos.y - otherPos.y
                let distance = max(1, sqrt(dx * dx + dy * dy))
                
                let repulsion = repulsionForce / (distance * distance)
                force = force + CGVector(
                    dx: (dx / distance) * repulsion,
                    dy: (dy / distance) * repulsion
                )
            }
            
            // 连接的弹簧力
            for edge in edges {
                var connectedNodeId: String?
                if edge.source == node.id {
                    connectedNodeId = edge.target
                } else if edge.target == node.id {
                    connectedNodeId = edge.source
                }
                
                if let connectedId = connectedNodeId,
                   let connectedPos = nodePositions[connectedId] {
                    let dx = connectedPos.x - currentPos.x
                    let dy = connectedPos.y - currentPos.y
                    let distance = sqrt(dx * dx + dy * dy)
                    let idealDistance: CGFloat = 180
                    
                    let spring = (distance - idealDistance) * springForce
                    force = force + CGVector(
                        dx: (dx / max(1, distance)) * spring,
                        dy: (dy / max(1, distance)) * spring
                    )
                }
            }
            
            // 更新速度和位置
            let newVel = (currentVel + force) * damping
            newVelocities[node.id] = newVel
            
            let newPos = CGPoint(
                x: currentPos.x + newVel.dx,
                y: currentPos.y + newVel.dy
            )
            newPositions[node.id] = constrainToBounds(newPos, in: canvasSize)
        }
        
        nodePositions = newPositions
        nodeVelocities = newVelocities
    }
}

// MARK: - Minimal Node View

struct MinimalNodeView: View {
    let node: UIGraphNode
    let size: Double
    let isSelected: Bool
    let isHighlighted: Bool
    let isDragging: Bool
    let onTap: () -> Void
    let onDragStart: () -> Void
    let onDragChange: (CGSize) -> Void
    let onDragEnd: (CGSize) -> Void
    
    private var macOSNodeColor: Color {
        switch node.type {
        case .word:
            // System semantic colors for better accessibility and dark mode support
            return Color(.systemBlue)
        case .tag:
            // Use semantic colors for different tag types
            if let tagType = node.tagType {
                switch tagType {
                case .memory: return Color(.systemPink)
                case .location: return Color(.systemGreen) 
                case .root: return Color(.systemOrange)
                case .shape: return Color(.systemPurple)
                case .sound: return Color(.systemYellow)
                case .custom: return Color(.systemGray)
                }
            } else {
                return Color(.systemPink)
            }
        }
    }
    
    var body: some View {
        ZStack {
            // 加大的圆形节点，使用macOS配色
            Circle()
                .fill(macOSNodeColor)
                .frame(width: size * 2.8, height: size * 2.8) // 增大180%
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? Color(.controlAccentColor) : Color.clear,
                            lineWidth: 3
                        )
                )
                .scaleEffect(isDragging ? 1.1 : 1.0)
                .shadow(
                    color: Color.black.opacity(0.15),
                    radius: isHighlighted || isDragging ? 4 : 2,
                    x: 0,
                    y: 1
                )
            
            // 始终显示的文字标签 - 使用苹果系统字体和动态颜色
            Text(node.label)
                .font(.system(size: size * 0.6, weight: .semibold, design: .default))
                .foregroundColor(.white)  // 在彩色节点上使用白色文字
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .shadow(color: Color.black.opacity(0.4), radius: 1.5, x: 0, y: 1)
                .allowsHitTesting(false) // 防止文字阻挡点击
        }
        .contentShape(Circle()) // 确保整个圆形区域可点击
        .onTapGesture {
            onTap()
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    onDragChange(value.translation)
                }
                .onEnded { value in
                    onDragEnd(value.translation)
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    onDragStart()
                }
        )
        .animation(.easeInOut(duration: 0.2), value: isHighlighted)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
    }
}

// MARK: - Elastic Connection View

struct ElasticConnectionView: View {
    let from: CGPoint
    let to: CGPoint
    let type: UIEdgeType
    let weight: Double
    let nodeSize: Double
    let isDragging: Bool
    
    @State private var animatedControlPoint1: CGPoint = .zero
    @State private var animatedControlPoint2: CGPoint = .zero
    @State private var animatedStartPoint: CGPoint = .zero
    @State private var animatedEndPoint: CGPoint = .zero
    
    private var connectionPoints: (start: CGPoint, end: CGPoint, control1: CGPoint, control2: CGPoint) {
        let direction = CGVector(dx: to.x - from.x, dy: to.y - from.y)
        let length = max(1, sqrt(direction.dx * direction.dx + direction.dy * direction.dy))
        
        let unitDirection = CGVector(dx: direction.dx / length, dy: direction.dy / length)
        let offset = nodeSize * 1.4 // 稍微增大偏移以避免节点重叠
        
        let start = CGPoint(
            x: from.x + unitDirection.dx * offset,
            y: from.y + unitDirection.dy * offset
        )
        let end = CGPoint(
            x: to.x - unitDirection.dx * offset,
            y: to.y - unitDirection.dy * offset
        )
        
        // 创建弹性控制点 - 使用三次贝塞尔曲线获得更自然的弯曲
        let distance = length
        let controlDistance = distance * 0.3 // 控制点距离
        
        // 垂直方向创建自然弯曲
        let perpendicular = CGVector(dx: -unitDirection.dy, dy: unitDirection.dx)
        let curvature: CGFloat = min(distance * 0.15, 40) // 更温和的弯曲
        
        let control1 = CGPoint(
            x: start.x + unitDirection.dx * controlDistance + perpendicular.dx * curvature,
            y: start.y + unitDirection.dy * controlDistance + perpendicular.dy * curvature
        )
        
        let control2 = CGPoint(
            x: end.x - unitDirection.dx * controlDistance + perpendicular.dx * curvature,
            y: end.y - unitDirection.dy * controlDistance + perpendicular.dy * curvature
        )
        
        return (start, end, control1, control2)
    }
    
    var body: some View {
        let points = connectionPoints
        
        ZStack {
            // 主连接线 - 使用三次贝塞尔曲线
            Path { path in
                path.move(to: animatedStartPoint == .zero ? points.start : animatedStartPoint)
                path.addCurve(
                    to: animatedEndPoint == .zero ? points.end : animatedEndPoint,
                    control1: animatedControlPoint1 == .zero ? points.control1 : animatedControlPoint1,
                    control2: animatedControlPoint2 == .zero ? points.control2 : animatedControlPoint2
                )
            }
            .stroke(
                connectionColor,
                style: StrokeStyle(
                    lineWidth: dynamicLineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .shadow(color: connectionColor.opacity(0.3), radius: 1, x: 0, y: 0.5)
            
            // 拖拽时的高亮效果
            if isDragging {
                Path { path in
                    path.move(to: animatedStartPoint == .zero ? points.start : animatedStartPoint)
                    path.addCurve(
                        to: animatedEndPoint == .zero ? points.end : animatedEndPoint,
                        control1: animatedControlPoint1 == .zero ? points.control1 : animatedControlPoint1,
                        control2: animatedControlPoint2 == .zero ? points.control2 : animatedControlPoint2
                    )
                }
                .stroke(
                    Color.blue.opacity(0.4),
                    style: StrokeStyle(
                        lineWidth: dynamicLineWidth + 1,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .blur(radius: 1)
            }
        }
        .onChange(of: points.start) { _, newValue in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.1)) {
                animatedStartPoint = newValue
            }
        }
        .onChange(of: points.end) { _, newValue in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.1)) {
                animatedEndPoint = newValue
            }
        }
        .onChange(of: points.control1) { _, newValue in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.1)) {
                animatedControlPoint1 = newValue
            }
        }
        .onChange(of: points.control2) { _, newValue in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.1)) {
                animatedControlPoint2 = newValue
            }
        }
        .onAppear {
            // 初始化动画点位
            animatedStartPoint = points.start
            animatedEndPoint = points.end
            animatedControlPoint1 = points.control1
            animatedControlPoint2 = points.control2
        }
    }
    
    private var dynamicLineWidth: CGFloat {
        let baseWidth: CGFloat = 1.8
        let weightMultiplier = CGFloat(weight * 0.8 + 0.2) // 0.2 to 1.0 range
        return baseWidth * weightMultiplier
    }
    
    private var connectionColor: Color {
        switch type {
        case .wordTag:
            return Color.blue.opacity(0.6)
        case .wordWord:
            return Color.green.opacity(0.5)
        case .tagTag:
            return Color.purple.opacity(0.5)
        }
    }
}

struct ArrowHead: View {
    let at: CGPoint
    let pointing: CGPoint
    let color: Color
    let opacity: Double
    
    var body: some View {
        let direction = CGVector(dx: at.x - pointing.x, dy: at.y - pointing.y)
        let length = sqrt(direction.dx * direction.dx + direction.dy * direction.dy)
        guard length > 0 else { return AnyView(EmptyView()) }
        
        let angle = atan2(direction.dy, direction.dx)
        let arrowSize: CGFloat = 8
        
        return AnyView(
            Path { path in
                path.move(to: at)
                path.addLine(to: CGPoint(
                    x: at.x - arrowSize * cos(angle - .pi / 6),
                    y: at.y - arrowSize * sin(angle - .pi / 6)
                ))
                path.move(to: at)
                path.addLine(to: CGPoint(
                    x: at.x - arrowSize * cos(angle + .pi / 6),
                    y: at.y - arrowSize * sin(angle + .pi / 6)
                ))
            }
            .stroke(color.opacity(opacity), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        )
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
