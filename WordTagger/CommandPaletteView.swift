import SwiftUI
import CoreLocation
import MapKit
import Carbon

struct CommandPaletteView: View {
    @EnvironmentObject private var store: NodeStore
    @Binding var isPresented: Bool
    @State private var query: String = ""

    @StateObject private var commandParser = CommandParser.shared
    @StateObject private var keyboardManager = KeyboardEventManager()
    @FocusState private var isTextFieldFocused: Bool
    @State private var shouldDismiss: Bool = false
    
    // 添加选中状态管理
    @State private var selectedIndex: Int = -1
    @State private var isInputMethodActive: Bool = false

    
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
    
    // MARK: - Computed Properties for View Components
    
    private var backgroundLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                if allowBackgroundDismiss {
                    print("🔴 命令面板背景空白区域被点击，关闭面板")
                    shouldDismiss = true
                } else {
                    print("🛡️ 背景关闭被禁用，忽略点击")
                }
            }
    }
    
    private var titleSection: some View {
        HStack(spacing: 4) {
            if keyboardManager.isInErrorRecovery {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.orange)
            } else {
                Image(systemName: "command")
                    .font(.system(size: 14, weight: .medium))
            }
            Text(keyboardManager.isInErrorRecovery ? "恢复中" : "层管理")
                .font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(keyboardManager.isInErrorRecovery ? Color.orange : Color.blue)
        )
        .foregroundColor(.white)
        .onTapGesture {
            if keyboardManager.isInErrorRecovery {
                keyboardManager.resetErrorState()
            }
        }
    }
    
    @ViewBuilder
    private func searchTextFieldBuilder() -> some View {
        TextField("搜索层名...", text: $query)
            .font(.system(size: 14))
            .focused($isTextFieldFocused)
            .textFieldStyle(.plain)
            .onChange(of: query) { _, newValue in
                showSearchDropdown = !newValue.isEmpty
                selectedIndex = -1
            }
            .onKeyPress(.return) {
                let currentEvent = NSApp.currentEvent
                let hasMarkedText = currentEvent?.charactersIgnoringModifiers?.isEmpty == false
                
                if hasMarkedText || isInputMethodActive {
                    print("🇯🇵 输入法激活，忽略回车键")
                    return .ignored
                }
                
                return handleSearchReturn()
            }
            .onKeyPress(.tab) {
                navigateSearchResults(direction: .down)
                return .handled
            }
            .onKeyPress(.escape) {
                print("🎹 ESC键被按下，当前query: '\(query)'")
                if !query.isEmpty {
                    print("✅ 第一次ESC：清空输入，保持焦点")
                    query = ""
                    showSearchDropdown = false
                    return .handled
                } else {
                    print("🚪 第二次ESC：退出窗口")
                    isTextFieldFocused = false
                    shouldDismiss = true
                    return .handled
                }
            }
            .onKeyPress(.init("\t"), phases: .down) { keyPress in
                if keyPress.modifiers.contains(.shift) {
                    navigateSearchResults(direction: .up)
                    return .handled
                } else {
                    navigateSearchResults(direction: .down)
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
            .onKeyPress(.init("r"), phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) {
                    handleCreateNewLayer()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.init("R"), phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) {
                    handleCreateNewLayer()
                    return .handled
                }
                return .ignored
            }
    }
    
    private var searchSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
            
            searchTextFieldBuilder()
            
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
    }
    
    private var filterStatusView: some View {
        Group {
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
        }
    }
    
    private var filterButton: some View {
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
    }
    
    private var currentLayerDisplay: some View {
        Group {
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
    }
    
    private var topToolbar: some View {
        HStack(spacing: 12) {
            titleSection
            searchSection
            
            Text("层结构图谱")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            
            Spacer()
            
            filterStatusView
            filterButton
            currentLayerDisplay
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var mainContentLayer: some View {
        VStack(spacing: 0) {
            topToolbar
            
            Divider()
            
            LayerStructureGraphViewSimple(
                filteredLayerIds: $filteredLayerIds,
                isPresented: $isPresented,
                showFilterSheet: $showFilterSheet
            )
            .environmentObject(store)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var searchDropdownOverlay: some View {
        Group {
            if showSearchDropdown && !query.isEmpty {
                let matchingLayers = store.layers.filter { layer in
                    layer.displayName.lowercased().contains(query.lowercased()) ||
                    layer.name.lowercased().contains(query.lowercased())
                }
                
                VStack {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "command")
                                .font(.system(size: 14, weight: .medium))
                            Text("层管理")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .opacity(0)
                        
                        VStack(alignment: .leading, spacing: 0) {
                            if matchingLayers.isEmpty {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 12))
                                    Text("没有匹配的层")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            } else {
                                ForEach(Array(matchingLayers.prefix(8).enumerated()), id: \.element.id) { index, layer in
                                    SearchDropdownItem(
                                        layer: layer,
                                        query: query,
                                        isFiltered: filteredLayerIds.contains(layer.id),
                                        isSelected: index == selectedIndex
                                    ) {
                                        selectSearchItem(layer)
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
                    .padding(.top, 45)
                    
                    Spacer()
                }
                .zIndex(3000)
                .allowsHitTesting(true)
            }
        }
    }
    
    var body: some View {
        ZStack {
            backgroundLayer
            mainContentLayer
            searchDropdownOverlay
        }
        .frame(minWidth: 750, minHeight: 450)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .onKeyPress(.escape) {
            print("🎹 顶层ESC键被按下，当前query: '\(query)', 焦点状态: \(isTextFieldFocused)")
            
            if isTextFieldFocused {
                if !query.isEmpty {
                    print("✅ 顶层第一次ESC：清空输入，保持焦点")
                    query = ""
                    showSearchDropdown = false
                    return .handled
                } else {
                    print("🚪 顶层第二次ESC：退出窗口")
                    isTextFieldFocused = false
                    shouldDismiss = true
                    return .handled
                }
            }
            
            print("🚪 顶层ESC：搜索框无焦点，直接退出")
            shouldDismiss = true
            return .handled
        }
        .onKeyPress(.init("g"), phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                guard keyboardManager.canExecuteCommand(KeyboardEventManager.Commands.commandG) else {
                    print("🎹 Command+G blocked by keyboard manager")
                    return .handled
                }
                
                keyboardManager.markCommandExecuted(KeyboardEventManager.Commands.commandG)
                Task {
                    do {
                        try await handleCommandGWithErrorHandling()
                    } catch {
                        keyboardManager.markCommandFailed(KeyboardEventManager.Commands.commandG, error: error as? KeyboardError ?? .unexpectedState)
                    }
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.init("w"), phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                guard keyboardManager.canExecuteCommand(KeyboardEventManager.Commands.commandW) else {
                    print("🎹 Command+W blocked by keyboard manager")
                    return .handled
                }
                
                print("🎹 Command+W detected, marking execution and clearing command states")
                keyboardManager.markCommandExecuted(KeyboardEventManager.Commands.commandW)
                
                keyboardManager.clearCommandState()
                print("✅ Command states cleared before executing Command+W")
                
                handleCommandW()
                return .handled
            }
            return .ignored
        }
        .onAppear {
            setupView()
            
            Task { @MainActor in
                if filteredLayerIds.isEmpty {
                    filteredLayerIds = Set(store.layers.map { $0.id })
                }
            }
            
            setupInputMethodMonitoring()
            
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("disableBackgroundDismiss"),
                object: nil,
                queue: .main
            ) { _ in
                print("🛡️ 收到禁用背景关闭通知")
                allowBackgroundDismiss = false
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    allowBackgroundDismiss = true
                    print("🔓 重新启用背景关闭")
                }
            }
            
            keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                print("🎹 NSEvent监听到键盘事件: keyCode=\(event.keyCode), characters=\(event.characters ?? "nil"), 焦点状态: \(isTextFieldFocused)")
                
                if event.keyCode == 53 {
                    print("🎹 NSEvent检测到ESC键，当前query: '\(query)', 焦点状态: \(isTextFieldFocused)")
                    
                    if isTextFieldFocused {
                        if !query.isEmpty {
                            print("✅ NSEvent第一次ESC：清空输入，保持焦点")
                            DispatchQueue.main.async {
                                query = ""
                                showSearchDropdown = false
                            }
                            return nil
                        } else {
                            print("🚪 NSEvent第二次ESC：退出窗口")
                            DispatchQueue.main.async {
                                isTextFieldFocused = false
                                shouldDismiss = true
                            }
                            return nil
                        }
                    } else {
                        print("🚪 NSEvent ESC：搜索框无焦点，直接退出")
                        DispatchQueue.main.async {
                            shouldDismiss = true
                        }
                        return nil
                    }
                }
                return event
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
            if let monitor = keyEventMonitor {
                NSEvent.removeMonitor(monitor)
                keyEventMonitor = nil
            }
            
            NotificationCenter.default.removeObserver(
                self,
                name: NSNotification.Name("AppleSelectedInputSourcesChangedNotification"),
                object: nil
            )
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
        // Clear keyboard event state before closing
        keyboardManager.clearCommandState()
        
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
    
    // 处理⌘R: 创建新层
    private func handleCreateNewLayer() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            print("🔍 CommandPalette: 查询为空，无法创建新层")
            return
        }
        
        // 首先检查是否是复合层格式
        let context = CommandContext(store: store)
        if let command = commandParser.parseDirectCommand(trimmedQuery, context: context) {
            // 如果解析出了命令，执行它
            Task {
                do {
                    let result = try await command.execute(with: context)
                    await MainActor.run {
                        handleCommandResult(result)
                        // 清空搜索框
                        query = ""
                        showSearchDropdown = false
                    }
                } catch {
                    print("❌ CommandPalette: 执行命令失败: \(error)")
                }
            }
            return
        }
        
        // 如果不是复合层格式，创建普通层
        // 检查是否已存在同名层
        let existingLayer = store.layers.first { layer in
            layer.displayName.lowercased() == trimmedQuery.lowercased() ||
            layer.name.lowercased() == trimmedQuery.lowercased()
        }
        
        if existingLayer != nil {
            print("⚠️ CommandPalette: 层 '\(trimmedQuery)' 已存在")
            return
        }
        
        // 创建新层
        let newLayer = store.createLayer(
            name: trimmedQuery.lowercased().replacingOccurrences(of: " ", with: "_"),
            displayName: trimmedQuery,
            color: "blue"
        )
        
        print("✅ CommandPalette: 成功创建新层 '\(newLayer.displayName)'")
        
        // 自动添加新层到过滤器
        filteredLayerIds.insert(newLayer.id)
        
        // 清空搜索框
        query = ""
        showSearchDropdown = false
        
        // 如果这是第一个层，自动激活
        if store.layers.count == 1 {
            Task {
                await store.switchToLayer(newLayer)
            }
        }
    }
    
    // 处理⌘G: 打开图谱窗口
    private func handleCommandG() {
        print("🎹 CommandPalette: 执行Command+G - 打开图谱窗口")
        
        // Verify that Command+W is not active to prevent interference
        if keyboardManager.isCommandActive(KeyboardEventManager.Commands.commandW) {
            print("⚠️ CommandPalette: Command+W is active, skipping Command+G execution")
            return
        }
        
        NotificationCenter.default.post(name: .openGraphWindow, object: nil)
    }
    
    // Enhanced Command+G handler with error handling
    private func handleCommandGWithErrorHandling() async throws {
        print("🎹 CommandPalette: 执行Command+G (with error handling) - 打开图谱窗口")
        
        // Check for focus issues
        guard NSApplication.shared.isActive else {
            throw KeyboardError.focusLost
        }
        
        // Verify that Command+W is not active to prevent interference
        if keyboardManager.isCommandActive(KeyboardEventManager.Commands.commandW) {
            print("⚠️ CommandPalette: Command+W is active, skipping Command+G execution")
            throw KeyboardError.eventConflict
        }
        
        // Check if we're in error recovery mode
        if keyboardManager.isInErrorRecovery {
            print("⚠️ CommandPalette: In error recovery mode, cannot execute Command+G")
            throw KeyboardError.unexpectedState
        }
        
        // Execute the command with timeout protection
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            throw KeyboardError.timeout
        }
        
        let commandTask = Task {
            NotificationCenter.default.post(name: .openGraphWindow, object: nil)
        }
        
        // Wait for either completion or timeout
        _ = try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = await commandTask.value
            }
            group.addTask {
                try await timeoutTask.value
            }
            
            // Return when first task completes
            try await group.next()
            group.cancelAll()
        }
        print("✅ Command+G executed successfully")
    }
    
    // 处理搜索结果导航
    private enum NavigationDirection {
        case up, down
    }
    
    private func navigateSearchResults(direction: NavigationDirection) {
        let matchingLayers = store.layers.filter { layer in
            layer.displayName.lowercased().contains(query.lowercased()) ||
            layer.name.lowercased().contains(query.lowercased())
        }
        
        guard !matchingLayers.isEmpty else { return }
        
        let maxIndex = min(8, matchingLayers.count) - 1
        
        switch direction {
        case .down:
            if selectedIndex < maxIndex {
                selectedIndex += 1
            } else {
                selectedIndex = 0 // 循环到第一个
            }
        case .up:
            if selectedIndex > 0 {
                selectedIndex -= 1
            } else {
                selectedIndex = maxIndex // 循环到最后一个
            }
        }
        
        print("🔍 导航搜索结果: 选中索引 \(selectedIndex)/\(maxIndex)")
    }
    
    private func handleSearchReturn() -> SwiftUI.KeyPress.Result {
        let matchingLayers = store.layers.filter { layer in
            layer.displayName.lowercased().contains(query.lowercased()) ||
            layer.name.lowercased().contains(query.lowercased())
        }
        
        guard !matchingLayers.isEmpty else {
            print("🔍 没有搜索结果，忽略回车键")
            return .handled
        }
        
        // 如果没有选中任何项，选中第一个
        if selectedIndex < 0 {
            selectedIndex = 0
        }
        
        let selectedLayer = Array(matchingLayers.prefix(8))[min(selectedIndex, matchingLayers.count - 1)]
        selectSearchItem(selectedLayer)
        
        return .handled
    }
    
    private func selectSearchItem(_ layer: Layer) {
        query = layer.displayName
        showSearchDropdown = false
        selectedIndex = -1
        print("✅ 选中搜索结果: \(layer.displayName)")
    }
    
    // 设置输入法监听
    private func setupInputMethodMonitoring() {
        // 使用正确的NSTextInputContext通知
        NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            // 检测键盘选择变化，可能表示输入法状态变化
            print("🇯🇵 键盘选择状态变化")
            self.checkInputMethodState()
        }
        
        // 使用NSTextInputContext的selectedKeyboardInputSource来检测输入法
        // 这是一个更可靠的方法来监控输入法状态
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleSelectedInputSourcesChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            print("🇯🇵 输入源发生变化")
            self.checkInputMethodState()
        }
    }
    
    // 检查当前输入法状态的辅助方法
    private func checkInputMethodState() {
        // 方法1: 检查当前事件是否有未提交的文本
        if let currentEvent = NSApp.currentEvent {
            let hasMarkedText = !(currentEvent.charactersIgnoringModifiers?.isEmpty ?? true)
            self.isInputMethodActive = hasMarkedText
            print("🇯🇵 输入法状态更新: \(hasMarkedText ? "激活" : "取消") (基于当前事件)")
            return
        }
        
        // 方法2: 检查输入源
        if let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            let sourceID = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID)
            if let sourceIDString = Unmanaged<CFString>.fromOpaque(sourceID!).takeUnretainedValue() as String? {
                let isNonEnglish = !sourceIDString.hasPrefix("com.apple.keylayout.") || 
                                 sourceIDString.contains("Hiragana") || 
                                 sourceIDString.contains("Katakana") ||
                                 sourceIDString.contains("Chinese") ||
                                 sourceIDString.contains("Korean")
                
                // 只有当输入源变化为非英文输入法时才设置为激活
                let wasActive = self.isInputMethodActive
                if isNonEnglish != wasActive {
                    self.isInputMethodActive = isNonEnglish
                    print("🇯🇵 输入法状态更新: \(isNonEnglish ? "激活" : "取消") (输入源: \(sourceIDString))")
                }
            }
        }
    }
    
    // 实时检测输入法是否激活 - 更精确的方法
    private func isInputMethodCurrentlyActive() -> Bool {
        // 方法1: 检查当前是否有marked text（未提交的输入法文本）
        if let currentEvent = NSApp.currentEvent,
           let characters = currentEvent.characters,
           !characters.isEmpty,
           currentEvent.characters != currentEvent.charactersIgnoringModifiers {
            print("🇯🇵 检测到marked text，输入法激活")
            return true
        }
        
        // 方法2: 检查当前输入源是否为非ASCII输入法
        if let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            let sourceID = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID)
            if let sourceIDString = Unmanaged<CFString>.fromOpaque(sourceID!).takeUnretainedValue() as String? {
                let isIME = sourceIDString.contains("Hiragana") || 
                           sourceIDString.contains("Katakana") ||
                           sourceIDString.contains("Chinese") ||
                           sourceIDString.contains("Korean") ||
                           sourceIDString.contains("Pinyin") ||
                           sourceIDString.contains("Romaji")
                
                if isIME {
                    print("🇯🇵 检测到IME输入源: \(sourceIDString)")
                    return true
                }
            }
        }
        
        // 方法3: 检查NSTextInputContext的marked range
        if let mainWindow = NSApp.mainWindow,
           let firstResponder = mainWindow.firstResponder as? NSTextView {
            let hasMarkedRange = firstResponder.markedRange().location != NSNotFound
            if hasMarkedRange {
                print("🇯🇵 检测到NSTextView有marked range")
                return true
            }
        }
        
        return false
    }
    
    // 处理⌘W: 关闭窗口
    private func handleCommandW() {
        print("🎹 CommandPalette: 执行Command+W - 关闭窗口")
        
        // Verify that Command+G is not active before proceeding
        if keyboardManager.isCommandActive(KeyboardEventManager.Commands.commandG) {
            print("⚠️ CommandPalette: Command+G is still active, clearing state before closing")
            // Clear the state again to ensure clean closure
            keyboardManager.clearCommandState()
        }
        
        // Verify that no other commands are active before closing
        if keyboardManager.isCommandActive(KeyboardEventManager.Commands.commandG) {
            print("⚠️ CommandPalette: Command+G still active after clearing, aborting window close")
            return
        }
        
        // Ensure Command+W doesn't trigger Command+G functionality by clearing all states
        keyboardManager.clearCommandState()
        
        print("✅ CommandPalette: All command states cleared, proceeding with window close")
        
        // Close the command palette
        shouldDismiss = true
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
        NodeContextGraphView(
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
        .environmentObject(store)
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
    let isSelected: Bool
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
            .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
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

// Preview temporarily disabled due to @FocusState initialization complexity
// #Preview {
//     CommandPaletteView(isPresented: .constant(true))
//         .environmentObject(NodeStore.shared)
// }