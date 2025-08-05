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
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        if let phonetic = currentNode.phonetic {
                            Text(phonetic)
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.1))
                                )
                        }
                    }
                    
                    if let meaning = currentNode.meaning {
                        Text(meaning)
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                }
                
                Divider()
                
                // 标签部分
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("标签")
                            .font(.headline)
                        
                        Spacer()
                        
                        Text("\(currentNode.tags.count) 个标签")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if currentNode.tags.isEmpty {
                        EmptyTagsView()
                    } else {
                        TagsByTypeView(tags: currentNode.tags)
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
        for type in Tag.TagType.allCases {
            if let tagsOfType = groupedTags[type], !tagsOfType.isEmpty {
                result.append(contentsOf: tagsOfType)
            }
        }
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                    .frame(width: 12, height: 12)
                Text(type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(tags.count)")
                    .font(.caption)
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
                    .frame(width: 12, height: 12)
                
                Spacer()
                
                if tag.hasCoordinates {
                    Image(systemName: "location.fill")
                        .font(.body)
                        .foregroundColor(.red)
                }
            }
            
            Text(tag.displayName)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            
            if tag.hasCoordinates, let lat = tag.latitude, let lon = tag.longitude {
                Text("\(String(format: "%.4f", lat)), \(String(format: "%.4f", lon))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.from(tagType: tag.type).opacity(isHighlighted ? 0.3 : 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            Color.from(tagType: tag.type).opacity(isHighlighted ? 0.8 : 0.3), 
                            lineWidth: isHighlighted ? 2 : 1
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
                .font(.body)
                .foregroundColor(.secondary)
            
            Text("为这个节点添加标签来更好地组织和记忆")
                .font(.caption)
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
        let allTags = currentNode.tags
        let locationTypeTags = allTags.filter { isLocationTag($0) }
        let locationWithCoords = currentNode.locationTags
        
        print("🔍 DetailPanel调试:")
        print("🔍 节点: \(currentNode.text)")
        print("🔍 所有标签数量: \(allTags.count)")
        print("🔍 location类型标签数量: \(locationTypeTags.count)")
        print("🔍 有坐标的location标签数量: \(locationWithCoords.count)")
        
        for tag in locationTypeTags {
            print("🔍 location标签: \(tag.value), 类型: \(tag.type.rawValue), 有坐标: \(tag.hasCoordinates)")
            print("🔍   纬度: \(tag.latitude?.description ?? "nil"), 经度: \(tag.longitude?.description ?? "nil")")
        }
        
        return locationWithCoords
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
                        Text("现有地点标签: \(locationTagsWithoutCoords.map { $0.displayName }.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(Color.blue)
                            .multilineTextAlignment(.center)
                        
                        VStack(spacing: 8) {
                            Text("请使用以下格式添加坐标信息：")
                                .font(.caption)
                                .foregroundColor(Color.secondary)
                            
                            // 生成示例命令
                            let exampleCommands = locationTagsWithoutCoords.map { tag in
                                "loc @39.9042,116.4074[\(tag.displayName)]"
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
                            tag.displayName,
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
                    if let firstTag = locationTags.first {
                        let newRegion = MKCoordinateRegion(
                            center: CLLocationCoordinate2D(
                                latitude: firstTag.latitude!,
                                longitude: firstTag.longitude!
                            ),
                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                        )
                        region = newRegion
                        cameraPosition = .region(newRegion)
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
            
            Text(tag.displayName)
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
        self.label = tag.displayName
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
    
    private func calculateGraphData(for node: Node) -> (nodes: [NodeGraphNode], edges: [NodeGraphEdge]) {
        let nodes = calculateGraphNodes(for: node)
        var edges: [NodeGraphEdge] = []
        let centerNode = nodes.first { $0.isCenter }!
        
        // 为每个标签节点创建与中心节点的连接
        for node in nodes where !node.isCenter {
            if let tag = node.tag {
                edges.append(NodeGraphEdge(
                    from: centerNode,
                    to: node,
                    relationshipType: tag.type.displayName
                ))
            }
        }
        
        return (nodes: nodes, edges: edges)
    }
    
    private func calculateGraphNodes(for node: Node) -> [NodeGraphNode] {
        var nodes: [NodeGraphNode] = []
        var addedTagKeys: Set<String> = []
        
        // 添加中心节点（当前节点）
        nodes.append(NodeGraphNode(node: node, isCenter: true))
        
        // 添加当前节点的所有标签作为节点（去重）
        for tag in node.tags {
            let tagKey = "\(tag.type.rawValue):\(tag.value)"
            if !addedTagKeys.contains(tagKey) {
                nodes.append(NodeGraphNode(tag: tag))
                addedTagKeys.insert(tagKey)
            }
        }
        
        // 添加位置标签作为节点（去重）
        for locationTag in node.locationTags {
            let tagKey = "\(locationTag.type.rawValue):\(locationTag.value)"
            if !addedTagKeys.contains(tagKey) {
                nodes.append(NodeGraphNode(tag: locationTag))
                addedTagKeys.insert(tagKey)
            }
        }
        
        return nodes
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