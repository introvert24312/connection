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
    
    // 层搜索/创建状态
    @State private var layerSearchText = ""
    @FocusState private var isSearchFieldFocused: Bool
    @State private var matchedLayers: [Layer] = []
    @State private var showingLayerDropdown = false
    
    
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
            // 设置输入框焦点
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
            }
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
        .background {
            Button("") {
                createNewLayer()
            }
            .keyboardShortcut("r", modifiers: .command)
            .hidden()
        }
    }
    
    // MARK: - 顶部工具栏（参考全局标签图谱的设计）
    
    private var toolbar: some View {
        HStack(alignment: .center, spacing: 12) {
            // 左侧：过滤状态显示
            filterStatusView
            
            Spacer()
            
            // 层搜索输入框（居中显示）
            TextField("新建层", text: $layerSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300, height: 32)
                .controlSize(.large)
                .font(.system(size: 14, weight: .medium))
                .focused($isSearchFieldFocused)
                .onSubmit {
                    switchToMatchedLayer()
                }
                .onChange(of: layerSearchText) { _, newValue in
                    updateMatchedLayers(searchText: newValue)
                    showingLayerDropdown = !matchedLayers.isEmpty && !newValue.isEmpty
                }
                .popover(isPresented: $showingLayerDropdown, arrowEdge: .bottom) {
                    layerDropdownView
                }
            
            Spacer()
            
            HStack(spacing: 8) {
                // 层预设按钮组
                Button("层预设") {
                    showingPresetMenu.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $showingPresetMenu, arrowEdge: .bottom) {
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
            onNodeSelected: { nodeId, commandPressed, optionPressed in
                handleNodeSelected(nodeId: nodeId, commandPressed: commandPressed, optionPressed: optionPressed)
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
    
    // MARK: - 层下拉框视图
    
    private var layerDropdownView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(matchedLayers.prefix(5)) { layer in
                LayerDropdownItem(
                    layer: layer,
                    searchText: layerSearchText,
                    onSelect: { selectedLayer in
                        selectLayerFromDropdown(selectedLayer)
                        showingLayerDropdown = false
                    }
                )
            }
            
            if matchedLayers.count > 5 {
                HStack {
                    Text("…还有\(matchedLayers.count - 5)个匹配项")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
        }
        .frame(width: 300)
    }
    
    // MARK: - 辅助方法
    
    /// 查找启动层图谱的源主窗口
    /// 通过窗口激活历史来确定是哪个主窗口打开了这个层图谱
    private func findSourceMainWindow() -> String? {
        let windowManager = WindowFocusManager.shared
        
        // 获取窗口激活历史
        let activationHistory = windowManager.getWindowActivationHistory()
        
        print("🔍 LayerGraphWindow: 查找源主窗口")
        print("   - 当前层图谱窗口ID: \(windowId.uuidString.prefix(8))")
        print("   - 窗口激活历史: [\(activationHistory.map { $0.prefix(8) }.joined(separator: ", "))]")
        
        // 🔧 从激活历史中查找最近的主窗口（排除当前层图谱窗口）
        if let recentMainWindowId = windowManager.getRecentMainWindowFromHistory(excluding: windowId.uuidString) {
            print("✅ LayerGraphWindow: 从激活历史找到源主窗口 - (\(recentMainWindowId.prefix(8)))")
            return recentMainWindowId
        }
        
        // 回退到第一个主窗口
        if let firstMainWindowId = windowManager.getMainWindowId() {
            print("⚠️ LayerGraphWindow: 回退到第一个主窗口 - (\(firstMainWindowId.prefix(8)))")
            return firstMainWindowId
        }
        
        print("❌ LayerGraphWindow: 无法找到任何主窗口")
        return nil
    }
    
    private func setupWindow() {
        // 🔧 建立窗口映射关系 - 将当前的层图谱窗口映射到启动它的主窗口
        // 从激活历史中找到最近的主窗口（在层图谱窗口打开之前的活跃主窗口）
        let targetMainWindowId = findSourceMainWindow()
        
        if let sourceWindowId = targetMainWindowId {
            // 建立常规窗口映射
            WindowFocusManager.shared.createWindowMapping(
                childWindowId: windowId.uuidString,
                sourceWindowId: sourceWindowId
            )
            
            // 🔧 注册层图谱窗口映射（一对一关系）
            WindowFocusManager.shared.registerLayerGraphWindow(
                mainWindowId: sourceWindowId,
                layerGraphWindowId: windowId.uuidString
            )
            
            print("🔗 LayerGraphWindow: 建立窗口映射 - 图谱窗口(\(windowId.uuidString.prefix(8))) <- 启动主窗口(\(sourceWindowId.prefix(8)))")
        } else {
            print("⚠️ LayerGraphWindow: 无法找到任何主窗口进行映射")
        }
        
        // 调试当前状态
        print("🔍 LayerGraphWindow: setupWindow starting")
        print("   - store.layers.count: \(store.layers.count)")
        print("   - initial filteredLayerIds.count: \(filteredLayerIds.count)")
        
        // 默认加载默认预设
        let defaultPreset = presetManager.getDefaultPreset(allLayers: store.layers)
        print("   - defaultPreset.filteredLayerIds.count: \(defaultPreset.filteredLayerIds.count)")
        
        loadPreset(defaultPreset)
        print("   - after loadPreset, filteredLayerIds.count: \(filteredLayerIds.count)")
        
        selectedLayerId = store.currentLayer?.id
        
        // 调试信息
        print("🔍 LayerGraphWindow: setupWindow completed")
        print("   - defaultPreset.id: \(defaultPreset.id)")
        print("   - presetManager.currentPreset?.id: \(presetManager.currentPreset?.id ?? UUID())")
        print("   - 是否匹配: \(presetManager.currentPreset?.id == defaultPreset.id)")
        
        // 确保 UI 更新
        DispatchQueue.main.async {
            self.presetManager.objectWillChange.send()
        }
        
        updateGraphData()
    }
    
    private func handleNodeSelected(nodeId: Int, commandPressed: Bool, optionPressed: Bool) {
        guard let selectedGraphNode = cachedNodes.first(where: { $0.id == nodeId }),
              let layerId = selectedGraphNode.layerId,
              let targetLayer = store.layers.first(where: { $0.id == layerId }) else {
            return
        }
        
        if optionPressed {
            // ⌥+点击：层图谱只显示层级，不支持节点文件夹操作
            print("⌥ Option+点击了层节点，层图谱不支持节点文件夹操作")
            return
        }
        
        if commandPressed {
            // ⌘+点击：通知对应的主窗口切换层
            switchToLayerInMainWindow(targetLayer)
        } else {
            // 普通点击：只选中
            selectedLayerId = layerId
            print("🔍 选中层: \(targetLayer.displayName)")
        }
    }
    
    private func switchToLayerInMainWindow(_ layer: Layer) {
        // 使用窗口映射关系找到对应的主窗口，支持多主窗口环境
        let targetWindowId = WindowFocusManager.shared.getSourceWindowId(for: windowId.uuidString)
        
        print("🔄 LayerGraphWindow: 切换到层 '\(layer.displayName)'")
        print("   - 当前层图谱窗口ID: \(windowId.uuidString.prefix(8))")
        print("   - 映射的目标主窗口ID: \(targetWindowId?.prefix(8) ?? "未找到")")
        
        // 通知映射的主窗口切换层
        NotificationCenter.default.post(
            name: NSNotification.Name("switchToLayer"),
            object: layer,
            userInfo: ["sourceWindowId": targetWindowId ?? ""]
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
    
    // MARK: - 复合层层级计算
    
    /// 计算复合层的层级深度
    private func calculateLayerDepth(layer: Layer, allLayers: [Layer], visited: Set<UUID> = Set()) -> Int {
        // 防止循环引用
        if visited.contains(layer.id) {
            return 0
        }
        
        if !layer.isCompound || layer.childLayerIds.isEmpty {
            return 0 // 普通层或无子层的复合层深度为0
        }
        
        var newVisited = visited
        newVisited.insert(layer.id)
        
        let childLayers = allLayers.filter { layer.childLayerIds.contains($0.id) }
        let maxChildDepth = childLayers.map { childLayer in
            calculateLayerDepth(layer: childLayer, allLayers: allLayers, visited: newVisited)
        }.max() ?? 0
        
        return maxChildDepth + 1
    }
    
    /// 根据层级深度获取颜色
    private func getColorForDepth(_ depth: Int) -> String {
        let colors = ["green", "purple", "orange", "red", "teal", "pink"]
        if depth == 0 {
            return "blue" // 普通层使用蓝色
        } else {
            let colorIndex = (depth - 1) % colors.count
            return colors[colorIndex]
        }
    }
    
    private func calculateLayerGraphData() -> (nodes: [LayerGraphNode], edges: [LayerGraphEdge]) {
        var nodes: [LayerGraphNode] = []
        var edges: [LayerGraphEdge] = []
        
        print("🎯 calculateLayerGraphData called")
        print("   - filteredLayerIds.count: \(filteredLayerIds.count)")
        print("   - store.layers.count: \(store.layers.count)")
        
        if filteredLayerIds.isEmpty {
            print("❌ filteredLayerIds is empty, returning empty graph data")
            return (nodes: nodes, edges: edges)
        }
        
        let filteredLayers = store.layers.filter { filteredLayerIds.contains($0.id) }
        let compoundLayers = filteredLayers.filter { $0.isCompound }
        let regularLayers = filteredLayers.filter { !$0.isCompound }
        
        // 添加复合层
        for layer in compoundLayers {
            let nodeCount = store.nodes.filter { $0.layerId == layer.id }.count
            let isSelected = layer.id == selectedLayerId
            let layerDepth = calculateLayerDepth(layer: layer, allLayers: store.layers)
            let colorForDepth = getColorForDepth(layerDepth)
            
            // 创建带有层级颜色的layer副本
            let layerWithDepthColor = layer.copy(withColor: colorForDepth)
            
            nodes.append(LayerGraphNode(layer: layerWithDepthColor, nodeCount: nodeCount, isSelected: isSelected, allLayers: store.layers))
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
        VStack(spacing: 0) {
            // 标题栏（更明显的样式区别）
            HStack {
                Text("🔧 层预设菜单")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                Spacer()
                Button {
                    showingPresetMenu = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("关闭")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.blue.opacity(0.1))
            
            Divider()
            
            // 预设列表
            ScrollView {
                LazyVStack(spacing: 8) {
                    // 默认预设
                    let defaultPreset = presetManager.getDefaultPreset(allLayers: store.layers)
                    let isDefaultSelected = presetManager.currentPreset?.id == defaultPreset.id
                    SimplePresetRow(
                        preset: defaultPreset,
                        isSelected: isDefaultSelected,
                        isDefault: true,
                        onSelect: { 
                            print("🔍 手动选择默认预设")
                            print("   - defaultPreset.id: \(defaultPreset.id)")
                            print("   - 当前选中状态: \(isDefaultSelected)")
                            loadPreset(defaultPreset)
                            showingPresetMenu = false
                        }
                    )
                    
                    if !presetManager.presets.isEmpty {
                        Divider()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }
                    
                    // 用户预设
                    ForEach(presetManager.presets.sorted(by: { $0.lastUsedAt > $1.lastUsedAt })) { preset in
                        SimplePresetRow(
                            preset: preset,
                            isSelected: presetManager.currentPreset?.id == preset.id,
                            isDefault: false,
                            onSelect: { 
                                loadPreset(preset)
                                showingPresetMenu = false
                            },
                            onDelete: { 
                                presetManager.deletePreset(preset)
                            }
                        )
                    }
                    
                    if presetManager.presets.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bookmark.slash")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                            Text("暂无自定义预设")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 32)
                    }
                }
                .padding(.vertical, 16)
            }
            .frame(maxHeight: 540)
        }
        .frame(width: 320, height: 540)
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
    
    // MARK: - 层搜索和创建功能
    
    private func updateMatchedLayers(searchText: String) {
        let trimmedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            matchedLayers = []
            return
        }
        
        matchedLayers = store.layers.filter { layer in
            layer.displayName.localizedCaseInsensitiveContains(trimmedText) ||
            layer.name.localizedCaseInsensitiveContains(trimmedText)
        }.sorted { $0.displayName < $1.displayName }
    }
    
    private func switchToMatchedLayer() {
        let trimmedInput = layerSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }
        
        // 找到匹配的层
        let matchingLayer = store.layers.first { layer in
            layer.displayName.localizedCaseInsensitiveContains(trimmedInput) ||
            layer.name.localizedCaseInsensitiveContains(trimmedInput)
        }
        
        if let layer = matchingLayer {
            // 切换到匹配的层
            switchToLayerInMainWindow(layer)
            print("🔄 切换到层: \(layer.displayName)")
            // 清空输入框
            layerSearchText = ""
            matchedLayers = []
        } else {
            print("⚠️ 未找到匹配的层: \(trimmedInput)")
        }
    }
    
    private func selectLayerFromDropdown(_ layer: Layer) {
        // 直接切换到选中的层
        switchToLayerInMainWindow(layer)
        print("🔄 从下拉框选择层: \(layer.displayName)")
        
        // 清空输入框和匹配结果
        layerSearchText = ""
        matchedLayers = []
        showingLayerDropdown = false
    }
    
    private func createNewLayer() {
        let trimmedInput = layerSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }
        
        // 解析输入：按空格分割
        let components = trimmedInput.components(separatedBy: " ").filter { !$0.isEmpty }
        
        if components.count == 1 {
            // 创建普通层
            createSimpleLayer(name: components[0])
        } else {
            // 创建复合层
            let compoundName = components[0]
            let childNames = Array(components[1...])
            createCompoundLayer(name: compoundName, childNames: childNames)
        }
    }
    
    private func createSimpleLayer(name: String) {
        // 生成内部名称（小写，下划线替换空格）
        let internalName = name.lowercased().replacingOccurrences(of: " ", with: "_")
        
        // 检查是否重名
        let nameExists = store.layers.contains { layer in
            layer.name.lowercased() == internalName.lowercased() || 
            layer.displayName.lowercased() == name.lowercased()
        }
        
        if nameExists {
            print("⚠️ 层名称已存在: \(name)")
            return
        }
        
        // 创建新层
        let newLayer = store.createLayer(
            name: internalName,
            displayName: name,
            color: "blue"
        )
        
        // 自动添加到当前筛选的层列表中
        filteredLayerIds.insert(newLayer.id)
        
        // 清空输入框
        layerSearchText = ""
        
        // 更新图谱数据
        updateGraphData()
        
        print("✅ 新建普通层成功: \(name) (内部名称: \(internalName))")
        print("🔄 已自动添加到当前筛选列表，当前筛选层数: \(filteredLayerIds.count)")
    }
    
    private func createCompoundLayer(name: String, childNames: [String]) {
        // 生成内部名称（小写，下划线替换空格）
        let internalName = name.lowercased().replacingOccurrences(of: " ", with: "_")
        
        // 检查复合层名是否重名
        let nameExists = store.layers.contains { layer in
            layer.name.lowercased() == internalName.lowercased() || 
            layer.displayName.lowercased() == name.lowercased()
        }
        
        if nameExists {
            print("⚠️ 复合层名称已存在: \(name)")
            return
        }
        
        // 检查所有子层是否存在
        var childLayerIds: [UUID] = []
        for childName in childNames {
            let childInternalName = childName.lowercased().replacingOccurrences(of: " ", with: "_")
            
            // 查找子层（按内部名称或显示名称）
            if let existingLayer = store.layers.first(where: { layer in
                layer.name.lowercased() == childInternalName.lowercased() || 
                layer.displayName.lowercased() == childName.lowercased()
            }) {
                childLayerIds.append(existingLayer.id)
            } else {
                print("❌ 子层不存在: \(childName)")
                print("💡 请先创建子层，然后再创建复合层")
                return
            }
        }
        
        // 创建复合层
        let newCompoundLayer = store.createCompoundLayer(
            name: internalName,
            displayName: name,
            childLayerIds: childLayerIds,
            color: "green"
        )
        
        // 自动添加到当前筛选的层列表中
        filteredLayerIds.insert(newCompoundLayer.id)
        
        // 清空输入框
        layerSearchText = ""
        
        // 更新图谱数据
        updateGraphData()
        
        print("✅ 新建复合层成功: \(name) (内部名称: \(internalName))")
        print("   📦 包含子层: \(childNames.joined(separator: ", "))")
        print("🔄 已自动添加到当前筛选列表，当前筛选层数: \(filteredLayerIds.count)")
    }
}


// MARK: - 层选择看板视图
struct LayerSelectionBoardView: View {
    let layers: [Layer]
    @Binding var selectedLayerIds: Set<UUID>
    let onClose: () -> Void
    
    @EnvironmentObject private var store: NodeStore
    @State private var searchText = ""
    @State private var showActiveOnly = false
    @State private var showingNewLayerDialog = false
    @State private var newLayerName = ""
    @State private var newLayerDisplayName = ""
    @State private var newLayerColor = "blue"
    
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
                    
                    Button("新建层") {
                        showingNewLayerDialog = true
                        newLayerName = ""
                        newLayerDisplayName = ""
                        newLayerColor = "blue"
                    }
                    .buttonStyle(.borderedProminent)
                    
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
        .sheet(isPresented: $showingNewLayerDialog) {
            NewLayerDialogView(
                newLayerName: $newLayerName,
                newLayerDisplayName: $newLayerDisplayName,
                newLayerColor: $newLayerColor,
                onCancel: { showingNewLayerDialog = false },
                onConfirm: { createNewLayer() }
            )
            .environmentObject(store)
        }
    }
    
    private func createNewLayer() {
        let actualName = newLayerName.isEmpty ? 
            newLayerDisplayName.lowercased().replacingOccurrences(of: " ", with: "_") : 
            newLayerName
        let actualDisplayName = newLayerDisplayName.isEmpty ? newLayerName : newLayerDisplayName
        
        let newLayer = store.createLayer(
            name: actualName,
            displayName: actualDisplayName,
            color: newLayerColor
        )
        
        // 自动选中新创建的层
        selectedLayerIds.insert(newLayer.id)
        
        // 关闭对话框
        showingNewLayerDialog = false
        
        print("✅ 创建新层: \(actualDisplayName) (\(actualName))")
    }
}

// MARK: - 新建层对话框
struct NewLayerDialogView: View {
    @Binding var newLayerName: String
    @Binding var newLayerDisplayName: String
    @Binding var newLayerColor: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    
    let availableColors = [
        ("blue", Color.blue),
        ("green", Color.green),
        ("orange", Color.orange),
        ("red", Color.red),
        ("purple", Color.purple),
        ("pink", Color.pink),
        ("yellow", Color.yellow),
        ("teal", Color.teal)
    ]
    
    var isFormValid: Bool {
        !newLayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
        !newLayerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // 标题
            Text("创建新层")
                .font(.title2)
                .fontWeight(.semibold)
            
            // 表单
            VStack(alignment: .leading, spacing: 16) {
                // 显示名称
                VStack(alignment: .leading, spacing: 4) {
                    Text("显示名称")
                        .font(.caption)
                        .fontWeight(.medium)
                    TextField("输入层的显示名称", text: $newLayerDisplayName)
                        .textFieldStyle(.roundedBorder)
                }
                
                // 内部名称
                VStack(alignment: .leading, spacing: 4) {
                    Text("内部名称（可选）")
                        .font(.caption)
                        .fontWeight(.medium)
                    TextField("留空则自动生成", text: $newLayerName)
                        .textFieldStyle(.roundedBorder)
                }
                
                // 颜色选择
                VStack(alignment: .leading, spacing: 8) {
                    Text("层颜色")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                        ForEach(availableColors, id: \.0) { colorName, color in
                            Button {
                                newLayerColor = colorName
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(newLayerColor == colorName ? Color.primary : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            
            // 按钮
            HStack(spacing: 12) {
                Button("取消") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                
                Button("创建") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isFormValid)
            }
        }
        .padding(20)
        .frame(width: 400)
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

// MARK: - 层预设管理视图
struct LayerPresetManagerView: View {
    @ObservedObject var presetManager: LayerGraphPresetManager
    let store: NodeStore
    let onPresetSelected: (LayerGraphPreset) -> Void
    
    @State private var searchText = ""
    
    private var filteredPresets: [LayerGraphPreset] {
        let allPresets = presetManager.presets
        if searchText.isEmpty {
            return allPresets.sorted(by: { $0.lastUsedAt > $1.lastUsedAt })
        }
        return allPresets.filter { preset in
            preset.name.localizedCaseInsensitiveContains(searchText)
        }.sorted(by: { $0.lastUsedAt > $1.lastUsedAt })
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // 标题
            HStack {
                Text("层预设管理")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            .padding(.horizontal)
            
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
            .padding(.horizontal)
            
            Divider()
            
            // 预设列表
            ScrollView {
                LazyVStack(spacing: 8) {
                    // 默认预设
                    let defaultPreset = presetManager.getDefaultPreset(allLayers: store.layers)
                    if searchText.isEmpty || defaultPreset.name.localizedCaseInsensitiveContains(searchText) {
                        ModernPresetRow(
                            preset: defaultPreset,
                            isSelected: presetManager.currentPreset?.id == defaultPreset.id,
                            isDefault: true,
                            onSelect: { onPresetSelected(defaultPreset) }
                        )
                    }
                    
                    let shouldShowDivider = !filteredPresets.isEmpty && (searchText.isEmpty || !defaultPreset.name.localizedCaseInsensitiveContains(searchText))
                    if shouldShowDivider {
                        Divider()
                            .padding(.horizontal)
                    }
                    
                    // 用户预设
                    ForEach(filteredPresets) { preset in
                        ModernPresetRow(
                            preset: preset,
                            isSelected: presetManager.currentPreset?.id == preset.id,
                            isDefault: false,
                            onSelect: { onPresetSelected(preset) },
                            onDelete: { presetManager.deletePreset(preset) }
                        )
                    }
                    
                    if filteredPresets.isEmpty && !searchText.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                            
                            Text("未找到匹配的预设")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("尝试使用不同的关键词搜索")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                }
                .padding(.horizontal)
            }
            
            if searchText.isEmpty && presetManager.presets.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    
                    Text("暂无自定义预设")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("选择层级后点击\"保存为预设\"")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 16)
    }
}

// MARK: - 简单预设行
struct SimplePresetRow: View {
    let preset: LayerGraphPreset
    let isSelected: Bool
    let isDefault: Bool
    let onSelect: () -> Void
    var onDelete: (() -> Void)? = nil
    
    @State private var isHovered = false
    @State private var showingDeleteAlert = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // 选中状态指示器
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .blue : .secondary)
                
                // 预设信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(preset.name)
                            .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? .blue : .primary)
                        
                        if isDefault {
                            Text("默认")
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                        
                        Text("\(preset.filteredLayerIds.count) 层")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    if !isDefault {
                        Text("上次使用: \(formatDate(preset.lastUsedAt))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                
                // 删除按钮
                if !isDefault, onDelete != nil, isHovered {
                    Button {
                        showingDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.blue.opacity(0.1) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .alert("删除预设", isPresented: $showingDeleteAlert) {
            Button("删除", role: .destructive) {
                onDelete?()
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

// MARK: - 现代化预设行
struct ModernPresetRow: View {
    let preset: LayerGraphPreset
    let isSelected: Bool
    let isDefault: Bool
    let onSelect: () -> Void
    var onDelete: (() -> Void)? = nil
    
    @State private var showingDeleteAlert = false
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // 选中状态指示器
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.clear)
                        .frame(width: 20, height: 20)
                    
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.secondary, lineWidth: 2)
                        .frame(width: 20, height: 20)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                // 预设信息
                VStack(alignment: .leading, spacing: 4) {
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
                        
                        // 层级数量
                        Text("\(preset.filteredLayerIds.count) 层")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    if !isDefault {
                        Text("上次使用: \(formatDate(preset.lastUsedAt))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                
                // 删除按钮（仅对用户创建的预设显示）
                if !isDefault, onDelete != nil, isHovered {
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
                    .fill(isSelected ? Color.blue.opacity(0.08) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .alert("删除预设", isPresented: $showingDeleteAlert) {
            Button("删除", role: .destructive) {
                onDelete?()
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

// MARK: - 层下拉框项目
struct LayerDropdownItem: View {
    let layer: Layer
    let searchText: String
    let onSelect: (Layer) -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            onSelect(layer)
        }) {
            HStack(spacing: 10) {
                // 层颜色指示器
                Circle()
                    .fill(Color.from(layer.color))
                    .frame(width: 12, height: 12)
                    .shadow(radius: 1)
                
                // 层信息
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(layer.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if layer.isCompound {
                            Image(systemName: "square.stack.3d.up")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        
                        Spacer()
                        
                        if layer.isActive {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                        }
                    }
                    
                    if layer.displayName != layer.name {
                        Text(layer.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(isHovered ? Color.blue.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - 预览

#Preview {
    LayerGraphWindowView()
        .environmentObject(NodeStore.shared)
}