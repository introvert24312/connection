import SwiftUI
import AppKit

struct GraphView: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var dataManager = NodeGraphDataManager()  // 🆕 每个视图独立的数据管理器
    @AppStorage("globalGraphInitialScale") private var globalGraphInitialScale: Double = 1.0
    @State private var cachedNodes: [NodeGraphNode] = []
    @State private var cachedEdges: [NodeGraphEdge] = []
    @State private var showingNodeSelector = false
    
    // 层级筛选状态
    @State private var showingLayerSelector = false
    
    // 预设和看板状态
    @State private var showingPresetManager = false
    @State private var showingSavePresetDialog = false
    @State private var newPresetName = ""
    @State private var newPresetDescription = ""
    
    // 🆕 使用数据管理器生成图谱数据
    private func updateGraphData() {
        // 🔒 如果图谱被锁定，不更新数据
        guard !dataManager.isLocked else {
            print("🔒 [全局节点图谱] 图谱已锁定，跳过数据更新")
            return
        }
        
        let data = dataManager.generateGraphData(from: store)
        cachedNodes = data.nodes
        cachedEdges = data.edges
    }
    
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                // 左侧：过滤信息显示
                buildFilterInfoView()
                
                Spacer()
                
                // 图谱预设按钮
                Button("图谱预设") {
                    showingPresetManager = true
                    print("📚 [全局节点图谱] 打开预设管理")
                }
                .buttonStyle(.bordered)
                .help("管理图谱预设")
                
                // 保存为预设按钮
                Button("保存为预设") {
                    showingSavePresetDialog = true
                    print("💾 [全局节点图谱] 保存当前状态为预设")
                }
                .buttonStyle(.bordered)
                .help("保存当前状态为预设")
                .disabled(dataManager.selectedNodeIds.isEmpty && dataManager.selectedLayerIds.isEmpty)
                
                // 🔒 锁定/解锁按钮
                Button(dataManager.isLocked ? "🔓 解锁" : "🔒 锁定") {
                    dataManager.toggleLockState(with: store)
                    updateGraphData()
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(dataManager.isLocked ? Color.orange.opacity(0.2) : Color.blue.opacity(0.1))
                .foregroundColor(dataManager.isLocked ? .orange : .blue)
                .cornerRadius(6)
                .help(dataManager.isLocked ? "解锁图谱以接收数据更新" : "锁定图谱以固定当前显示内容")
                
                // 节点看板按钮
                Button("节点看板") {
                    showNodeBoardWindow()
                    print("📋 [全局节点图谱] 打开节点看板")
                }
                .buttonStyle(.borderedProminent)
                .help("打开节点看板")
                
                // 重置按钮
                if dataManager.hasActiveFilters {
                    Button("显示全部") {
                        dataManager.clearAllFilters()
                        updateGraphData()
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
                NodeContextGraphView(
                    nodes: cachedNodes,
                    edges: cachedEdges,
                    title: "全局节点图谱",
                    initialScale: globalGraphInitialScale,
                    onNodeSelected: { nodeId, commandPressed, optionPressed in
                        // 检测Option键，处理节点文件夹功能
                        if optionPressed {
                            print("⌥ Option+点击节点，ID: \(nodeId)")
                            if let selectedGraphNode = cachedNodes.first(where: { $0.id == nodeId }),
                               let selectedNode = selectedGraphNode.node {
                                // 打开节点文件夹
                                NodeFolderManager.shared.openNodeFolderInFinder(selectedNode)
                            }
                            return
                        }
                        
                        // 当点击节点时，选择对应的节点（只有节点才会触发选择）
                        if let selectedGraphNode = cachedNodes.first(where: { $0.id == nodeId }),
                           let selectedNode = selectedGraphNode.node {
                            store.selectNode(selectedNode)
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environmentObject(store)
            }
        }
        .sheet(isPresented: $showingNodeSelector) {
            NodeSelectorView(selectedNodeIds: $dataManager.selectedNodeIds)
                .environmentObject(store)
                .frame(width: 700, height: 600)
                .background(WindowAccessor())
        }
        .sheet(isPresented: $showingLayerSelector) {
            LayerSelectorView(selectedLayerIds: $dataManager.selectedLayerIds)
                .environmentObject(store)
                .frame(width: 600, height: 500)
                .background(LayerWindowAccessor())
        }
        .sheet(isPresented: $showingPresetManager) {
            NodeGraphPresetManagerView(
                selectedNodeIds: $dataManager.selectedNodeIds,
                selectedLayerIds: $dataManager.selectedLayerIds
            )
            .environmentObject(store)
            .frame(width: 800, height: 600)
        }
        .alert("保存节点图谱预设", isPresented: $showingSavePresetDialog) {
            TextField("预设名称", text: $newPresetName)
            TextField("描述（可选）", text: $newPresetDescription)
            
            Button("保存") {
                if !newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    saveCurrentAsPreset()
                    newPresetName = ""
                    newPresetDescription = ""
                }
            }
            .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            
            Button("取消", role: .cancel) {
                newPresetName = ""
                newPresetDescription = ""
            }
        } message: {
            Text("为当前的节点和层级筛选状态创建一个预设，以便后续快速加载。")
        }
        .onKeyPress(.init("k"), phases: .down) { _ in
            NotificationCenter.default.post(name: Notification.Name("fitGraph"), object: nil)
            return .handled
        }
        .onAppear {
            print("📋 [全局节点图谱] 视图出现，初始化数据管理器")
            updateGraphData()
        }
        .onChange(of: store.nodes) {
            updateGraphData()
        }
        .onChange(of: dataManager.selectedNodeIds) {
            updateGraphData()
        }
        .onChange(of: dataManager.selectedLayerIds) {
            updateGraphData()
        }
        .onChange(of: dataManager.displayedNodes) {
            updateGraphData()
        }
        .onChange(of: store.selectedTag) {
            updateGraphData()
        }
        .onChange(of: store.showAllTagTypeNodes) {
            updateGraphData()
        }
        .onChange(of: store.expandedTagTypes) {
            updateGraphData()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NodeBoardSelectionChanged"))) { notification in
            if let userInfo = notification.userInfo,
               let nodeIds = userInfo["selectedNodeIds"] as? [UUID],
               let layerIds = userInfo["selectedLayerIds"] as? [UUID] {
                
                print("🔄 GraphView: 收到节点看板选择变化通知")
                print("   - 节点: \(nodeIds.count) 个")
                print("   - 层级: \(layerIds.count) 个")
                
                // 更新数据管理器的选择状态
                dataManager.updateSelectedNodes(Set(nodeIds))
                dataManager.updateSelectedLayers(Set(layerIds))
                
                // 强制更新图谱数据
                updateGraphData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("compoundNodeRefreshed"))) { notification in
            print("📨 [GraphView] 收到复合节点刷新通知！")
            
            if let userInfo = notification.userInfo {
                print("   - 通知数据: \(userInfo)")
                if let compoundNodeId = userInfo["compoundNodeId"] as? UUID,
                   let compoundNodeName = userInfo["compoundNodeName"] as? String,
                   let childNodeName = userInfo["childNodeName"] as? String {
                    print("   - 复合节点: \(compoundNodeName) (ID: \(compoundNodeId))")
                    print("   - 子节点: \(childNodeName)")
                }
            }
            
            // 如果图谱被锁定，不进行更新
            if !dataManager.isLocked {
                print("🔄 GraphView: 开始更新图谱数据...")
                // 强制更新图谱数据以反映复合节点的最新状态
                updateGraphData()
                print("✅ GraphView: 图谱已更新以反映复合节点变化")
            } else {
                print("🔒 GraphView: 图谱已锁定，跳过更新")
            }
        }
        .navigationTitle("全局节点图谱")
    }
    
    
    // MARK: - 过滤信息显示
    
    @ViewBuilder
    private func buildFilterInfoView() -> some View {
        if dataManager.isLocked {
            // 🔒 锁定状态显示
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                
                Text("图谱已锁定")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fontWeight(.medium)
                
                Text("(\(dataManager.lockedNodes?.count ?? 0) 个节点)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if dataManager.hasActiveFilters {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                Text(dataManager.buildFilterDescription(with: store))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "circle.hexagonpath")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                Text("节点: \(store.nodes.count) | 层级: \(store.layers.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    
    // MARK: - 预设和看板功能
    
    private func showNodeBoardWindow() {
        // 创建节点看板窗口
        let nodeBoardView = NodeBoardView()
        .environmentObject(store)
        
        let hostingView = NSHostingView(rootView: nodeBoardView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.contentView = hostingView
        newWindow.title = "节点看板"
        newWindow.setFrameAutosaveName("NodeBoardWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        
        print("🪟 [节点看板] 窗口已创建")
    }
    
    private func saveCurrentAsPreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = newPresetDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !name.isEmpty else { return }
        
        // 创建并保存节点图谱预设
        let preset = NodeGraphPreset(
            name: name,
            description: description.isEmpty ? nil : description,
            selectedNodeIds: dataManager.selectedNodeIds,
            selectedLayerIds: dataManager.selectedLayerIds,
            createdAt: Date(),
            lastUsed: Date()
        )
        
        NodeGraphPresetManager.shared.savePreset(preset)
        
        print("💾 保存节点图谱预设: \(name)")
        print("   - 选中节点数: \(dataManager.selectedNodeIds.count)")
        print("   - 选中层数: \(dataManager.selectedLayerIds.count)")
        print("   - 描述: \(description.isEmpty ? "无" : description)")
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
            
            Text("添加一些节点来生成全局节点图谱")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}






// MARK: - 层级分组标题
struct LayerSectionHeader: View {
    let layer: Layer
    let nodeCount: Int
    let isSelected: Bool
    let onLayerTapped: (NSEvent) -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            // 选中状态指示器
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundColor(isSelected ? .blue : .secondary)
            
            // 层级颜色指示器
            Circle()
                .fill(Color.from(layer.color))
                .frame(width: 16, height: 16)
                .shadow(radius: 1)
            
            Text(layer.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isSelected ? .blue : .primary)
            
            Text("(\(nodeCount))")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            
            if layer.isCompound {
                Image(systemName: "square.stack.3d.up")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            Spacer()
            
            // 提示文字
            if isHovered {
                Text("点击选择整个层级 • ⌘+点击多选")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            // 由于无法直接获取NSEvent，我们创建一个模拟事件
            let currentEvent = NSApp.currentEvent ?? NSEvent()
            onLayerTapped(currentEvent)
        }
        .help("点击选择整个层级，Command+点击进行多选")
    }
}

// MARK: - 紧凑节点卡片
struct CompactNodeCard: View {
    let node: Node
    let layer: Layer
    let isSelected: Bool
    let onNodeTapped: (NSEvent) -> Void
    @EnvironmentObject private var store: NodeStore
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 节点名称和选中状态
            HStack {
                Text(node.text)
                    .font(.system(size: 16, weight: .medium))  // 增大字体从13到16
                    .foregroundColor(isSelected ? .blue : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                // 选中状态指示器
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))  // 增大图标
                        .foregroundColor(.blue)
                }
            }
            
            // 节点含义
            if let meaning = node.meaning {
                Text(meaning)
                    .font(.system(size: 14))  // 增大字体从12到14
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            
            // 显示主要标签
            if !node.tags.isEmpty {
                let displayTags = Array(node.tags.prefix(3))  // 显示前3个标签
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 4) {
                    ForEach(displayTags.indices, id: \.self) { index in
                        let tag = displayTags[index]
                        HStack(spacing: 2) {
                            Text(tag.type.displayName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.blue)
                                .lineLimit(1)
                            Text(tag.value)
                                .font(.system(size: 11))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
                }
            }
            
            Spacer()
            
            // 底部信息栏
            HStack {
                // 标签总数指示器
                if !node.tags.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .font(.system(size: 12))  // 增大图标
                            .foregroundColor(.blue)
                        Text("\(node.tags.count)")
                            .font(.system(size: 12))  // 增大字体从10到12
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // 节点类型指示器
                if node.isCompound {
                    HStack(spacing: 2) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 12))  // 增大图标
                            .foregroundColor(.purple)
                        Text("复合")
                            .font(.system(size: 11))
                            .foregroundColor(.purple)
                    }
                }
            }
        }
        .padding(14)  // 增大内边距
        .frame(minHeight: 140, maxHeight: 160)  // 增大卡片高度
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.blue.opacity(0.1) : (isHovered ? Color.blue.opacity(0.05) : Color(NSColor.controlBackgroundColor)))
                .stroke(
                    isSelected ? Color.blue : (isHovered ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2)),
                    lineWidth: isSelected ? 2 : (isHovered ? 1.5 : 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            let currentEvent = NSApp.currentEvent ?? NSEvent()
            onNodeTapped(currentEvent)
        }
        .help(buildTooltipWithSelection())
    }
    
    private func buildTooltipWithSelection() -> String {
        var tooltip = node.text
        if let meaning = node.meaning {
            tooltip += "\n\n\(meaning)"
        }
        tooltip += "\n\n层级: \(layer.displayName)"
        if !node.tags.isEmpty {
            tooltip += "\n标签数量: \(node.tags.count)"
        }
        tooltip += "\n\n点击选择节点 • ⌘+点击多选"
        if isSelected {
            tooltip += "\n✅ 当前已选中"
        }
        return tooltip
    }
}

// MARK: - 节点图谱预设管理视图

struct NodeGraphPresetManagerView: View {
    @Binding var selectedNodeIds: Set<UUID>
    @Binding var selectedLayerIds: Set<UUID>
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var presetManager = NodeGraphPresetManager.shared
    
    @State private var searchText = ""
    @State private var showingDeleteAlert = false
    @State private var presetToDelete: NodeGraphPreset?
    
    private var filteredPresets: [NodeGraphPreset] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return presetManager.presetsSortedByLastUsed
        }
        
        return presetManager.presets.filter { preset in
            preset.name.localizedCaseInsensitiveContains(searchText) ||
            preset.description?.localizedCaseInsensitiveContains(searchText) == true
        }.sorted { $0.lastUsed > $1.lastUsed }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("节点图谱预设管理")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("(\(presetManager.presets.count) 个预设)")
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
                    
                    Text(searchText.isEmpty ? "暂无保存的节点图谱预设" : "没有找到匹配的预设")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if searchText.isEmpty {
                        Text("在全局节点图谱中选择节点和层级后，点击\"保存为预设\"来创建您的第一个预设。")
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
                            PresetRowView(
                                preset: preset,
                                isCurrentPreset: presetManager.currentPreset?.id == preset.id,
                                store: store,
                                onLoad: {
                                    let result = presetManager.loadPreset(preset)
                                    selectedNodeIds = result.selectedNodeIds
                                    selectedLayerIds = result.selectedLayerIds
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
        .alert("删除预设", isPresented: $showingDeleteAlert, presenting: presetToDelete) { preset in
            Button("删除", role: .destructive) {
                presetManager.deletePreset(preset)
                presetToDelete = nil
            }
            Button("取消", role: .cancel) {
                presetToDelete = nil
            }
        } message: { preset in
            Text("确定要删除预设 \"\(preset.name)\" 吗？此操作无法撤销。")
        }
    }
}

// MARK: - 预设行视图

struct PresetRowView: View {
    let preset: NodeGraphPreset
    let isCurrentPreset: Bool
    let store: NodeStore
    let onLoad: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    private func getNodeNames(for nodeIds: Set<UUID>) -> [String] {
        return store.nodes
            .filter { nodeIds.contains($0.id) }
            .map { $0.text }
            .sorted()
    }
    
    private func getLayerNames(for layerIds: Set<UUID>) -> [String] {
        return store.layers
            .filter { layerIds.contains($0.id) }
            .map { $0.displayName }
            .sorted()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 预设标题行
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(preset.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if isCurrentPreset {
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
                // 节点信息
                if !preset.selectedNodeIds.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "circle")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            Text("节点 (\(preset.selectedNodeIds.count))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        
                        let nodeNames = getNodeNames(for: preset.selectedNodeIds)
                        Text(nodeNames.prefix(3).joined(separator: ", ") + (nodeNames.count > 3 ? "..." : ""))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                // 层级信息
                if !preset.selectedLayerIds.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "square.stack")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                            Text("层级 (\(preset.selectedLayerIds.count))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                        }
                        
                        let layerNames = getLayerNames(for: preset.selectedLayerIds)
                        Text(layerNames.prefix(3).joined(separator: ", ") + (layerNames.count > 3 ? "..." : ""))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
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
                .fill(isCurrentPreset ? Color.green.opacity(0.05) : Color(NSColor.controlBackgroundColor))
                .stroke(
                    isCurrentPreset ? Color.green.opacity(0.3) : (isHovered ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2)),
                    lineWidth: isCurrentPreset ? 2 : (isHovered ? 1.5 : 1)
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


#Preview {
    GraphView()
        .environmentObject(NodeStore.shared)
}

// MARK: - 全局节点图谱窗口管理器 - 支持多开版本

/// 全局节点图谱窗口管理器，支持多开模式，每个窗口都有独立的数据管理器
@MainActor
class NodeGraphWindowManager: ObservableObject {
    static let shared = NodeGraphWindowManager()
    
    // 不再保存窗口引用，每次都创建新窗口以支持多开
    private init() {
        print("🏗️ [节点图谱窗口管理器] 初始化，支持多开模式")
    }
    
    /// 显示全局节点图谱窗口 - 支持多开
    func showNodeGraphWindow() {
        print("🪟 [节点图谱窗口管理器] 创建新的节点图谱窗口")
        
        // 🆕 每次都创建新的GraphView实例，每个实例都有独立的数据管理器
        let contentView = GraphView()
            .environmentObject(NodeStore.shared)
        
        let hostingView = NSHostingView(rootView: contentView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.contentView = hostingView
        newWindow.title = "全局节点图谱"
        newWindow.setFrameAutosaveName("NodeGraphWindow")
        newWindow.isReleasedWhenClosed = false
        
        // 窗口关闭处理 - 不保存窗口引用
        let delegate = NodeGraphWindowDelegate {
            print("🗑️ [节点图谱窗口] 窗口已关闭")
        }
        newWindow.delegate = delegate
        
        // 🆕 多开支持：不再保存窗口引用，每次都创建新窗口
        newWindow.makeKeyAndOrderFront(nil)
        
        print("✅ [节点图谱窗口管理器] 新窗口已创建并显示")
    }
}

// MARK: - 节点图谱窗口委托

private class NodeGraphWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}