import SwiftUI
import CoreLocation
import MapKit
import MapKit

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
    }
}

// MARK: - 节点详情视图

struct NodeDetailView: View {
    let node: Node
    @EnvironmentObject private var store: NodeStore
    
    // 从store中获取最新的节点数据
    private var currentNode: Node {
        return store.nodes.first { $0.id == node.id } ?? node
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 单词信息
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(currentNode.text)
                            .font(.system(size: 36, weight: .bold))
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        if let phonetic = currentNode.phonetic {
                            Text(phonetic)
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.1))
                                )
                        }
                    }
                    
                    if let meaning = currentNode.meaning {
                        Text(meaning)
                            .font(.system(size: 24))
                            .foregroundColor(.primary)
                    }
                }
                
                Divider()
                
                // 标签部分
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("标签")
                            .font(.system(size: 20, weight: .semibold))
                        
                        Spacer()
                        
                        Text("\(currentNode.tags.count) 个标签")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    let displayTags = currentNode.tags.filter { tag in
                        // 过滤掉复合节点和子节点引用标签，因为它们是内部使用的
                        if case .custom(let key) = tag.type {
                            return !(key == "compound" || key == "child")
                        }
                        return true
                    }
                    
                    if displayTags.isEmpty {
                        EmptyTagsView()
                    } else {
                        TagsByTypeView(tags: displayTags)
                    }
                }
                
                // 移除了无效的元数据信息（创建时间、更新时间、单词ID）
            }
            .padding(24)
        }
    }
}

// MARK: - 按类型分组的标签视图

struct TagsByTypeView: View {
    let tags: [Tag]
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool
    
    private var groupedTags: [Tag.TagType: [Tag]] {
        Dictionary(grouping: tags, by: { $0.type })
    }
    
    private var flattenedTags: [Tag] {
        var result: [Tag] = []
        // 先添加预定义类型的标签
        for type in Tag.TagType.allCases {
            if let tagsOfType = groupedTags[type], !tagsOfType.isEmpty {
                result.append(contentsOf: tagsOfType)
            }
        }
        // 再添加自定义类型的标签
        for (type, tagsOfType) in groupedTags {
            if !Tag.TagType.allCases.contains(where: { $0.rawValue == type.rawValue }) {
                result.append(contentsOf: tagsOfType)
            }
        }
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 先显示预定义类型的标签
            ForEach(Tag.TagType.allCases, id: \.self) { type in
                if let tagsOfType = groupedTags[type], !tagsOfType.isEmpty {
                    TagTypeSection(
                        type: type, 
                        tags: tagsOfType,
                        selectedIndex: $selectedIndex,
                        flattenedTags: flattenedTags
                    )
                }
            }
            // 再显示自定义类型的标签
            ForEach(Array(groupedTags.keys), id: \.self) { type in
                if !Tag.TagType.allCases.contains(where: { $0.rawValue == type.rawValue }),
                   let tagsOfType = groupedTags[type], !tagsOfType.isEmpty {
                    TagTypeSection(
                        type: type, 
                        tags: tagsOfType,
                        selectedIndex: $selectedIndex,
                        flattenedTags: flattenedTags
                    )
                }
            }
        }
        .focused($isFocused)
        .onKeyPress(.upArrow) {
            navigateVertically(direction: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            navigateVertically(direction: 1)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            navigateHorizontally(direction: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigateHorizontally(direction: 1)
            return .handled
        }
        .onAppear {
            isFocused = true
        }
    }
    
    private func navigateVertically(direction: Int) {
        let newIndex = selectedIndex + direction
        if newIndex >= 0 && newIndex < flattenedTags.count {
            selectedIndex = newIndex
        }
    }
    
    private func navigateHorizontally(direction: Int) {
        let newIndex = selectedIndex + direction * 2 // 每行假设有2个元素
        if newIndex >= 0 && newIndex < flattenedTags.count {
            selectedIndex = newIndex
        }
    }
}

struct TagTypeSection: View {
    let type: Tag.TagType
    let tags: [Tag]
    @Binding var selectedIndex: Int
    let flattenedTags: [Tag]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color.from(tagType: type))
                    .frame(width: 14, height: 14)
                Text(type.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .fontWeight(.medium)
                Spacer()
                Text("\(tags.count)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: [
                    GridItem(.adaptive(minimum: 60), spacing: 12)
                ], spacing: 12) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { localIndex, tag in
                        let globalIndex = flattenedTags.firstIndex(where: { $0.id == tag.id }) ?? 0
                        DetailTagCard(
                            tag: tag,
                            isHighlighted: globalIndex == selectedIndex
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: 150) // 增加最大高度以容纳更大的标签
        }
    }
}

struct DetailTagCard: View {
    let tag: Tag
    let isHighlighted: Bool
    
    init(tag: Tag, isHighlighted: Bool = false) {
        self.tag = tag
        self.isHighlighted = isHighlighted
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(Color.from(tagType: tag.type))
                    .frame(width: 14, height: 14)
                
                Spacer()
                
                if tag.hasCoordinates {
                    Image(systemName: "location.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                }
            }
            
            Text(tag.value)
                .font(.system(size: 22, weight: .semibold))
                .fontWeight(.semibold)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            
            if tag.hasCoordinates, let lat = tag.latitude, let lon = tag.longitude {
                Text("\(String(format: "%.4f", lat)), \(String(format: "%.4f", lon))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.from(tagType: tag.type).opacity(isHighlighted ? 0.3 : 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            Color.from(tagType: tag.type).opacity(isHighlighted ? 0.8 : 0.3), 
                            lineWidth: isHighlighted ? 3 : 2
                        )
                )
        )
    }
}

// MARK: - 空标签状态

struct EmptyTagsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tag.slash")
                .font(.largeTitle)
                .foregroundColor(.gray)
            
            Text("暂无标签")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
            
            Text("为这个节点添加标签来更好地组织和记忆")
                .font(.system(size: 14))
                .foregroundColor(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
        )
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
                    ForEach(locationTags, id: \.id) { tag in
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
        objectWillChange.send()
    }
    
    // 清除所有缓存
    func clearAllCache() {
        cache.removeAll()
        objectWillChange.send()
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
            .focusable()
            .onKeyPress(.init("l"), phases: .down) { keyPress in
                if keyPress.modifiers == .command {
                    showingFullscreenGraph = true
                    print("🖥️ Command+L: 打开全屏图谱")
                    return .handled
                }
                return .ignored
            }
            .contextMenu {
                Button("全屏显示 (⌘L)") {
                    showingFullscreenGraph = true
                    print("🖥️ 右键菜单: 全屏显示图谱")
                }
            }
            .sheet(isPresented: $showingFullscreenGraph) {
                FullscreenGraphSheet(
                    node: currentNode,
                    graphData: graphData
                )
            }
        }
    }
}

// MARK: - 全屏图谱视图

struct FullscreenGraphSheet: View {
    let node: Node
    let graphData: (nodes: [NodeGraphNode], edges: [NodeGraphEdge])
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: NodeStore
    @AppStorage("fullscreenGraphInitialScale") private var fullscreenGraphInitialScale: Double = 0.8
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 工具栏
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("节点关系图谱")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("\(node.text) - \(graphData.nodes.count) 个节点, \(graphData.edges.count) 条连接")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // 缩放控制
                    HStack {
                        Button(action: {
                            fullscreenGraphInitialScale = max(0.3, fullscreenGraphInitialScale - 0.1)
                        }) {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .disabled(fullscreenGraphInitialScale <= 0.3)
                        
                        Text(String(format: "%.0f%%", fullscreenGraphInitialScale * 100))
                            .font(.caption)
                            .frame(width: 40)
                        
                        Button(action: {
                            fullscreenGraphInitialScale = min(2.0, fullscreenGraphInitialScale + 0.1)
                        }) {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .disabled(fullscreenGraphInitialScale >= 2.0)
                    }
                    .buttonStyle(.borderless)
                    
                    Button("适应窗口") {
                        // 发送fit graph通知
                        NotificationCenter.default.post(name: Notification.Name("fitGraph"), object: nil)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("关闭") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // 图谱显示区域
                UniversalRelationshipGraphView(
                    nodes: graphData.nodes,
                    edges: graphData.edges,
                    title: "全屏节点关系图谱",
                    initialScale: fullscreenGraphInitialScale,
                    onNodeSelected: { nodeId in
                        // 当点击节点时，选择对应的节点并关闭全屏
                        if let selectedNode = graphData.nodes.first(where: { $0.id == nodeId }),
                           let selectedTargetNode = selectedNode.node {
                            store.selectNode(selectedTargetNode)
                            dismiss()
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarBackButtonHidden(true)
        }
        .frame(minWidth: 800, minHeight: 600)
        .onKeyPress(.escape) {
            // ESC键关闭全屏
            dismiss()
            return .handled
        }
        .onKeyPress(.init("l"), phases: .down) { keyPress in
            if keyPress.modifiers == .command {
                // Command+L也可以关闭全屏
                dismiss()
                return .handled
            }
            return .ignored
        }
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