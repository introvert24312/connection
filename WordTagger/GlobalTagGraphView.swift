import SwiftUI

// MARK: - 全局标签图谱视图

struct GlobalTagGraphView: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var dataManager = GlobalTagDataManager()  // 🆕 每个视图独立的数据管理器
    @Environment(\.dismiss) private var dismiss
    @AppStorage("globalTagGraphInitialScale") private var globalTagGraphInitialScale: Double = 1.0
    
    @State private var graphData: (nodes: [GlobalTagGraphNode], edges: [GlobalTagGraphEdge])?
    @State private var isLoading = false
    @State private var resetTrigger = UUID()
    @State private var hasPerformedInitialLoad = false
    
    // 🔒 图谱锁定状态 - 锁定后不再接收数据更新
    @State private var isLocked = false
    @State private var lockedGraphData: (nodes: [GlobalTagGraphNode], edges: [GlobalTagGraphEdge])?
    
    // 🆕 图谱预设管理状态
    @State private var showingPresetSheet = false
    @State private var showingSavePresetDialog = false
    @State private var newPresetName = ""
    @State private var newPresetDescription = ""
    
    // 🔒 计算属性：根据锁定状态决定显示哪个数据
    private var displayGraphData: (nodes: [GlobalTagGraphNode], edges: [GlobalTagGraphEdge])? {
        if isLocked {
            return lockedGraphData
        } else {
            return graphData
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            toolbar
            
            Divider()
            
            // 图谱主体
            Group {
                if isLoading {
                    loadingView
                } else if let data = displayGraphData, !data.nodes.isEmpty {
                    GlobalTagGraphCanvas(
                        nodes: data.nodes, 
                        edges: data.edges, 
                        resetTrigger: resetTrigger,
                        initialScale: globalTagGraphInitialScale
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
        .navigationTitle("全局标签图谱")
        .onAppear {
            print("🌍 [全局标签图谱] 视图出现，当前isLoading: \(isLoading), hasPerformedInitialLoad: \(hasPerformedInitialLoad)")
            
            // 🔧 强制确保初始状态正确
            isLoading = false
            
            // 🆕 检查是否有恢复的上次使用预设，如果有则自动加载数据
            if dataManager.currentPreset != nil {
                let hasValidFilters = !dataManager.filteredLayers.isEmpty || 
                                    !dataManager.filteredTagTypes.isEmpty || 
                                    !dataManager.filteredTagValues.isEmpty
                if hasValidFilters {
                    print("🔄 [全局标签图谱] 检测到已恢复的预设，自动加载图谱数据")
                    loadGraphData()
                } else {
                    print("📋 [全局标签图谱] 已恢复预设但过滤条件为空，保持空白状态")
                }
            } else {
                print("📋 [全局标签图谱] 没有上次使用的预设，保持空白状态")
            }
        }
        .onReceive(dataManager.$filteredLayers.combineLatest(dataManager.$filteredTagTypes, dataManager.$filteredTagValues)) { layers, types, values in
            print("🔄 [全局标签图谱] 过滤器变化，准备重新加载数据")
            print("   新的过滤条件: 层级=\(layers.count), 类型=\(types.count), 值=\(values.count)")
            
            // 🔒 如果图谱被锁定，忽略所有数据更新
            guard !isLocked else {
                print("🔒 [全局标签图谱] 图谱已锁定，忽略过滤器变化")
                return
            }
            
            // 🔧 如果有有效的过滤条件，则触发加载
            let hasValidFilters = !layers.isEmpty || !types.isEmpty || !values.isEmpty
            guard hasValidFilters else {
                print("⏸️ [全局标签图谱] 没有有效的过滤条件，跳过加载")
                return
            }
            
            // 标记已执行初始加载（由过滤器触发）
            hasPerformedInitialLoad = true
            
            // 🔧 防抖动：延迟100ms再执行，避免快速连续更改时的多次调用
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !self.isLoading {  // 只有在不加载时才执行
                    self.loadGraphData()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("tagTypeSelected"))) { notification in
            print("📨 [全局标签图谱] 收到主窗口标签类型选择通知")
            print("📨 [全局标签图谱] 通知详情: \(notification)")
            print("📨 [全局标签图谱] userInfo: \(notification.userInfo ?? [:])")
            
            if let userInfo = notification.userInfo,
               let tagType = userInfo["tagType"] as? Tag.TagType {
                print("🏷️ [全局标签图谱] 同步标签类型选择: \(tagType.displayName)")
                print("🏷️ [全局标签图谱] 标签类型rawValue: \(tagType.rawValue)")
                
                // 🔒 如果图谱被锁定，忽略通知
                guard !isLocked else {
                    print("🔒 [全局标签图谱] 图谱已锁定，忽略标签类型选择通知")
                    return
                }
                
                print("🔄 [全局标签图谱] 开始更新过滤器")
                
                // 更新过滤器以显示选中的标签类型
                DispatchQueue.main.async {
                    print("🧹 [全局标签图谱] 清除现有过滤器")
                    print("   - 清除前 filteredLayers: \(dataManager.filteredLayers)")
                    print("   - 清除前 filteredTagValues: \(dataManager.filteredTagValues)")
                    print("   - 清除前 filteredTagTypes: \(dataManager.filteredTagTypes.map { $0.displayName })")
                    
                    // 清除所有过滤器
                    dataManager.filteredLayers.removeAll()
                    dataManager.filteredTagValues.removeAll()
                    
                    // 设置选中的标签类型过滤器
                    dataManager.filteredTagTypes = Set([tagType])
                    
                    print("✅ [全局标签图谱] 过滤器更新完成")
                    print("   - 新的 filteredLayers: \(dataManager.filteredLayers)")
                    print("   - 新的 filteredTagValues: \(dataManager.filteredTagValues)")
                    print("   - 新的 filteredTagTypes: \(dataManager.filteredTagTypes.map { $0.displayName })")
                    print("✅ [全局标签图谱] 已同步更新过滤器，显示标签类型: \(tagType.displayName)")
                }
            } else {
                print("❌ [全局标签图谱] 无法解析通知内容")
                if let userInfo = notification.userInfo {
                    print("   - userInfo keys: \(userInfo.keys)")
                    for (key, value) in userInfo {
                        print("   - \(key): \(value) (type: \(type(of: value)))")
                    }
                }
            }
        }
        .onKeyPress(.escape) {
            print("🔙 [全局标签图谱] ESC键按下，关闭窗口")
            dismiss()
            return .handled
        }
        .onChange(of: showingPresetSheet) { _, isShowing in
            if isShowing {
                showGlobalTagGraphPresetManager()
                showingPresetSheet = false
            }
        }
        .alert("保存图谱预设", isPresented: $showingSavePresetDialog) {
            TextField("预设名称", text: $newPresetName)
            TextField("描述（可选）", text: $newPresetDescription)
            
            Button("保存") {
                let trimmedName = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
                print("🚀 [全局标签图谱] 保存按钮点击 - 预设名称: '\(trimmedName)'")
                print("🔍 [全局标签图谱] 当前过滤状态:")
                print("   - 层级: \(dataManager.filteredLayers)")
                print("   - 标签类型: \(dataManager.filteredTagTypes)")
                print("   - 标签值: \(dataManager.filteredTagValues)")
                
                if !trimmedName.isEmpty {
                    let description = newPresetDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    print("📝 [全局标签图谱] 开始调用saveCurrentAsPreset...")
                    dataManager.saveCurrentAsPreset(
                        name: trimmedName,
                        description: description.isEmpty ? nil : description
                    )
                    print("✅ [全局标签图谱] saveCurrentAsPreset调用完成")
                    
                    // 清空输入框
                    newPresetName = ""
                    newPresetDescription = ""
                } else {
                    print("⚠️ [全局标签图谱] 预设名称为空，跳过保存")
                }
            }
            .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            
            Button("取消", role: .cancel) {
                newPresetName = ""
                newPresetDescription = ""
            }
        } message: {
            Text("为当前的标签过滤状态创建一个预设，以便后续快速加载。")
        }
    }
    
    // MARK: - 子视图
    
    private var toolbar: some View {
        HStack(alignment: .center, spacing: 8) {
            // 🆕 将过滤状态显示移到最左边，替换关闭按钮
            filterStatusView
            
            Spacer()
            
            HStack(spacing: 8) {
                // 🆕 图谱预设按钮组
                Button("图谱预设") {
                    print("📚 [全局标签图谱] 打开预设管理")
                    print("🔍 [全局标签图谱] 当前DataManager状态:")
                    print("   - 层级: \(dataManager.filteredLayers)")
                    print("   - 标签类型: \(dataManager.filteredTagTypes.map { $0.displayName })")
                    print("   - 标签值: \(dataManager.filteredTagValues)")
                    print("   - 预设数量: \(dataManager.graphPresets.count)")
                    showingPresetSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("保存为预设") {
                    showingSavePresetDialog = true
                    print("💾 [全局标签图谱] 保存当前状态为预设")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(dataManager.filteredLayers.isEmpty && 
                         dataManager.filteredTagTypes.isEmpty && 
                         dataManager.filteredTagValues.isEmpty)
                
                Divider()
                    .frame(height: 20)
                
                // 🔒 锁定/解锁按钮
                Button(isLocked ? "🔓 解锁" : "🔒 锁定") {
                    toggleLockState()
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isLocked ? Color.orange.opacity(0.2) : Color.blue.opacity(0.1))
                .foregroundColor(isLocked ? .orange : .blue)
                .cornerRadius(6)
                .help(isLocked ? "解锁图谱以接收数据更新" : "锁定图谱以固定当前显示内容")
                
                Divider()
                    .frame(height: 20)
                
                Button("重置视图") { 
                    withAnimation(.easeInOut(duration: 0.5)) {
                        resetTrigger = UUID()
                    }
                    print("🔄 [全局标签图谱] 重置视图")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(graphData == nil)
                
                Button("标签看板") {
                    showAssociatedTagIndexWindow()
                    print("📋 [全局标签图谱] 打开标签看板")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Button("关闭") { 
                    dismiss() 
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .frame(height: 36) // 固定工具栏高度
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    
    private var filterStatusView: some View {
        HStack(spacing: 8) {
            // 🔒 锁定状态指示
            if isLocked {
                Image(systemName: "lock.fill")
                    .foregroundColor(.orange)
                Text("图谱已锁定")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fontWeight(.medium)
            } else if !dataManager.filteredLayers.isEmpty || !dataManager.filteredTagTypes.isEmpty || !dataManager.filteredTagValues.isEmpty {
                Image(systemName: "line.horizontal.3.decrease.circle")
                    .foregroundColor(.blue)
                
                Text(buildFilterText())
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Image(systemName: "globe")
                    .foregroundColor(.green)
                Text("显示所有标签")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxHeight: 30) // 限制最大高度
    }
    
    private func showGlobalTagGraphPresetManager() {
        print("📚 [全局标签图谱] 打开专用的预设管理系统")
        
        // 使用匹配的NewGlobalTagGraphPresetManagerView  
        let contentView = NewGlobalTagGraphPresetManagerView(dataManager: dataManager)
            .environmentObject(NodeStore.shared)
        
        let hostingView = NSHostingView(rootView: contentView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 300, y: 300, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.contentView = hostingView
        newWindow.title = "全局标签图谱预设管理"
        newWindow.setFrameAutosaveName("GlobalTagGraphPresetManagerWindow")
        newWindow.isReleasedWhenClosed = false
        
        // 窗口关闭处理
        let delegate = GlobalTagGraphPresetWindowDelegate()
        newWindow.delegate = delegate
        
        newWindow.makeKeyAndOrderFront(nil)
    }

    private func buildFilterText() -> String {
        var parts: [String] = []
        
        if !dataManager.filteredLayers.isEmpty {
            parts.append("层级: \(dataManager.filteredLayers.joined(separator: ", "))")
        }
        if !dataManager.filteredTagTypes.isEmpty {
            parts.append("类型: \(dataManager.filteredTagTypes.map { $0.displayName }.joined(separator: ", "))")
        }
        if !dataManager.filteredTagValues.isEmpty {
            let values = Array(dataManager.filteredTagValues.prefix(3)).joined(separator: ", ")
            parts.append("值: \(values)\(dataManager.filteredTagValues.count > 3 ? "..." : "")")
        }
        
        return parts.joined(separator: " | ")
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
            Image(systemName: "network")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("暂无图谱数据")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("选择标签筛选条件来生成全局标签图谱")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 关联功能
    
    private func showAssociatedTagIndexWindow() {
        // 🆕 创建与当前图谱窗口关联的标签索引窗口
        let associatedTagIndexView = NewTagIndexBoardView(
            associatedDataManager: dataManager  // 传递当前窗口的数据管理器
        )
        .environmentObject(store)
        
        let hostingView = NSHostingView(rootView: associatedTagIndexView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.contentView = hostingView
        newWindow.title = "标签看板"
        newWindow.setFrameAutosaveName("AssociatedTagIndexBoardWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        
        print("🪟 [标签看板] 窗口已创建")
    }
    
    // MARK: - 数据加载
    
    /// 加载当前层的标签图谱数据（默认加载使用）
    private func loadCurrentLayerGraphData() {
        print("🔄 [全局标签图谱] loadCurrentLayerGraphData开始，当前isLoading: \(isLoading)")
        
        // 🔒 如果图谱被锁定，忽略加载请求
        guard !isLocked else {
            print("🔒 [全局标签图谱] 图谱已锁定，忽略当前层加载请求")
            return
        }
        
        guard !isLoading else {
            print("⏸️ [全局标签图谱] 已在加载中，跳过当前层加载请求")
            return
        }
        
        // 设置只加载当前层的过滤器
        if let currentLayer = store.currentLayer {
            print("📋 [全局标签图谱] 设置过滤器为当前层: \(currentLayer.displayName)")
            dataManager.filteredLayers = Set([currentLayer.displayName])
            
            // 然后使用正常的加载流程
            loadGraphData()
        } else {
            print("⚠️ [全局标签图谱] 没有当前层，跳过自动加载")
        }
    }
    
    // 🔒 锁定/解锁切换函数
    private func toggleLockState() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if isLocked {
                // 解锁：清除锁定的数据，恢复正常数据流
                print("🔓 [全局标签图谱] 解锁图谱，恢复数据更新")
                isLocked = false
                lockedGraphData = nil
                
                // 解锁后立即重新加载当前数据
                if !isLoading {
                    loadGraphData()
                }
            } else {
                // 锁定：保存当前数据状态
                print("🔒 [全局标签图谱] 锁定图谱，冻结当前显示内容")
                isLocked = true
                lockedGraphData = graphData
                
                // 打印锁定的数据信息
                if let data = lockedGraphData {
                    print("🔒 锁定数据: \(data.nodes.count)个节点, \(data.edges.count)条边")
                }
            }
        }
    }
    
    private func loadGraphData() {
        print("🔄 [全局标签图谱] loadGraphData开始，当前isLoading: \(isLoading)")
        
        // 🔒 如果图谱被锁定，忽略加载请求
        guard !isLocked else {
            print("🔒 [全局标签图谱] 图谱已锁定，忽略数据加载请求")
            return
        }
        
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
    let initialScale: Double
    
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
                    initialScale: initialScale,
                    onNodeSelected: { nodeId, commandPressed, optionPressed in
                        handleNodeSelection(nodeId: nodeId, commandPressed: commandPressed, optionPressed: optionPressed)
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
    
    private func handleNodeSelection(nodeId: Int, commandPressed: Bool, optionPressed: Bool) {
        guard let node = nodes.first(where: { $0.id == nodeId }) else { return }
        
        print("🖱️ [全局标签图谱] 选中节点: \(node.label) (类型: \(node.nodeType))")
        
        // 检测Option键，只对内容节点处理文件夹功能
        if optionPressed {
            switch node.nodeType {
            case .contentNode(let contentNode):
                print("⌥ Option+点击全局标签图谱内容节点: \(contentNode.text)")
                NodeFolderManager.shared.openNodeFolderInFinder(contentNode)
                return
            default:
                print("⌥ Option+点击了非内容节点，忽略文件夹操作")
                // 对于其他类型的节点，Option键不执行特殊操作，继续正常流程
                break
            }
        }
        
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


// MARK: - 图谱预设管理视图

struct GraphPresetManagerView: View {
    @ObservedObject var dataManager: GlobalTagDataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    
    private var filteredPresets: [GraphPreset] {
        if searchText.isEmpty {
            return dataManager.graphPresets.sorted(by: { $0.lastUsed > $1.lastUsed })
        }
        return dataManager.graphPresets.filter { preset in
            preset.name.localizedCaseInsensitiveContains(searchText) ||
            (preset.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }.sorted(by: { $0.lastUsed > $1.lastUsed })
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("图谱预设管理")
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
            
            if filteredPresets.isEmpty && searchText.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("暂无保存的图谱预设")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("在全局标签图谱中选择标签后，点击\"保存为预设\"来创建您的第一个预设。")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredPresets.isEmpty && !searchText.isEmpty {
                // 搜索无结果状态
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("未找到匹配的预设")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("尝试使用不同的关键词搜索")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredPresets) { preset in
                            ModernGraphPresetRow(
                                preset: preset,
                                isCurrent: dataManager.currentPreset?.id == preset.id,
                                onLoad: {
                                    dataManager.loadPreset(preset)
                                    // 不再自动关闭窗口，让用户确认预设效果后手动关闭
                                },
                                onDelete: {
                                    dataManager.deletePreset(preset)
                                }
                            )
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}

struct ModernGraphPresetRow: View {
    let preset: GraphPreset
    let isCurrent: Bool
    let onLoad: () -> Void
    let onDelete: () -> Void
    
    @State private var showingDeleteAlert = false
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onLoad) {
            HStack(spacing: 12) {
                // 选中状态指示器
                ZStack {
                    Circle()
                        .fill(isCurrent ? Color.blue : Color.clear)
                        .frame(width: 20, height: 20)
                    
                    Circle()
                        .stroke(isCurrent ? Color.blue : Color.secondary, lineWidth: 2)
                        .frame(width: 20, height: 20)
                    
                    if isCurrent {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                // 预设信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(preset.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        if isCurrent {
                            Text("当前")
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                        }
                        
                        Spacer()
                    }
                    
                    if let description = preset.description {
                        Text(description)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    
                    HStack(spacing: 12) {
                        if !preset.filteredLayers.isEmpty {
                            Label("\(preset.filteredLayers.count) 层级", systemImage: "folder")
                        }
                        if !preset.filteredTagTypes.isEmpty {
                            Label("\(preset.filteredTagTypes.count) 类型", systemImage: "tag")
                        }
                        if !preset.filteredTagValues.isEmpty {
                            Label("\(preset.filteredTagValues.count) 标签", systemImage: "bookmark")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    
                    Text("创建于 \(formatDate(preset.createdAt))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                
                // 删除按钮（hover时显示）
                if isHovered {
                    Button {
                        showingDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("删除预设")
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isCurrent ? Color.blue.opacity(0.08) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isCurrent ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isCurrent)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .alert("删除预设", isPresented: $showingDeleteAlert) {
            Button("删除", role: .destructive) {
                onDelete()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("确定要删除预设 \"\(preset.name)\" 吗？此操作无法撤销。")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 全局标签图谱预设管理窗口委托

private class GlobalTagGraphPresetWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        print("🗑️ [全局标签图谱预设管理] 窗口已关闭")
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
        // 🆕 支持多开：不再检查已存在窗口，直接创建新窗口
        
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
        
        // 🆕 多开支持：不再保存窗口引用，每次都创建新窗口
        // self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        
        print("🪟 [全局标签图谱] 窗口已创建")
    }
    
    func closeWindow() {
        window?.close()
        window = nil
        windowDelegate = nil
    }
}

// MARK: - 新的全局标签图谱预设管理视图

struct NewGlobalTagGraphPresetManagerView: View {
    @ObservedObject var dataManager: GlobalTagDataManager
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var showingDeleteAlert = false
    @State private var presetToDelete: GraphPreset?
    
    private var filteredPresets: [GraphPreset] {
        if searchText.isEmpty {
            return dataManager.graphPresets.sorted(by: { $0.lastUsed > $1.lastUsed })
        }
        return dataManager.graphPresets.filter { preset in
            preset.name.localizedCaseInsensitiveContains(searchText) ||
            (preset.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }.sorted(by: { $0.lastUsed > $1.lastUsed })
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("全局标签图谱预设管理")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("(\(dataManager.graphPresets.count) 个预设)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
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
            
            // 预设列表
            if filteredPresets.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: searchText.isEmpty ? "bookmark.slash" : "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text(searchText.isEmpty ? "暂无保存的标签图谱预设" : "没有找到匹配的预设")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if searchText.isEmpty {
                        Text("在全局标签图谱中选择标签后，点击\"保存为预设\"来创建您的第一个预设。")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredPresets) { preset in
                            NewGlobalTagGraphPresetRowView(
                                preset: preset,
                                isCurrent: dataManager.currentPreset?.id == preset.id,
                                onLoad: {
                                    loadPreset(preset)
                                    dismiss()
                                },
                                onDelete: {
                                    presetToDelete = preset
                                    showingDeleteAlert = true
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .padding()
        .frame(width: 800, height: 600)
        .onAppear {
            print("🔍 [全局标签图谱预设管理] 视图出现")
            print("   - 收到的dataManager状态:")
            print("     - 层级: \(dataManager.filteredLayers)")
            print("     - 标签类型: \(dataManager.filteredTagTypes.map { $0.displayName })")
            print("     - 标签值: \(dataManager.filteredTagValues)")
            print("     - 预设数量: \(dataManager.graphPresets.count)")
        }
        .alert("删除预设", isPresented: $showingDeleteAlert, presenting: presetToDelete) { preset in
            Button("删除", role: .destructive) {
                dataManager.deletePreset(preset)
                presetToDelete = nil
            }
            Button("取消", role: .cancel) {
                presetToDelete = nil
            }
        } message: { preset in
            Text("确定要删除预设 \"\(preset.name)\" 吗？此操作无法撤销。")
        }
    }
    
    private func loadPreset(_ preset: GraphPreset) {
        print("📖 [全局标签图谱预设管理] 开始加载预设: \(preset.name)")
        print("   - 预设内容: 层级=\(preset.filteredLayers), 类型=\(preset.filteredTagTypes), 值=\(preset.filteredTagValues)")
        dataManager.loadPreset(preset)
        print("✅ [全局标签图谱预设管理] 加载预设完成")
    }
}

// MARK: - 新的全局标签图谱预设行视图

struct NewGlobalTagGraphPresetRowView: View {
    let preset: GraphPreset
    let isCurrent: Bool
    let onLoad: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 预设标题行
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(preset.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if isCurrent {
                            Text("当前")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                    }
                    
                    if let description = preset.description {
                        Text(description)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                // 操作按钮
                HStack(spacing: 8) {
                    Button("加载") {
                        onLoad()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    if isHovered {
                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("删除预设")
                    }
                }
            }
            
            // 预设内容概览
            HStack(spacing: 20) {
                // 过滤条件信息
                HStack(spacing: 12) {
                    if !preset.filteredLayers.isEmpty {
                        Label("\(preset.filteredLayers.count) 层级", systemImage: "folder")
                    }
                    if !preset.filteredTagTypes.isEmpty {
                        Label("\(preset.filteredTagTypes.count) 类型", systemImage: "tag")
                    }
                    if !preset.filteredTagValues.isEmpty {
                        Label("\(preset.filteredTagValues.count) 标签", systemImage: "bookmark")
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                
                Spacer()
                
                // 时间信息
                VStack(alignment: .trailing, spacing: 2) {
                    Text("创建: \(preset.createdAt, formatter: dateFormatter)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Text("使用: \(preset.lastUsed, formatter: dateFormatter)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrent ? Color.green.opacity(0.05) : Color(NSColor.controlBackgroundColor))
                .stroke(
                    isCurrent ? Color.green.opacity(0.3) : (isHovered ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2)),
                    lineWidth: isCurrent ? 2 : (isHovered ? 1.5 : 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            // 单击加载预设
            onLoad()
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}