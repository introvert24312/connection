import SwiftUI

// MARK: - 数据模型

struct TagTypeGraphData {
    let tagType: Tag.TagType
    let tagValues: [TagValueNode]
}

struct TagValueNode {
    let value: String
    let nodes: [Node]
    let usageCount: Int
}

enum TagGraphNodeType {
    case tagType(Tag.TagType)           // 中心节点
    case tagValue(String, Int)          // 标签值节点 (值, 使用次数)
    case contentNode(Node)              // 内容节点
}

// MARK: - 主视图

struct TagTypeGraphView: View {
    let tagType: Tag.TagType
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var graphData: TagTypeGraphData?
    @State private var isLoading = true
    @State private var showingExportSheet = false
    @State private var resetTrigger = UUID()
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            toolbar
            
            Divider()
            
            // 图谱主体
            if isLoading {
                loadingView
            } else if let data = graphData {
                TagTypeGraphCanvas(data: data, resetTrigger: resetTrigger)
            } else {
                emptyStateView
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .navigationTitle("标签类型图谱: \(tagType.displayName)")
        .onAppear {
            print("📊 TagTypeGraphView appeared for: \(tagType.displayName)")
            loadGraphData()
        }
        .onKeyPress(.escape) {
            print("📊 TagTypeGraphView: ESC pressed, dismissing")
            dismiss()
            return .handled
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportGraphSheetView(
                tagType: tagType,
                graphData: graphData
            )
        }
    }
    
    // MARK: - 子视图
    
    private var toolbar: some View {
        HStack {
            Button("关闭") { 
                dismiss() 
            }
            .keyboardShortcut(.escape, modifiers: [])
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("重置视图") { 
                    withAnimation(.easeInOut(duration: 0.5)) {
                        resetTrigger = UUID()
                    }
                    print("🔄 重置图谱视图")
                }
                .disabled(graphData == nil)
                
                Button("导出图谱") { 
                    showingExportSheet = true
                    print("📤 导出图谱")
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
        
        // 异步加载数据，避免阻塞UI
        Task { @MainActor in
            let data = store.getTagTypeGraphData(for: tagType)
            self.graphData = data
            self.isLoading = false
            print("🕸️ 图谱数据加载完成: \(tagType.displayName), 标签值数量: \(data.tagValues.count)")
        }
    }
}

// MARK: - 图谱画布

struct TagTypeGraphCanvas: View {
    let data: TagTypeGraphData
    let resetTrigger: UUID
    @State private var selectedNode: TagValueNode?
    @State private var hoveredNode: TagValueNode?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景
                Color.clear
                
                // 图谱层
                GraphLayer(
                    data: data,
                    selectedNode: $selectedNode,
                    hoveredNode: $hoveredNode,
                    canvasSize: geometry.size,
                    resetTrigger: resetTrigger
                )
                
                // 信息面板
                if let selected = selectedNode {
                    InfoPanel(tagValue: selected)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: resetTrigger) { _, _ in
            // 重置所有选中和悬停状态
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedNode = nil
                hoveredNode = nil
            }
        }
    }
}

// MARK: - 图谱渲染层

struct GraphLayer: View {
    let data: TagTypeGraphData
    @Binding var selectedNode: TagValueNode?
    @Binding var hoveredNode: TagValueNode?
    let canvasSize: CGSize
    let resetTrigger: UUID
    
    // 图谱布局参数
    private let centerRadius: CGFloat = 80
    private let tagValueRadius: CGFloat = 200
    private let contentNodeRadius: CGFloat = 350
    
    @State private var hoveredContentNode: Node?
    @State private var animationOffset: CGFloat = 0
    
    var body: some View {
        ZStack {
            // 连接线
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
                .stroke(isValueHovered ? Color.blue.opacity(0.6) : Color.secondary.opacity(0.3), lineWidth: isValueHovered ? 2 : 1)
                .animation(.easeInOut(duration: 0.2), value: isValueHovered)
                
                // 标签值到内容节点的连接线
                ForEach(Array(tagValue.nodes.prefix(5).enumerated()), id: \.offset) { nodeIndex, node in
                    let nodeAngle = angle + (Double(nodeIndex - 2) * 0.2)  // 展开角度
                    let nodePos = positionForContentNode(angle: nodeAngle, canvasSize: canvasSize)
                    let isNodeHovered = hoveredContentNode?.id == node.id
                    
                    Path { path in
                        path.move(to: tagValuePos)
                        path.addLine(to: nodePos)
                    }
                    .stroke(
                        isNodeHovered ? Color.green.opacity(0.8) : 
                        isValueHovered ? Color.blue.opacity(0.4) : 
                        Color.secondary.opacity(0.2), 
                        lineWidth: isNodeHovered ? 1.5 : (isValueHovered ? 1 : 0.5)
                    )
                    .animation(.easeInOut(duration: 0.2), value: isNodeHovered)
                    .animation(.easeInOut(duration: 0.2), value: isValueHovered)
                }
            }
            
            // 中心节点（标签类型）
            CenterNode(tagType: data.tagType, position: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2))
            
            // 标签值节点
            ForEach(data.tagValues.indices, id: \.self) { index in
                let tagValue = data.tagValues[index]
                let angle = angleForIndex(index, total: data.tagValues.count)
                let position = positionForTagValue(angle: angle, canvasSize: canvasSize)
                
                TagValueNodeView(
                    tagValue: tagValue,
                    position: position,
                    isSelected: selectedNode?.value == tagValue.value,
                    isHovered: hoveredNode?.value == tagValue.value
                )
                .contentShape(Circle().size(width: 80, height: 80)) // 限制悬停区域
                .onTapGesture {
                    selectedNode = selectedNode?.value == tagValue.value ? nil : tagValue
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hoveredNode = hovering ? tagValue : nil
                    }
                }
                
                // 内容节点（每个标签值显示前5个）
                ForEach(Array(tagValue.nodes.prefix(5).enumerated()), id: \.offset) { nodeIndex, node in
                    let nodeAngle = angle + (Double(nodeIndex - 2) * 0.2)
                    let nodePos = positionForContentNode(angle: nodeAngle, canvasSize: canvasSize)
                    
                    ContentNodeView(
                        node: node, 
                        position: nodePos,
                        isHovered: hoveredContentNode?.id == node.id
                    )
                    .contentShape(Circle().size(width: 50, height: 50)) // 限制悬停区域
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredContentNode = hovering ? node : nil
                        }
                    }
                    .onTapGesture {
                        print("🖱️ 点击内容节点: \(String(node.text.prefix(20)))")
                    }
                }
            }
        }
        .onChange(of: resetTrigger) { _, _ in
            // 重置悬停状态
            withAnimation(.easeInOut(duration: 0.3)) {
                hoveredContentNode = nil
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

// MARK: - 节点视图组件

struct CenterNode: View {
    let tagType: Tag.TagType
    let position: CGPoint
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(Color.from(tagType: tagType))
                .frame(width: 60, height: 60)
                .scaleEffect(pulseScale)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .shadow(radius: 2)
                        .scaleEffect(pulseScale)
                )
                .overlay(
                    // 添加微妙的光晕效果
                    Circle()
                        .stroke(Color.from(tagType: tagType).opacity(0.3), lineWidth: 8)
                        .scaleEffect(pulseScale * 1.1)
                        .opacity(0.6)
                )
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        pulseScale = 1.05
                    }
                }
            
            Text(tagType.displayName)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.regularMaterial)
                        .shadow(radius: 1)
                )
        }
        .position(position)
    }
}

struct TagValueNodeView: View {
    let tagValue: TagValueNode
    let position: CGPoint
    let isSelected: Bool
    let isHovered: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(isSelected ? Color.blue : (isHovered ? Color.blue.opacity(0.7) : Color.gray))
                .frame(width: isSelected || isHovered ? 36 : 30, height: isSelected || isHovered ? 36 : 30)
                .overlay(
                    Text("\(tagValue.usageCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                )
            
            // 改进节点名称显示
            Text(tagValue.value)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .blue : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.regularMaterial)
                        .opacity(isSelected || isHovered ? 1.0 : 0.8)
                )
        }
        .scaleEffect(isSelected || isHovered ? 1.2 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0), value: isSelected)
        .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0), value: isHovered)
        .position(position)
    }
}

struct ContentNodeView: View {
    let node: Node
    let position: CGPoint
    let isHovered: Bool
    
    init(node: Node, position: CGPoint, isHovered: Bool = false) {
        self.node = node
        self.position = position
        self.isHovered = isHovered
    }
    
    var body: some View {
        VStack(spacing: 6) {
            // 主节点圆圈
            Circle()
                .fill(isHovered ? Color.green.opacity(0.8) : Color.secondary.opacity(0.4))
                .frame(width: isHovered ? 20 : 16, height: isHovered ? 20 : 16)
                .overlay(
                    Circle()
                        .stroke(isHovered ? Color.green : Color.secondary, lineWidth: isHovered ? 2 : 1)
                )
                .scaleEffect(isHovered ? 1.2 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
            
            // 节点名称 - 始终显示
            Text(String(node.text.prefix(20)) + (node.text.count > 20 ? "..." : ""))
                .font(.system(size: 10, weight: isHovered ? .semibold : .medium))
                .foregroundColor(isHovered ? .green : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.regularMaterial)
                        .opacity(isHovered ? 1.0 : 0.85)
                        .shadow(radius: isHovered ? 2 : 1)
                )
                .scaleEffect(isHovered ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .position(position)
    }
}

// MARK: - 信息面板

struct InfoPanel: View {
    let tagValue: TagValueNode
    
    var headerView: some View {
        HStack {
            Text("标签值: \(tagValue.value)")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Text("\(tagValue.usageCount) 个节点")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }
    
    var nodesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(tagValue.nodes.prefix(10), id: \.id) { node in
                    HStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                        
                        Text(String(node.text.prefix(50)))
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                }
                
                if tagValue.nodes.count > 10 {
                    Text("还有 \(tagValue.nodes.count - 10) 个节点...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .frame(maxHeight: 200)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            
            Text("关联节点:")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            nodesList
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(radius: 8)
        )
        .frame(maxWidth: 300)
        .position(x: 200, y: 100)
    }
}

// MARK: - NodeStore 扩展

extension NodeStore {
    /// 获取标签类型的图谱数据
    func getTagTypeGraphData(for tagType: Tag.TagType) -> TagTypeGraphData {
        let analysis = getTagUsageAnalysis()
        let filteredAnalysis = analysis.filter { $0.tagType == tagType }
        
        let tagValues = filteredAnalysis.map { usage in
            TagValueNode(
                value: usage.tagValue,
                nodes: usage.nodes,
                usageCount: usage.nodeCount
            )
        }
        
        return TagTypeGraphData(tagType: tagType, tagValues: tagValues)
    }
}

// MARK: - 导出图谱工具

struct ExportGraphSheetView: View {
    let tagType: Tag.TagType
    let graphData: TagTypeGraphData?
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .text
    @State private var isExporting = false
    
    enum ExportFormat: String, CaseIterable {
        case text = "文本格式"
        case json = "JSON格式"
        case csv = "CSV格式"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("导出图谱数据")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("标签类型: \(tagType.displayName)")
                    .font(.headline)
                
                if let data = graphData {
                    Text("包含 \(data.tagValues.count) 个标签值和 \(data.tagValues.reduce(0) { $0 + $1.nodes.count }) 个节点")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("导出格式")
                    .font(.headline)
                
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    HStack {
                        Image(systemName: selectedFormat == format ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedFormat == format ? .blue : .secondary)
                        
                        Text(format.rawValue)
                            .font(.system(size: 15))
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedFormat = format
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            HStack {
                Spacer()
                
                Button("导出") {
                    performExport()
                }
                .disabled(isExporting || graphData == nil)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
    }
    
    private func performExport() {
        guard let data = graphData else { return }
        
        isExporting = true
        
        let savePanel = NSSavePanel()
        savePanel.title = "导出图谱数据"
        savePanel.nameFieldStringValue = "\(tagType.displayName)_graph"
        
        switch selectedFormat {
        case .text:
            savePanel.allowedContentTypes = [.plainText]
        case .json:
            savePanel.allowedContentTypes = [.json]
        case .csv:
            savePanel.allowedContentTypes = [.commaSeparatedText]
        }
        
        savePanel.begin { response in
            defer { isExporting = false }
            
            guard response == .OK, let url = savePanel.url else {
                return
            }
            
            do {
                let content = generateExportContent(data: data, format: selectedFormat)
                try content.write(to: url, atomically: true, encoding: .utf8)
                print("✅ 成功导出图谱数据到: \(url.path)")
                dismiss()
            } catch {
                print("❌ 导出失败: \(error)")
            }
        }
    }
    
    private func generateExportContent(data: TagTypeGraphData, format: ExportFormat) -> String {
        switch format {
        case .text:
            return generateTextFormat(data: data)
        case .json:
            return generateJSONFormat(data: data)
        case .csv:
            return generateCSVFormat(data: data)
        }
    }
    
    private func generateTextFormat(data: TagTypeGraphData) -> String {
        var content = "标签类型图谱: \(data.tagType.displayName)\n"
        content += "生成时间: \(Date().formatted())\n\n"
        
        for tagValue in data.tagValues {
            content += "标签值: \(tagValue.value) (使用次数: \(tagValue.usageCount))\n"
            for node in tagValue.nodes {
                content += "  - \(node.text)\n"
            }
            content += "\n"
        }
        
        return content
    }
    
    private func generateJSONFormat(data: TagTypeGraphData) -> String {
        let exportData: [String: Any] = [
            "tagType": data.tagType.displayName,
            "exportTime": ISO8601DateFormatter().string(from: Date()),
            "tagValues": data.tagValues.map { tagValue in
                [
                    "value": tagValue.value,
                    "usageCount": tagValue.usageCount,
                    "nodes": tagValue.nodes.map { node in
                        [
                            "id": node.id.uuidString,
                            "text": node.text
                        ]
                    }
                ]
            }
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "{}"
    }
    
    private func generateCSVFormat(data: TagTypeGraphData) -> String {
        var content = "标签值,使用次数,节点ID,节点内容\n"
        
        for tagValue in data.tagValues {
            for node in tagValue.nodes {
                content += "\"\(tagValue.value)\",\(tagValue.usageCount),\"\(node.id.uuidString)\",\"\(node.text.replacingOccurrences(of: "\"", with: "\"\""))\"\n"
            }
        }
        
        return content
    }
}