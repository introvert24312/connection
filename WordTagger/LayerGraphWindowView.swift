import SwiftUI

// MARK: - 层图谱窗口视图

struct LayerGraphWindowView: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var presetManager = LayerGraphPresetManager.shared
    @State private var windowId = UUID()
    
    // 当前筛选的层
    @State private var filteredLayerIds: Set<UUID> = []
    
    // 图谱相关状态
    @State private var cachedNodes: [LayerGraphNode] = []
    @State private var cachedEdges: [LayerGraphEdge] = []
    @State private var selectedLayerId: UUID?
    
    // UI状态
    @State private var showingPresetSaveDialog = false
    @State private var newPresetName = ""
    @State private var showingPresetMenu = false
    
    
    // 使用设置中的层结构图谱缩放级别
    @AppStorage("layerStructureGraphInitialScale") private var layerGraphInitialScale: Double = 0.9
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏（仿照全局标签图谱）
            toolbar
            
            Divider()
            
            // 图谱内容
            graphContent
        }
        .registerWindow(windowId, type: .graph, displayName: "层结构图谱")
        .onAppear {
            setupWindow()
        }
        .onChange(of: store.layers) { _, _ in
            updateGraphData()
            // 更新默认预设（如果当前是默认预设）
            presetManager.updateDefaultPreset(allLayers: store.layers)
        }
        .onChange(of: filteredLayerIds) { _, _ in
            updateGraphData()
        }
        .alert("保存层图谱预设", isPresented: $showingPresetSaveDialog) {
            TextField("预设名称", text: $newPresetName)
            
            Button("保存") {
                if !newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    presetManager.savePreset(
                        name: newPresetName.trimmingCharacters(in: .whitespacesAndNewlines),
                        filteredLayerIds: filteredLayerIds
                    )
                    newPresetName = ""
                }
            }
            .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            
            Button("取消", role: .cancel) {
                newPresetName = ""
            }
        } message: {
            Text("为当前的层选择状态创建一个预设，以便后续快速加载。")
        }
    }
    
    // MARK: - 顶部工具栏（参考全局标签图谱的设计）
    
    private var toolbar: some View {
        HStack(alignment: .center, spacing: 8) {
            // 左侧：过滤状态显示
            filterStatusView
            
            Spacer()
            
            HStack(spacing: 8) {
                // 层预设按钮组
                Button("层预设") {
                    showingPresetMenu.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $showingPresetMenu) {
                    presetMenuView
                }
                
                Button("保存为预设") {
                    showingPresetSaveDialog = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(filteredLayerIds.isEmpty)
                
                Divider()
                    .frame(height: 20)
                
                Button("重置视图") {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        resetGraphView()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                // 层看板按钮
                Button("层看板") {
                    showLayerSelectionWindow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("刷新") {
                    updateGraphData()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - 图谱内容
    
    private var graphContent: some View {
        Group {
            if cachedNodes.isEmpty {
                emptyGraphView
            } else {
                layerGraph
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyGraphView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("暂无层数据")
                .font(.body)
                .foregroundColor(.secondary)
            
            Text("使用预设或筛选层来显示图谱")
                .font(.caption)
                .foregroundColor(Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var layerGraph: some View {
        NodeContextGraphView(
            nodes: cachedNodes,
            edges: cachedEdges,
            title: "层结构图谱",
            initialScale: layerGraphInitialScale,
            onNodeSelected: { nodeId, commandPressed in
                handleNodeSelected(nodeId: nodeId, commandPressed: commandPressed)
            },
            onNodeDeselected: {
                selectedLayerId = nil
            }
        )
        .environmentObject(store)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 预设保存对话框
    
    private var presetSaveDialog: some View {
        VStack(spacing: 16) {
            Text("保存层组合预设")
                .font(.headline)
            
            TextField("预设名称", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
            
            Text("将保存当前选中的 \(filteredLayerIds.count) 个层")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Button("取消") {
                    showingPresetSaveDialog = false
                }
                
                Spacer()
                
                Button("保存") {
                    saveCurrentPreset()
                    showingPresetSaveDialog = false
                }
                .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
    
    // MARK: - 辅助方法
    
    private func setupWindow() {
        // 建立窗口映射关系
        if let activeWindowId = WindowFocusManager.shared.activeWindowInfo?.id {
            WindowFocusManager.shared.createWindowMapping(
                childWindowId: windowId.uuidString,
                sourceWindowId: activeWindowId
            )
            print("🔗 LayerGraphWindow: 建立窗口映射 - 图谱窗口(\(windowId.uuidString.prefix(8))) <- 主窗口(\(activeWindowId.prefix(8)))")
        }
        
        // 加载当前预设或默认预设
        let currentPreset = presetManager.getCurrentPreset(allLayers: store.layers)
        filteredLayerIds = currentPreset.filteredLayerIds
        selectedLayerId = store.currentLayer?.id
        
        updateGraphData()
    }
    
    private func handleNodeSelected(nodeId: Int, commandPressed: Bool) {
        guard let selectedGraphNode = cachedNodes.first(where: { $0.id == nodeId }),
              let layerId = selectedGraphNode.layerId,
              let targetLayer = store.layers.first(where: { $0.id == layerId }) else {
            return
        }
        
        if commandPressed {
            // ⌘+点击：通知对应的主窗口切换层
            if !targetLayer.isCompound {
                switchToLayerInMainWindow(targetLayer)
            } else {
                print("⚠️ 复合层不支持切换")
            }
        } else {
            // 普通点击：只选中
            selectedLayerId = layerId
            print("🔍 选中层: \(targetLayer.displayName)")
        }
    }
    
    private func switchToLayerInMainWindow(_ layer: Layer) {
        // 获取对应的主窗口ID
        let sourceWindowId = WindowFocusManager.shared.getSourceWindowId(for: windowId.uuidString)
        
        print("🔄 LayerGraphWindow: 切换到层 '\(layer.displayName)'")
        print("   - 目标主窗口: \(sourceWindowId?.prefix(8) ?? "unknown")")
        
        // 通知对应的主窗口切换层
        NotificationCenter.default.post(
            name: NSNotification.Name("switchToLayer"),
            object: layer,
            userInfo: ["sourceWindowId": sourceWindowId ?? ""]
        )
    }
    
    private func loadPreset(_ preset: LayerGraphPreset) {
        presetManager.loadPreset(preset)
        filteredLayerIds = preset.filteredLayerIds
        print("📂 LayerGraphWindow: 加载预设 '\(preset.name)' - \(preset.filteredLayerIds.count)个层")
    }
    
    private func saveCurrentPreset() {
        let trimmedName = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        presetManager.savePreset(name: trimmedName, filteredLayerIds: filteredLayerIds)
    }
    
    private func getCurrentPresetName() -> String {
        if let current = presetManager.currentPreset {
            return current.name
        } else {
            return "默认"
        }
    }
    
    private func updateGraphData() {
        let data = calculateLayerGraphData()
        cachedNodes = data.nodes
        cachedEdges = data.edges
    }
    
    private func calculateLayerGraphData() -> (nodes: [LayerGraphNode], edges: [LayerGraphEdge]) {
        var nodes: [LayerGraphNode] = []
        var edges: [LayerGraphEdge] = []
        
        if filteredLayerIds.isEmpty {
            return (nodes: nodes, edges: edges)
        }
        
        let filteredLayers = store.layers.filter { filteredLayerIds.contains($0.id) }
        let compoundLayers = filteredLayers.filter { $0.isCompound }
        let regularLayers = filteredLayers.filter { !$0.isCompound }
        
        // 添加复合层
        for layer in compoundLayers {
            let nodeCount = store.nodes.filter { $0.layerId == layer.id }.count
            let isSelected = layer.id == selectedLayerId
            nodes.append(LayerGraphNode(layer: layer, nodeCount: nodeCount, isSelected: isSelected, allLayers: store.layers))
        }
        
        // 添加独立的普通层
        let childLayerIds = Set(compoundLayers.flatMap { $0.childLayerIds })
        let independentLayers = regularLayers.filter { !childLayerIds.contains($0.id) }
        
        for layer in independentLayers {
            let nodeCount = store.nodes.filter { $0.layerId == layer.id }.count
            let isSelected = layer.id == selectedLayerId
            nodes.append(LayerGraphNode(layer: layer, nodeCount: nodeCount, isSelected: isSelected, allLayers: store.layers))
        }
        
        // 添加子层
        let childLayers = regularLayers.filter { childLayerIds.contains($0.id) }
        for layer in childLayers {
            let nodeCount = store.nodes.filter { $0.layerId == layer.id }.count
            let isSelected = layer.id == selectedLayerId
            nodes.append(LayerGraphNode(layer: layer, nodeCount: nodeCount, isSelected: isSelected, allLayers: store.layers))
        }
        
        // 创建连接
        for layer in compoundLayers {
            guard let parentNode = nodes.first(where: { $0.layerId == layer.id }) else { continue }
            
            for childLayerId in layer.childLayerIds {
                if let childNode = nodes.first(where: { $0.layerId == childLayerId }) {
                    edges.append(LayerGraphEdge(
                        from: parentNode,
                        to: childNode,
                        relationshipType: "包含"
                    ))
                }
            }
        }
        
        return (nodes: nodes, edges: edges)
    }
    
    // MARK: - 过滤状态视图
    private var filterStatusView: some View {
        HStack(spacing: 8) {
            if !filteredLayerIds.isEmpty {
                Image(systemName: "line.horizontal.3.decrease.circle")
                    .foregroundColor(.blue)
                
                Text(buildFilterText())
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Image(systemName: "square.stack.3d.forward.dottedline")
                    .foregroundColor(.green)
                Text("显示所有层")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxHeight: 30)
    }
    
    // MARK: - 预设菜单视图
    private var presetMenuView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("层预设管理")
                .font(.headline)
                .padding(.horizontal)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 4) {
                    // 默认预设
                    let defaultPreset = presetManager.getDefaultPreset(allLayers: store.layers)
                    PresetRow(
                        preset: defaultPreset,
                        isSelected: presetManager.currentPreset?.id == defaultPreset.id,
                        isDefault: true,
                        onSelect: { loadPreset(defaultPreset) }
                    )
                    
                    if !presetManager.presets.isEmpty {
                        Divider()
                        
                        // 用户预设
                        ForEach(presetManager.presets.sorted { $0.lastUsedAt > $1.lastUsedAt }) { preset in
                            PresetRow(
                                preset: preset,
                                isSelected: presetManager.currentPreset?.id == preset.id,
                                isDefault: false,
                                onSelect: { loadPreset(preset) },
                                onDelete: { presetManager.deletePreset(preset) }
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 280)
        .padding(.vertical, 8)
    }
    
    // MARK: - 辅助方法
    
    private func showSavePresetDialog() {
        newPresetName = ""
        showingPresetSaveDialog = true
    }
    
    private func resetGraphView() {
        // 重置图谱视图，类似全局标签图谱的重置功能
        updateGraphData()
        print("🔄 LayerGraphWindow: 重置图谱视图")
    }
    
    private func showLayerSelectionWindow() {
        let layerBoardView = LayerSelectionBoardView(
            layers: store.layers,
            selectedLayerIds: $filteredLayerIds,
            onClose: { }  // Window will handle its own closing
        )
        .environmentObject(store)
        
        let hostingView = NSHostingView(rootView: layerBoardView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 600, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.contentView = hostingView
        newWindow.title = "层看板"
        newWindow.setFrameAutosaveName("LayerSelectionBoardWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        
        print("🪟 [层看板] 窗口已创建")
    }
    
    private func buildFilterText() -> String {
        if filteredLayerIds.isEmpty {
            return ""
        }
        
        let count = filteredLayerIds.count
        let total = store.layers.count
        
        if count == total {
            return "显示全部 \(total) 层"
        } else {
            return "已选择 \(count)/\(total) 层"
        }
    }
}

// MARK: - 预设行组件
struct PresetRow: View {
    let preset: LayerGraphPreset
    let isSelected: Bool
    let isDefault: Bool
    let onSelect: () -> Void
    var onDelete: (() -> Void)? = nil
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // 选中状态指示器
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.system(size: 14))
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(preset.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        
                        if isDefault {
                            Text("默认")
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                        }
                        
                        Spacer()
                        
                        Text("\(preset.filteredLayerIds.count) 层")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    if !isDefault {
                        Text("上次使用: \(formatDate(preset.lastUsedAt))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                // 删除按钮（仅对用户创建的预设显示）
                if !isDefault, let onDelete = onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.7))
                            .font(.system(size: 12))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("删除预设")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 层选择看板视图
struct LayerSelectionBoardView: View {
    let layers: [Layer]
    @Binding var selectedLayerIds: Set<UUID>
    let onClose: () -> Void
    
    @State private var searchText = ""
    @State private var showActiveOnly = false
    
    private var filteredLayers: [Layer] {
        let filtered = layers.filter { layer in
            let matchesSearch = searchText.isEmpty || 
                               layer.displayName.localizedCaseInsensitiveContains(searchText) ||
                               layer.name.localizedCaseInsensitiveContains(searchText)
            let matchesActive = !showActiveOnly || layer.isActive
            return matchesSearch && matchesActive
        }
        return filtered.sorted { $0.displayName < $1.displayName }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("层看板")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("完成") {
                    // Close the current window
                    if let window = NSApplication.shared.keyWindow {
                        window.close()
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 搜索和筛选栏
            VStack(spacing: 12) {
                HStack {
                    // 搜索框
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("搜索层...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    // 仅显示活跃层
                    Toggle("仅活跃", isOn: $showActiveOnly)
                        .toggleStyle(SwitchToggleStyle())
                }
                
                // 操作按钮行
                HStack {
                    Button("全选") {
                        selectedLayerIds = Set(filteredLayers.map { $0.id })
                    }
                    .buttonStyle(.bordered)
                    
                    Button("清空") {
                        selectedLayerIds.removeAll()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("反选") {
                        let allIds = Set(filteredLayers.map { $0.id })
                        selectedLayerIds = allIds.subtracting(selectedLayerIds)
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Text("\(selectedLayerIds.count)/\(layers.count) 已选择")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 层列表 - 使用网格布局
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(filteredLayers) { layer in
                        LayerSelectionCard(
                            layer: layer,
                            isSelected: selectedLayerIds.contains(layer.id),
                            onToggle: {
                                if selectedLayerIds.contains(layer.id) {
                                    selectedLayerIds.remove(layer.id)
                                } else {
                                    selectedLayerIds.insert(layer.id)
                                }
                            }
                        )
                    }
                }
                .padding()
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 500, minHeight: 600)
    }
}

// MARK: - 层选择卡片
struct LayerSelectionCard: View {
    let layer: Layer
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 8) {
                // 顶部：选择状态和颜色指示器
                HStack {
                    // 层颜色指示器
                    Circle()
                        .fill(Color.from(layer.color))
                        .frame(width: 16, height: 16)
                        .shadow(radius: 1)
                    
                    Spacer()
                    
                    // 状态指示器
                    HStack(spacing: 4) {
                        if layer.isActive {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                        }
                        
                        if layer.isCompound {
                            Image(systemName: "square.stack.3d.up")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Spacer()
                    
                    // 选择状态指示器
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(isSelected ? .blue : .secondary)
                }
                
                // 中间：层名称
                VStack(spacing: 2) {
                    Text(layer.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    
                    Text(layer.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // 底部：额外信息
                if layer.isCompound && !layer.childLayerIds.isEmpty {
                    Text("\(layer.childLayerIds.count) 子层")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(3)
                } else {
                    // 占位空间保持卡片高度一致
                    Text("")
                        .font(.caption2)
                }
            }
            .padding(12)
            .frame(minHeight: 100)  // 设置最小高度保持一致性
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
    }
}

// MARK: - 预览

#Preview {
    LayerGraphWindowView()
        .environmentObject(NodeStore.shared)
}