import SwiftUI
import CoreLocation
import MapKit

struct CommandPaletteView: View {
    @EnvironmentObject private var store: NodeStore
    @Binding var isPresented: Bool
    @State private var query: String = ""

    @StateObject private var commandParser = CommandParser.shared
    @FocusState private var isTextFieldFocused: Bool
    @State private var shouldDismiss: Bool = false

    
    // 添加安全关闭标志，防止意外关闭
    @State private var allowBackgroundDismiss: Bool = true
    
    // 层过滤器状态 - 提升到CommandPaletteView级别
    @State private var filteredLayerIds: Set<UUID> = []
    
    // 搜索下拉框状态
    @State private var showSearchDropdown: Bool = false
    
    // 过滤器Sheet状态
    @State private var showFilterSheet: Bool = false
    
    // NSEvent监听器引用
    @State private var keyEventMonitor: Any?
    
    var body: some View {
        // 最外层容器，只处理真正的背景点击
        ZStack {
            // 背景点击检测层 - 只有点击到真正的空白区域且允许关闭时才关闭
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    // 只有在允许背景关闭且点击到真正的背景空白区域才关闭面板
                    if allowBackgroundDismiss {
                        print("🔴 命令面板背景空白区域被点击，关闭面板")
                        shouldDismiss = true
                    } else {
                        print("🛡️ 背景关闭被禁用，忽略点击")
                    }
                }
            
            ZStack {
                VStack(spacing: 0) {
                    // 统一的顶部工具栏 - 合并为一行
                    HStack(spacing: 12) {
                        // 左侧标题
                        HStack(spacing: 4) {
                            Image(systemName: "command")
                                .font(.system(size: 14, weight: .medium))
                            Text("层管理")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blue)
                        )
                        .foregroundColor(.white)
                        
                        // 中间搜索框 - 适中尺寸，移除焦点框
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                            
                            TextField("搜索层名...", text: $query)
                                .font(.system(size: 14))
                                .focused($isTextFieldFocused)
                                .textFieldStyle(.plain) // 移除默认样式
                                .onChange(of: query) { _, newValue in
                                    showSearchDropdown = !newValue.isEmpty
                                }
                                .onKeyPress(.escape) {
                                    print("🎹 ESC键被按下，当前query: '\(query)'")
                                    // 智能ESC逻辑：第一次清空输入，第二次退出窗口
                                    if !query.isEmpty {
                                        // 如果有输入内容，第一次ESC清空输入但保持焦点
                                        print("✅ 第一次ESC：清空输入，保持焦点")
                                        query = ""
                                        showSearchDropdown = false
                                        // 保持焦点在输入框
                                        return .handled
                                    } else {
                                        // 如果输入为空，第二次ESC退出窗口
                                        print("🚪 第二次ESC：退出窗口")
                                        isTextFieldFocused = false
                                        shouldDismiss = true
                                        return .handled
                                    }
                                }
                                .onKeyPress(.init("j"), phases: .down) { keyPress in
                                    if keyPress.modifiers.contains(.command) {
                                        if keyPress.modifiers.contains(.shift) {
                                            handleRemoveLayerFromFilter()
                                        } else {
                                            handleAddLayerToFilter()
                                        }
                                        return .handled
                                    }
                                    return .ignored
                                }
                                .onKeyPress(.init("J"), phases: .down) { keyPress in
                                    if keyPress.modifiers.contains(.command) {
                                        handleRemoveLayerFromFilter()
                                        return .handled
                                    }
                                    return .ignored
                                }
                            
                            if !query.isEmpty {
                                Button(action: {
                                    query = ""
                                    showSearchDropdown = false
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.textBackgroundColor))
                                .stroke(isTextFieldFocused ? Color.blue.opacity(0.5) : Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .frame(maxWidth: 300)
                        
                        // 层结构图谱标题
                        Text("层结构图谱")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        // 显示当前过滤状态
                        if filteredLayerIds.count != store.layers.count {
                            Text("已过滤 \(filteredLayerIds.count)/\(store.layers.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.orange.opacity(0.2))
                                )
                        }
                        
                        // 过滤器按钮
                        Button(action: {
                            showFilterSheet = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 12))
                                Text("过滤器")
                                    .font(.system(size: 12))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("打开层过滤器")
                        
                        // 右侧当前层显示
                        if let currentLayer = store.currentLayer {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text(currentLayer.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.green.opacity(0.1))
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    Divider()
                    
                    // 图谱区域（占用全部剩余空间）
                    LayerStructureGraphViewSimple(
                        filteredLayerIds: $filteredLayerIds,
                        isPresented: $isPresented,
                        showFilterSheet: $showFilterSheet
                    )
                    .environmentObject(store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // 搜索下拉框 - 放在最顶层确保不被遮挡
                if showSearchDropdown && !query.isEmpty {
                    let matchingLayers = store.layers.filter { layer in
                        layer.displayName.lowercased().contains(query.lowercased()) ||
                        layer.name.lowercased().contains(query.lowercased())
                    }
                    
                    if !matchingLayers.isEmpty {
                        VStack {
                            HStack {
                                // 占位符，对齐到搜索框位置
                                HStack(spacing: 4) {
                                    Image(systemName: "command")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("层管理")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .opacity(0) // 隐藏但保持布局
                                
                                // 下拉框内容
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(matchingLayers.prefix(8), id: \.id) { layer in
                                        SearchDropdownItem(
                                            layer: layer,
                                            query: query,
                                            isFiltered: filteredLayerIds.contains(layer.id)
                                        ) {
                                            // 点击选择层
                                            query = layer.displayName
                                            showSearchDropdown = false
                                        }
                                    }
                                    
                                    if matchingLayers.count > 8 {
                                        HStack {
                                            Text("还有 \(matchingLayers.count - 8) 个结果...")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                    }
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(NSColor.windowBackgroundColor))
                                        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
                                )
                                .frame(maxWidth: 300)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 45) // 调整到搜索框下方
                            
                            Spacer()
                        }
                        .zIndex(3000) // 最高层级
                        .allowsHitTesting(true)
                    }
                }
            }
        } // 结束最外层ZStack
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        // 在最高层级添加ESC键处理，确保不被其他地方拦截
        .onKeyPress(.escape) {
            print("🎹 顶层ESC键被按下，当前query: '\(query)', 焦点状态: \(isTextFieldFocused)")
            
            // 只有当搜索框有焦点时才处理ESC键
            if isTextFieldFocused {
                if !query.isEmpty {
                    // 第一次ESC：清空输入，保持焦点
                    print("✅ 顶层第一次ESC：清空输入，保持焦点")
                    query = ""
                    showSearchDropdown = false
                    return .handled
                } else {
                    // 第二次ESC：退出窗口
                    print("🚪 顶层第二次ESC：退出窗口")
                    isTextFieldFocused = false
                    shouldDismiss = true
                    return .handled
                }
            }
            
            // 如果搜索框没有焦点，直接退出
            print("🚪 顶层ESC：搜索框无焦点，直接退出")
            shouldDismiss = true
            return .handled
        }
        .onAppear {
            setupView()
            
            // 初始化层过滤器为显示所有层 - 使用Task避免在视图更新期间发布更改
            Task { @MainActor in
                if filteredLayerIds.isEmpty {
                    filteredLayerIds = Set(store.layers.map { $0.id })
                }
            }
            
            // 监听禁用背景关闭的通知
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("disableBackgroundDismiss"),
                object: nil,
                queue: .main
            ) { _ in
                print("🛡️ 收到禁用背景关闭通知")
                allowBackgroundDismiss = false
                
                // 短暂延迟后重新启用
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    allowBackgroundDismiss = true
                    print("🔓 重新启用背景关闭")
                }
            }
            
            // 添加NSEvent监听来处理ESC键，绕过SwiftUI的默认处理
            keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                print("🎹 NSEvent监听到键盘事件: keyCode=\(event.keyCode), characters=\(event.characters ?? "nil"), 焦点状态: \(isTextFieldFocused)")
                
                // ESC键的keyCode是53
                if event.keyCode == 53 {
                    print("🎹 NSEvent检测到ESC键，当前query: '\(query)', 焦点状态: \(isTextFieldFocused)")
                    
                    // 只有当搜索框有焦点时才处理ESC键
                    if isTextFieldFocused {
                        if !query.isEmpty {
                            // 第一次ESC：清空输入，保持焦点
                            print("✅ NSEvent第一次ESC：清空输入，保持焦点")
                            DispatchQueue.main.async {
                                query = ""
                                showSearchDropdown = false
                            }
                            return nil // 消费事件，不传递给其他处理器
                        } else {
                            // 第二次ESC：退出窗口
                            print("🚪 NSEvent第二次ESC：退出窗口")
                            DispatchQueue.main.async {
                                isTextFieldFocused = false
                                shouldDismiss = true
                            }
                            return nil // 消费事件
                        }
                    } else {
                        // 如果搜索框没有焦点，直接退出
                        print("🚪 NSEvent ESC：搜索框无焦点，直接退出")
                        DispatchQueue.main.async {
                            shouldDismiss = true
                        }
                        return nil // 消费事件
                    }
                }
                
                return event // 不是ESC键，传递事件
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            LayerFilterSheet(
                filteredLayerIds: $filteredLayerIds,
                store: store
            )
        }

        .onChange(of: shouldDismiss) { _, newValue in
            if newValue {
                dismissView()
            }
        }
        .onDisappear {
            // 清理通知监听
            NotificationCenter.default.removeObserver(
                self,
                name: NSNotification.Name("disableBackgroundDismiss"),
                object: nil
            )
            
            // 清理NSEvent监听器
            if let monitor = keyEventMonitor {
                NSEvent.removeMonitor(monitor)
                keyEventMonitor = nil
                print("🧹 清理NSEvent监听器")
            }
        }
    }
    
    // MARK: - View Logic
    
    private func setupView() {
        query = ""
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTextFieldFocused = true
        }
    }
    
    private func dismissView() {
        // 立即清除搜索框焦点，防止残留蓝色边框
        isTextFieldFocused = false
        
        // 立即关闭窗口，不使用延迟
        isPresented = false
        shouldDismiss = false
    }
    

    
    private func handleCommandResult(_ result: CommandResult) {
        switch result {
        case .success(let message):
            print("Success: \(message)")
        case .nodeCreated(let node):
            store.selectNode(node)
        case .nodeSelected(let node):
            store.selectNode(node)
        case .tagAdded(_, let node):
            store.selectNode(node)
        case .searchPerformed(_):
            break
        case .navigationRequested(let destination):
            handleNavigation(destination)
        case .layerSwitched(let layer):
            print("已切换到层: \(layer.displayName)")
        case .error(let message):
            print("Error: \(message)")
        }
    }
    
    private func handleNavigation(_ destination: NavigationDestination) {
        switch destination {
        case .map:
            NotificationCenter.default.post(name: .openMapWindow, object: nil)
        case .graph:
            NotificationCenter.default.post(name: .openGraphWindow, object: nil)
        case .settings:
            break
        case .node(let id):
            if let node = store.nodes.first(where: { $0.id == id }) {
                store.selectNode(node)
            }
        }
    }
    
    // 处理⌘J: 添加层到过滤器
    private func handleAddLayerToFilter() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else {
            print("🔍 CommandPalette: 查询为空，无法添加层到过滤器")
            return
        }
        
        // 查找匹配的层
        let matchingLayers = store.layers.filter { layer in
            layer.displayName.lowercased().contains(trimmedQuery) ||
            layer.name.lowercased().contains(trimmedQuery)
        }
        
        if let firstMatch = matchingLayers.first {
            filteredLayerIds.insert(firstMatch.id)
            print("✅ CommandPalette: 添加层 '\(firstMatch.displayName)' 到过滤器")
            
            // 如果是复合层，也添加其子层
            if firstMatch.isCompound {
                for childLayerId in firstMatch.childLayerIds {
                    filteredLayerIds.insert(childLayerId)
                    if let childLayer = store.layers.first(where: { $0.id == childLayerId }) {
                        print("✅ CommandPalette: 同时添加子层 '\(childLayer.displayName)' 到过滤器")
                    }
                }
            }
        } else {
            print("❌ CommandPalette: 未找到匹配的层: '\(trimmedQuery)'")
        }
    }
    
    // 处理⌘⇧J: 从过滤器中移除层
    private func handleRemoveLayerFromFilter() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else {
            print("🔍 CommandPalette: 查询为空，无法从过滤器移除层")
            return
        }
        
        // 查找匹配的层
        let matchingLayers = store.layers.filter { layer in
            layer.displayName.lowercased().contains(trimmedQuery) ||
            layer.name.lowercased().contains(trimmedQuery)
        }
        
        if let firstMatch = matchingLayers.first {
            filteredLayerIds.remove(firstMatch.id)
            print("❌ CommandPalette: 从过滤器移除层 '\(firstMatch.displayName)'")
            
            // 如果是复合层，也移除其子层
            if firstMatch.isCompound {
                for childLayerId in firstMatch.childLayerIds {
                    filteredLayerIds.remove(childLayerId)
                    if let childLayer = store.layers.first(where: { $0.id == childLayerId }) {
                        print("❌ CommandPalette: 同时移除子层 '\(childLayer.displayName)' 从过滤器")
                    }
                }
            }
        } else {
            print("❌ CommandPalette: 未找到匹配的层: '\(trimmedQuery)'")
        }
    }
}

// MARK: - Simplified Layer Structure Graph View

struct LayerStructureGraphViewSimple: View {
    @EnvironmentObject private var store: NodeStore
    @Binding var filteredLayerIds: Set<UUID>
    @Binding var isPresented: Bool
    @Binding var showFilterSheet: Bool
    @State private var cachedNodes: [LayerGraphNode] = []
    @State private var cachedEdges: [LayerGraphEdge] = []
    @State private var selectedLayerId: UUID?
    
    // 使用设置中的层结构图谱缩放级别
    @AppStorage("layerStructureGraphInitialScale") private var layerGraphInitialScale: Double = 0.9
    
    var body: some View {
        graphContent
        .background(Color.clear)
        .allowsHitTesting(true)
        // 使用最高优先级手势拦截所有交互事件
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    print("🛡️ 层图谱拖动事件被拦截")
                    // 不执行任何操作，只是拦截事件
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    print("🛡️ 层图谱点击事件被拦截")
                    // 不执行任何操作，只是拦截事件
                }
        )
        .onAppear {
            // Use Task to avoid publishing changes during view updates
            Task { @MainActor in
                if filteredLayerIds.isEmpty {
                    filteredLayerIds = Set(store.layers.map { $0.id })
                }
                updateLayerGraphData()
                selectedLayerId = store.currentLayer?.id
            }
        }
        .onChange(of: store.layers) { _, _ in
            updateLayerGraphData()
        }
        .onChange(of: filteredLayerIds) { _, _ in
            updateLayerGraphData()
        }
        .onKeyPress(.init("k"), phases: .down) { _ in
            NotificationCenter.default.post(name: Notification.Name("fitGraph"), object: nil)
            return .handled
        }
    }
    
    private var filterControlSection: some View {
        // 移除重复的控制栏，因为已经合并到顶部
        EmptyView()
    }
    

    


    

    
    private var graphContent: some View {
        Group {
            if cachedNodes.isEmpty {
                emptyGraphView
            } else {
                layerGraph
            }
        }
    }
    
    private var emptyGraphView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("暂无层数据")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var layerGraph: some View {
        UniversalRelationshipGraphView(
            nodes: cachedNodes,
            edges: cachedEdges,
            title: "层结构图谱",
            initialScale: layerGraphInitialScale,
            onNodeSelected: { nodeId in
                if let selectedGraphNode = cachedNodes.first(where: { $0.id == nodeId }),
                   let layerId = selectedGraphNode.layerId,
                   let targetLayer = store.layers.first(where: { $0.id == layerId }) {
                    
                    // 检查是否按住了Command键
                    let currentEvent = NSApp.currentEvent
                    let isCommandPressed = currentEvent?.modifierFlags.contains(.command) ?? false
                    
                    if isCommandPressed {
                        // ⌘+点击：切换到该层（只对普通层有效）
                        if !targetLayer.isCompound {
                            print("🔄 CommandPalette: ⌘+点击切换到层 '\(targetLayer.displayName)'")
                            Task {
                                await store.switchToLayer(targetLayer)
                                // 切换层后关闭命令面板
                                await MainActor.run {
                                    isPresented = false
                                }
                            }
                        } else {
                            print("⚠️ CommandPalette: 复合层不支持切换，请选择普通层")
                        }
                    } else {
                        // 普通点击：只选中层，不切换
                        selectedLayerId = layerId
                        print("🔍 选中层: \(targetLayer.displayName)，按⌘+点击可切换到此层")
                    }
                }
            },
            onNodeDeselected: {
                // 完全移除空白区域点击的任何响应，防止意外关闭
                print("🔍 图谱空白区域被点击，完全忽略此事件")
                // 不执行任何操作，包括状态变化
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        // 移除可能导致事件冒泡的手势处理
        .allowsHitTesting(true)
        // 使用最高优先级手势拦截所有点击，防止事件向上传播
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    print("🛡️ 图谱区域点击被拦截，防止窗口关闭")
                    
                    // 通知父视图禁用背景关闭
                    NotificationCenter.default.post(
                        name: NSNotification.Name("disableBackgroundDismiss"),
                        object: nil
                    )
                }
        )
    }
    
    private func toggleLayerFilter(_ layer: Layer) {
        if filteredLayerIds.contains(layer.id) {
            // 移除层
            filteredLayerIds.remove(layer.id)
            print("❌ CommandPalette: 手动移除层 '\(layer.displayName)'")
            
            // 如果是复合层，也移除其子层
            if layer.isCompound {
                for childLayerId in layer.childLayerIds {
                    filteredLayerIds.remove(childLayerId)
                    if let childLayer = store.layers.first(where: { $0.id == childLayerId }) {
                        print("❌ CommandPalette: 同时移除子层 '\(childLayer.displayName)'")
                    }
                }
            }
        } else {
            // 添加层
            filteredLayerIds.insert(layer.id)
            print("✅ CommandPalette: 手动添加层 '\(layer.displayName)'")
            
            // 如果是复合层，也添加其子层
            if layer.isCompound {
                for childLayerId in layer.childLayerIds {
                    filteredLayerIds.insert(childLayerId)
                    if let childLayer = store.layers.first(where: { $0.id == childLayerId }) {
                        print("✅ CommandPalette: 同时添加子层 '\(childLayer.displayName)'")
                    }
                }
            }
        }
    }
    
    private func updateLayerGraphData() {
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
}

// MARK: - Layer Graph Types

struct LayerGraphNode: UniversalGraphNode {
    let id: Int
    let label: String
    let subtitle: String?
    let layerId: UUID?
    let layer: Layer?
    let nodeCount: Int
    let isCompound: Bool
    let isSelected: Bool
    
    init(layer: Layer, nodeCount: Int, isSelected: Bool = false, allLayers: [Layer] = []) {
        self.id = GraphNodeIDGenerator.shared.idForLayer(layer)
        self.label = layer.displayName
        self.layerId = layer.id
        self.layer = layer
        self.nodeCount = nodeCount
        self.isCompound = layer.isCompound
        self.isSelected = isSelected
        
        if layer.isCompound {
            let childCount = layer.childLayerIds.count
            self.subtitle = "复合层 • \(childCount) 个子层 • \(nodeCount) 个节点"
        } else {
            self.subtitle = "\(nodeCount) 个节点"
        }
    }
}

struct LayerGraphEdge: UniversalGraphEdge {
    let fromId: Int
    let toId: Int
    let label: String?
    
    init(from: LayerGraphNode, to: LayerGraphNode, relationshipType: String) {
        self.fromId = from.id
        self.toId = to.id
        self.label = relationshipType
    }
}

// MARK: - GraphNodeIDGenerator Layer Extension
extension GraphNodeIDGenerator {
    func idForLayer(_ layer: Layer) -> Int {
        let layerKey = "layer:\(layer.id.uuidString)"
        lock.lock()
        defer { lock.unlock() }
        
        if let existingID = tagIDMap[layerKey] {
            return existingID
        }
        
        currentID += 1
        tagIDMap[layerKey] = currentID
        return currentID
    }
}

struct LayerFilterChip: View {
    let layer: Layer
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject private var store: NodeStore
    
    // 获取复合层的子层名称
    private var childLayerNames: [String] {
        guard layer.isCompound else { return [] }
        return layer.childLayerIds.compactMap { childId in
            store.layers.first(where: { $0.id == childId })?.displayName
        }
    }
    
    // 生成显示文本
    private var displayText: String {
        if layer.isCompound && !childLayerNames.isEmpty {
            let childText = childLayerNames.joined(separator: ", ")
            return "\(layer.displayName) (\(childText))"
        } else {
            return layer.displayName
        }
    }
    
    // 生成帮助文本
    private var helpText: String {
        if layer.isCompound && !childLayerNames.isEmpty {
            let childText = childLayerNames.joined(separator: ", ")
            return "复合层: \(layer.displayName)\n包含子层: \(childText)"
        } else if layer.isCompound {
            return "复合层: \(layer.displayName)"
        } else {
            return "普通层: \(layer.displayName)"
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                // 层类型指示器
                Circle()
                    .fill(layer.isCompound ? Color.purple : Color.blue)
                    .frame(width: 6, height: 6)
                
                Text(displayText)
                    .font(.caption)
                    .fontWeight(isSelected ? .medium : .regular)
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                
                if isSelected {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isSelected ? Color.blue : Color.gray.opacity(0.2))
            )
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}

// MARK: - CommandRowView

private struct CommandRowView: View {
    let command: Command
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 子层命令使用不同的图标和颜色
                if isChildLayer {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(width: 28)
                } else {
                    Image(systemName: command.icon)
                        .font(.title2)
                        .foregroundColor(iconColor)
                        .frame(width: 28)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(command.title)
                        .font(.title3)
                        .fontWeight(isChildLayer ? .regular : .semibold)
                        .foregroundColor(isChildLayer ? .secondary : .primary)
                        .lineLimit(1)
                    
                    Text(command.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Category badge - 子层使用不同样式
                if !isChildLayer {
                    Text(command.category.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(iconColor.opacity(0.2))
                        )
                        .foregroundColor(iconColor)
                }
                
                if isSelected {
                    Image(systemName: "return")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, isChildLayer ? 16 : 10)  // 子层增加左边距
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.15) : Color.clear)
        )
    }
    
    // 检查是否为子层命令
    private var isChildLayer: Bool {
        if let switchCommand = command as? SwitchLayerCommand {
            return switchCommand.isChildLayer
        }
        return false
    }
    
    private var iconColor: Color {
        switch command.category {
        case .system: return .gray
        case .layer: return .purple
        }
    }
}



// MARK: - Notification Extensions

extension Notification.Name {
    static let openMapWindow = Notification.Name("openMapWindow")
    static let openGraphWindow = Notification.Name("openGraphWindow")
    static let addNewNode = Notification.Name("addNewNode")
    static let focusSearch = Notification.Name("focusSearch")
    static let addLayerToGraphFilter = Notification.Name("addLayerToGraphFilter")
    static let removeLayerFromGraphFilter = Notification.Name("removeLayerFromGraphFilter")
}

// MARK: - 搜索下拉项组件
struct SearchDropdownItem: View {
    let layer: Layer
    let query: String
    let isFiltered: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // 层类型图标
                Circle()
                    .fill(layer.isCompound ? Color.purple : Color.blue)
                    .frame(width: 12, height: 12)
                
                // 层名称（高亮匹配部分）
                HStack(spacing: 4) {
                    Text(layer.displayName)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                    
                    if layer.isCompound {
                        Text("复合")
                            .font(.caption)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(4)
                            .foregroundColor(.purple)
                    }
                }
                
                Spacer()
                
                // 过滤状态
                if isFiltered {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                }
                
                // 快捷键提示
                Text("⌘J")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            // 可以添加悬停效果
        }
    }
}

// MARK: - 层过滤器Sheet
struct LayerFilterSheet: View {
    @Binding var filteredLayerIds: Set<UUID>
    let store: NodeStore
    @State private var searchText: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var filteredLayers: [Layer] {
        if searchText.isEmpty {
            return store.sortedLayers
        } else {
            return store.sortedLayers.filter { layer in
                layer.displayName.localizedCaseInsensitiveContains(searchText) ||
                layer.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("层过滤器")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(filteredLayerIds.count)/\(store.layers.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
                
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("搜索层名...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding()
            
            // 快速操作按钮
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button("全选") {
                        filteredLayerIds = Set(store.layers.map { $0.id })
                    }
                    .buttonStyle(.bordered)
                    
                    Button("清空") {
                        filteredLayerIds.removeAll()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("仅复合层") {
                        filteredLayerIds = Set(store.layers.filter { $0.isCompound }.map { $0.id })
                    }
                    .buttonStyle(.bordered)
                    
                    Button("仅普通层") {
                        filteredLayerIds = Set(store.layers.filter { !$0.isCompound }.map { $0.id })
                    }
                    .buttonStyle(.bordered)
                    
                    if let currentLayer = store.currentLayer {
                        Button("当前层") {
                            filteredLayerIds = [currentLayer.id]
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)
            }
            
            Divider()
            
            // 层列表
            List {
                ForEach(filteredLayers, id: \.id) { layer in
                    LayerFilterRow(
                        layer: layer,
                        isSelected: filteredLayerIds.contains(layer.id)
                    ) {
                        toggleLayer(layer)
                    }
                }
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
    
    private func toggleLayer(_ layer: Layer) {
        if filteredLayerIds.contains(layer.id) {
            filteredLayerIds.remove(layer.id)
            
            // 如果是复合层，也移除其子层
            if layer.isCompound {
                for childLayerId in layer.childLayerIds {
                    filteredLayerIds.remove(childLayerId)
                }
            }
        } else {
            filteredLayerIds.insert(layer.id)
            
            // 如果是复合层，也添加其子层
            if layer.isCompound {
                for childLayerId in layer.childLayerIds {
                    filteredLayerIds.insert(childLayerId)
                }
            }
        }
    }
}

// MARK: - 层过滤器行组件
struct LayerFilterRow: View {
    let layer: Layer
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // 选择状态
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .secondary)
                    .font(.system(size: 18))
                
                // 层类型图标
                Circle()
                    .fill(layer.isCompound ? Color.purple : Color.blue)
                    .frame(width: 14, height: 14)
                
                // 层信息
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(layer.displayName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        
                        if layer.isCompound {
                            Text("复合")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.2))
                                .cornerRadius(4)
                                .foregroundColor(.purple)
                        }
                        
                        Spacer()
                    }
                    
                    if layer.name != layer.displayName {
                        Text(layer.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CommandPaletteView(isPresented: .constant(true))
        .environmentObject(NodeStore.shared)
}