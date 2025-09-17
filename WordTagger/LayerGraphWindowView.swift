import SwiftUI

// MARK: - 层图谱窗口视图

struct LayerGraphWindowView: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var presetManager = LayerGraphPresetManager.shared
    @State private var windowId = UUID()
    
    // 当前筛选的层
    @State private var filteredLayerIds: Set<UUID> = []
    
    // 保存最后激活的有效窗口ID
    @State private var lastActiveTargetWindowId: String? = nil
    
    // 图谱相关状态
    @State private var cachedNodes: [LayerGraphNode] = []
    @State private var cachedEdges: [LayerGraphEdge] = []
    @State private var selectedLayerId: UUID?
    
    // UI状态
    @State private var showingPresetSaveDialog = false
    @State private var newPresetName = ""
    @State private var showingPresetManagerWindow = false
    
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
        .onDisappear {
            // 窗口关闭时清理全局层图谱窗口记录
            WindowFocusManager.shared.clearGlobalLayerGraphWindow()
            print("🧹 LayerGraphWindow: 清理全局层图谱窗口记录")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("focusLayerGraphWindow"))) { notification in
            // 🔧 处理激活层图谱窗口的通知
            if let userInfo = notification.userInfo,
               let targetWindowId = userInfo["windowId"] as? String {
                // 检查是否是发给当前窗口的通知
                if targetWindowId == windowId.uuidString {
                    print("🎯 LayerGraphWindow: 收到激活窗口通知")
                    // 使用 WindowFocusManager 激活窗口
                    WindowFocusManager.shared.activateWindow(windowId)
                }
            }
        }
        .onAppear {
            setupWindow()
            // 默认加载所有层
            if filteredLayerIds.isEmpty {
                filteredLayerIds = Set(store.layers.map { $0.id })
            }
            // 设置输入框焦点
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
            }
            
            // 🚀 最简单有效的窗口切换监听 - 直接监听系统通知
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [windowId] notification in
                guard let window = notification.object as? NSWindow else { return }
                let newWindowTitle = window.title
                
                // 过滤掉自己（层图谱窗口）
                if newWindowTitle.contains("层结构图谱") || newWindowTitle.contains("Layer Graph") {
                    return
                }
                
                print("🔄 LayerGraphWindow: 检测到窗口切换 - '\(newWindowTitle)'")
                
                // 🔧 延迟处理，确保系统已完全设置好keyWindow
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    handleWindowSwitchWithWindow(window, title: newWindowTitle)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("userClickedWindow"))) { notification in
            // 接收用户点击窗口的通知
            if let userInfo = notification.userInfo,
               let clickedWindowId = userInfo["windowId"] as? String,
               let windowType = userInfo["windowType"] as? String,
               let isRealClick = userInfo["isRealClick"] as? Bool,
               isRealClick { // 只处理真实的用户点击
                // 只记录标准窗口（排除层图谱窗口和地图窗口）
                if windowType == "standard" && clickedWindowId != windowId.uuidString {
                    // 验证这是一个有效的窗口ID
                    if WindowFocusManager.shared.isWindowRegistered(UUID(uuidString: clickedWindowId) ?? UUID()) {
                        lastActiveTargetWindowId = clickedWindowId
                        print("🎯 LayerGraphWindow: 用户真实点击了窗口，锁定目标 - (\(clickedWindowId.prefix(8)))")
                        print("🔒 LayerGraphWindow: 锁定用户点击目标，禁止被窗口切换覆盖")
                    } else {
                        print("⚠️ LayerGraphWindow: 忽略无效的窗口ID - (\(clickedWindowId.prefix(8)))")
                    }
                }
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
            // 已删除预设描述文本
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
                Button("预设管理") {
                    showLayerGraphPresetManagerWindow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
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
    
    /// 处理窗口切换事件 - 直接使用通知中的window参数（更可靠）
    /// - Parameters:
    ///   - window: 从通知中获取的NSWindow实例
    ///   - title: 窗口标题（仅用于日志）
    private func handleWindowSwitchWithWindow(_ window: NSWindow, title: String) {
        print("\n🔍 === 详细调试：窗口切换分析 ===")
        print("📋 用户看到的窗口标题: '\(title)'")
        print("📋 NSWindow对象ID: \(ObjectIdentifier(window))")
        print("📋 当前时间: \(Date())")
        
        // 🔍 详细分析当前系统状态
        let windowManager = WindowFocusManager.shared
        let allWindows = windowManager.getAllRegisteredWindows()
        
        print("\n📊 系统中所有注册窗口:")
        for (index, windowInfo) in allWindows.enumerated() {
            let marker = windowInfo.id == lastActiveTargetWindowId ? " ⭐️[当前记录的目标]" : ""
            print("   [\(index)] '\(windowInfo.displayName)' - ID: \(windowInfo.id.prefix(8)) - 类型: \(windowInfo.type)\(marker)")
        }
        
        // 🚨 修复关键bug：检查是否有用户真实点击的目标，如果有则不要覆盖！
        if let currentTarget = lastActiveTargetWindowId,
           let targetUUID = UUID(uuidString: currentTarget),
           let targetInfo = windowManager.getWindowInfo(for: targetUUID),
           targetInfo.type == .standard {
            print("\n🔒 === 保护用户点击目标 ===")
            print("   已有用户真实点击的目标: \(currentTarget.prefix(8))")
            print("   目标窗口名: '\(targetInfo.displayName)'")
            print("   🚫 拒绝被窗口切换事件覆盖！")
            print("   ⚠️  这个目标将用于 Command+点击层图谱")
            print("=================")
            return
        }
        
        // 🔧 只有在没有用户真实点击目标时，才使用 WindowFocusManager 的活跃窗口
        if let activeWindowId = windowManager.getActiveWindowId(),
           let activeWindowInfo = windowManager.getWindowInfo(for: activeWindowId),
           activeWindowInfo.type == .standard,
           activeWindowId.uuidString != windowId.uuidString {
            
            let previousTarget = lastActiveTargetWindowId
            lastActiveTargetWindowId = activeWindowId.uuidString
            
            print("\n🎯 === 目标窗口更新（使用活跃窗口）===")
            print("   之前的目标: \(previousTarget?.prefix(8) ?? "无")")
            print("   新的目标: \(activeWindowId.uuidString.prefix(8))")
            print("   目标窗口名: '\(activeWindowInfo.displayName)'")
            print("   ✅ 使用 WindowFocusManager 的活跃窗口（无用户点击覆盖）")
            print("   ⚠️  这个窗口将接收 Command+点击层图谱的通知")
            print("=================")
            return
        }
        
        print("\n🔍 回退：检查NSWindow映射:")
        if let windowUUID = windowManager.getWindowIdFromNSWindow(window) {
            let windowIdString = windowUUID.uuidString
            print("✅ 找到映射: NSWindow -> WindowID(\(windowIdString.prefix(8)))")
            
            if let windowInfo = windowManager.getWindowInfo(for: windowUUID) {
                print("✅ 窗口信息: '\(windowInfo.displayName)' (类型: \(windowInfo.type))")
                
                // 确保这不是当前层图谱窗口
                if windowIdString != windowId.uuidString {
                    // 验证这是一个标准窗口
                    if windowInfo.type == .standard {
                        let previousTarget = lastActiveTargetWindowId
                        lastActiveTargetWindowId = windowIdString
                        
                        print("\n🎯 === 目标窗口更新（NSWindow映射）===")
                        print("   之前的目标: \(previousTarget?.prefix(8) ?? "无")")
                        print("   新的目标: \(windowIdString.prefix(8))")
                        print("   目标窗口名: '\(windowInfo.displayName)'")
                        print("   ⚠️  请记住这个目标窗口，Command+点击层图谱时应该切换到这个窗口！")
                        print("=================")
                        return
                    } else {
                        print("🔍 跳过：窗口不是标准类型")
                        return
                    }
                } else {
                    print("🔍 跳过：这是层图谱窗口自己")
                    return
                }
            } else {
                print("❌ 错误：找到映射但获取窗口信息失败")
            }
        } else {
            print("❌ 错误：NSWindow映射失败")
        }
        
        print("\n🔄 回退到原方法...")
        // 如果直接方法失败，使用回退方案
        handleWindowSwitch(title)
    }
    
    /// 处理窗口切换事件 - 通过NSWindow实例直接查找WindowID（回退方案）
    /// - Parameter newWindowTitle: 新窗口的标题（仅用于日志）
    private func handleWindowSwitch(_ newWindowTitle: String) {
        print("🔄 LayerGraphWindow: 处理窗口切换 - '\(newWindowTitle)'")
        
        // 🚀 最可靠的方法：直接通过NSWindow实例查找对应的WindowID
        guard let keyWindow = NSApplication.shared.keyWindow else {
            print("❌ LayerGraphWindow: 没有key窗口")
            return
        }
        
        // 使用WindowFocusManager的getWindowIdFromNSWindow方法
        let windowManager = WindowFocusManager.shared
        if let windowUUID = windowManager.getWindowIdFromNSWindow(keyWindow) {
            let windowIdString = windowUUID.uuidString
            
            // 确保这不是当前层图谱窗口
            if windowIdString != windowId.uuidString {
                // 验证这是一个标准窗口
                if let windowInfo = windowManager.getWindowInfo(for: windowUUID),
                   windowInfo.type == .standard {
                    lastActiveTargetWindowId = windowIdString
                    print("✅ LayerGraphWindow: 通过NSWindow映射找到目标窗口 - \(windowInfo.displayName) (\(windowIdString.prefix(8)))")
                    return
                } else {
                    print("🔍 LayerGraphWindow: 窗口不是标准类型 - 跳过")
                    return
                }
            } else {
                print("🔍 LayerGraphWindow: 跳过自己的窗口")
                return
            }
        }
        
        // 如果无法通过NSWindow映射找到，回退到当前活跃窗口
        if let activeWindowId = windowManager.getActiveWindowId(),
           let activeWindowInfo = windowManager.getWindowInfo(for: activeWindowId),
           activeWindowInfo.type == .standard,
           activeWindowId.uuidString != windowId.uuidString {
            lastActiveTargetWindowId = activeWindowId.uuidString
            print("⚠️ LayerGraphWindow: 回退使用当前活跃窗口 - \(activeWindowInfo.displayName) (\(activeWindowId.uuidString.prefix(8)))")
            return
        }
        
        // 最后的回退：使用第一个可用的标准窗口
        let allWindows = windowManager.getAllRegisteredWindows()
        if let firstStandardWindow = allWindows.first(where: { 
            $0.type == .standard && $0.id != windowId.uuidString 
        }) {
            lastActiveTargetWindowId = firstStandardWindow.id
            print("⚠️ LayerGraphWindow: 最终回退到第一个标准窗口 - \(firstStandardWindow.displayName) (\(firstStandardWindow.id.prefix(8)))")
        } else {
            print("❌ LayerGraphWindow: 无法找到任何标准窗口作为目标")
        }
    }
    
    /// 查找启动层图谱的源主窗口
    /// 通过lastActiveTargetWindowId或窗口激活历史来确定是哪个主窗口打开了这个层图谱
    private func findSourceMainWindow() -> String? {
        // 优先使用保存的最后激活窗口ID
        if let targetId = lastActiveTargetWindowId {
            print("✅ LayerGraphWindow: 使用保存的目标窗口 - (\(targetId.prefix(8)))")
            return targetId
        }
        
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
        // 🔧 注册为全局唯一的层图谱窗口
        WindowFocusManager.shared.registerGlobalLayerGraphWindow(windowId.uuidString)
        print("🔗 LayerGraphWindow: 注册为全局层图谱窗口 - (\(windowId.uuidString.prefix(8)))")
        
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
        print("\n🚀 === 层图谱Command+点击调试 ===")
        print("🎯 用户Command+点击了层: '\(layer.displayName)'")
        print("📋 层ID: \(layer.id)")
        print("📋 点击时间: \(Date())")
        
        // 调试信息：打印所有注册的窗口
        let windowManager = WindowFocusManager.shared
        print("\n📊 系统中所有注册窗口:")
        let allWindows = windowManager.getAllRegisteredWindows()
        for (idx, windowInfo) in allWindows.enumerated() {
            let marker = windowInfo.id == lastActiveTargetWindowId ? " ⭐️[目标窗口]" : ""
            print("   [\(idx)] '\(windowInfo.displayName)' - ID: \(windowInfo.id.prefix(8)) - 类型: \(windowInfo.type)\(marker)")
        }
        
        print("\n🔍 检查记录的目标窗口:")
        if let targetId = lastActiveTargetWindowId {
            print("✅ 找到记录的目标窗口ID: \(targetId.prefix(8))")
            
            // 获取目标窗口的详细信息
            if let targetUUID = UUID(uuidString: targetId),
               let targetWindowInfo = windowManager.getWindowInfo(for: targetUUID) {
                print("✅ 目标窗口详情:")
                print("   - 显示名: '\(targetWindowInfo.displayName)'")
                print("   - 类型: \(targetWindowInfo.type)")
                print("   - 是否仍注册: \(windowManager.isWindowRegistered(targetUUID))")
                
                if windowManager.isWindowRegistered(targetUUID) {
                    print("\n📡 === 发送层切换通知 ===")
                    print("   目标窗口: '\(targetWindowInfo.displayName)' (\(targetId.prefix(8)))")
                    print("   要切换的层: '\(layer.displayName)'")
                    print("   ⚠️  注意观察：这个窗口应该会收到层切换通知并切换到指定层")
                    print("================")
                    
                    // 通知目标窗口切换层
                    NotificationCenter.default.post(
                        name: NSNotification.Name("switchToLayer"),
                        object: layer,
                        userInfo: ["sourceWindowId": targetId]
                    )
                } else {
                    print("❌ 目标窗口已失效，清除记录")
                    lastActiveTargetWindowId = nil
                    performFallbackLayerSwitch(layer)
                }
            } else {
                print("❌ 无法获取目标窗口详情")
                performFallbackLayerSwitch(layer)
            }
        } else {
            print("❌ 没有记录的目标窗口！这不应该发生，因为用户应该先点击了某个窗口")
            print("🔄 执行回退方案...")
            performFallbackLayerSwitch(layer)
        }
        
        print("\n=== 层图谱Command+点击调试结束 ===\n")
    }
    
    /// 执行回退的层切换方案
    private func performFallbackLayerSwitch(_ layer: Layer) {
        let windowManager = WindowFocusManager.shared
        let history = windowManager.getWindowActivationHistory()
        
        print("🔍 LayerGraphWindow: 尝试回退方案...")
        print("   - 激活历史: [\(history.map { $0.prefix(8) }.joined(separator: ", "))]")
        
        for windowIdString in history {
            if windowIdString != windowId.uuidString && 
               windowManager.isValidTargetWindow(windowIdString) {
                print("📡 LayerGraphWindow: 使用回退方案，发送到窗口 - (\(windowIdString.prefix(8)))\n")
                
                NotificationCenter.default.post(
                    name: NSNotification.Name("switchToLayer"),
                    object: layer,
                    userInfo: ["sourceWindowId": windowIdString]
                )
                break
            }
        }
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
    
    private func showLayerGraphPresetManagerWindow() {
        let presetManagerView = LayerGraphPresetManagerView(
            filteredLayerIds: $filteredLayerIds
        )
        .environmentObject(store)
        
        let hostingView = NSHostingView(rootView: presetManagerView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 300, height: 525),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        // 移除最小尺寸限制，允许用户自由调整大小
        newWindow.minSize = NSSize(width: 270, height: 300)
        newWindow.contentView = hostingView
        newWindow.title = "图谱预设管理"
        newWindow.setFrameAutosaveName("LayerGraphPresetManagerWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        
        print("🪟 [预设管理] 窗口已创建")
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
            print("🔄 从输入框切换到层: \(layer.displayName)")
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
    @Binding var selectedLayerIds: Set<UUID>
    let onClose: () -> Void
    
    @EnvironmentObject private var store: NodeStore
    @State private var searchText = ""
    @State private var showActiveOnly = false
    @State private var showingNewLayerDialog = false
    @State private var newLayerName = ""
    @State private var newLayerDisplayName = ""
    @State private var newLayerColor = "blue"
    @State private var showingDeleteSelectedAlert = false
    @State private var showingEditLayerDialog = false
    @State private var editingLayer: Layer?
    @State private var editLayerDisplayName = ""
    
    private var filteredLayers: [Layer] {
        let filtered = store.layers.filter { layer in
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
                    
                    Button("删除选中") {
                        showingDeleteSelectedAlert = true
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    .disabled(selectedLayerIds.isEmpty)
                    
                    Spacer()
                    
                    Text("\(selectedLayerIds.count)/\(store.layers.count) 已选择")
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
                            },
                            onEdit: { layerToEdit in
                                showingEditLayerDialog = true
                                editingLayer = layerToEdit
                                editLayerDisplayName = layerToEdit.displayName
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
        .alert("删除选中的层", isPresented: $showingDeleteSelectedAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                deleteSelectedLayers()
            }
        } message: {
            let selectedLayers = store.layers.filter { selectedLayerIds.contains($0.id) }
            let totalNodes = selectedLayers.flatMap { layer in
                store.nodes.filter { $0.layerId == layer.id }
            }.count
            
            Text("确定要删除选中的 \(selectedLayerIds.count) 个层吗？\n\n这将删除 \(totalNodes) 个节点及其所有数据。此操作无法撤销。")
        }
        .sheet(isPresented: $showingEditLayerDialog) {
            EditLayerDialogView(
                layer: editingLayer ?? Layer(name: "", displayName: "", color: "blue"),
                editLayerDisplayName: $editLayerDisplayName,
                onCancel: { showingEditLayerDialog = false },
                onConfirm: { updateLayerName() }
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
    
    private func deleteSelectedLayers() {
        let selectedLayers = store.layers.filter { selectedLayerIds.contains($0.id) }
        for layer in selectedLayers {
            store.deleteLayer(layer)
        }
        selectedLayerIds.removeAll()
        print("🗑️ 删除了 \(selectedLayers.count) 个层")
    }
    
    private func updateLayerName() {
        guard let layer = editingLayer else { return }
        
        let trimmedName = editLayerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        // 更新层名
        store.updateLayerDisplayName(layer: layer, newDisplayName: trimmedName)
        
        // 关闭对话框
        showingEditLayerDialog = false
        
        print("✅ 更新层名: \(layer.displayName) -> \(trimmedName)")
    }
}

// MARK: - 编辑层名对话框
struct EditLayerDialogView: View {
    let layer: Layer
    @Binding var editLayerDisplayName: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @FocusState private var isFocused: Bool
    
    var isFormValid: Bool {
        !editLayerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        editLayerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines) != layer.displayName
    }
    
    var body: some View {
        TextField("层名", text: $editLayerDisplayName)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 14))
            .focused($isFocused)
            .onSubmit {
                if isFormValid {
                    onConfirm()
                }
            }
            .onAppear {
                // 自动聚焦并选中全部文本
                isFocused = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let window = NSApplication.shared.keyWindow,
                       let fieldEditor = window.fieldEditor(false, for: nil) {
                        fieldEditor.selectAll(nil)
                    }
                }
            }
            .padding(16)
            .frame(width: 250)
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
    var onEdit: ((Layer) -> Void)?
    @EnvironmentObject private var store: NodeStore
    
    var body: some View {
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
                Text(layer.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                // 底部：统计信息
                VStack(spacing: 2) {
                    // 节点和标签统计
                    HStack(spacing: 8) {
                        let nodeCount = store.nodes.filter { $0.layerId == layer.id }.count
                        let tagCount = store.nodes.filter { $0.layerId == layer.id }.flatMap { $0.tags }.count
                        
                        Text("\(nodeCount) 节点")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("\(tagCount) 标签")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // 复合层信息
                    if layer.isCompound && !layer.childLayerIds.isEmpty {
                        Text("\(layer.childLayerIds.count) 子层")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(3)
                    }
                }
        }
        .padding(12)
        .frame(minHeight: 100)  // 设置最小高度保持一致性
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { location in
            // 检查是否按下了 Option 键
            if NSEvent.modifierFlags.contains(.option) {
                // Option+点击：编辑层名
                onEdit?(layer)
            } else {
                // 普通点击：切换选择状态
                onToggle()
            }
        }
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
                        Text(layer.name)
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