import SwiftUI
import CoreLocation
import MapKit

struct CommandPaletteView: View {
    @EnvironmentObject private var store: NodeStore
    @Binding var isPresented: Bool
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @StateObject private var commandParser = CommandParser.shared
    @FocusState private var isTextFieldFocused: Bool
    @State private var shouldDismiss: Bool = false
    @State private var availableCommands: [Command] = []
    
    // 添加安全关闭标志，防止意外关闭
    @State private var allowBackgroundDismiss: Bool = true
    
    // 层过滤器状态 - 提升到CommandPaletteView级别
    @State private var filteredLayerIds: Set<UUID> = []
    
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
            
            VStack(spacing: 0) {
                // 顶部工具栏
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "command")
                    Text("命令")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue)
                )
                .foregroundColor(.white)
                
                Spacer()
                
                if let currentLayer = store.currentLayer {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        Text(currentLayer.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 内容区域 - 添加事件拦截防止意外关闭
            HStack(spacing: 0) {
                // 左侧：层管理搜索
                VStack(spacing: 0) {
                    // 搜索框
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("搜索层名...", text: $query)
                            .font(.title2)
                            .focused($isTextFieldFocused)
                            .onKeyPress(.escape) {
                                isTextFieldFocused = false
                                shouldDismiss = true
                                return .handled
                            }
                            .onKeyPress(.init("j"), phases: .down) { keyPress in
                                if keyPress.modifiers.contains(.command) {
                                    if keyPress.modifiers.contains(.shift) {
                                        // ⌘⇧J: 从过滤器中移除层
                                        handleRemoveLayerFromFilter()
                                    } else {
                                        // ⌘J: 添加层到过滤器
                                        handleAddLayerToFilter()
                                    }
                                    return .handled
                                }
                                return .ignored
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(NSColor.textBackgroundColor))
                    
                    Divider()
                    
                    // 层管理说明
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("层管理")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text("在上方搜索框中输入层名，然后使用快捷键管理图谱中显示的层。")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Text("⌘J")
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                                
                                Text("添加层到图谱")
                                    .font(.body)
                            }
                            
                            HStack(spacing: 8) {
                                Text("⌘⇧J")
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                                
                                Text("从图谱中移除层")
                                    .font(.body)
                            }
                            
                            HStack(spacing: 8) {
                                Text("Esc")
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                                
                                Text("关闭面板")
                                    .font(.body)
                            }
                        }
                        
                        if !query.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("搜索结果")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                let matchingLayers = store.layers.filter { layer in
                                    layer.displayName.lowercased().contains(query.lowercased()) ||
                                    layer.name.lowercased().contains(query.lowercased())
                                }
                                
                                if matchingLayers.isEmpty {
                                    Text("未找到匹配的层")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                } else {
                                    ForEach(matchingLayers.prefix(5), id: \.id) { layer in
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(layer.isCompound ? Color.purple : Color.blue)
                                                .frame(width: 8, height: 8)
                                            
                                            Text(layer.displayName)
                                                .font(.body)
                                            
                                            if layer.isCompound {
                                                Text("(复合层)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            Spacer()
                                            
                                            if filteredLayerIds.contains(layer.id) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                                    .font(.caption)
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                    
                                    if matchingLayers.count > 5 {
                                        Text("... 还有 \(matchingLayers.count - 5) 个")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(width: 300)
                
                Divider()
                
                // 右侧：层关系图谱
                VStack(spacing: 0) {
                    HStack {
                        Text("层结构图谱")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Text("\(store.layers.count) 个层")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    
                    Divider()
                    
                    LayerStructureGraphViewSimple(filteredLayerIds: $filteredLayerIds)
                        .environmentObject(store)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.clear)
                        .allowsHitTesting(true)
                        // 使用最高优先级手势完全拦截所有点击事件
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded { _ in
                                    print("🛡️ 层图谱区域点击被完全拦截")
                                    // 不执行任何操作，只是拦截事件防止冒泡
                                }
                        )
                }
                .frame(minWidth: 500, maxWidth: .infinity)
                .background(Color.clear)
                .allowsHitTesting(true)
                // 为整个右侧面板添加事件拦截
                .simultaneousGesture(
                    TapGesture()
                        .onEnded { _ in
                            print("🛡️ 右侧面板点击被拦截，防止窗口关闭")
                        }
                )
            }
            .background(Color(NSColor.windowBackgroundColor))
            .allowsHitTesting(true)
            // 为整个内容区域添加事件拦截，防止点击内容区域时关闭窗口
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        print("🛡️ 内容区域点击被拦截，防止意外关闭")
                        // 临时禁用背景关闭，防止事件冒泡
                        allowBackgroundDismiss = false
                        
                        // 短暂延迟后重新启用背景关闭
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            allowBackgroundDismiss = true
                        }
                    }
            )
        }
        } // 结束最外层ZStack
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .onAppear {
            setupView()
            
            // 初始化层过滤器为显示所有层
            filteredLayerIds = Set(store.layers.map { $0.id })
            
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
        }
        .onChange(of: query) { _, newQuery in
            updateAvailableCommands()
            selectedIndex = 0
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
        }
    }
    
    // MARK: - View Logic
    
    private func setupView() {
        query = ""
        selectedIndex = 0
        updateAvailableCommands()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTextFieldFocused = true
        }
    }
    
    private func dismissView() {
        // 清除搜索框焦点，防止残留蓝色边框
        isTextFieldFocused = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isPresented = false
            shouldDismiss = false
        }
    }
    
    @MainActor
    private func updateAvailableCommands() {
        print("🔄 CommandPalette: 更新可用命令")
        print("   - 当前查询: '\(query)'")
        
        let context = CommandContext(
            store: store,
            currentNode: store.selectedNode,
            selectedTag: store.selectedTag
        )
        
        Task {
            let newCommands = await commandParser.parse(query, context: context)
            await MainActor.run {
                availableCommands = newCommands
                print("   - 更新后命令数量: \(availableCommands.count)")
                if !availableCommands.isEmpty {
                    print("   - 第一个命令: \(availableCommands[0].title)")
                }
            }
        }
    }
    
    private func executeSelectedCommand() {
        print("🎯 CommandPalette: executeSelectedCommand 被调用")
        print("   - 可用命令数量: \(availableCommands.count)")
        print("   - 选中索引: \(selectedIndex)")
        print("   - 查询内容: '\(query)'")
        print("   - 搜索框是否聚焦: \(isTextFieldFocused)")
        
        guard !availableCommands.isEmpty, selectedIndex < availableCommands.count else { 
            print("❌ CommandPalette: 无效的命令选择，取消执行")
            return 
        }
        
        let command = availableCommands[selectedIndex]
        print("🎯 CommandPalette: 准备执行选中的命令 - \(command.title)")
        
        // 添加额外的安全检查
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("⚠️ CommandPalette: 查询为空时执行命令，可能是意外触发")
            
            // 如果是层切换命令且查询为空，可能是意外触发
            if command is SwitchLayerCommand {
                print("🛡️ CommandPalette: 阻止空查询时的层切换命令执行")
                return
            }
        }
        
        executeCommand(command)
    }
    
    
    private func executeCommand(_ command: Command) {
        // 添加调试日志来追踪命令执行
        print("🚀 CommandPalette: 执行命令 - \(command.title)")
        print("   - 命令类型: \(type(of: command))")
        print("   - 命令ID: \(command.id)")
        
        // 如果是层切换命令，添加额外的保护
        if let switchCommand = command as? SwitchLayerCommand {
            print("⚠️ CommandPalette: 检测到层切换命令执行")
            print("   - 目标层: \(switchCommand.title)")
            print("   - 是否子层: \(switchCommand.isChildLayer)")
            
            // 检查是否是意外执行（例如，用户没有明确选择这个命令）
            if !isTextFieldFocused && query.isEmpty {
                print("🛡️ CommandPalette: 阻止意外的层切换命令执行")
                print("   - 搜索框未聚焦且查询为空，可能是意外触发")
                return
            }
        }
        
        let context = CommandContext(
            store: store,
            currentNode: store.selectedNode,
            selectedTag: store.selectedTag
        )
        
        Task {
            do {
                let result = try await command.execute(with: context)
                await MainActor.run {
                    handleCommandResult(result)
                    
                    if case .error(_) = result {
                        return
                    }
                    
                    isTextFieldFocused = false
                    withAnimation(.linear(duration: 0.05)) {
                        isPresented = false
                    }
                }
            } catch {
                await MainActor.run {
                    isTextFieldFocused = false
                    isPresented = false
                }
            }
        }
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
    @State private var cachedNodes: [LayerGraphNode] = []
    @State private var cachedEdges: [LayerGraphEdge] = []
    @State private var selectedLayerId: UUID?
    @State private var layerSearchText: String = ""
    
    // 使用设置中的层结构图谱缩放级别
    @AppStorage("layerStructureGraphInitialScale") private var layerGraphInitialScale: Double = 0.9
    
    var body: some View {
        VStack(spacing: 0) {
            filterControlSection
            Divider()
            selectedLayerInfo
            graphContent
        }
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
            filteredLayerIds = Set(store.layers.map { $0.id })
            updateLayerGraphData()
            selectedLayerId = store.currentLayer?.id
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
        VStack(spacing: 0) {
            // 工具栏样式的过滤器控制
            HStack {
                Text("层结构图谱")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // 层选择器按钮
                Button(action: {
                    // 切换全选/清空状态
                    if filteredLayerIds.count == store.layers.count {
                        filteredLayerIds.removeAll()
                    } else {
                        filteredLayerIds = Set(store.layers.map { $0.id })
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: filteredLayerIds.isEmpty ? "square" : (filteredLayerIds.count == store.layers.count ? "checkmark.square.fill" : "minus.square.fill"))
                        Text("选择层")
                        if !filteredLayerIds.isEmpty {
                            Text("(\(filteredLayerIds.count))")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .help("选择要显示的层")
                
                // 层搜索框
                TextField("搜索层名...", text: $layerSearchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .onSubmit {
                        // 搜索框回车不执行任何操作
                        print("🛡️ 层搜索框回车被拦截")
                    }
                
                // 快速过滤按钮
                Menu("过滤") {
                    Button("全选") {
                        filteredLayerIds = Set(store.layers.map { $0.id })
                    }
                    
                    Button("清空") {
                        filteredLayerIds.removeAll()
                    }
                    
                    Button("仅复合层") {
                        filteredLayerIds = Set(store.layers.filter { $0.isCompound }.map { $0.id })
                    }
                    
                    Button("仅普通层") {
                        filteredLayerIds = Set(store.layers.filter { !$0.isCompound }.map { $0.id })
                    }
                    
                    if let currentLayer = store.currentLayer {
                        Button("当前层") {
                            filteredLayerIds = [currentLayer.id]
                        }
                    }
                }
                .buttonStyle(.bordered)
                

                
                // 重置按钮
                if !filteredLayerIds.isEmpty && filteredLayerIds.count != store.layers.count {
                    Button("显示全部") {
                        filteredLayerIds = Set(store.layers.map { $0.id })
                        layerSearchText = ""
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 层标签显示区域（类似GraphView的节点选择器）
            if !filteredLayers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filteredLayers.prefix(10), id: \.id) { layer in
                            LayerFilterChip(
                                layer: layer,
                                isSelected: filteredLayerIds.contains(layer.id)
                            ) {
                                toggleLayerFilter(layer)
                            }
                        }
                        
                        if filteredLayers.count > 10 {
                            Text("... +\(filteredLayers.count - 10)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .frame(height: 40)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
        }
        .background(Color.clear)
        .allowsHitTesting(true)
        // 使用最高优先级手势拦截点击事件
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    print("🛡️ 层过滤器区域点击被拦截")
                    // 通知父视图禁用背景关闭
                    NotificationCenter.default.post(
                        name: NSNotification.Name("disableBackgroundDismiss"),
                        object: nil
                    )
                }
        )
    }
    

    

    
    // 根据搜索文本过滤层
    private var filteredLayers: [Layer] {
        if layerSearchText.isEmpty {
            return store.sortedLayers
        } else {
            return store.sortedLayers.filter { layer in
                layer.displayName.localizedCaseInsensitiveContains(layerSearchText) ||
                layer.name.localizedCaseInsensitiveContains(layerSearchText)
            }
        }
    }
    
    private var selectedLayerInfo: some View {
        Group {
            if let selectedLayerId = selectedLayerId,
               let selectedLayer = store.layers.first(where: { $0.id == selectedLayerId }) {
                HStack {
                    Text("选中层: \(selectedLayer.displayName)")
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Button("切换到此层") {
                        Task {
                            await store.switchToLayer(selectedLayer)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
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
                    // 只选中层，不切换层！切换层会关闭命令面板
                    selectedLayerId = layerId
                    print("🔍 选中层: \(targetLayer.displayName)，使用上方按钮切换")
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
            filteredLayerIds.remove(layer.id)
        } else {
            filteredLayerIds.insert(layer.id)
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
        case .node: return .green
        case .tag: return .orange
        case .search: return .blue
        case .navigation: return .red
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

#Preview {
    CommandPaletteView(isPresented: .constant(true))
        .environmentObject(NodeStore.shared)
}