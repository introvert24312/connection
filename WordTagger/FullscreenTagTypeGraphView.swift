import SwiftUI

// MARK: - 全屏标签类型图谱视图

struct FullscreenTagTypeGraphView: View {
    let tagType: Tag.TagType
    @EnvironmentObject private var store: NodeStore
    @State private var graphData: TagTypeGraphData?
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            toolbar
            
            Divider()
            
            // 图谱主体
            if isLoading {
                loadingView
            } else if let data = graphData {
                // 使用现有的WebKit-based图谱系统
                TagTypeWebGraphView(data: data)
            } else {
                emptyStateView
            }
        }
        .navigationTitle("标签类型图谱: \(tagType.displayName)")
        .onAppear {
            print("📊 FullscreenTagTypeGraphView appeared for: \(tagType.displayName)")
            loadGraphData()
        }
    }
    
    // MARK: - 子视图
    
    private var toolbar: some View {
        HStack {
            Text("标签类型图谱: \(tagType.displayName)")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("重新加载") { 
                    loadGraphData()
                }
                .disabled(isLoading)
                
                Button("适应画布") { 
                    // TODO: 调用WebKit图谱的适应画布功能
                    print("🔄 适应画布")
                }
                .disabled(graphData == nil)
            }
        }
        .padding()
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("正在加载标签类型图谱...")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "network.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("暂无图谱数据")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            
            Text("该标签类型下没有可用的节点关系")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 数据加载
    
    private func loadGraphData() {
        isLoading = true
        
        Task { @MainActor in
            let data = store.getTagTypeGraphData(for: tagType)
            self.graphData = data
            self.isLoading = false
            print("🕸️ 图谱数据加载完成: \(tagType.displayName), 标签值数量: \(data.tagValues.count)")
        }
    }
}

// MARK: - WebKit-based 标签类型图谱

struct TagTypeWebGraphView: View {
    let data: TagTypeGraphData
    
    var body: some View {
        // 这里我们将复用现有的WebKit图谱引擎
        // 但是适配为标签类型图谱的数据结构
        TagTypeGraphCanvasView(data: data)
    }
}

// MARK: - 画布视图（使用现有图谱引擎）

struct TagTypeGraphCanvasView: View {
    let data: TagTypeGraphData
    @State private var selectedNode: TagValueNode?
    @State private var hoveredNode: TagValueNode?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景
                Color(NSColor.windowBackgroundColor)
                
                // 这里将使用现有的图谱引擎，但数据结构需要适配
                // 暂时使用原有的SwiftUI实现，后续可以改为WebKit版本
                TagTypeGraphLayer(
                    data: data,
                    selectedNode: $selectedNode,
                    hoveredNode: $hoveredNode,
                    canvasSize: geometry.size
                )
                
                // 信息面板
                if let selected = selectedNode {
                    TagTypeInfoPanel(tagValue: selected)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 图谱渲染层（全屏优化版本）

struct TagTypeGraphLayer: View {
    let data: TagTypeGraphData
    @Binding var selectedNode: TagValueNode?
    @Binding var hoveredNode: TagValueNode?
    let canvasSize: CGSize
    
    // 适配全屏的布局参数（更大的间距）
    private let centerRadius: CGFloat = 100
    private let tagValueRadius: CGFloat = 280
    private let contentNodeRadius: CGFloat = 450
    
    @State private var hoveredContentNode: Node?
    
    var body: some View {
        ZStack {
            // 连接线（保持原有逻辑）
            ForEach(data.tagValues.indices, id: \.self) { index in
                let tagValue = data.tagValues[index]
                let angle = angleForIndex(index, total: data.tagValues.count)
                let tagValuePos = positionForTagValue(angle: angle, canvasSize: canvasSize)
                let isValueHovered = hoveredNode?.value == tagValue.value
                
                // 中心到标签值的连接线
                Path { path in
                    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    path.move(to: center)
                    path.addLine(to: tagValuePos)
                }
                .stroke(isValueHovered ? Color.blue.opacity(0.6) : Color.secondary.opacity(0.3), lineWidth: isValueHovered ? 3 : 2)
                .animation(.easeInOut(duration: 0.2), value: isValueHovered)
                
                // 标签值到内容节点的连接线
                ForEach(Array(tagValue.nodes.prefix(8).enumerated()), id: \.offset) { nodeIndex, node in
                    let nodeAngle = angle + (Double(nodeIndex - 4) * 0.15)  // 更密集的展开角度
                    let nodePos = positionForContentNode(angle: nodeAngle, canvasSize: canvasSize)
                    let isNodeHovered = hoveredContentNode?.id == node.id
                    
                    Path { path in
                        path.move(to: tagValuePos)
                        path.addLine(to: nodePos)
                    }
                    .stroke(
                        isNodeHovered ? Color.green.opacity(0.8) : 
                        isValueHovered ? Color.blue.opacity(0.4) : 
                        Color.secondary.opacity(0.25), 
                        lineWidth: isNodeHovered ? 2 : (isValueHovered ? 1.5 : 1)
                    )
                    .animation(.easeInOut(duration: 0.2), value: isNodeHovered)
                    .animation(.easeInOut(duration: 0.2), value: isValueHovered)
                }
            }
            
            // 中心节点（标签类型）- 全屏版本更大
            FullscreenCenterNode(tagType: data.tagType, position: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2))
            
            // 标签值节点
            ForEach(data.tagValues.indices, id: \.self) { index in
                let tagValue = data.tagValues[index]
                let angle = angleForIndex(index, total: data.tagValues.count)
                let position = positionForTagValue(angle: angle, canvasSize: canvasSize)
                
                FullscreenTagValueNodeView(
                    tagValue: tagValue,
                    position: position,
                    isSelected: selectedNode?.value == tagValue.value,
                    isHovered: hoveredNode?.value == tagValue.value
                )
                .contentShape(Circle().size(width: 120, height: 120))
                .onTapGesture {
                    selectedNode = selectedNode?.value == tagValue.value ? nil : tagValue
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hoveredNode = hovering ? tagValue : nil
                    }
                }
                
                // 内容节点（每个标签值显示前8个）
                ForEach(Array(tagValue.nodes.prefix(8).enumerated()), id: \.offset) { nodeIndex, node in
                    let nodeAngle = angle + (Double(nodeIndex - 4) * 0.15)
                    let nodePos = positionForContentNode(angle: nodeAngle, canvasSize: canvasSize)
                    
                    FullscreenContentNodeView(
                        node: node, 
                        position: nodePos,
                        isHovered: hoveredContentNode?.id == node.id
                    )
                    .contentShape(Circle().size(width: 60, height: 60))
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredContentNode = hovering ? node : nil
                        }
                    }
                    .onTapGesture {
                        print("🖱️ 点击内容节点: \(String(node.text.prefix(20)))")
                        // TODO: 可以添加选中节点并导航到主窗口的功能
                    }
                }
            }
        }
    }
    
    // MARK: - 布局计算
    
    private func angleForIndex(_ index: Int, total: Int) -> Double {
        return Double(index) * 2 * .pi / Double(total)
    }
    
    private func positionForTagValue(angle: Double, canvasSize: CGSize) -> CGPoint {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * tagValueRadius,
            y: center.y + CGFloat(sin(angle)) * tagValueRadius
        )
    }
    
    private func positionForContentNode(angle: Double, canvasSize: CGSize) -> CGPoint {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * contentNodeRadius,
            y: center.y + CGFloat(sin(angle)) * contentNodeRadius
        )
    }
}

// MARK: - 全屏版本的节点组件

struct FullscreenCenterNode: View {
    let tagType: Tag.TagType
    let position: CGPoint
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(Color.from(tagType: tagType))
                .frame(width: 80, height: 80)  // 更大的中心节点
                .scaleEffect(pulseScale)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .shadow(radius: 3)
                        .scaleEffect(pulseScale)
                )
                .overlay(
                    Circle()
                        .stroke(Color.from(tagType: tagType).opacity(0.3), lineWidth: 12)
                        .scaleEffect(pulseScale * 1.15)
                        .opacity(0.6)
                )
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                        pulseScale = 1.08
                    }
                }
            
            Text(tagType.displayName)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.regularMaterial)
                        .shadow(radius: 2)
                )
        }
        .position(position)
    }
}

struct FullscreenTagValueNodeView: View {
    let tagValue: TagValueNode
    let position: CGPoint
    let isSelected: Bool
    let isHovered: Bool
    
    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(isSelected ? Color.blue : (isHovered ? Color.blue.opacity(0.7) : Color.gray))
                .frame(width: isSelected || isHovered ? 50 : 42, height: isSelected || isHovered ? 50 : 42)  // 更大的标签值节点
                .overlay(
                    Text("\(tagValue.usageCount)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                )
            
            Text(tagValue.value)
                .font(.system(size: 16, weight: isSelected ? .semibold : .medium))  // 更大的字体
                .foregroundColor(isSelected ? .blue : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.regularMaterial)
                        .opacity(isSelected || isHovered ? 1.0 : 0.85)
                        .shadow(radius: isSelected || isHovered ? 2 : 1)
                )
        }
        .scaleEffect(isSelected || isHovered ? 1.2 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0), value: isSelected)
        .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0), value: isHovered)
        .position(position)
    }
}

struct FullscreenContentNodeView: View {
    let node: Node
    let position: CGPoint
    let isHovered: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            // 主节点圆圈
            Circle()
                .fill(isHovered ? Color.green.opacity(0.8) : Color.secondary.opacity(0.5))
                .frame(width: isHovered ? 24 : 20, height: isHovered ? 24 : 20)  // 更大的内容节点
                .overlay(
                    Circle()
                        .stroke(isHovered ? Color.green : Color.secondary, lineWidth: isHovered ? 2 : 1)
                )
                .scaleEffect(isHovered ? 1.3 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
            
            // 节点名称 - 始终显示，全屏版本更清晰
            Text(String(node.text.prefix(25)) + (node.text.count > 25 ? "..." : ""))
                .font(.system(size: 12, weight: isHovered ? .semibold : .medium))
                .foregroundColor(isHovered ? .green : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.regularMaterial)
                        .opacity(isHovered ? 1.0 : 0.9)
                        .shadow(radius: isHovered ? 3 : 1)
                )
                .scaleEffect(isHovered ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .position(position)
    }
}

// MARK: - 全屏版本的信息面板

struct TagTypeInfoPanel: View {
    let tagValue: TagValueNode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 头部信息
            HStack {
                Text("标签值: \(tagValue.value)")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Text("\(tagValue.usageCount) 个节点")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            
            Text("关联节点:")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            
            // 节点列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(tagValue.nodes.prefix(15), id: \.id) { node in
                        HStack {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                            
                            Text(String(node.text.prefix(60)))
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            Spacer()
                        }
                    }
                    
                    if tagValue.nodes.count > 15 {
                        Text("还有 \(tagValue.nodes.count - 15) 个节点...")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(radius: 12)
        )
        .frame(maxWidth: 400)
        .position(x: 300, y: 150)  // 固定在左上角
    }
}