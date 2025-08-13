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
                // 左侧：命令列表
                VStack(spacing: 0) {
                    // 搜索框
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("搜索命令...", text: $query, onCommit: {
                            executeSelectedCommand()
                        })
                        .font(.title2)
                        .focused($isTextFieldFocused)
                        .onKeyPress(.upArrow) {
                            selectedIndex = max(0, selectedIndex - 1)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            selectedIndex = min(availableCommands.count - 1, selectedIndex + 1)
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            isTextFieldFocused = false
                            shouldDismiss = true
                            return .handled
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(NSColor.textBackgroundColor))
                    
                    Divider()
                    
                    // 命令列表
                    if availableCommands.isEmpty && !query.isEmpty {
                        VStack {
                            Text("未找到匹配的命令")
                                .foregroundColor(.secondary)
                                .padding(.vertical, 20)
                        }
                        .frame(maxHeight: 60)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(availableCommands.enumerated()), id: \.offset) { index, command in
                                    CommandRowView(
                                        command: command,
                                        isSelected: index == selectedIndex
                                    ) {
                                        executeCommand(command)
                                    }
                                    .id(index)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .frame(minHeight: 400, maxHeight: .infinity)
                    }
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
                    
                    LayerStructureGraphViewSimple()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isPresented = false
            shouldDismiss = false
        }
    }
    
    @MainActor
    private func updateAvailableCommands() {
        let context = CommandContext(
            store: store,
            currentNode: store.selectedNode,
            selectedTag: store.selectedTag
        )
        
        Task {
            availableCommands = await commandParser.parse(query, context: context)
        }
    }
    
    private func executeSelectedCommand() {
        guard !availableCommands.isEmpty, selectedIndex < availableCommands.count else { return }
        let command = availableCommands[selectedIndex]
        executeCommand(command)
    }
    
    
    private func executeCommand(_ command: Command) {
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
}

// MARK: - Simplified Layer Structure Graph View

struct LayerStructureGraphViewSimple: View {
    @EnvironmentObject private var store: NodeStore
    @State private var cachedNodes: [LayerGraphNode] = []
    @State private var cachedEdges: [LayerGraphEdge] = []
    @State private var selectedLayerId: UUID?
    @State private var filteredLayerIds: Set<UUID> = []
    @State private var layerSearchText: String = ""
    
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
    }
    
    private var filterControlSection: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("层过滤器")
                        .font(.body)
                        .fontWeight(.semibold)
                    Text("选择要显示在图谱中的层")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                filterButtons
            }
            
            // 独立的层搜索框 - 完全隔离
            IsolatedLayerSearchBox(searchText: $layerSearchText)
            
            // 过滤后的层列表
            layerFilterScrollView
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .background(Color.clear)
        .allowsHitTesting(true)
        // 使用最高优先级手势拦截点击事件
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    print("🛡️ 层过滤器区域点击被拦截")
                    // 不执行任何操作，只是拦截事件
                }
        )
    }
    
    private var filterButtons: some View {
        HStack(spacing: 8) {
            Button("全选") {
                filteredLayerIds = Set(store.layers.map { $0.id })
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Button("清空") {
                filteredLayerIds.removeAll()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Button("当前层") {
                if let currentLayer = store.currentLayer {
                    filteredLayerIds = [currentLayer.id]
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
    
    private var layerFilterScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filteredLayers) { layer in
                    LayerFilterToggle(
                        layer: layer,
                        isSelected: filteredLayerIds.contains(layer.id)
                    ) {
                        toggleLayerFilter(layer)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 40)
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
            initialScale: 0.9,
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

struct LayerFilterToggle: View {
    let layer: Layer
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .font(.body)
                
                Text(layer.displayName)
                    .font(.body)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

// MARK: - IsolatedLayerSearchBox

private struct IsolatedLayerSearchBox: View {
    @Binding var searchText: String
    @State private var internalSearchText: String = ""
    @FocusState private var isInternalFocused: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.caption)
            
            // 使用内部状态，完全隔离
            TextField("搜索层名...", text: $internalSearchText)
                .font(.caption)
                .textFieldStyle(.plain)
                .focused($isInternalFocused)
                .onChange(of: internalSearchText) { _, newValue in
                    // 只传递搜索文本，不传递任何焦点或命令事件
                    searchText = newValue
                }
                .onAppear {
                    internalSearchText = searchText
                }
                .onSubmit {
                    // 完全阻止回车键的所有默认行为
                    print("🛡️ 层搜索框回车键被按下，阻止事件传播")
                    // 不执行任何操作，防止触发父级的命令执行
                }
                // 阻止所有键盘事件向上传播
                .onKeyPress(.escape) {
                    isInternalFocused = false
                    return .handled
                }
                .onKeyPress(.return) {
                    // 完全拦截回车键
                    print("🛡️ 层搜索框拦截回车键")
                    return .handled
                }
                .allowsHitTesting(true)
            
            if !internalSearchText.isEmpty {
                Button(action: { 
                    internalSearchText = ""
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .allowsHitTesting(true)
        // 使用最高优先级手势完全拦截所有点击事件
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    print("🛡️ 层搜索框最高优先级手势拦截点击")
                    isInternalFocused = true
                    
                    // 通知父视图禁用背景关闭
                    NotificationCenter.default.post(
                        name: NSNotification.Name("disableBackgroundDismiss"),
                        object: nil
                    )
                }
        )
        // 移除可能导致事件冒泡的其他手势
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