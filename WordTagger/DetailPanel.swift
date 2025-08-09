import SwiftUI
import CoreLocation
import MapKit
import UniformTypeIdentifiers

struct DetailPanel: View {
    let node: Node
    @EnvironmentObject private var store: NodeStore
    @State private var tab: Tab = .related
    @State private var showingEditSheet = false
    
    // 从store中获取最新的节点数据
    private var currentNode: Node {
        return store.nodes.first { $0.id == node.id } ?? node
    }
    
    enum Tab: String, CaseIterable {
        case related = "图谱"
        case map = "地图"
        case detail = "详情"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标签栏
            HStack {
                Picker("视图", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                
                Spacer()
                
                Button(action: { showingEditSheet = true }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
                .help("编辑节点")
                
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 内容区域
            Group {
                switch tab {
                case .detail:
                    NodeDetailView(node: currentNode)
                case .map:
                    NodeMapView(node: currentNode)
                case .related:
                    NodeGraphView(node: currentNode)
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditNodeSheet(node: currentNode)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("toggleDetailEditMode"))) { notification in
            // 收到全局Command+T通知，切换到详情页并切换编辑模式
            if let notificationNode = notification.object as? Node,
               notificationNode.id == node.id {
                // 静默切换到详情编辑模式
                withAnimation(.easeInOut(duration: 0.2)) {
                    tab = .detail // 切换到详情页
                }
                
                // 延迟一点确保tab切换完成后再切换编辑模式
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // 发送通知给NodeDetailView切换编辑模式
                    NotificationCenter.default.post(
                        name: NSNotification.Name("toggleNodeDetailEditMode"),
                        object: notificationNode
                    )
                }
            }
        }
    }
}

// MARK: - 节点详情视图

struct NodeDetailView: View {
    let node: Node
    @EnvironmentObject private var store: NodeStore
    @State private var markdownText: String = ""
    @StateObject private var imageManager = NodeImageManager.shared
    @State private var debounceTask: Task<Void, Never>?
    @State private var isEditing: Bool = false
    @FocusState private var isTextEditorFocused: Bool
    
    // 从store中获取最新的节点数据
    private var currentNode: Node {
        return store.nodes.first { $0.id == node.id } ?? node
    }

    private var hasMermaid: Bool {
        // 检测是否包含 mermaid 代码块或常见的 mermaid 关键字
        let pattern = #"(^|\n)```(mermaid|mmd)\b|(^|\n):::mermaid\b|(^|\n)(graph|sequenceDiagram|classDiagram|erDiagram|gantt|pie|journey)\b"#
        return markdownText.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 简洁的标题栏
            HStack {
                Text(currentNode.text)
                    .font(.headline)
                Spacer()
                
                // 状态指示器 - 仅显示编辑状态
                if isEditing {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("编辑中")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if markdownText.isEmpty {
                    Text("点击开始编辑...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 编辑按钮
                Button("编辑") {
                    isEditing.toggle()
                }
            }
            .padding(.horizontal)

            // 使用 Milkdown WebView 实时 Markdown 编辑（主角）
            MilkdownWebView(
                markdown: markdownText,
                onChange: { newValue in
                    debouncedSave(newValue)
                    markdownText = newValue
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)   // 让它吃满可用空间
            .background(Color.clear)
            .zIndex(2)

            // TODO: 移除独立预览区域，改为真正的编辑器内联就地渲染
            // if hasMermaid {
            //     Divider().opacity(0.15)
            //     MermaidWebView(markdown: markdownText)
            //         .frame(height: 220)
            //         .background(Color.clear)
            //         .allowsHitTesting(false)
            //         .zIndex(0)
            // }
            
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            loadMarkdown()
        }
        .onChange(of: currentNode.id) { _, _ in
            loadMarkdown()
        }
        .onChange(of: isEditing) { _, newValue in
            if newValue {
                // 静默进入编辑模式
            }
        }
        .onKeyPress(.init("/"), phases: .down) { keyPress in
            if keyPress.modifiers == .command {
                // Command+/: 切换编辑模式
                isEditing.toggle()
                return .handled
            }
            return .ignored
        }
        .onDisappear {
            // 清理异步任务
            debounceTask?.cancel()
        }
    }
    
    private func loadMarkdown() {
        markdownText = currentNode.markdown
    }
    
    private func saveMarkdown() {
        Task { @MainActor in
            store.updateNodeMarkdown(currentNode.id, markdown: markdownText)
        }
    }
    
    private func debouncedSave(_ newValue: String) {
        // 取消之前的任务
        debounceTask?.cancel()
        
        // 创建新的防抖任务
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒延迟
            
            if !Task.isCancelled {
                store.updateNodeMarkdown(currentNode.id, markdown: newValue)
            }
        }
    }
    
    private func handleImageDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.image") {
                provider.loadItem(forTypeIdentifier: "public.image") { item, error in
                    guard error == nil else {
                        print("图片拖拽加载失败: \(error!)")
                        return
                    }
                    
                    var imageURL: URL?
                    
                    if let url = item as? URL {
                        imageURL = url
                    } else if let data = item as? Data {
                        // 处理剪贴板或其他数据源的图片
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent("dropped_image_\(UUID().uuidString).png")
                        try? data.write(to: tempURL)
                        imageURL = tempURL
                    }
                    
                    guard let sourceURL = imageURL else { return }
                    
                    DispatchQueue.main.async {
                        if let fileName = self.imageManager.copyImageFromURL(sourceURL) {
                            let imageMarkdown = self.imageManager.generateImageMarkdown(fileName: fileName)
                            self.insertTextAtCursor(imageMarkdown + "\n\n")
                        }
                    }
                }
                return true
            }
        }
        return false
    }
    
    private func insertTextAtCursor(_ text: String) {
        if markdownText.isEmpty {
            markdownText = text
        } else {
            markdownText += "\n" + text
        }
    }
}


// MARK: - 元数据行

struct MetadataRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - 地图视图

struct NodeMapView: View {
    let node: Node
    @EnvironmentObject private var store: NodeStore
    
    // 从store中获取最新的节点数据
    private var currentNode: Node {
        return store.nodes.first { $0.id == node.id } ?? node
    }
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var cameraPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    )
    
    // 检查是否是地图/位置标签
    private func isLocationTag(_ tag: Tag) -> Bool {
        if case .custom(let key) = tag.type {
            let locationKeys = ["loc", "location", "地点", "位置"]
            return locationKeys.contains(key.lowercased())
        }
        return false
    }
    
    private var locationTags: [Tag] {
        var allLocationTags: [Tag] = []
        
        // 添加当前节点的地图标签
        let currentNodeLocationTags = currentNode.locationTags
        allLocationTags.append(contentsOf: currentNodeLocationTags)
        
        print("🔍 DetailPanel调试:")
        print("🔍 节点: \(currentNode.text)")
        print("🔍 是否复合节点: \(currentNode.isCompound)")
        print("🔍 当前节点地图标签数量: \(currentNodeLocationTags.count)")
        
        // 如果是复合节点，收集所有子节点的地图标签
        if currentNode.isCompound {
            // 获取子节点引用标签
            let childReferenceTags = currentNode.tags.filter {
                if case .custom(let key) = $0.type {
                    return key == "child"
                }
                return false
            }
            
            print("🔍 复合节点子节点引用: \(childReferenceTags.count)个")
            
            for childRefTag in childReferenceTags {
                let childNodeName = childRefTag.value
                print("🔍 查找子节点: \(childNodeName)")
                
                // 从store中查找实际的子节点
                if let childNode = store.nodes.first(where: { $0.text.lowercased() == childNodeName.lowercased() }) {
                    let childLocationTags = childNode.locationTags
                    allLocationTags.append(contentsOf: childLocationTags)
                    
                    print("🔍 子节点 '\(childNode.text)' 地图标签数量: \(childLocationTags.count)")
                    for tag in childLocationTags {
                        print("🔍   地图标签: \(tag.value), 坐标: \(tag.latitude ?? 0),\(tag.longitude ?? 0)")
                    }
                } else {
                    print("⚠️ 子节点 '\(childNodeName)' 未找到")
                }
            }
        }
        
        print("🔍 总地图标签数量: \(allLocationTags.count)")
        return allLocationTags
    }
    
    var body: some View {
        Group {
            if locationTags.isEmpty {
                // 检查是否有location类型但没有坐标的标签
                let locationTagsWithoutCoords = currentNode.tags.filter { isLocationTag($0) && !$0.hasCoordinates }
                
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    
                    if locationTagsWithoutCoords.isEmpty {
                        Text("该节点暂无地点标签")
                            .font(.body)
                            .foregroundColor(.secondary)
                        Text("添加地点标签来在地图上显示相关位置")
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("该节点有地点标签但缺少坐标信息")
                            .font(.body)
                            .foregroundColor(.secondary)
                        Text("现有地点标签: \(locationTagsWithoutCoords.map { $0.value }.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(Color.blue)
                            .multilineTextAlignment(.center)
                        
                        VStack(spacing: 8) {
                            Text("请使用以下格式添加坐标信息：")
                                .font(.caption)
                                .foregroundColor(Color.secondary)
                            
                            // 生成示例命令
                            let exampleCommands = locationTagsWithoutCoords.map { tag in
                                "loc @39.9042,116.4074[\(tag.value)]"
                            }
                            
                            ForEach(exampleCommands, id: \.self) { command in
                                Text(command)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.blue.opacity(0.1))
                                    )
                                    .onTapGesture {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(command, forType: .string)
                                    }
                            }
                            
                            Text("点击上方命令可复制到剪贴板")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Button("打开节点编辑") {
                            // 触发编辑界面
                            NotificationCenter.default.post(
                                name: NSNotification.Name("editNode"),
                                object: node
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Map(position: $cameraPosition) {
                    ForEach(Array(locationTags.enumerated()), id: \.0) { _, tag in
                        Annotation(
                            tag.value,
                            coordinate: CLLocationCoordinate2D(
                                latitude: tag.latitude!,
                                longitude: tag.longitude!
                            ),
                            anchor: .center
                        ) {
                            MapPinView(tag: tag)
                        }
                    }
                }
                .mapStyle(.standard)
                .onAppear {
                    if !locationTags.isEmpty {
                        // 如果只有一个地点，居中显示
                        if locationTags.count == 1 {
                            let tag = locationTags.first!
                            let newRegion = MKCoordinateRegion(
                                center: CLLocationCoordinate2D(
                                    latitude: tag.latitude!,
                                    longitude: tag.longitude!
                                ),
                                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                            )
                            region = newRegion
                            cameraPosition = .region(newRegion)
                        } else {
                            // 如果有多个地点，计算包含所有地点的区域
                            let latitudes = locationTags.compactMap { $0.latitude }
                            let longitudes = locationTags.compactMap { $0.longitude }
                            
                            let minLat = latitudes.min()!
                            let maxLat = latitudes.max()!
                            let minLon = longitudes.min()!
                            let maxLon = longitudes.max()!
                            
                            let centerLat = (minLat + maxLat) / 2
                            let centerLon = (minLon + maxLon) / 2
                            
                            // 添加一些边距
                            let latDelta = max(0.01, (maxLat - minLat) * 1.3)
                            let lonDelta = max(0.01, (maxLon - minLon) * 1.3)
                            
                            let newRegion = MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                                span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
                            )
                            region = newRegion
                            cameraPosition = .region(newRegion)
                            
                            print("🗺️ 显示多个地点，中心: (\(centerLat), \(centerLon)), 范围: (\(latDelta), \(lonDelta))")
                        }
                    }
                }
            }
        }
    }
}

struct MapPinView: View {
    let tag: Tag
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 24, height: 24)
                
                Image(systemName: "location.fill")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            
            Text(tag.value)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.9))
                        .shadow(radius: 2)
                )
        }
    }
}

// MARK: - 全局ID生成器
class GraphNodeIDGenerator {
    static let shared = GraphNodeIDGenerator()
    private var currentID: Int = 1000000 // 从一个大数开始避免冲突
    private var tagIDMap: [String: Int] = [:] // 缓存标签的ID
    private let lock = NSLock()
    
    private init() {}
    
    func nextID() -> Int {
        lock.lock()
        defer { lock.unlock() }
        currentID += 1
        return currentID
    }
    
    // 为标签生成确定性ID
    func idForTag(_ tag: Tag) -> Int {
        let tagKey = "\(tag.type.rawValue):\(tag.value)"
        lock.lock()
        defer { lock.unlock() }
        
        if let existingID = tagIDMap[tagKey] {
            return existingID
        }
        
        currentID += 1
        tagIDMap[tagKey] = currentID
        return currentID
    }
}

// MARK: - 节点图谱节点数据模型

struct NodeGraphNode: UniversalGraphNode {
    let id: Int
    let label: String
    let subtitle: String?
    let node: Node?
    let tag: Tag?
    let nodeType: NodeType
    let isCenter: Bool
    
    enum NodeType {
        case node
        case tag(Tag.TagType)
    }
    
    init(node: Node, isCenter: Bool = false) {
        // 使用全局ID生成器确保绝对唯一
        self.id = GraphNodeIDGenerator.shared.nextID()
        self.label = node.text
        self.subtitle = node.meaning
        self.node = node
        self.tag = nil
        self.nodeType = .node
        self.isCenter = isCenter
    }
    
    init(tag: Tag) {
        // 使用确定性ID确保相同标签总是有相同ID
        self.id = GraphNodeIDGenerator.shared.idForTag(tag)
        self.label = tag.value
        self.subtitle = tag.type.displayName
        self.node = nil
        self.tag = tag
        self.nodeType = .tag(tag.type)
        self.isCenter = false
    }
}

struct NodeGraphEdge: UniversalGraphEdge {
    let fromId: Int
    let toId: Int
    let label: String?
    
    init(from: NodeGraphNode, to: NodeGraphNode, relationshipType: String) {
        self.fromId = from.id
        self.toId = to.id
        self.label = relationshipType
    }
}

// MARK: - 全局图谱数据缓存管理器
class NodeGraphDataCache: ObservableObject {
    static let shared = NodeGraphDataCache()
    
    private var cache: [UUID: (nodes: [NodeGraphNode], edges: [NodeGraphEdge])] = [:]
    
    private init() {
        // 监听节点变化以清除相关缓存
        NotificationCenter.default.addObserver(
            forName: Notification.Name("nodeUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let nodeId = notification.userInfo?["nodeId"] as? UUID {
                self?.invalidateCache(for: nodeId)
                print("🗑️ 清除节点图谱缓存: \(nodeId)")
            }
        }
    }
    
    // 清除特定节点的缓存
    func invalidateCache(for nodeId: UUID) {
        cache.removeValue(forKey: nodeId)
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    // 清除所有缓存
    func clearAllCache() {
        cache.removeAll()
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
        print("🗑️ 清除所有图谱缓存")
    }
    
    @MainActor
    func getCachedGraphData(for node: Node) -> (nodes: [NodeGraphNode], edges: [NodeGraphEdge]) {
        // 检查缓存
        if let cached = cache[node.id] {
            #if DEBUG
            @AppStorage("enableGraphDebug") var enableGraphDebug: Bool = false
            if enableGraphDebug {
                print("📋 使用缓存的图谱数据: \(node.text)")
            }
            #endif
            return cached
        }
        
        // 计算新的图谱数据
        let graphData = calculateGraphData(for: node)
        cache[node.id] = graphData
        
        #if DEBUG
        @AppStorage("enableGraphDebug") var enableGraphDebug: Bool = false
        if enableGraphDebug {
            print("📊 计算新的图谱数据: \(node.text)")
        }
        #endif
        
        return graphData
    }
    
    @MainActor
    private func calculateGraphData(for node: Node) -> (nodes: [NodeGraphNode], edges: [NodeGraphEdge]) {
        let nodes = calculateGraphNodes(for: node)
        var edges: [NodeGraphEdge] = []
        let centerNode = nodes.first { $0.isCenter }!
        
        // 建立层次化连接：高级复合节点 → 低级复合节点 → 节点 → 标签
        if node.isCompound {
            // 分组节点和标签
            let nodeGraphNodes = nodes.filter { !$0.isCenter && $0.node != nil }
            let tagGraphNodes = nodes.filter { !$0.isCenter && $0.tag != nil }
            
            // 第一层：中心节点连接到直接子节点
            let directChildNodes = getDirectChildNodes(of: node, in: nodeGraphNodes)
            for childNode in directChildNodes {
                edges.append(NodeGraphEdge(
                    from: centerNode,
                    to: childNode,
                    relationshipType: "子节点"
                ))
                print("🔗 连接: \(centerNode.label) → \(childNode.label) (子节点)")
            }
            
            // 后续层：处理每个子节点的连接
            for childNodeGraph in nodeGraphNodes {
                guard let childNode = childNodeGraph.node else { continue }
                
                if childNode.isCompound {
                    // 如果子节点也是复合节点，连接到它的子节点
                    let grandChildNodes = getDirectChildNodes(of: childNode, in: nodeGraphNodes)
                    for grandChildNode in grandChildNodes {
                        edges.append(NodeGraphEdge(
                            from: childNodeGraph,
                            to: grandChildNode,
                            relationshipType: "子节点"
                        ))
                        print("🔗 连接: \(childNodeGraph.label) → \(grandChildNode.label) (子节点)")
                    }
                }
                
                // 连接到这个节点的直接标签
                let nodeOwnedTags = getDirectTagsOf(childNode, in: tagGraphNodes)
                for tagGraph in nodeOwnedTags {
                    edges.append(NodeGraphEdge(
                        from: childNodeGraph,
                        to: tagGraph,
                        relationshipType: tagGraph.tag?.type.displayName ?? "标签"
                    ))
                    print("🔗 连接: \(childNodeGraph.label) → \(tagGraph.label) (\(tagGraph.tag?.type.displayName ?? "标签"))")
                }
            }
            
            // 处理中心节点自身的标签
            let centerOwnedTags = getDirectTagsOf(node, in: tagGraphNodes)
            for tagGraph in centerOwnedTags {
                edges.append(NodeGraphEdge(
                    from: centerNode,
                    to: tagGraph,
                    relationshipType: tagGraph.tag?.type.displayName ?? "标签"
                ))
                print("🔗 连接: \(centerNode.label) → \(tagGraph.label) (\(tagGraph.tag?.type.displayName ?? "标签"))")
            }
            
        } else {
            // 普通节点：直接连接到所有标签
            for graphNode in nodes where !graphNode.isCenter {
                if let tag = graphNode.tag {
                    edges.append(NodeGraphEdge(
                        from: centerNode,
                        to: graphNode,
                        relationshipType: tag.type.displayName
                    ))
                }
            }
        }
        
        return (nodes: nodes, edges: edges)
    }
    
    // 获取节点的直接子节点（不包括间接子节点）
    @MainActor
    private func getDirectChildNodes(of parentNode: Node, in allNodeGraphNodes: [NodeGraphNode]) -> [NodeGraphNode] {
        let childReferenceTags = parentNode.tags.filter {
            if case .custom(let key) = $0.type, key == "child" {
                return true
            }
            return false
        }
        
        var directChildren: [NodeGraphNode] = []
        for childRefTag in childReferenceTags {
            let childNodeName = childRefTag.value
            if let childNodeGraph = allNodeGraphNodes.first(where: {
                $0.node?.text.lowercased() == childNodeName.lowercased()
            }) {
                directChildren.append(childNodeGraph)
            }
        }
        
        return directChildren
    }
    
    // 获取节点的直接标签（不包括从子节点继承的标签）
    @MainActor
    private func getDirectTagsOf(_ node: Node, in allTagGraphNodes: [NodeGraphNode]) -> [NodeGraphNode] {
        var directTags: [NodeGraphNode] = []
        
        // 添加节点的直接标签（跳过管理标签）
        for tag in node.tags {
            if case .custom(let key) = tag.type, (key == "compound" || key == "child") {
                continue
            }
            
            if let tagGraph = allTagGraphNodes.first(where: { tagGraphNode in
                if let graphTag = tagGraphNode.tag {
                    return graphTag.type == tag.type && graphTag.value == tag.value
                }
                return false
            }) {
                directTags.append(tagGraph)
            }
        }
        
        // 添加位置标签
        for locationTag in node.locationTags {
            if let tagGraph = allTagGraphNodes.first(where: { tagGraphNode in
                if let graphTag = tagGraphNode.tag {
                    return graphTag.type == locationTag.type && graphTag.value == locationTag.value
                }
                return false
            }) {
                directTags.append(tagGraph)
            }
        }
        
        return directTags
    }
    
    // 帮助方法：查找标签属于哪个子节点
    @MainActor
    private func findTagOwner(tag: Tag, inChildNodes childNodes: [NodeGraphNode]) -> NodeGraphNode? {
        for childNode in childNodes {
            if let actualNode = childNode.node {
                // 检查标签是否属于这个子节点
                if actualNode.tags.contains(where: { $0.type == tag.type && $0.value == tag.value }) ||
                   actualNode.locationTags.contains(where: { $0.type == tag.type && $0.value == tag.value }) {
                    return childNode
                }
            }
        }
        return nil
    }
    
    @MainActor
    private func calculateGraphNodes(for node: Node) -> [NodeGraphNode] {
        var nodes: [NodeGraphNode] = []
        var addedTagKeys: Set<String> = []
        var addedChildNodes: Set<String> = []
        
        // 添加中心节点（当前节点）
        nodes.append(NodeGraphNode(node: node, isCenter: true))
        
        // 如果是复合节点，处理子节点引用，但保持层次结构
        if node.isCompound {
            // 查找子节点引用标签
            let childReferenceTags = node.tags.filter {
                if case .custom(let key) = $0.type {
                    return key == "child"
                }
                return false
            }
            
            // 为每个子节点引用查找实际的子节点并添加
            for childRefTag in childReferenceTags {
                let childNodeName = childRefTag.value
                if !addedChildNodes.contains(childNodeName) {
                    // 从store中查找实际的子节点
                    if let actualChildNode = NodeStore.shared.nodes.first(where: { $0.text.lowercased() == childNodeName.lowercased() }) {
                        // 添加子节点本身
                        nodes.append(NodeGraphNode(node: actualChildNode, isCenter: false))
                        addedChildNodes.insert(childNodeName)
                        print("🔗 图谱中添加子节点: \(actualChildNode.text), 是否为复合节点: \(actualChildNode.isCompound)")
                        
                        // 递归添加子节点的结构，但保持层次关系
                        var visitedNodes: Set<String> = []
                        addChildNodeStructure(for: actualChildNode, addedTagKeys: &addedTagKeys, addedChildNodes: &addedChildNodes, nodes: &nodes, depth: 1, visitedNodes: &visitedNodes)
                    }
                }
            }
        }
        
        // 添加当前节点的直接标签（非复合节点管理标签）
        for tag in node.tags {
            let tagKey = "\(tag.type.rawValue):\(tag.value)"
            
            // 跳过子节点引用标签和复合节点标签，因为我们已经添加了实际的子节点
            if case .custom(let key) = tag.type {
                if key == "child" || key == "compound" {
                    continue
                }
            }
            
            if !addedTagKeys.contains(tagKey) {
                nodes.append(NodeGraphNode(tag: tag))
                addedTagKeys.insert(tagKey)
            }
        }
        
        // 添加当前节点的位置标签
        for locationTag in node.locationTags {
            let tagKey = "\(locationTag.type.rawValue):\(locationTag.value)"
            if !addedTagKeys.contains(tagKey) {
                nodes.append(NodeGraphNode(tag: locationTag))
                addedTagKeys.insert(tagKey)
            }
        }
        
        return nodes
    }
    
    // 新方法：递归添加子节点结构，保持层次关系
    @MainActor
    private func addChildNodeStructure(for node: Node, addedTagKeys: inout Set<String>, addedChildNodes: inout Set<String>, nodes: inout [NodeGraphNode], depth: Int, visitedNodes: inout Set<String>) {
        // 防止无限递归和循环引用
        guard depth <= 10 else { return }
        if visitedNodes.contains(node.text.lowercased()) { return }
        visitedNodes.insert(node.text.lowercased())
        
        let indentPrefix = String(repeating: "  ", count: depth)
        print("\(indentPrefix)🏗️ 添加子节点结构: \(node.text) (深度: \(depth))")
        
        // 如果这个节点是复合节点，添加它的直接子节点
        if node.isCompound {
            let childReferenceTags = node.tags.filter {
                if case .custom(let key) = $0.type, key == "child" {
                    return true
                }
                return false
            }
            
            for childRefTag in childReferenceTags {
                let childNodeName = childRefTag.value
                if !addedChildNodes.contains(childNodeName) {
                    if let childNode = NodeStore.shared.nodes.first(where: { $0.text.lowercased() == childNodeName.lowercased() }) {
                        // 添加子节点
                        nodes.append(NodeGraphNode(node: childNode, isCenter: false))
                        addedChildNodes.insert(childNodeName)
                        print("\(indentPrefix)  ↳ 添加子节点: \(childNode.text)")
                        
                        // 递归添加更深层的子节点结构
                        addChildNodeStructure(for: childNode, addedTagKeys: &addedTagKeys, addedChildNodes: &addedChildNodes, nodes: &nodes, depth: depth + 1, visitedNodes: &visitedNodes)
                    }
                }
            }
        }
        
        // 添加当前节点的直接标签（不是子节点引用或复合节点标签）
        for tag in node.tags {
            if case .custom(let key) = tag.type, (key == "compound" || key == "child") {
                continue // 跳过管理标签
            }
            
            let tagKey = "\(tag.type.rawValue):\(tag.value)"
            if !addedTagKeys.contains(tagKey) {
                nodes.append(NodeGraphNode(tag: tag))
                addedTagKeys.insert(tagKey)
                print("\(indentPrefix)  ↳ 添加标签: \(tag.type.displayName) - \(tag.value)")
            }
        }
        
        // 添加位置标签
        for locationTag in node.locationTags {
            let locationTagKey = "\(locationTag.type.rawValue):\(locationTag.value)"
            if !addedTagKeys.contains(locationTagKey) {
                nodes.append(NodeGraphNode(tag: locationTag))
                addedTagKeys.insert(locationTagKey)
                print("\(indentPrefix)  ↳ 添加位置标签: \(locationTag.type.displayName) - \(locationTag.value)")
            }
        }
        
        visitedNodes.remove(node.text.lowercased())
    }
    
    // 递归添加节点的所有标签，包括多级复合节点的标签
    @MainActor
    private func addTagsRecursively(for node: Node, addedTagKeys: inout Set<String>, nodes: inout [NodeGraphNode], depth: Int, visitedNodes: inout Set<String>) {
        // 防止无限递归，设置最大深度限制和循环检测
        guard depth <= 10 else {
            print("⚠️ 递归深度超过限制，停止处理节点: \(node.text)")
            return
        }
        
        // 防止循环引用
        if visitedNodes.contains(node.text.lowercased()) {
            print("⚠️ 检测到循环引用，跳过节点: \(node.text)")
            return
        }
        visitedNodes.insert(node.text.lowercased())
        
        let indentPrefix = String(repeating: "  ", count: depth)
        print("\(indentPrefix)🔄 递归处理节点: \(node.text) (深度: \(depth))")
        
        // 添加当前节点的直接标签（过滤掉内部管理标签）
        for tag in node.tags {
            // 过滤掉复合节点内部标签
            if case .custom(let key) = tag.type, (key == "compound" || key == "child") {
                continue
            }
            
            let tagKey = "\(tag.type.rawValue):\(tag.value)"
            if !addedTagKeys.contains(tagKey) {
                nodes.append(NodeGraphNode(tag: tag))
                addedTagKeys.insert(tagKey)
                print("\(indentPrefix)  ↳ 添加标签: \(tag.type.displayName) - \(tag.value)")
            }
        }
        
        // 添加当前节点的位置标签
        for locationTag in node.locationTags {
            let locationTagKey = "\(locationTag.type.rawValue):\(locationTag.value)"
            if !addedTagKeys.contains(locationTagKey) {
                nodes.append(NodeGraphNode(tag: locationTag))
                addedTagKeys.insert(locationTagKey)
                print("\(indentPrefix)  ↳ 添加位置标签: \(locationTag.type.displayName) - \(locationTag.value)")
            }
        }
        
        // 如果当前节点是复合节点，递归处理它的子节点
        if node.isCompound {
            let childReferenceTags = node.tags.filter {
                if case .custom(let key) = $0.type, key == "child" {
                    return true
                }
                return false
            }
            
            for childRefTag in childReferenceTags {
                let childNodeName = childRefTag.value
                if let childNode = NodeStore.shared.nodes.first(where: { $0.text.lowercased() == childNodeName.lowercased() }) {
                    print("\(indentPrefix)🔗 发现子节点: \(childNode.text)")
                    // 递归处理子节点
                    addTagsRecursively(for: childNode, addedTagKeys: &addedTagKeys, nodes: &nodes, depth: depth + 1, visitedNodes: &visitedNodes)
                }
            }
        }
        
        // 递归完成后，从访问列表中移除当前节点，允许在其他分支中再次访问
        visitedNodes.remove(node.text.lowercased())
    }
    
    func clearCache() {
        cache.removeAll()
    }
}

// MARK: - 节点关系图谱视图

struct NodeGraphView: View {
    let node: Node
    @EnvironmentObject private var store: NodeStore
    @AppStorage("detailGraphInitialScale") private var detailGraphInitialScale: Double = 1.0
    @StateObject private var graphCache = NodeGraphDataCache.shared
    @State private var showingFullscreenGraph = false
    
    // 从store中获取最新的节点数据
    private var currentNode: Node {
        return store.nodes.first { $0.id == node.id } ?? node
    }
    
    var body: some View {
        // 使用全局缓存获取图谱数据，避免重复计算
        let graphData = graphCache.getCachedGraphData(for: currentNode)
        
        VStack {
            // 直接显示图谱内容，无标题栏
            if graphData.nodes.count <= 1 {
                EmptyGraphView()
            } else {
                UniversalRelationshipGraphView(
                    nodes: graphData.nodes,
                    edges: graphData.edges,
                    title: "节点详情图谱",
                    initialScale: detailGraphInitialScale,
                    onNodeSelected: { nodeId in
                        // 当点击节点时，选择对应的节点（只有节点才会触发选择）
                        if let selectedNode = graphData.nodes.first(where: { $0.id == nodeId }),
                           let selectedTargetNode = selectedNode.node {
                            store.selectNode(selectedTargetNode)
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contextMenu {
                    Button("全屏显示 (⌘L) - 已禁用") {
                        Swift.print("🖥️ 右键菜单: 全屏功能已禁用用于调试")
                        // 禁用全屏功能来测试崩溃
                    }
                }
            }
        }
        .focusable()
        .onKeyPress(.init("l"), phases: .down) { keyPress in
            if keyPress.modifiers == .command {
                Swift.print("🎯 Command+L 检测到，开始处理...")
                let windowManager = FullscreenGraphWindowManager.shared
                
                // 检查是否已经有全屏图谱窗口打开
                if windowManager.isWindowActive() {
                    Swift.print("📝 NodeGraphView: Command+L - 关闭现有全屏图谱窗口")
                    windowManager.hideFullscreenGraph()
                } else {
                    Swift.print("📝 NodeGraphView: Command+L - 打开全屏图谱窗口")
                    Swift.print("🎯 当前节点: \(currentNode.text)")
                    Swift.print("🎯 图谱数据: \(graphData.nodes.count)个节点, \(graphData.edges.count)条边")
                    
                    windowManager.showFullscreenGraph(node: currentNode, graphData: graphData)
                    
                    // 通过通知打开窗口
                    NotificationCenter.default.post(
                        name: NSNotification.Name("requestOpenFullscreenGraph"),
                        object: nil
                    )
                    
                    Swift.print("🎯 通知已发送，等待窗口打开...")
                }
                
                return .handled
            }
            return .ignored
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FullscreenGraphClosed"))) { _ in
            print("📝 通知: 收到 FullscreenGraphClosed 通知")
            showingFullscreenGraph = false
            print("📝 通知: showingFullscreenGraph 设置为 false")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("requestOpenFullscreenGraphFromDetail"))) { notification in
            if let node = notification.object as? Node,
               node.id == currentNode.id {
                print("📝 NodeGraphView: 收到Command+L触发的全屏图谱请求")
                
                let windowManager = FullscreenGraphWindowManager.shared
                if !windowManager.isWindowActive() {
                    print("📝 NodeGraphView: 打开全屏图谱")
                    let graphData = graphCache.getCachedGraphData(for: currentNode)
                    
                    windowManager.showFullscreenGraph(node: currentNode, graphData: graphData)
                    
                    // 通过通知打开窗口
                    NotificationCenter.default.post(
                        name: NSNotification.Name("requestOpenFullscreenGraph"),
                        object: nil
                    )
                }
            }
        }
    }
}

// MARK: - SwiftUI原生全屏图谱管理器
class FullscreenGraphWindowManager: ObservableObject {
    static let shared = FullscreenGraphWindowManager()
    
    @Published var showingFullscreenGraph = false
    @Published var currentGraphNode: Node?
    @Published var currentGraphData: (nodes: [NodeGraphNode], edges: [NodeGraphEdge])?
    
    private init() {
        Swift.print("📝 SwiftUI FullscreenGraphWindowManager 初始化")
    }
    
    func showFullscreenGraph(node: Node, graphData: (nodes: [NodeGraphNode], edges: [NodeGraphEdge])) {
        Swift.print("🔍 显示SwiftUI全屏图谱")
        Swift.print("🔍 节点: \(node.text), 数据: \(graphData.nodes.count)个节点, \(graphData.edges.count)条边")
        
        // 确保数据设置在主线程
        DispatchQueue.main.async {
            self.currentGraphNode = node
            self.currentGraphData = graphData
            self.showingFullscreenGraph = true
            
            Swift.print("🔍 数据已设置: currentGraphNode=\(self.currentGraphNode?.text ?? "nil"), showingFullscreenGraph=\(self.showingFullscreenGraph)")
            
            // 发送打开窗口通知
            NotificationCenter.default.post(
                name: NSNotification.Name("openFullscreenGraph"),
                object: nil
            )
            
            // 延迟确保窗口激活
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.activateFullscreenWindow()
            }
        }
    }
    
    func activateFullscreenWindow() {
        Swift.print("🔍 开始查找全屏图谱窗口...")
        Swift.print("🔍 当前活动窗口总数: \(NSApp.windows.count)")
        
        for (index, window) in NSApp.windows.enumerated() {
            Swift.print("🔍 窗口 \(index): 标题=\(window.title), 类型=\(String(describing: type(of: window)))")
            Swift.print("🔍 窗口 \(index): isKeyWindow=\(window.isKeyWindow), isMainWindow=\(window.isMainWindow)")
        }
        
        // 查找全屏图谱窗口并激活
        for window in NSApp.windows {
            if window.title == "全屏图谱" || window.title.contains("图谱") {
                Swift.print("🎯 找到全屏图谱窗口 (标题匹配)，激活中...")
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()  // 强制置前
                NSApp.activate(ignoringOtherApps: true)
                
                // 确保窗口真正获得焦点
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    window.makeKey()
                    Swift.print("🎯 窗口焦点设置完成: isKeyWindow=\(window.isKeyWindow)")
                }
                return
            }
        }
        
        // 如果通过标题未找到，尝试通过内容查找
        for window in NSApp.windows {
            if let contentView = window.contentView,
               String(describing: type(of: contentView)).contains("FullscreenGraphView") ||
               String(describing: type(of: contentView)).contains("NSSplitView") { // WindowGroup 创建的窗口
                Swift.print("🎯 通过内容找到全屏图谱窗口，激活中...")
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()  // 强制置前
                NSApp.activate(ignoringOtherApps: true)
                
                // 确保窗口真正获得焦点
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    window.makeKey()
                    Swift.print("🎯 窗口焦点设置完成: isKeyWindow=\(window.isKeyWindow)")
                }
                return
            }
        }
        
        Swift.print("❌ 未找到全屏图谱窗口")
    }
    
    func hideFullscreenGraph() {
        Swift.print("⚡️ 隐藏SwiftUI全屏图谱")
        showingFullscreenGraph = false
        currentGraphNode = nil
        currentGraphData = nil
        
        // 查找并关闭全屏图谱窗口
        for window in NSApp.windows {
            if window.title == "全屏图谱" {
                Swift.print("🚪 找到全屏图谱窗口，关闭中...")
                window.close()
                break
            }
        }
        
        NotificationCenter.default.post(name: NSNotification.Name("FullscreenGraphClosed"), object: nil)
    }
    
    func isWindowActive() -> Bool {
        Swift.print("🔍 检查全屏图谱窗口是否活动...")
        
        // 检查实际窗口是否存在
        let hasActiveWindow = NSApp.windows.contains { window in
            Swift.print("🔍 检查窗口: 标题=\(window.title), 可见=\(window.isVisible), isKey=\(window.isKeyWindow)")
            return (window.title == "全屏图谱" || window.title.contains("图谱")) && window.isVisible
        }
        
        Swift.print("🔍 检查结果: hasActiveWindow=\(hasActiveWindow), showingFullscreenGraph=\(showingFullscreenGraph)")
        
        // 如果窗口不存在但状态为true，修正状态
        if showingFullscreenGraph && !hasActiveWindow {
            Swift.print("🔧 修正状态：窗口已关闭但状态未更新")
            showingFullscreenGraph = false
        }
        
        Swift.print("🔍 窗口状态检查: showingFullscreenGraph=\(showingFullscreenGraph), hasActiveWindow=\(hasActiveWindow)")
        return hasActiveWindow
    }
}

// MARK: - SwiftUI全屏图谱视图
struct FullscreenGraphView: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var windowManager = FullscreenGraphWindowManager.shared
    @Environment(\.dismissWindow) private var dismissWindow
    @FocusState private var isFocused: Bool
    @AppStorage("fullscreenGraphInitialScale") private var fullscreenGraphInitialScale: Double = 1.0
    
    var body: some View {
        let _ = Swift.print("🔎 FullscreenGraphView.body 开始渲染...")
        let _ = Swift.print("🔎 windowManager.currentGraphNode: \(windowManager.currentGraphNode?.text ?? "nil")")
        let _ = Swift.print("🔎 windowManager.currentGraphData: \(windowManager.currentGraphData?.nodes.count ?? -1)个节点")
        
        return VStack(spacing: 0) {
            if let node = windowManager.currentGraphNode,
               let graphData = windowManager.currentGraphData {
                
                let _ = Swift.print("✅ FullscreenGraphView: 有数据，开始渲染图谱")
                
                
                // 顶部标题栏
                VStack(spacing: 4) {
                    HStack {
                        Text("全屏图谱: \(node.text)")
                            .font(.title)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Button(action: closeWindow) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("关闭 (ESC 或 Command+L)")
                    }
                    
                    Text("复合节点层级图谱 • 按 ESC 或 Command+L 关闭")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .background(Color(.windowBackgroundColor).opacity(0.8))
                
                Divider()
                
                // 实际的图谱内容 - 完整的复合节点层级结构
                UniversalRelationshipGraphView(
                    nodes: graphData.nodes,
                    edges: graphData.edges,
                    title: "复合节点全屏图谱",
                    initialScale: fullscreenGraphInitialScale,
                    onNodeSelected: { nodeId in
                        // 在全屏图谱中点击节点时，选择对应的节点
                        if let selectedNode = graphData.nodes.first(where: { $0.id == nodeId }),
                           let selectedTargetNode = selectedNode.node {
                            store.selectNode(selectedTargetNode)
                            Swift.print("🎯 全屏图谱: 选中节点 \(selectedTargetNode.text)")
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else {
                // 加载状态
                let _ = Swift.print("❌ FullscreenGraphView: 无数据，显示加载界面")
                let _ = Swift.print("❌ 详细状态: node=\(windowManager.currentGraphNode?.text ?? "nil"), data=\(windowManager.currentGraphData?.nodes.count ?? -1)")
                
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    
                    Text("正在加载复合节点图谱...")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("复合节点将按层级从中心向外辐射显示")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    // 调试按钮
                    Button("手动刷新数据") {
                        Swift.print("🔄 手动刷新: showingFullscreenGraph=\(windowManager.showingFullscreenGraph)")
                        DispatchQueue.main.async {
                            windowManager.objectWillChange.send()
                        }
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.windowBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .focused($isFocused)  // 使用 @FocusState
        .onKeyPress(.escape) {
            Swift.print("🎯 FullscreenGraphView: ESC键按下，关闭窗口")
            closeWindow()
            return .handled
        }
        .onKeyPress(.init("l"), phases: .down) { keyPress in
            Swift.print("🎯 FullscreenGraphView: L键按下，修饰符: \(keyPress.modifiers)")
            if keyPress.modifiers == .command {
                Swift.print("🎯 FullscreenGraphView: Command+L检测到，关闭窗口")
                closeWindow()
                return .handled
            }
            return .ignored
        }
        .onAppear {
            Swift.print("🖥️ 全屏图谱视图已显示")
            
            // 立即设置 SwiftUI 焦点
            isFocused = true
            Swift.print("🎯 SwiftUI 焦点已设置: isFocused=\(isFocused)")
            
            // 显示图谱结构信息
            if let graphData = windowManager.currentGraphData {
                Swift.print("📊 全屏图谱数据: \(graphData.nodes.count)个节点, \(graphData.edges.count)条边")
                
                // 打印层级结构信息
                let centerNodes = graphData.nodes.filter { $0.isCenter }
                let compoundNodes = graphData.nodes.filter { !$0.isCenter && $0.node?.isCompound == true }
                let regularNodes = graphData.nodes.filter { !$0.isCenter && $0.node?.isCompound == false && $0.node != nil }
                let tagNodes = graphData.nodes.filter { $0.tag != nil }
                
                Swift.print("🏗️ 复合节点结构:")
                Swift.print("  - 中心节点: \(centerNodes.count)个")
                Swift.print("  - 复合子节点: \(compoundNodes.count)个")
                Swift.print("  - 普通节点: \(regularNodes.count)个")
                Swift.print("  - 标签节点: \(tagNodes.count)个")
            }
            
            // 确保窗口获得键盘焦点（多重保障）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Swift.print("🎯 第一次尝试激活全屏图谱窗口...")
                isFocused = true  // 再次设置 SwiftUI 焦点
                FullscreenGraphWindowManager.shared.activateFullscreenWindow()
            }
            
            // 添加额外的焦点设置延迟
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Swift.print("🎯 第二次尝试激活全屏图谱窗口...")
                isFocused = true  // 第三次设置 SwiftUI 焦点
                FullscreenGraphWindowManager.shared.activateFullscreenWindow()
            }
        }
        .onDisappear {
            Swift.print("🖥️ 全屏图谱视图已关闭")
            // 确保状态被正确重置
            windowManager.showingFullscreenGraph = false
            windowManager.currentGraphNode = nil
            windowManager.currentGraphData = nil
        }
    }
    
    private func closeWindow() {
        Swift.print("🚪 关闭全屏图谱窗口")
        windowManager.hideFullscreenGraph()
        dismissWindow(id: "fullscreenGraph")
    }
}

// MARK: - 生命周期追踪器
class ViewLifecycleTracker: ObservableObject {
    let name: String
    
    init(name: String) {
        self.name = name
        Swift.print("📝 🟢 \(name) 创建")
    }
    
    deinit {
        Swift.print("📝 🔴 \(name) 销毁")
    }
}

// MARK: - 编辑节点表单

struct EditNodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: NodeStore
    
    let node: Node
    @State private var text: String
    @State private var phonetic: String
    @State private var meaning: String
    
    init(node: Node) {
        self.node = node
        self._text = State(initialValue: node.text)
        self._phonetic = State(initialValue: node.phonetic ?? "")
        self._meaning = State(initialValue: node.meaning ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("节点信息") {
                    TextField("节点", text: $text)
                    TextField("音标（可选）", text: $phonetic)
                    TextField("含义（可选）", text: $meaning, axis: .vertical)
                        .lineLimit(3)
                }
            }
            .navigationTitle("编辑节点")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.updateNode(
                            node.id,
                            text: text.isEmpty ? nil : text,
                            phonetic: phonetic.isEmpty ? nil : phonetic,
                            meaning: meaning.isEmpty ? nil : meaning
                        )
                        dismiss()
                    }
                    .disabled(text.isEmpty)
                }
            }
        }
        .frame(width: 400, height: 300)
    }
}



// MARK: - 代码块视图

struct CodeBlockView: View {
    let code: String
    let language: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 代码块头部
            HStack {
                Text(language.isEmpty ? "代码" : language.uppercased())
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: copyToClipboard) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("复制代码")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            // 代码内容
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.title3, design: .monospaced))  // 更大
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }
}

// MARK: - Mermaid图表视图

struct MermaidView: View {
    let diagram: String
    @State private var isExpanded = true  // 默认展开显示代码
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mermaid头部
            HStack {
                Image(systemName: getIconName())
                    .foregroundColor(.blue)
                Text("\(getMermaidDescription()) - Mermaid图表")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: copyToClipboard) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("复制代码")
                    
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help(isExpanded ? "收起代码" : "展开代码")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            
            if isExpanded {
                // 显示图表预览信息和代码
                VStack(alignment: .leading, spacing: 12) {
                    // 图表信息摘要
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: getIconName())
                                .font(.title2)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(getMermaidDescription())
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text(getContentSummary())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            
                            Spacer()
                        }
                        
                        // 显示图表的主要元素
                        Text(getElementsSummary())
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(6)
                    
                    // 原始代码
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mermaid 源码：")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(diagram)
                                .font(.system(.title3, design: .monospaced))  // 更大
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .padding(12)
                        }
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(4)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            } else {
                // 收起时的简化显示
                HStack(spacing: 12) {
                    Image(systemName: getIconName())
                        .font(.title)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(getMermaidDescription())
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("点击展开查看详细信息")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(16)
                .background(Color.blue.opacity(0.05))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            isExpanded.toggle()
        }
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagram, forType: .string)
    }
    
    private func getMermaidDescription() -> String {
        let firstLine = diagram.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
        
        if firstLine.hasPrefix("graph") {
            return "流程图"
        } else if firstLine.hasPrefix("sequenceDiagram") {
            return "时序图"
        } else if firstLine.hasPrefix("classDiagram") {
            return "类图"
        } else if firstLine.hasPrefix("erDiagram") {
            return "实体关系图"
        } else if firstLine.hasPrefix("gantt") {
            return "甘特图"
        } else if firstLine.hasPrefix("pie") {
            return "饼图"
        } else if firstLine.hasPrefix("journey") {
            return "用户旅程图"
        } else {
            return "Mermaid 图表"
        }
    }
    
    private func getIconName() -> String {
        let firstLine = diagram.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
        
        if firstLine.hasPrefix("graph") {
            return "flowchart"
        } else if firstLine.hasPrefix("sequenceDiagram") {
            return "arrow.left.arrow.right"
        } else if firstLine.hasPrefix("classDiagram") {
            return "rectangle.3.offgrid"
        } else if firstLine.hasPrefix("erDiagram") {
            return "square.grid.3x3"
        } else if firstLine.hasPrefix("gantt") {
            return "calendar"
        } else if firstLine.hasPrefix("pie") {
            return "chart.pie"
        } else if firstLine.hasPrefix("journey") {
            return "map"
        } else {
            return "chart.bar.doc.horizontal"
        }
    }
    
    private func getContentSummary() -> String {
        let lines = diagram.components(separatedBy: .newlines)
        let contentLines = lines.dropFirst().filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        if contentLines.count <= 3 {
            return "包含 \(contentLines.count) 行定义"
        } else {
            return "包含 \(contentLines.count) 行定义 - 复杂图表"
        }
    }
    
    private func getElementsSummary() -> String {
        let content = diagram.lowercased()
        var elements: [String] = []
        
        // 分析内容中的关键元素
        if content.contains("-->") || content.contains("->") {
            let arrowCount = content.components(separatedBy: "-->").count + content.components(separatedBy: "->").count - 2
            elements.append("\(arrowCount)个连接")
        }
        
        if content.contains("[") && content.contains("]") {
            let nodeCount = content.components(separatedBy: "[").count - 1
            elements.append("\(nodeCount)个节点")
        }
        
        if content.contains("{") && content.contains("}") {
            let decisionCount = content.components(separatedBy: "{").count - 1
            elements.append("\(decisionCount)个判断")
        }
        
        if elements.isEmpty {
            return "分析图表结构..."
        } else {
            return elements.joined(separator: ", ")
        }
    }
}

// MARK: - 简化的Mermaid WebView渲染器
import WebKit

struct MermaidWebView: NSViewRepresentable {
    let markdown: String
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        // macOS: 彻底透明
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.setValue(false, forKey: "opaque")

        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = generateHTML(from: markdown)
        // 使用Documents目录作为baseURL以支持本地图片
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        webView.loadHTMLString(html, baseURL: documentsURL)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    private func processLocalImages(in markdown: String) -> String {
        // 正则表达式匹配Markdown图片语法：![alt](NodeImages/filename)
        let pattern = #"!\[([^\]]*)\]\(NodeImages/([^)]+)\)"#
        
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(markdown.startIndex..., in: markdown)
            
            var processedMarkdown = markdown
            let matches = regex.matches(in: markdown, range: range)
            
            // 从后往前替换，避免索引偏移问题
            for match in matches.reversed() {
                if let altRange = Range(match.range(at: 1), in: markdown),
                   let fileRange = Range(match.range(at: 2), in: markdown),
                   let fullRange = Range(match.range(at: 0), in: markdown) {
                    
                    let altText = String(markdown[altRange])
                    let fileName = String(markdown[fileRange])
                    
                    // 使用相对路径，依赖baseURL
                    let replacement = "![\(altText)](NodeImages/\(fileName))"
                    
                    processedMarkdown.replaceSubrange(fullRange, with: replacement)
                }
            }
            
            return processedMarkdown
        } catch {
            print("图片路径处理失败: \(error)")
            return markdown
        }
    }
    
    // 工具：把 Swift 字符串安全地嵌进 JS 模板字符串
    private func escapeForJavaScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "\\'")
    }
    
    private func generateHTML(from markdown: String) -> String {
        // 处理本地图片路径
        let processedMarkdown = processLocalImages(in: markdown)
        
        return #"""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Mermaid Preview</title>
            
            <!-- Marked.js -->
            <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
            
            <!-- Mermaid 最新版本 -->
            <script src="https://cdn.jsdelivr.net/npm/mermaid@10.6.1/dist/mermaid.min.js"></script>
        <script>
          window.addEventListener('error', function(e){
            if (String(e.message || '').includes('mermaid')) {
              var b = document.createElement('div');
              b.textContent = 'Mermaid 加载失败：请检查网络，或稍后重试。';
              b.style.cssText = 'position:fixed;left:12px;bottom:12px;padding:6px 10px;border-radius:6px;background:rgba(255,0,0,.1);border:1px solid rgba(255,0,0,.3);font:12px -apple-system,BlinkMacSystemFont,Segoe UI,Roboto;z-index:9999;';
              document.body.appendChild(b);
            }
          });
        </script>
    
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
                    line-height: 1.6;
                    color: #333;
                    margin: 0;
                    padding: 16px;
                    background-color: transparent;;
                }
                
                @media (prefers-color-scheme: dark) {
                    body { background-color: transparent; color: #d4d4d4; }
                    pre { background-color: #2d2d2d !important; }
                    code { background-color: #2d2d2d; color: #d4d4d4; }
                }
                
                h1, h2, h3 { margin-top: 24px; margin-bottom: 16px; }
                p { margin-bottom: 16px; }
                
                pre {
                    background-color: #f6f8fa;
                    border-radius: 6px;
                    padding: 16px;
                    margin: 16px 0;
                    overflow-x: auto;
                }
                
                code {
                    background-color: rgba(175, 184, 193, 0.2);
                    border-radius: 3px;
                    padding: 0.2em 0.4em;
                    font-family: 'SF Mono', Monaco, monospace;
                }
                
              .mermaid {
                  text-align: center;
                  margin: 20px 0;
                  padding: 0;
                  border: none;
                  border-radius: 0;
                  background-color: transparent;
                  opacity: 0;
                  transition: opacity 0.3s ease-in-out;
              }
                
                .mermaid.rendered {
                    opacity: 1;
                }
                #debug-log{ position:fixed; right:8px; bottom:8px; width:320px; max-height:40vh; overflow:auto; font:11px -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Arial; background:rgba(0,0,0,.6); color:#fff; padding:8px 10px; border-radius:8px; box-shadow:0 2px 10px rgba(0,0,0,.3); z-index:99999; }
                #debug-log.hidden{ display:none; }
                #debug-log div{ margin-bottom:4px; word-break:break-word; white-space:pre-wrap; }
                
                #content {
                    opacity: 0;
                    transition: opacity 0.3s ease-in-out;
                }
                
                #content.ready {
                    opacity: 1;
                }
                
                img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 6px;
                    margin: 16px 0;
                    box-shadow: 0 2px 8px rgba(0,0,0,0.1);
                }
                
                @media (prefers-color-scheme: dark) {
                    .mermaid { }
                    img {
                        box-shadow: 0 2px 8px rgba(255,255,255,0.1);
                    }
                }
            </style>
        </head>
        <body>
            <div id="content"></div>
            <div id="debug-log" class="hidden"></div>
            
            <script>
                // ===== Debug helpers =====
                (function(){
                  window.__MMD_DEBUG = true;
                  window.__mmdLog = function(){
                    try{ console.log('🟣[MermaidWebView]', ...arguments); }catch(_){ }
                    try{
                      var box = document.getElementById('debug-log');
                      if (box){
                        box.classList.remove('hidden');
                        var line = document.createElement('div');
                        line.textContent = Array.from(arguments).map(x => (typeof x==='string'? x : JSON.stringify(x))).join(' ');
                        box.appendChild(line);
                        box.scrollTop = box.scrollHeight;
                      }
                    }catch(_){ }
                  };
                  window.addEventListener('error', function(e){ __mmdLog('window.error', String(e && e.message || e)); });
                  window.addEventListener('unhandledrejection', function(e){ __mmdLog('unhandledrejection', String(e && (e.reason && e.reason.message) || e && e.reason || e)); });
                })();
                __mmdLog('boot');
                // 主题检测和监听
                const darkModeQuery = window.matchMedia('(prefers-color-scheme: dark)');
                let isDarkMode = darkModeQuery.matches;
                
                // 获取当前主题配置
                function getCurrentThemeConfig() {
                    return {
                        startOnLoad: false,
                        theme: isDarkMode ? 'dark' : 'base',
                        securityLevel: 'loose',
                        fontFamily: 'system-ui, -apple-system, sans-serif',
                        flowchart: { 
                            useMaxWidth: true, 
                            htmlLabels: true,
                            curve: 'basis'
                        },
                        sequence: { useMaxWidth: true },
                        gantt: { useMaxWidth: true },
                        journey: { useMaxWidth: true },
                        pie: { useMaxWidth: true }
                    };
                }
                
                // 初始化Mermaid
                mermaid.initialize(getCurrentThemeConfig());
                __mmdLog('mermaid.initialize called', typeof mermaid, (window.mermaid && window.mermaid.version) ? ('v'+window.mermaid.version) : 'no-version');
                
                // 监听主题变化
                darkModeQuery.addListener(function(e) {
                    __mmdLog('theme changed', e.matches ? 'dark' : 'light');
                    isDarkMode = e.matches;
                    
                    // 重新配置并重新渲染所有Mermaid图表
                    mermaid.initialize(getCurrentThemeConfig());
                    reRenderMermaidCharts();
                });
                
                // 配置Marked
                marked.setOptions({
                    breaks: true,
                    gfm: true
                });
                
                // Markdown内容（规范化：容错 mermiad/mmd/:::mermaid，并尽量补齐未闭合围栏）
                const rawMarkdown = `\#(escapeForJavaScript(processedMarkdown))`;
                let normalized = rawMarkdown
                  // 常见拼写：mermiad / mmd
                  .replace(/```mermiad/gi, '```mermaid')
                  .replace(/```mmd/gi, '```mermaid')
                  // 支持 :::mermaid ... :::
                  .replace(/:::mermaid\s([\s\S]*?):::/gi, '```mermaid\n$1\n```');
                // 若存在未闭合的 ```mermaid，则在文末补一个 ```
                if (/```mermaid[\s\S]*?(?!```)[\s\S]*$/.test(normalized) && !/```\s*$/.test(normalized)) {
                  normalized += '\n```';
                }
                const markdownContent = normalized;
                
                // 重新渲染Mermaid图表的函数
                function reRenderMermaidCharts() {
                    __mmdLog('reRenderMermaidCharts()');
                    const contentDiv = document.getElementById('content');
                    const mermaidElements = contentDiv.querySelectorAll('.mermaid');
                    __mmdLog('reRender elements', mermaidElements.length);
                    if (mermaidElements.length === 0) {
                        return;
                    }
                    
                    // 清理现有的渲染内容，保留原始文本
                    mermaidElements.forEach((element, index) => {
                        // 重置元素内容为原始Mermaid代码
                        const originalCode = element.getAttribute('data-original-code');
                        if (originalCode) {
                            element.innerHTML = originalCode;
                            element.removeAttribute('data-processed');
                        }
                        
                        // 移除rendered类以重新触发动画
                        element.classList.remove('rendered');
                    });
                    
                    // 使用setTimeout确保DOM更新完成后再重新渲染
                    setTimeout(() => {
                        (window.mermaid ? mermaid.run() : Promise.reject(new Error('Mermaid not available'))).then(() => {
                            __mmdLog('mermaid.run success');
                            // 重新添加rendered类，触发淡入动画
                            mermaidElements.forEach(element => {
                                element.classList.add('rendered');
                            });
                        }).catch(error => {
                            __mmdLog('mermaid.run failed', String(error && error.message || error));
                        });
                    }, 10);
                }
                
                // 渲染函数
                function renderContent() {
                    __mmdLog('renderContent start');
                    
                    // 解析 markdown
                    let html = marked.parse(markdownContent);
                    __mmdLog('marked.parse ok');
                    
                    const parser = new DOMParser();
                    const doc = parser.parseFromString(html, 'text/html');

                    // 找出 mermaid 代码块（显式语言+关键字兜底）
                    let blocks = Array.from(doc.querySelectorAll('pre code.language-mermaid'));
                    const kw = /^(graph|sequenceDiagram|classDiagram|erDiagram|gantt|pie|journey)\b/;
                    blocks = blocks.concat(
                      Array.from(doc.querySelectorAll('pre code'))
                        .filter(el => !el.className.includes('language-mermaid') && kw.test((el.textContent || '').trim()))
                    );

                    __mmdLog('mermaid blocks found', blocks.length);

                    // ✅ 关键：就地替换 <pre> 为 <div class="mermaid">
                    blocks.forEach((block, index) => {
                      // --- robust in-place replacement ---
                      // 1) sanitize text
                      let code = (block.textContent || '').replace(/\uFEFF/g, '').trim();
                      const lines = code.split(/\r?\n/);
                      const kw = /^(graph|sequenceDiagram|classDiagram|erDiagram|gantt|pie|journey)\b/;
                      const firstDiagramIdx = lines.findIndex(l => kw.test(l.trim()) || /^%%\{/.test(l.trim()));
                      if (firstDiagramIdx > 0) code = lines.slice(firstDiagramIdx).join('\n');

                      // 2) create mermaid node
                      const mer = doc.createElement('div');
                      mer.className = 'mermaid';
                      mer.id = 'mermaid-' + index;
                      mer.textContent = code;
                      mer.setAttribute('data-original-code', code);

                      // 3) find best replacement target in the parsed DOM
                      let target = block.closest('pre, .code, .code-block, p, div');
                      if (!target) target = block.parentElement;

                      if (target && target.parentNode) {
                        target.replaceWith(mer);     // ✅ in-place
                        __mmdLog('replaceWith ok at', mer.id);
                      } else if (block && block.parentNode) {
                        // fallback: insert before then remove original block (still in the same parent)
                        block.parentNode.insertBefore(mer, block);
                        block.remove();
                        __mmdLog('insertBefore fallback at', mer.id);
                      } else {
                        // FORBIDDEN: Never append! This would push diagrams to bottom
                        __mmdLog('CRITICAL: No replacement target found for', mer.id, 'keeping original block position');
                        // Insert right after the original block to maintain position
                        if (block.nextSibling) {
                          block.parentNode.insertBefore(mer, block.nextSibling);
                          block.remove();
                          __mmdLog('insertAfter final fallback at', mer.id);
                        } else {
                          // Absolute last resort - replace the block directly
                          block.parentNode.replaceChild(mer, block);
                          __mmdLog('replaceChild final fallback at', mer.id);
                        }
                      }
                    });

                    // 把修改后的文档一次性写回页面
                    const contentDiv = document.getElementById('content');
                    contentDiv.innerHTML = doc.body.innerHTML;
                    __mmdLog('wrote HTML back to #content');
                    
                    // ✅ 硬断言：确保没有未替换的mermaid代码块
                    const remainingBlocks = document.querySelectorAll('#content pre code.language-mermaid, #content pre code').length;
                    if (remainingBlocks > 0) {
                      __mmdLog('WARNING: Found', remainingBlocks, 'unprocessed code blocks after replacement');
                    }

                    // 再触发渲染（先写回，再 run）
                    setTimeout(() => {
                      const mermaidElements = document.getElementById('content').querySelectorAll('.mermaid');
                      __mmdLog('about to mermaid.run', mermaidElements.length, (window.mermaid && typeof window.mermaid.run));
                      
                      if (mermaidElements.length > 0) {
                        (window.mermaid ? mermaid.run() : Promise.reject(new Error('Mermaid not available')))
                          .then(() => {
                            __mmdLog('mermaid.run success');
                            mermaidElements.forEach(element => {
                              element.classList.add('rendered');
                            });
                            // 显示整个内容
                            setTimeout(() => {
                              contentDiv.classList.add('ready');
                            }, 50);
                          })
                          .catch(err => {
                            __mmdLog('mermaid.run failed', String(err && err.message || err));
                            // 即使渲染失败也要显示内容
                            contentDiv.classList.add('ready');
                          });
                      } else {
                        // 如果没有Mermaid图表，直接显示内容
                        contentDiv.classList.add('ready');
                      }
                    }, 10);
                }
                
                // 确保渲染一定触发；并在文档就绪 / 完全加载后再尝试一次
                try { renderContent(); } catch (e) { console.error(e); }
                document.addEventListener('DOMContentLoaded', () => { try { renderContent(); } catch (e) { console.error(e); } });
                window.addEventListener('load', () => { try { renderContent(); } catch (e) { console.error(e); } });
            </script>
        </body>
        </html>
"""#
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
        }
    }
}

// MARK: - 实时 Markdown（Milkdown）WebView
import WebKit

struct MilkdownWebView: NSViewRepresentable {
    var markdown: String
    var onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parentMarkdown: markdown, onChange: onChange) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let uc = WKUserContentController()
        uc.add(context.coordinator, name: "bridge")
        config.userContentController = uc
        config.preferences.setValue(true, forKey: "developerExtrasEnabled") // 可右键 Inspect

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.focusRingType = .none   // ← 关掉 AppKit 焦点环
        // macOS 侧彻底透明（isOpaque 在 macOS 是只读，用 KVC 与图层实现）
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.setValue(false, forKey: "opaque")
        
        // 确保用户可以交互 - 这些是View的默认行为，无需显式设置

        webView.navigationDelegate = context.coordinator

        // 初次载入
        let html = context.coordinator.generateHTML(initialMarkdown: markdown)
        webView.loadHTMLString(html, baseURL: nil)
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // 仅当外部 markdown 发生变化时，注入到编辑器；避免回环
        context.coordinator.setMarkdownIfNeeded(markdown)
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var lastSentFromSwift: String
        private var isSettingFromSwift = false
        private let onChange: (String) -> Void

        init(parentMarkdown: String, onChange: @escaping (String) -> Void) {
            self.lastSentFromSwift = parentMarkdown
            self.onChange = onChange
        }

        // 接收来自 JS 的消息
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "bridge" else { return }
            if let dict = message.body as? [String: Any], let type = dict["type"] as? String {
                if type == "log" {
                    if let args = dict["args"] as? [String] {
                        print("🟣[Milkdown] " + args.joined(separator: " "))
                    } else {
                        print("🟣[Milkdown] <log>")
                    }
                    return
                }
                if type == "markdown", let value = dict["value"] as? String {
                    // 来自编辑器的变更
                    if !isSettingFromSwift {
                        lastSentFromSwift = value
                        onChange(value)
                    }
                }
            } else {
                print("🟣[Milkdown] \(message.body)")
            }
        }

        func setMarkdownIfNeeded(_ newValue: String) {
            guard newValue != lastSentFromSwift else { return }
            lastSentFromSwift = newValue
            isSettingFromSwift = true
            let escaped = escapeForJavaScript(newValue)
            let js = "window.__milkdown_setMarkdown && window.__milkdown_setMarkdown(\"\(escaped)\");"
            webView?.evaluateJavaScript(js) { [weak self] _, _ in
                self?.isSettingFromSwift = false
            }
        }

        // 生成自包含的 HTML（从 CDN 加载模块；首次需要联网）
        func generateHTML(initialMarkdown: String) -> String {
            let md = escapeForJavaScript(initialMarkdown)
            return #"""
            <!doctype html>
            <html>
            <head>
              <meta charset="utf-8" />
              <meta name="viewport" content="width=device-width, initial-scale=1" />
              <title>Milkdown Editor</title>
              <style>
                :root{ --text: #111827; }
                @media (prefers-color-scheme: dark){ :root{ --text: #e5e7eb; } }
                html,body{height:100%;margin:0}
                /* 关键：彻底透明，交给 SwiftUI 打底色 */
                body{background:transparent !important;color:var(--text) !important;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial,PingFang SC,Hiragino Sans GB,Microsoft YaHei,Noto Sans CJK SC,sans-serif;-webkit-font-smoothing:antialiased;-moz-osx-font-smoothing:grayscale}
                .container{max-width:960px;margin:0 auto;padding:0}
                #app{background:transparent !important;border:none !important;border-radius:0;min-height:0;padding:0;box-shadow:none}
                .milkdown{background:transparent !important}
                .ProseMirror{background:transparent !important}
                /* 在编辑器内联预览 Mermaid（只展示，不拦截编辑） */
                .pm-mermaid-preview{ margin:12px 0; padding:0; background:transparent; pointer-events:none; opacity:1; }
                /* 右下角调试面板 */
                #md-debug{ position:fixed; right:8px; bottom:8px; width:320px; max-height:40vh; overflow:auto;
                  font:11px -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Arial; background:rgba(0,0,0,.6); color:#fff;
                  padding:8px 10px; border-radius:8px; box-shadow:0 2px 10px rgba(0,0,0,.3); z-index:99999; pointer-events:none; }
                #md-debug.hidden{ display:none; }
                #md-debug div{ margin-bottom:4px; white-space:pre-wrap; word-break:break-word; }
                .milkdown{padding:0 !important;margin:0 !important}
                .ProseMirror{padding:0 !important;margin:0 !important}
                /* 移除聚焦蓝框（AppKit & WebKit 双保险） */
                *:focus{ outline: none !important; }
                .milkdown .ProseMirror:focus{ outline: none !important; box-shadow: none !important; }
                .milkdown .editor:focus{ outline: none !important; box-shadow: none !important; }
                ::-moz-focus-inner{ border: 0 !important; }
                a{color:#8b5cf6;text-decoration:none}
                a:hover{text-decoration:underline}

                /* Typography */
                .milkdown .editor{font-size:16px;line-height:1.75;letter-spacing:.1px}
                .milkdown h1,.milkdown h2,.milkdown h3,.milkdown h4{font-weight:750;letter-spacing:-.01em;margin:1.25em 0 .6em}
                .milkdown h1{font-size:1.9rem}
                .milkdown h2{font-size:1.6rem}
                .milkdown h3{font-size:1.3rem}
                .milkdown p{margin:.6em 0}
                .milkdown ul,.milkdown ol{margin:.6em 0 .6em 1.3em}

                /* Code */
                .milkdown pre,.milkdown code{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace}
                .milkdown pre{background:rgba(0,0,0,.05);border:0;border-radius:10px;padding:12px 14px;overflow:auto}
                @media (prefers-color-scheme: dark){ .milkdown pre{background:rgba(255,255,255,.06)} }
                .milkdown code:not(pre code){background:rgba(0,0,0,.05);padding:2px 6px;border-radius:6px}
                @media (prefers-color-scheme: dark){ .milkdown code:not(pre code){background:rgba(255,255,255,.06)} }

                /* HR */
                .milkdown hr{border:0;border-top:1px solid rgba(0,0,0,.12);margin:2em 0}
                @media (prefers-color-scheme: dark){ .milkdown hr{border-top-color: rgba(255,255,255,.15)} }

                /* 内联 Mermaid 预览样式 - 允许显示但不拦截编辑 */
                .pm-mermaid-preview {
                  margin: 12px 0;
                  padding: 0;
                  background: transparent;
                  pointer-events: none !important;  /* 关键：不拦截编辑器交互 */
                  opacity: 1;
                  max-width: 100%;
                  overflow-x: auto;
                }

                .pm-mermaid-preview svg {
                  max-width: 100%;
                  height: auto;
                }

                /* 隐藏被 Mermaid 图表替换的代码块 */
                .mermaid-hidden-code {
                  display: none !important;
                  height: 0 !important;
                  margin: 0 !important;
                  padding: 0 !important;
                  overflow: hidden !important;
                }

                /* Debug 浮窗不拦截事件 */
                #debug-log { pointer-events: none !important; }

                /* 确保编辑器区域可滚动并撑满高度 */
                html, body { height: 100%; }
                #app, #root, .milkdown, .ProseMirror { min-height: 100%; }
              </style>
              <script src="https://cdn.jsdelivr.net/npm/mermaid@10.6.1/dist/mermaid.min.js"></script>
              <script>
                (function(){
                  try{
                    const dark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
                    if (window.mermaid && window.mermaid.initialize){
                      window.mermaid.initialize({ startOnLoad:false, securityLevel:'loose', theme: dark ? 'dark' : 'base' });
                    }
                  }catch(e){ console.warn('Mermaid init failed', e); }
                })();
              </script>
            </head>
            <body>
              <div class="container">
                <div id="app"></div>
              </div>
              <div id="md-debug" class="hidden"></div>
              <script type="module">
                (function(){
                  window.__MMD_DEBUG = true;
                  window.__mmdLog = function(){
                    try{ console.log('🟣[Milkdown]', ...arguments); }catch(_){}
                    try{
                      const args = Array.from(arguments).map(x => (typeof x === 'string' ? x : JSON.stringify(x)));
                      window.webkit?.messageHandlers?.bridge?.postMessage({ type:'log', args });
                    }catch(_){}
                    try{
                      const box = document.getElementById('md-debug');
                      if (box){
                        box.classList.remove('hidden');
                        const line = document.createElement('div');
                        line.textContent = (Array.from(arguments).map(x => (typeof x==='string'? x : JSON.stringify(x))).join(' '));
                        box.appendChild(line);
                        box.scrollTop = box.scrollHeight;
                      }
                    }catch(_){}
                  };
                })();
                __mmdLog('milkdown boot');
                
                import { Editor, rootCtx, defaultValueCtx, editorViewCtx } from 'https://esm.sh/@milkdown/core@7';
                import { commonmark } from 'https://esm.sh/@milkdown/preset-commonmark@7';
                import { listener, listenerCtx } from 'https://esm.sh/@milkdown/plugin-listener@7';
                import { exitCode } from 'https://esm.sh/prosemirror-commands@1';
                import { TextSelection } from 'https://esm.sh/prosemirror-state@1';
                import { Plugin, PluginKey } from 'https://esm.sh/prosemirror-state@1';
                import { Decoration, DecorationSet } from 'https://esm.sh/prosemirror-view@1';

                let editor; let debouncing;
                
                // === 安全的 Mermaid 内联预览插件 ===
                const mermaidPreviewKey = new PluginKey('safe-mermaid-preview');
                
                function buildMermaidDecorations(state) {
                  const decos = [];
                  const { doc } = state;
                  const mermaidStart = /^(graph|sequenceDiagram|classDiagram|erDiagram|gantt|pie|journey)\b/i;
                  
                  doc.descendants((node, pos) => {
                    if (node.type && node.type.name === 'code_block') {
                      const lang = (node.attrs && (node.attrs.language || node.attrs.params || node.attrs.lang) || '').toString().toLowerCase();
                      const text = (node.textContent || '').trim();
                      
                      // Mermaid 检测：有语言标识 或 有实际图表内容
                      const hasLanguage = lang.includes('mermaid');
                      const hasValidContent = text && text.length > 0 && mermaidStart.test(text);
                      
                      // 只有在有语言标识且有内容，或者有有效图表内容时才处理
                      if ((hasLanguage && text.length > 0) || hasValidContent) {
                        // 清理代码（移除无关首行）
                        let cleanCode = text.replace(/\uFEFF/g, '').trim();
                        
                        const lines = cleanCode.split(/\r?\n/);
                        const firstDiagramIdx = lines.findIndex(l => mermaidStart.test(l.trim()) || /^%%\{/.test(l.trim()));
                        if (firstDiagramIdx > 0) cleanCode = lines.slice(firstDiagramIdx).join('\n');
                        
                        // 再次检查清理后的代码是否为空
                        if (!cleanCode || cleanCode.trim().length === 0) {
                          return; // 跳过清理后为空的代码块
                        }
                        
                        const dom = document.createElement('div');
                        dom.className = 'pm-mermaid-preview';
                        dom.setAttribute('data-source', cleanCode);
                        dom.textContent = cleanCode; // 先显示原始代码，稍后渲染
                        
                        // 关键：用隐藏代码块 + widget 图表的方式实现"替换"效果
                        // 1. 隐藏原代码块
                        decos.push(Decoration.node(pos, pos + node.nodeSize, {
                          'class': 'mermaid-hidden-code'
                        }));
                        
                        // 2. 在同位置显示图表
                        decos.push(Decoration.widget(pos, dom, { 
                          side: 0, 
                          ignoreSelection: true,  // 不影响光标选择
                          stopEvent: () => true   // 阻止事件冒泡到编辑器
                        }));
                      }
                    }
                  });
                  
                  return DecorationSet.create(doc, decos);
                }
                
                const safeMermaidPlugin = new Plugin({
                  key: mermaidPreviewKey,
                  state: {
                    init() { return DecorationSet.empty; },
                    apply(tr, old, _oldState, newState) {
                      if (tr.docChanged) return buildMermaidDecorations(newState);
                      return old.map(tr.mapping, tr.doc);
                    }
                  },
                  props: {
                    decorations(state) { return this.getState(state); }
                  },
                  view(view) {
                    function renderPreviews() {
                      const nodes = view.dom.querySelectorAll('.pm-mermaid-preview:not(.rendered)');
                      if (!nodes.length) return;
                      
                      nodes.forEach(el => {
                        const src = el.getAttribute('data-source') || el.textContent || '';
                        el.innerHTML = '';
                        
                        try {
                          if (window.mermaid && window.mermaid.render) {
                            const id = 'mmd-' + Math.random().toString(36).slice(2);
                            window.mermaid.render(id, src).then(({ svg }) => {
                              el.innerHTML = svg;
                              el.classList.add('rendered', 'success');
                              __mmdLog('Inline mermaid rendered:', id);
                            }).catch(e => {
                              __mmdLog('Inline mermaid render failed:', String(e?.message || e));
                              // 渲染失败时显示错误信息而不是原始代码
                              el.innerHTML = `<div style="color: #ef4444; font-size: 12px; padding: 8px; background: rgba(239, 68, 68, 0.1); border-radius: 4px; border: 1px solid rgba(239, 68, 68, 0.2);">
                                ⚠️ Mermaid 渲染失败: ${String(e?.message || e)}
                                <details style="margin-top: 4px;">
                                  <summary style="cursor: pointer; user-select: none;">查看原始代码</summary>
                                  <pre style="white-space: pre-wrap; font-family: monospace; font-size: 11px; margin: 4px 0 0 0;">${src}</pre>
                                </details>
                              </div>`;
                              el.classList.add('rendered', 'error');
                            });
                          }
                        } catch (e) {
                          __mmdLog('Inline mermaid error:', String(e?.message || e));
                          el.innerHTML = `<div style="color: #ef4444; font-size: 12px; padding: 8px;">⚠️ Mermaid 初始化失败</div>`;
                          el.classList.add('rendered', 'error');
                        }
                      });
                    }
                    
                    // 延迟渲染以确保DOM就绪
                    setTimeout(renderPreviews, 100);
                    return { update: () => setTimeout(renderPreviews, 100) };
                  }
                });
                
                async function setup(initial){
                  editor = await Editor.make()
                    .config((ctx)=>{
                      ctx.set(rootCtx, document.getElementById('app'));
                      ctx.set(defaultValueCtx, initial);
                      const l = ctx.get(listenerCtx);
                      l.markdownUpdated((_, md)=>{
                        clearTimeout(debouncing);
                        debouncing = setTimeout(()=>{
                          window.webkit?.messageHandlers?.bridge?.postMessage({type:'markdown', value: md});
                        }, 200);
                      });
                    })
                    .use(commonmark)
                    .use(listener)
                    .create();
                    __mmdLog('editor ready');
                    
                    // 注入安全的内联 Mermaid 预览插件
                    try {
                      editor.action((ctx) => {
                        const view = ctx.get(editorViewCtx);
                        const newState = view.state.reconfigure({
                          plugins: view.state.plugins.concat(safeMermaidPlugin)
                        });
                        view.updateState(newState);
                        __mmdLog('Safe mermaid plugin injected');
                      });
                    } catch (e) {
                      __mmdLog('Plugin injection failed:', String(e?.message || e));
                    }
                }

                // 获取当前 EditorView 的辅助函数
                const withView = (fn) => editor?.action((ctx)=>{ try { fn(ctx.get(editorViewCtx)); } catch(e){} });

                // 退出代码块：Shift+Enter 或 Alt+Enter；在代码块中键入 ``` 也会自动退出
                let backtickCount = 0;
                document.addEventListener('keydown', (e)=>{
                  // 退出快捷键：Shift+Enter / Alt+Enter
                  if (e.key === 'Enter' && (e.shiftKey || e.altKey)) {
                    withView((view)=>{ if (exitCode(view.state, view.dispatch)) e.preventDefault(); });
                    return;
                  }


                  // 在代码块中，连续输入 ``` 自动退出
                  if (e.key === '`') {
                    backtickCount++;
                    if (backtickCount >= 3) {
                      withView((view)=>{
                        const {$from} = view.state.selection;
                        const inCode = $from.parent?.type?.name === 'code_block';
                        if (inCode && exitCode(view.state, view.dispatch)) {
                          e.preventDefault();
                        }
                      });
                      backtickCount = 0;
                    }
                  } else {
                    backtickCount = 0;
                  }

                  // 回车时若当前行仅为 ``` 则删除该行并退出代码块
                  if (e.key === 'Enter' && !e.shiftKey && !e.altKey) {
                    withView((view)=>{
                      const {$from} = view.state.selection;
                      const inCode = $from.parent?.type?.name === 'code_block';
                      if (!inCode) return;
                      const text = $from.parent.textContent || '';
                      const pos = $from.parentOffset;
                      const before = text.slice(0, pos);
                      const lastLine = before.split('\n').pop() || '';
                      if (/^```\s*$/.test(lastLine)) {
                        e.preventDefault();
                        const start = $from.start();
                        const lineStart = pos - lastLine.length;
                        let tr = view.state.tr.delete(start + lineStart, start + pos);
                        view.dispatch(tr);
                        exitCode(view.state, view.dispatch);
                      }
                    });
                  }
                });

                // Swift 调用：覆盖内容
                window.__milkdown_setMarkdown = (md)=>{
                  if (!editor){ return; }
                  import('https://esm.sh/@milkdown/utils@7').then(({ callCommand })=>{
                    editor.action(callCommand((ctx)=>{
                      const { replaceAll } = ctx.getState();
                      return replaceAll(md);
                    }));
                  });
                };

                // 将 Swift 传入的 Markdown 注入到 JS（Swift 侧已完成转义）
                setup(`\#(md)`);
                
                // 确保设置完成后再次检查 Mermaid
                setTimeout(checkMermaidAndForce, 100);

                // 确保 Mermaid 就绪后触发内联预览渲染
                (function ensureMermaidReady() {
                  function checkAndRender() {
                    if (window.mermaid && window.mermaid.render && editor) {
                      __mmdLog('Triggering mermaid inline preview update');
                      try {
                        editor.action((ctx) => {
                          const view = ctx.get(editorViewCtx);
                          view.dispatch(view.state.tr.setMeta('forceMermaidUpdate', true));
                        });
                      } catch (e) {
                        __mmdLog('Force update failed:', String(e?.message || e));
                      }
                    } else {
                      setTimeout(checkAndRender, 500);
                    }
                  }
                  setTimeout(checkAndRender, 100);
                })();
              </script>
            </body>
            </html>
"""#
        }

        // 工具：转义到 JS 字符串
        func escapeForJavaScript(_ string: String) -> String {
            return string
                .replacingOccurrences(of: "\\\\", with: "\\\\\\\\")
                .replacingOccurrences(of: "`", with: "\\\\`")
                .replacingOccurrences(of: "$", with: "\\\\$")
                .replacingOccurrences(of: "\\n", with: "\\\\n")
                .replacingOccurrences(of: "\\r", with: "\\\\r")
                .replacingOccurrences(of: "\\\"", with: "\\\\\\\"")
                .replacingOccurrences(of: "'", with: "\\\\'")
        }

        // 屏蔽外链跳转，保留内部脚本运行
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
        }
    }
}


// MARK: - 图片管理器

class NodeImageManager: ObservableObject {
    static let shared = NodeImageManager()
    
    private init() {}
    
    private var imagesDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imagesURL = documentsPath.appendingPathComponent("NodeImages")
        
        // 确保目录存在
        if !FileManager.default.fileExists(atPath: imagesURL.path) {
            try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        }
        
        return imagesURL
    }
    
    func selectAndCopyImage() -> String? {
        let panel = NSOpenPanel()
        panel.title = "选择图片"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        
        if panel.runModal() == .OK, let url = panel.url {
            return copyImageToAppDirectory(from: url)
        }
        
        return nil
    }
    
    func copyImageFromURL(_ sourceURL: URL) -> String? {
        return copyImageToAppDirectory(from: sourceURL)
    }
    
    private func copyImageToAppDirectory(from sourceURL: URL) -> String? {
        let fileExtension = sourceURL.pathExtension
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = imagesDirectory.appendingPathComponent(fileName)
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return fileName // 返回相对路径
        } catch {
            print("图片复制失败: \(error)")
            return nil
        }
    }
    
    func getImageURL(for fileName: String) -> URL {
        return imagesDirectory.appendingPathComponent(fileName)
    }
    
    func deleteImage(fileName: String) {
        let imageURL = imagesDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: imageURL)
    }
    
    func generateImageMarkdown(fileName: String, description: String = "图片") -> String {
        return "![\(description)](NodeImages/\(fileName))"
    }
}


#Preview {
    let sampleNode = Node(
        text: "example",
        phonetic: "/ɪɡˈzæmpəl/",
        meaning: "例子，示例",
        layerId: UUID()
    )
    
    DetailPanel(node: sampleNode)
        .environmentObject(NodeStore.shared)
}

