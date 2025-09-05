import SwiftUI

// MARK: - 全局标签图谱视图

struct GlobalTagGraphView: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var dataManager = GlobalTagDataManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var graphData: (nodes: [GlobalTagGraphNode], edges: [GlobalTagGraphEdge])?
    @State private var isLoading = false
    @State private var resetTrigger = UUID()
    @State private var showingExportSheet = false
    @State private var hasPerformedInitialLoad = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            toolbar
            
            Divider()
            
            // 图谱主体
            Group {
                if isLoading {
                    loadingView
                } else if let data = graphData, !data.nodes.isEmpty {
                    GlobalTagGraphCanvas(
                        nodes: data.nodes, 
                        edges: data.edges, 
                        resetTrigger: resetTrigger
                    )
                } else {
                    emptyStateView
                }
            }
            .onAppear {
                print("🔄 [全局标签图谱] UI状态检查 - isLoading: \(isLoading), hasData: \(graphData?.nodes.count ?? 0)个节点")
                // 🚨 强制调试：检查数据是否真的被设置
                if let data = graphData {
                    print("🚨 [调试] graphData存在: \(data.nodes.count)个节点, \(data.edges.count)条边")
                    for (i, node) in data.nodes.enumerated() {
                        print("   节点\(i): \(node.label) (ID: \(node.id))")
                    }
                } else {
                    print("🚨 [调试] graphData为nil")
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .navigationTitle("全局标签图谱")
        .onAppear {
            print("🌍 [全局标签图谱] 视图出现，当前isLoading: \(isLoading), hasPerformedInitialLoad: \(hasPerformedInitialLoad)")
            
            // 🔧 强制确保初始状态正确
            isLoading = false
            
            // 只在首次出现或没有数据时才加载
            if !hasPerformedInitialLoad || graphData == nil {
                print("🚀 [全局标签图谱] 执行初始数据加载")
                hasPerformedInitialLoad = true
                loadGraphData()
            } else {
                print("📊 [全局标签图谱] 已有数据，跳过重复加载")
            }
        }
        .onReceive(dataManager.$filteredLayers.combineLatest(dataManager.$filteredTagTypes, dataManager.$filteredTagValues)) { layers, types, values in
            print("🔄 [全局标签图谱] 过滤器变化，准备重新加载数据")
            print("   新的过滤条件: 层级=\(layers.count), 类型=\(types.count), 值=\(values.count)")
            // 🔧 防抖动：延迟100ms再执行，避免快速连续更改时的多次调用
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !self.isLoading {  // 只有在不加载时才执行
                    self.loadGraphData()
                }
            }
        }
        .onKeyPress(.escape) {
            print("🔙 [全局标签图谱] ESC键按下，关闭窗口")
            dismiss()
            return .handled
        }
        .sheet(isPresented: $showingExportSheet) {
            GlobalTagExportSheetView(graphData: graphData)
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
            
            // 过滤状态显示
            filterStatusView
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("重置视图") { 
                    withAnimation(.easeInOut(duration: 0.5)) {
                        resetTrigger = UUID()
                    }
                    print("🔄 [全局标签图谱] 重置视图")
                }
                .disabled(graphData == nil)
                
                Button("导出图谱") { 
                    showingExportSheet = true
                    print("📤 [全局标签图谱] 导出图谱")
                }
                .disabled(graphData == nil)
                
                Button("打开标签索引") {
                    NewTagIndexWindowManager.shared.showTagIndexWindow()
                    print("📋 [全局标签图谱] 打开标签索引面板")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
    
    private var filterStatusView: some View {
        VStack(spacing: 4) {
            if !dataManager.filteredLayers.isEmpty || !dataManager.filteredTagTypes.isEmpty || !dataManager.filteredTagValues.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "line.horizontal.3.decrease.circle")
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        if !dataManager.filteredLayers.isEmpty {
                            Text("层级: \(dataManager.filteredLayers.joined(separator: ", "))")
                        }
                        if !dataManager.filteredTagTypes.isEmpty {
                            Text("类型: \(dataManager.filteredTagTypes.map { $0.displayName }.joined(separator: ", "))")
                        }
                        if !dataManager.filteredTagValues.isEmpty {
                            Text("值: \(Array(dataManager.filteredTagValues.prefix(3)).joined(separator: ", "))\(dataManager.filteredTagValues.count > 3 ? "..." : "")")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    Button("清除") {
                        dataManager.filteredLayers.removeAll()
                        dataManager.filteredTagTypes.removeAll()
                        dataManager.filteredTagValues.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            } else {
                HStack {
                    Image(systemName: "globe")
                        .foregroundColor(.green)
                    Text("显示所有标签")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("正在生成全局标签图谱...")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            
            Text("分析所有节点的标签关系")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "network.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("无标签数据")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                Text("可能的原因:")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• 节点中没有标签")
                    Text("• 过滤条件过于严格")
                    Text("• 数据尚未加载完成")
                }
                .font(.body)
                .foregroundColor(.secondary)
            }
            
            Button("刷新数据") {
                print("🔄 [全局标签图谱] 手动刷新数据，重置所有状态")
                isLoading = false  // 强制重置状态
                graphData = nil
                hasPerformedInitialLoad = false  // 重置初始加载标记
                loadGraphData()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - 数据加载
    
    private func loadGraphData() {
        print("🔄 [全局标签图谱] loadGraphData开始，当前isLoading: \(isLoading)")
        
        // 添加强制重置机制：如果连续多次调用都被跳过，强制重置状态
        if isLoading {
            print("⚠️ [全局标签图谱] 检测到加载状态异常，检查是否需要强制重置")
            
            // 设置一个合理的超时检查，如果状态异常持续太久就强制重置
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self.isLoading && self.graphData == nil {
                    print("🔧 [全局标签图谱] 强制重置异常的加载状态")
                    self.isLoading = false
                    // 递归调用重新尝试加载
                    self.loadGraphData()
                }
            }
            
            print("⏸️ [全局标签图谱] 已在加载中，跳过本次请求")
            return
        }
        
        // 在主线程上设置加载状态
        print("🔄 [全局标签图谱] 设置isLoading = true，清空graphData")
        isLoading = true
        graphData = nil
        
        // 确保在外层设置 defer，无论 Task 如何都会执行
        let resetLoadingState = {
            DispatchQueue.main.async {
                self.isLoading = false
                print("🔄 [全局标签图谱] isLoading已重置为false")
            }
        }
        
        // 设置超时机制
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 30_000_000_000) // 30秒超时
            if !Task.isCancelled {
                print("⏰ [全局标签图谱] 加载超时，强制重置状态")
                resetLoadingState()
            }
        }
        
        Task { @MainActor in
            defer {
                timeoutTask.cancel() // 正常完成时取消超时任务
            }
            
            do {
                print("🔄 [全局标签图谱] Task开始执行")
                print("🔄 [全局标签图谱] 开始生成图谱数据")
                print("   - 数据源节点数: \(store.nodes.count)")
                print("   - 数据源层级数: \(store.layers.count)")
                
                let data = dataManager.generateGlobalGraphData(from: store)
                
                print("✅ [全局标签图谱] 图谱数据生成完成")
                print("   - 节点数: \(data.nodes.count)")
                print("   - 边数: \(data.edges.count)")
                
                // 检查任务是否被取消
                try Task.checkCancellation()
                
                // 🔧 修复竞态条件：同时更新数据和状态
                self.graphData = data
                self.isLoading = false  // 立即重置状态
                
                print("✅ [修复竞态] 同步更新: graphData=\(data.nodes.count)个节点, isLoading=false")
                
                if data.nodes.isEmpty {
                    print("⚠️ [全局标签图谱] 警告：没有生成任何节点数据")
                } else {
                    print("✅ [全局标签图谱] 成功生成图谱数据：")
                    for (i, node) in data.nodes.enumerated() {
                        print("   节点\(i): \(node.label) (ID: \(node.id))")
                    }
                }
                
            } catch {
                print("❌ [全局标签图谱] 数据加载失败: \(error)")
                // 出错时也要重置状态
                self.isLoading = false
            }
        }
    }
}

// MARK: - 全局标签图谱画布

struct GlobalTagGraphCanvas: View {
    let nodes: [GlobalTagGraphNode]
    let edges: [GlobalTagGraphEdge]
    let resetTrigger: UUID
    
    @State private var selectedNode: GlobalTagGraphNode?
    @State private var hoveredNode: GlobalTagGraphNode?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景
                Color.clear
                
                // 使用现有的UniversalRelationshipGraphView
                UniversalRelationshipGraphView(
                    nodes: nodes,
                    edges: edges,
                    title: "全局标签图谱",
                    initialScale: 1.0,
                    onNodeSelected: { nodeId, commandPressed in
                        handleNodeSelection(nodeId: nodeId, commandPressed: commandPressed)
                    }
                )
                .id("global-tag-graph-\(resetTrigger)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: resetTrigger) { _, _ in
            // 重置选中状态
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedNode = nil
                hoveredNode = nil
            }
        }
    }
    
    private func handleNodeSelection(nodeId: Int, commandPressed: Bool) {
        guard let node = nodes.first(where: { $0.id == nodeId }) else { return }
        
        print("🖱️ [全局标签图谱] 选中节点: \(node.label) (类型: \(node.nodeType))")
        
        // 根据节点类型执行不同操作
        switch node.nodeType {
        case .root:
            print("📍 [全局标签图谱] 选中根节点")
            
        case .tagType(let tagType):
            print("🏷️ [全局标签图谱] 选中标签类型: \(tagType.displayName)")
            // 可以展开显示更多该类型的标签值
            
        case .tagValue(let value, let count):
            print("🔖 [全局标签图谱] 选中标签值: \(value) (使用 \(count) 次)")
            // 可以显示包含该标签的节点列表
            
        case .contentNode(let node):
            print("📄 [全局标签图谱] 选中内容节点: \(node.text)")
            // 可以跳转到该节点
            NotificationCenter.default.post(
                name: NSNotification.Name("selectNodeFromGlobalGraph"),
                object: node
            )
        }
        
        selectedNode = node
    }
}

// MARK: - 全局标签图谱导出

struct GlobalTagExportSheetView: View {
    let graphData: (nodes: [GlobalTagGraphNode], edges: [GlobalTagGraphEdge])?
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
                Text("导出全局标签图谱")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("全局标签图谱数据")
                    .font(.headline)
                
                if let data = graphData {
                    Text("包含 \(data.nodes.count) 个节点和 \(data.edges.count) 条关系")
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
        savePanel.title = "导出全局标签图谱"
        savePanel.nameFieldStringValue = "global_tag_graph"
        
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
                print("✅ [全局标签图谱] 导出成功: \(url.path)")
                dismiss()
            } catch {
                print("❌ [全局标签图谱] 导出失败: \(error)")
            }
        }
    }
    
    private func generateExportContent(data: (nodes: [GlobalTagGraphNode], edges: [GlobalTagGraphEdge]), format: ExportFormat) -> String {
        switch format {
        case .text:
            return generateTextFormat(data: data)
        case .json:
            return generateJSONFormat(data: data)
        case .csv:
            return generateCSVFormat(data: data)
        }
    }
    
    private func generateTextFormat(data: (nodes: [GlobalTagGraphNode], edges: [GlobalTagGraphEdge])) -> String {
        var content = "全局标签图谱导出\n"
        content += "生成时间: \(Date().formatted())\n\n"
        
        content += "=== 节点列表 ===\n"
        for node in data.nodes {
            content += "ID: \(node.id), 标签: \(node.label)"
            if let subtitle = node.subtitle {
                content += ", 描述: \(subtitle)"
            }
            content += ", 类型: \(node.nodeType)\n"
        }
        
        content += "\n=== 关系列表 ===\n"
        for edge in data.edges {
            content += "从 \(edge.fromId) 到 \(edge.toId)"
            if let label = edge.label {
                content += " (\(label))"
            }
            content += "\n"
        }
        
        return content
    }
    
    private func generateJSONFormat(data: (nodes: [GlobalTagGraphNode], edges: [GlobalTagGraphEdge])) -> String {
        let exportData: [String: Any] = [
            "exportTime": ISO8601DateFormatter().string(from: Date()),
            "graphType": "GlobalTagGraph",
            "nodes": data.nodes.map { node in
                [
                    "id": node.id,
                    "label": node.label,
                    "subtitle": node.subtitle ?? "",
                    "isCenter": node.isCenter
                ]
            },
            "edges": data.edges.map { edge in
                [
                    "fromId": edge.fromId,
                    "toId": edge.toId,
                    "label": edge.label ?? ""
                ]
            }
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "{}"
    }
    
    private func generateCSVFormat(data: (nodes: [GlobalTagGraphNode], edges: [GlobalTagGraphEdge])) -> String {
        var content = "节点ID,节点标签,节点描述,节点类型\n"
        
        for node in data.nodes {
            content += "\(node.id),\"\(node.label)\",\"\(node.subtitle ?? "")\",\"\(node.nodeType)\"\n"
        }
        
        return content
    }
}

// MARK: - 全局标签图谱窗口委托

private class GlobalTagGraphWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

// MARK: - 全局标签图谱窗口管理器

@MainActor
class GlobalTagGraphWindowManager: ObservableObject {
    static let shared = GlobalTagGraphWindowManager()
    
    private var window: NSWindow?
    private var windowDelegate: GlobalTagGraphWindowDelegate?
    
    private init() {}
    
    func showGlobalTagGraphWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        let contentView = GlobalTagGraphView()
            .environmentObject(NodeStore.shared)
        
        let hostingView = NSHostingView(rootView: contentView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.contentView = hostingView
        newWindow.title = "全局标签图谱"
        newWindow.setFrameAutosaveName("GlobalTagGraphWindow")
        newWindow.isReleasedWhenClosed = false
        
        // 窗口关闭处理
        let delegate = GlobalTagGraphWindowDelegate { [weak self] in
            self?.window = nil
            self?.windowDelegate = nil
        }
        self.windowDelegate = delegate
        newWindow.delegate = delegate
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        
        print("🪟 [全局标签图谱] 窗口已创建")
    }
    
    func closeWindow() {
        window?.close()
        window = nil
        windowDelegate = nil
    }
}