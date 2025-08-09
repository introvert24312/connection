import SwiftUI
import CoreLocation
import MapKit
import UniformTypeIdentifiers
import AppKit

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
    @Environment(\.colorScheme) private var colorScheme
    @State private var markdownText: String = ""
    @StateObject private var imageManager = NodeImageManager.shared
    @State private var saveTask: Task<Void, Never>?
    @State private var isEditing: Bool = false
    @State private var vditorCoordinator: VditorWebView.Coordinator?
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
        let _ = print("🚨🚨🚨 NodeDetailView RENDERING - Node: \(currentNode.text)")
        
        VStack(alignment: .leading, spacing: 8) {
            // 简洁的标题栏
            HStack {
                Text(currentNode.text)
                    .font(.title2)
                    .fontWeight(.semibold)
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
            }
            .padding(.horizontal)


            // Vditor 即时渲染编辑器（Typora 体验）
            VditorWebView(
                markdown: markdownText,
                nodeId: currentNode.id.uuidString,
                onChange: { newValue in
                    print("🚨🚨🚨 VDITOR ONCHANGE CALLED - length: \(newValue.count)")
                    print("🚨🚨🚨 CONTENT PREVIEW: \(newValue.prefix(200))")
                    print("🚨🚨🚨 CURRENT NODE: \(currentNode.text) (\(currentNode.id))")
                    instantSave(newValue)
                    markdownText = newValue
                },
                coordinatorBinding: $vditorCoordinator
            )
            .id("vditor-\(currentNode.id)-\(colorScheme)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onChange(of: currentNode.id) { oldId, newId in
            print("🔄 节点ID发生变化: \(oldId) -> \(newId)")
            
            // 等待当前保存任务完成，避免切换时保存被掐断
            if let currentSaveTask = saveTask {
                Task {
                    await currentSaveTask.value
                    print("✅ 等待之前的保存任务完成")
                    await MainActor.run {
                        loadMarkdown()
                        // 确保编辑器内容也重新加载
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            vditorCoordinator?.setMarkdown(markdownText, forceUpdate: true)
                        }
                    }
                }
            } else {
                loadMarkdown()
                // 确保编辑器内容也重新加载
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    vditorCoordinator?.setMarkdown(markdownText, forceUpdate: true)
                }
            }
        }
        .onChange(of: node.id) { oldId, newId in
            print("🔄 传入节点ID发生变化: \(oldId) -> \(newId)")
            // 当传入的node发生变化时，也要重新加载内容
            loadMarkdown()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                vditorCoordinator?.setMarkdown(markdownText, forceUpdate: true)
            }
        }
        .onChange(of: isEditing) { _, newValue in
            if newValue {
                // 静默进入编辑模式
            }
        }
        .onChange(of: colorScheme) { _, newValue in
            print("🎨 主题变化: \(newValue == .dark ? "dark" : "light")")
            // 主题变化时强制刷新 Vditor 内容以应用新主题
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                vditorCoordinator?.setMarkdown(markdownText, forceUpdate: true)
            }
        }
        .onKeyPress(.init("/"), phases: .down) { keyPress in
            if keyPress.modifiers == .command {
                // Command+/: 切换Vditor编辑模式
                print("🎯 Command+/ pressed - toggling Vditor mode")
                vditorCoordinator?.toggleMode()
                return .handled
            }
            return .ignored
        }
        .onDisappear {
            // 清理异步任务
            saveTask?.cancel()
        }
    }
    
    private func loadMarkdown() {
        loadMarkdownFromFile()
    }
    
    private func saveMarkdown() {
        Task { @MainActor in
            store.updateNodeMarkdown(currentNode.id, markdown: markdownText)
        }
    }
    
    private func instantSave(_ newValue: String) {
        print("🚨🚨🚨 INSTANT SAVE CALLED!")
        print("🚨🚨🚨 NODE: \(currentNode.text)")
        print("🚨🚨🚨 CONTENT LENGTH: \(newValue.count)")
        
        // 取消之前的任务避免重复保存
        saveTask?.cancel()
        
        // 立即更新内存中的数据
        store.updateNodeMarkdown(currentNode.id, markdown: newValue)
        
        // 立即异步保存到文件
        saveTask = Task {
            await saveMarkdownToFile(newValue)
        }
    }
    
    private func saveMarkdownToFile(_ content: String) async {
        print("🚨🚨🚨 SAVING MARKDOWN FILE...")
        
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ 无法获取Documents目录")
            return
        }
        
        // 创建WordTagger文件夹
        let wordTaggerURL = documentsURL.appendingPathComponent("WordTagger")
        let markdownURL = wordTaggerURL.appendingPathComponent("Markdown")
        
        do {
            try FileManager.default.createDirectory(at: markdownURL, withIntermediateDirectories: true)
            
            // 创建安全的文件名（移除特殊字符）
            let safeFileName = currentNode.text
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
                .replacingOccurrences(of: "?", with: "_")
                .replacingOccurrences(of: "*", with: "_")
                .replacingOccurrences(of: "\"", with: "_")
                .replacingOccurrences(of: "<", with: "_")
                .replacingOccurrences(of: ">", with: "_")
                .replacingOccurrences(of: "|", with: "_")
            
            let fileURL = markdownURL.appendingPathComponent("\(safeFileName).md")
            
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            
            print("✅ Markdown文件已保存: \(fileURL.path)")
            
        } catch {
            print("❌ 保存Markdown文件失败: \(error)")
        }
    }
    
    private func loadMarkdownFromFile() {
        print("🚨🚨🚨 LOADING MARKDOWN FILE...")
        
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ 无法获取Documents目录")
            return
        }
        
        let wordTaggerURL = documentsURL.appendingPathComponent("WordTagger")
        let markdownURL = wordTaggerURL.appendingPathComponent("Markdown")
        
        // 创建安全的文件名
        let safeFileName = currentNode.text
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "*", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "<", with: "_")
            .replacingOccurrences(of: ">", with: "_")
            .replacingOccurrences(of: "|", with: "_")
        
        let fileURL = markdownURL.appendingPathComponent("\(safeFileName).md")
        
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            markdownText = content
            print("✅ 从文件加载Markdown内容: \(content.count)字符")
            
            // 确保编辑器也更新内容
            DispatchQueue.main.async {
                print("📝 loadMarkdownFromFile: 设置编辑器内容")
                vditorCoordinator?.setMarkdown(content, forceUpdate: true)
            }
        } catch {
            print("📄 文件不存在或无法读取，使用默认内容: \(error)")
            // 文件不存在时使用Node的默认markdown内容
            let defaultContent = currentNode.markdown
            markdownText = defaultContent
            
            // 确保编辑器也更新默认内容
            DispatchQueue.main.async {
                print("📝 loadMarkdownFromFile: 设置默认内容到编辑器")
                vditorCoordinator?.setMarkdown(defaultContent, forceUpdate: true)
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
    @Environment(\.colorScheme) private var colorScheme
    let markdown: String
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        // macOS: 彻底透明
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.setValue(false, forKey: "opaque")
        
        // Force initial appearance to match current system theme BEFORE first load
        let isDark = (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        webView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Sync WKWebView appearance with SwiftUI colorScheme before (re)loading content
        let isDarkNow = (colorScheme == .dark)
        let needsAppearanceUpdate = ((webView.appearance?.name == .darkAqua) != isDarkNow)
        if needsAppearanceUpdate {
            webView.appearance = NSAppearance(named: isDarkNow ? .darkAqua : .aqua)
            // Ask the page to re-render with the new theme if it exposes a hook
            webView.evaluateJavaScript("typeof onTheme==='function' && onTheme()")
        }
        
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
            .replacingOccurrences(of: "'", with: "\"")
    }
    
    private func generateHTML(from markdown: String) -> String {
        // 处理本地图片路径并转义
        let processed = processLocalImages(in: markdown)
        let escaped = escapeForJavaScript(processed)

        return #"""
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <title>Mermaid Preview</title>

          <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
          <script src="Resources/mermaid/mermaid.min.js"></script>

          <style>
            :root{ --bg:transparent; --fg:#1f2328; --muted:#6e7781; --code-bg:#f6f8fa; --code-fg:#1f2328; --s1:4px; --s2:8px; --s3:12px; --s4:16px; }
            @media (prefers-color-scheme: dark){ :root{ --fg:#c9d1d9; --muted:#9aa0a6; --code-bg:#2d2d2d; --code-fg:#e6e6e6; } }
            html,body{ color-scheme:light dark; margin:0; padding:var(--s4); background:var(--bg); color:var(--fg); font:14px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif; }
            #content{ opacity:0; transition:opacity .2s ease; }
            #content.ready{ opacity:1; }
            pre{ background:var(--code-bg); color:var(--code-fg); border-radius:6px; padding:var(--s4); overflow:auto; }

            .mermaid{ display:block; margin:var(--s4) 0; padding:0; text-align:center; overflow:visible; background:transparent; }
            #content, .mermaid, .mmd-block{ position:relative; z-index:auto; }
            .mermaid>svg{ display:block; width:100%; max-width:100%; height:auto; block-size:auto; }

            /* fix label clipping with htmlLabels */
            .mermaid .label foreignObject{ overflow:visible; }
            .mermaid .label foreignObject>div{ display:block; padding:2px 4px; white-space:normal; word-break:break-word; line-height:1.4; }
          </style>
        </head>
        <body>
          <div id="content"></div>
          <script>
            function currentMermaidConfig(){
              const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
              const shared = {
                startOnLoad: false,
                securityLevel: 'loose',
                fontFamily: "-apple-system, 'SF Pro Text', 'Segoe UI', Arial, sans-serif",
                flowchart: { useMaxWidth: true, htmlLabels: true, curve: 'basis', padding: 8, nodeSpacing: 40, rankSpacing: 40 }
              };
              return isDark ? {
                ...shared,
                theme: 'dark',
                themeVariables: {
                  primaryColor:'#161b22', primaryTextColor:'#c9d1d9', primaryBorderColor:'#30363d',
                  lineColor:'#58a6ff', background:'#0d1117', mainBkg:'#161b22', secondaryColor:'#21262d',
                  fontSize:'16px', lineHeight:'1.4'
                }
              } : {
                ...shared,
                theme: 'default',
                themeVariables: {
                  primaryColor:'#ffffff', primaryTextColor:'#24292f', primaryBorderColor:'#d0d7de',
                  lineColor:'#0969da', tertiaryColor:'#f6f8fa', background:'#ffffff',
                  fontSize:'16px', lineHeight:'1.4'
                }
              };
            }

            function containerFix(){
              document.querySelectorAll('.mermaid,.mmd-block').forEach(div=>{
                div.style.position='relative'; div.style.zIndex='auto';
                div.style.removeProperty('transform'); div.style.removeProperty('min-width'); div.style.removeProperty('min-height');
              });
              document.querySelectorAll('.mermaid>svg').forEach(svg=>{
                svg.style.display='block'; svg.style.width='100%'; svg.style.height='auto';
                svg.style.removeProperty('min-width'); svg.style.removeProperty('min-height'); svg.style.removeProperty('transform');
              });
            }

            function mdToHtmlWithMermaid(md){
              const blockRe = /```\s*(mermaid|mmd)[^\n]*\n([\s\S]*?)```/gi;
              let i = 0;
              const html = md.replace(blockRe, (m, lang, code)=>{
                const def = code.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
                return `<div class=\"mermaid\" data-mermaid-def=\"${def}\">Loading diagram ${++i}…</div>`;
              });
              return marked.parse(html);
            }

            function initMermaid(){ window.mermaid.initialize(currentMermaidConfig()); }

            async function renderAll(){
              const list = Array.from(document.querySelectorAll('[data-mermaid-def]'));
              let i = 0;
              for (const el of list){
                const def = el.getAttribute('data-mermaid-def'); if(!def) continue;
                try{
                  const out = await window.mermaid.render('mmd'+(i++), def, el);
                  if (typeof out === 'string') el.innerHTML = out; else if (out && out.svg) { el.innerHTML = out.svg; out.bindFunctions && out.bindFunctions(el); }
                }catch(e){ console.warn('mermaid render error', e); }
              }
              containerFix();
            }

            function setMarkdown(md){
              const host = document.getElementById('content');
              host.innerHTML = mdToHtmlWithMermaid(md||'');
              initMermaid();
              renderAll();
              host.classList.add('ready');
            }

            const mq = window.matchMedia('(prefers-color-scheme: dark)');
            function onTheme(){ initMermaid(); renderAll(); }
            if (mq.addEventListener) mq.addEventListener('change', onTheme); else if (mq.addListener) mq.addListener(onTheme);

            // bootstrap with Swift content
            setMarkdown(`\
            
            \#(escaped)
            
            `);
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

struct VditorWebView: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    var markdown: String
    var nodeId: String
    var onChange: (String) -> Void
    @Binding var coordinatorBinding: Coordinator?
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(onChange: onChange)
        DispatchQueue.main.async {
            coordinatorBinding = coordinator
        }
        return coordinator
    }
    
    class VditorCoordinator {
        weak var coordinator: Coordinator?
        
        init(_ coordinator: Coordinator) {
            self.coordinator = coordinator
        }
        
        func toggleMode() {
            coordinator?.toggleMode()
        }
        
        func updateContent(_ content: String) {
            coordinator?.setMarkdown(content)
        }
    }
    
    func makeNSView(context: Context) -> WKWebView {
        print("🚨🚨🚨 VditorWebView makeNSView CALLED")
        
        let config = WKWebViewConfiguration()
        let uc = WKUserContentController()
        uc.add(context.coordinator, name: "bridge")
        config.userContentController = uc
        
        let webView = WKWebView(frame: .zero, configuration: config)
        
        // Force initial appearance to match current system theme BEFORE first load
        let isDark = (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        webView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        
        let html = generateVditorHTML()
        print("🚨🚨🚨 Loading Vditor HTML, length: \(html.count)")
        webView.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
        context.coordinator.webView = webView
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        let isDarkNow = (colorScheme == .dark)
        let needsAppearanceUpdate = ((webView.appearance?.name == .darkAqua) != isDarkNow)
        if needsAppearanceUpdate {
            webView.appearance = NSAppearance(named: isDarkNow ? .darkAqua : .aqua)
            // Preferred hook for the editor (if defined in the page)
            webView.evaluateJavaScript("window.__applyNativeTheme && window.__applyNativeTheme(\(isDarkNow ? "true" : "false"))")
            // Fallback hook (same name as Mermaid page)
            webView.evaluateJavaScript("typeof onTheme==='function' && onTheme()")
        }
        
        context.coordinator.currentNodeId = nodeId
        context.coordinator.setMarkdown(markdown)
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        private let onChange: (String) -> Void
        private var lastSyncedValue: String = ""
        private var isUpdatingFromSwift = false
        var currentNodeId: String = ""
        
        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            print("🔍 Received message: \(message.body)")
            
            guard let dict = message.body as? [String: Any],
                  let type = dict["type"] as? String else {
                print("❌ Invalid message format: \(message.body)")
                return
            }
            
            switch type {
            case "change":
                if !isUpdatingFromSwift,
                   let value = dict["value"] as? String {
                    print("📝 Vditor content changed - length: \(value.count), preview: \(value.prefix(50))...")
                    print("📝 Calling onChange callback...")
                    lastSyncedValue = value
                    onChange(value)
                    print("📝 onChange callback completed")
                } else {
                    print("⚠️ Skipping change - isUpdatingFromSwift: \(isUpdatingFromSwift)")
                }
            case "ready":
                print("✅ Vditor ready in DetailPanel")
                // 编辑器准备好后，同步当前值
                if !lastSyncedValue.isEmpty {
                    print("📥 Syncing existing value to editor: \(lastSyncedValue.prefix(50))...")
                    setMarkdown(lastSyncedValue)
                } else {
                    print("📄 No existing value to sync")
                }
            case "modeChanged":
                if let mode = dict["mode"] as? String {
                    print("🔄 Vditor mode changed to: \(mode)")
                    DispatchQueue.main.async {
                        // 这里可以更新UI状态，比如更新编辑状态指示
                    }
                }
            default:
                print("❓ Unknown message type: \(type)")
                break
            }
        }
        
        func setMarkdown(_ markdown: String, forceUpdate: Bool = false) {
            if !forceUpdate && markdown == lastSyncedValue {
                print("📝 Skipping markdown update - same content: \(markdown.prefix(50))")
                return
            }
            
            print("📝 Setting markdown - length: \(markdown.count), preview: \(markdown.prefix(50))")
            
            isUpdatingFromSwift = true
            lastSyncedValue = markdown
            
            let escaped = markdown
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            let js = "window.vditor?.setValue(\"\(escaped)\");"
            
            // 确保编辑器已经准备好
            webView?.evaluateJavaScript("window.vditor !== undefined") { result, error in
                if let isReady = result as? Bool, isReady {
                    self.webView?.evaluateJavaScript(js) { _, evalError in
                        if let evalError = evalError {
                            print("❌ Failed to set markdown: \(evalError)")
                        } else {
                            print("✅ Successfully set markdown")
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.isUpdatingFromSwift = false
                        }
                    }
                } else {
                    print("⚠️ Vditor not ready, retrying in 0.2s...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.webView?.evaluateJavaScript(js) { _, _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.isUpdatingFromSwift = false
                            }
                        }
                    }
                }
            }
        }
        
        func toggleMode() {
            webView?.evaluateJavaScript("window.toggleVditorMode && window.toggleVditorMode();") { _, error in
                if let error = error {
                    print("❌ Failed to toggle Vditor mode: \(error)")
                } else {
                    print("✅ Vditor mode toggle called")
                }
            }
        }
    }
    
    private func generateVditorHTML() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/vditor@3.10.4/dist/index.css">
            <style>
                /* 移除Tanda主题加载 */
            </style>
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    background: transparent;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Helvetica Neue', Arial, 'Noto Sans', sans-serif;
                }
                #vditor {
                    height: 100vh;
                    border: none !important;
                }
                
                /* 全局移除所有Vditor相关边框 */
                .vditor, .vditor * {
                    border: none !important;
                    outline: none !important;
                    box-shadow: none !important;
                }
                
                /* Github官方浅色主题 - 移除边框 */
                .vditor {
                    --panel-background-color: #ffffff;
                    --textarea-background-color: #ffffff;
                    --toolbar-background-color: #f6f8fa;
                    --border-color: transparent;
                    --text-color: #24292f !important;
                    --second-color: #24292f !important;
                    --count-color: #24292f !important;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Helvetica Neue', Arial, sans-serif;
                    border: none !important;
                }
                
                /* 强制浅色主题文字为深色 - 只在浅色模式下生效 */
                @media (prefers-color-scheme: light) {
                    .vditor .vditor-ir {
                        color: #24292f !important;
                    }
                    
                    .vditor .vditor-ir * {
                        color: #24292f !important;
                    }
                }
                
                /* Github官方工具栏 - 移除边框 */
                .vditor-toolbar {
                    border: none !important;
                    background-color: #f6f8fa !important;
                    padding: 8px 16px !important;
                }
                
                /* Github官方编辑区域 - 透明背景 */
                .vditor-ir {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Helvetica Neue', Arial, sans-serif !important;
                    font-size: 18px !important;
                    line-height: 1.7 !important;
                    color: #24292f !important;
                    background-color: transparent !important;
                }
                
                /* 浅色主题全局字体大小强制设置 - 只在浅色模式下生效 */
                @media (prefers-color-scheme: light) {
                    .vditor-ir *, .vditor-ir p, .vditor-ir div, .vditor-ir span {
                        font-size: 18px !important;
                        color: #24292f !important;
                    }
                    
                    /* 浅色主题标题字体大小 */
                    .vditor-ir h1 {
                        font-size: 32px !important;
                        font-weight: 700 !important;
                        color: #24292f !important;
                    }
                    
                    .vditor-ir h2 {
                        font-size: 28px !important;
                        font-weight: 600 !important;
                        color: #24292f !important;
                    }
                    
                    .vditor-ir h3 {
                        font-size: 24px !important;
                        font-weight: 600 !important;
                        color: #24292f !important;
                    }
                    
                    .vditor-ir h4, .vditor-ir h5, .vditor-ir h6 {
                        font-size: 20px !important;
                        font-weight: 600 !important;
                        color: #24292f !important;
                    }
                    
                    /* 浅色主题 - Mermaid节点强制放大 - 超高优先级 */
                    html body div .vditor-ir .mermaid svg rect,
                    html body div .vditor-ir .mermaid svg circle,
                    html body div .vditor-ir .mermaid svg ellipse,
                    html body div .vditor-ir .mermaid svg polygon,
                    html body div .vditor-ir .mermaid rect,
                    html body div .vditor-ir .mermaid circle,
                    html body div .vditor-ir .mermaid ellipse,
                    html body div .vditor-ir .mermaid polygon,
                    html body div .mermaid svg rect,
                    html body div .mermaid svg circle,
                    html body div .mermaid svg ellipse,
                    html body div .mermaid svg polygon,
                    html body div .mermaid rect,
                    html body div .mermaid circle,
                    html body div .mermaid ellipse,
                    html body div .mermaid polygon,
                    html body .mermaid svg rect,
                    html body .mermaid svg circle,
                    html body .mermaid svg ellipse,
                    html body .mermaid svg polygon,
                    html body .mermaid rect,
                    html body .mermaid circle,
                    html body .mermaid ellipse,
                    html body .mermaid polygon {
                        transform: scale(1.4) !important;
                        transform-origin: center !important;
                        stroke-width: 4px !important;
                        stroke: #333 !important;
                    }
                    
                    html body div .vditor-ir .mermaid,
                    html body div .mermaid,
                    html body .mermaid {
                        transform: scale(1.5) !important;
                        transform-origin: center !important;
                        min-width: 800px !important;
                        min-height: 600px !important;
                        margin: 40px auto !important;
                        padding: 50px !important;
                    }
                }
                
                /* Clean dark theme - rely on Mermaid theme config for diagrams */
                @media (prefers-color-scheme: dark) {
                    :root {
                        --of-theme-color: #ff9100;
                        --of-darkest-color: #2d2d2d;
                        --of-darker-color: #1e1e1e;
                        --of-dark-color: #292929;
                        --of-strong: white;
                        --of-strong-code: #00ffa6;
                        --of-text-color: #c6c5b8;
                        --bg-color: var(--of-darker-color);
                        --text-color: var(--of-text-color);
                    }
                    
                    .vditor {
                        --panel-background-color: var(--of-darker-color);
                        --textarea-background-color: var(--of-darker-color);
                        --toolbar-background-color: var(--of-darkest-color);
                        --border-color: transparent;
                        --text-color: var(--of-text-color);
                        --second-color: var(--of-text-color);
                        --count-color: var(--of-text-color);
                        border: none !important;
                        color: var(--of-text-color);
                        background: var(--of-darker-color);
                    }
                    
                    .vditor-toolbar {
                        border: none !important;
                        background-color: var(--of-darkest-color) !important;
                        color: var(--of-text-color);
                    }
                    
                    .vditor-ir {
                        color: var(--of-text-color) !important;
                        background-color: transparent !important;
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Helvetica Neue', Arial, sans-serif;
                        line-height: 1.7;
                    }
                    
                    /* 暗色主题文字样式 */
                    .vditor-ir *, 
                    .vditor-ir p, 
                    .vditor-ir div:not(.mermaid):not([class*="mermaid"]), 
                    .vditor-ir span:not(.mermaid *),
                    .vditor-ir li, 
                    .vditor-ir blockquote, 
                    .vditor-ir code:not(.mermaid *),
                    .vditor-ir table,
                    .vditor-ir td,
                    .vditor-ir th {
                        color: var(--of-text-color) !important;
                    }
                    
                    /* 标题样式 */
                    .vditor-ir h1,
                    .vditor-ir h2,
                    .vditor-ir h3,
                    .vditor-ir h4,
                    .vditor-ir h5,
                    .vditor-ir h6 {
                        color: var(--of-strong) !important;
                        font-weight: bold;
                    }
                    
                    .vditor-ir h1 {
                        font-size: 2.5rem !important;
                        border-bottom: 1px solid #383838;
                    }
                    
                    .vditor-ir h2 {
                        font-size: 1.63rem !important;
                    }
                    
                    .vditor-ir h3 {
                        font-size: 1.6rem !important;
                    }
                    
                    .vditor-ir h4 {
                        font-size: 1.12rem !important;
                    }
                    
                    .vditor-ir h5 {
                        font-size: 0.97rem !important;
                    }
                    
                    .vditor-ir h6 {
                        font-size: 0.93rem !important;
                        color: #d3d3d3 !important;
                    }
                    
                    /* 强调文字 */
                    .vditor-ir strong,
                    .vditor-ir b {
                        color: var(--of-strong) !important;
                    }
                    
                    /* 代码样式 */
                    .vditor-ir code {
                        background: rgba(255, 255, 255, 0.05) !important;
                        color: var(--of-strong-code) !important;
                        border-radius: 0.2rem;
                    }
                    
                    /* 引用样式 */
                    .vditor-ir blockquote {
                        border: 1px solid var(--of-theme-color);
                        background-color: var(--of-dark-color);
                        border-radius: 8px;
                        padding: 20px;
                        color: white !important;
                    }
                    
                    /* 链接样式 */
                    .vditor-ir a {
                        color: var(--of-theme-color) !important;
                        text-decoration: underline;
                    }
                    
                    .vditor-ir a:hover {
                        color: white !important;
                    }
                    
                    /* Mermaid图表暗色主题强制覆盖 - 使用最高优先级 */
                    
                    /* 1. Mermaid容器整体背景和尺寸 - 超级强制 */
                    .vditor-ir .mermaid,
                    .vditor-ir .mermaid > svg,
                    .vditor-ir div[data-processed-by="mermaid"],
                    div.mermaid,
                    .mermaid {
                        background: var(--of-darker-color) !important;
                        background-color: var(--of-darker-color) !important;
                        border-radius: 12px !important;
                        padding: 50px !important;
                        margin: 40px 0 !important;
                        width: 100% !important;
                        min-width: 800px !important;
                        min-height: 600px !important;
                        height: auto !important;
                        max-width: none !important;
                        display: block !important;
                        overflow: visible !important;
                        transform: scale(1.5) !important;
                        transform-origin: center !important;
                    }
                    
                    /* 1.1 SVG内部容器尺寸强制放大 */
                    .vditor-ir .mermaid svg,
                    .mermaid svg {
                        width: 100% !important;
                        height: auto !important;
                        min-width: 500px !important;
                        min-height: 400px !important;
                        background: rgba(28, 28, 30, 0.95) !important;
                        background-color: rgba(28, 28, 30, 0.95) !important;
                        transform: scale(1.1) !important;
                    }
                    
                    /* 2. 暗色Mermaid节点 - 直接覆盖所有可能的选择器 */
                    .mermaid * {
                        color: var(--of-text-color) !important;
                    }
                    
                    .mermaid rect,
                    .mermaid circle,
                    .mermaid ellipse,
                    .mermaid polygon {
                        fill: var(--of-dark-color) !important;
                        stroke: var(--of-theme-color) !important;
                        stroke-width: 3px !important;
                        transform: scale(1.3) !important;
                        transform-origin: center !important;
                    }
                    
                    .mermaid text {
                        fill: var(--of-text-color) !important;
                        color: var(--of-text-color) !important;
                        font-size: 16px !important;
                        font-weight: 600 !important;
                    }
                    
                    /* 3. 所有文字元素 - 强制黑色 - 超高优先级 */
                    html body .vditor-ir .mermaid svg text,
                    html body .vditor-ir .mermaid svg .label,
                    html body .vditor-ir .mermaid svg .node .label,
                    html body .vditor-ir .mermaid svg g text,
                    html body .vditor-ir .mermaid svg g .label,
                    html body .vditor-ir .mermaid text,
                    html body .vditor-ir .mermaid .label,
                    html body .vditor-ir .mermaid .node .label,
                    html body .vditor-ir .mermaid .nodeLabel,
                    html body .vditor-ir .mermaid .edgeLabel,
                    html body .vditor-ir .mermaid .cluster-label,
                    html body .vditor-ir .mermaid .titleText,
                    html body .mermaid svg text,
                    html body .mermaid text,
                    html body .mermaid .label,
                    html body .mermaid .nodeLabel,
                    html body .mermaid .edgeLabel {
                        fill: var(--of-text-color) !important;
                        color: var(--of-text-color) !important;
                        font-weight: 600 !important;
                        font-size: 16px !important;
                    }
                    
                    /* 4. 连接线和边框 */
                    .vditor-ir .mermaid svg .edgePath path,
                    .vditor-ir .mermaid svg .flowchart-link,
                    .vditor-ir .mermaid svg .edge-pattern-solid,
                    .vditor-ir .mermaid .edgePath .path,
                    .vditor-ir .mermaid .flowchart-link,
                    .vditor-ir .mermaid .edge-pattern-solid,
                    .vditor-ir .mermaid path.link,
                    .vditor-ir .mermaid line {
                        stroke: rgba(142, 142, 147, 1) !important;
                        stroke-width: 2px !important;
                        fill: none !important;
                    }
                    
                    /* 5. 箭头标记 */
                    .vditor-ir .mermaid svg marker polygon,
                    .vditor-ir .mermaid svg marker path,
                    .vditor-ir .mermaid marker polygon,
                    .vditor-ir .mermaid marker path {
                        fill: rgba(142, 142, 147, 1) !important;
                        stroke: rgba(142, 142, 147, 1) !important;
                    }
                    
                    /* 6. 特殊图表类型优化 */
                    /* 时序图 */
                    .vditor-ir .mermaid .actor,
                    .vditor-ir .mermaid .activation {
                        fill: rgba(58, 58, 60, 1) !important;
                        stroke: rgba(142, 142, 147, 1) !important;
                    }
                    
                    .vditor-ir .mermaid .actor-line,
                    .vditor-ir .mermaid .messageLine0,
                    .vditor-ir .mermaid .messageLine1 {
                        stroke: rgba(142, 142, 147, 1) !important;
                    }
                    
                    /* 甘特图 */
                    .vditor-ir .mermaid .section0,
                    .vditor-ir .mermaid .section1,
                    .vditor-ir .mermaid .section2,
                    .vditor-ir .mermaid .section3,
                    .vditor-ir .mermaid .task0,
                    .vditor-ir .mermaid .task1,
                    .vditor-ir .mermaid .task2,
                    .vditor-ir .mermaid .task3 {
                        fill: rgba(58, 58, 60, 1) !important;
                        stroke: rgba(142, 142, 147, 1) !important;
                    }
                    
                    /* 7. 强制覆盖任何内联样式 - 最高优先级 */
                    .vditor-ir .mermaid svg[style*="background"],
                    .vditor-ir .mermaid svg[style*="background-color"] {
                        background: rgba(28, 28, 30, 0.95) !important;
                        background-color: rgba(28, 28, 30, 0.95) !important;
                    }
                    
                    /* 8. 运行时动态样式覆盖 - 针对Mermaid生成的具体class */
                    .vditor-ir .mermaid .nodeLabel,
                    .vditor-ir .mermaid .cluster .nodeLabel,
                    .vditor-ir .mermaid g.label text,
                    .vditor-ir .mermaid g.node text,
                    .vditor-ir .mermaid g.cluster text,
                    .vditor-ir .mermaid .edgeLabels .edgeLabel text,
                    .vditor-ir .mermaid .edgeLabel text {
                        fill: rgba(235, 235, 245, 1) !important;
                        color: rgba(235, 235, 245, 1) !important;
                    }
                    
                    /* 9. JavaScript运行时强制覆盖 */
                    .mermaid-override-styles rect { fill: var(--of-dark-color) !important; }
                    .mermaid-override-styles circle { fill: var(--of-dark-color) !important; }
                    .mermaid-override-styles ellipse { fill: var(--of-dark-color) !important; }
                    .mermaid-override-styles polygon { fill: var(--of-dark-color) !important; }
                }
                
                /* === 终极强制覆盖规则 - 最高优先级 === */
                
                /* 浅色模式：超高优先级强制放大 */
                html body div.vditor div.vditor-ir div.mermaid svg rect,
                html body div.vditor div.vditor-ir div.mermaid svg circle,
                html body div.vditor div.vditor-ir div.mermaid svg ellipse,
                html body div.vditor div.vditor-ir div.mermaid svg polygon,
                html body div.vditor div.vditor-ir div.mermaid rect[style],
                html body div.vditor div.vditor-ir div.mermaid circle[style],
                html body div.vditor div.vditor-ir div.mermaid ellipse[style],
                html body div.vditor div.vditor-ir div.mermaid polygon[style] {
                    transform: scale(1.6) !important;
                    transform-origin: center !important;
                    stroke-width: 4px !important;
                    stroke: #333333 !important;
                }
                
                /* 浅色模式：整体容器强制放大 */
                html body div.vditor div.vditor-ir div.mermaid {
                    transform: scale(1.8) !important;
                    transform-origin: center !important;
                    min-width: 900px !important;
                    min-height: 700px !important;
                    padding: 60px !important;
                    margin: 50px auto !important;
                }
                
                /* 暗色模式：超高优先级强制颜色 */
                @media (prefers-color-scheme: dark) {
                    html body div.vditor div.vditor-ir div.mermaid svg rect[style],
                    html body div.vditor div.vditor-ir div.mermaid svg circle[style],
                    html body div.vditor div.vditor-ir div.mermaid svg ellipse[style],
                    html body div.vditor div.vditor-ir div.mermaid svg polygon[style],
                    html body div.vditor div.vditor-ir div.mermaid rect,
                    html body div.vditor div.vditor-ir div.mermaid circle,
                    html body div.vditor div.vditor-ir div.mermaid ellipse,
                    html body div.vditor div.vditor-ir div.mermaid polygon {
                        fill: #292929 !important;
                        stroke: #ff9100 !important;
                        stroke-width: 3px !important;
                        transform: scale(1.4) !important;
                        transform-origin: center !important;
                    }
                    
                    html body div.vditor div.vditor-ir div.mermaid svg text[style],
                    html body div.vditor div.vditor-ir div.mermaid text {
                        fill: #c6c5b8 !important;
                        color: #c6c5b8 !important;
                        font-size: 16px !important;
                        font-weight: 600 !important;
                    }
                }
                
                /* SVG容器最高优先级覆盖 */
                html body div.vditor div.vditor-ir div.mermaid > svg {
                    width: 100% !important;
                    height: auto !important;
                    max-width: none !important;
                    min-width: 800px !important;
                    min-height: 600px !important;
                    transform: scale(1.2) !important;
                }
            </style>
        </head>
        <body>
            <div id="vditor"></div>
            
            <script src="https://cdn.jsdelivr.net/npm/vditor@3.10.4/dist/index.min.js"></script>
            <script>
                let vditor;
                
                // 检测主题
                const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
                
                // 初始化 Vditor (IR 模式 = 即时渲染，SV 模式 = 源码分栏)
                let currentMode = 'ir'; // 默认即时渲染模式
                vditor = new Vditor('vditor', {
                    mode: currentMode, // 关键：即时渲染模式，类似 Typora
                    theme: 'classic', // 使用经典主题
                    value: '',
                    width: '100%',
                    height: '100vh',
                    cache: { enable: false },
                    preview: {
                        theme: {
                            current: isDark ? 'dark' : 'github', // GitHub风格主题
                            list: {
                                'github': 'GitHub',
                                'dark': 'GitHub Dark'
                            }
                        },
                        hljs: {
                            enable: true,
                            style: isDark ? 'github-dark' : 'github'
                        },
                        mermaid: {
                            theme: isDark ? 'dark' : 'default',
                            startOnLoad: false,
                            securityLevel: 'loose',
                            fontFamily: "-apple-system, 'SF Pro Text', 'Segoe UI', Arial, sans-serif",
                            flowchart: { 
                                useMaxWidth: true, 
                                htmlLabels: true, 
                                curve: 'basis', 
                                padding: 12, 
                                nodeSpacing: 50, 
                                rankSpacing: 60,
                                diagramPadding: 8
                            },
                            themeVariables: isDark ? {
                                // 主要背景和颜色
                                background: '#0d1117',
                                primaryColor: '#1f2937',
                                primaryTextColor: '#e5e7eb',
                                primaryBorderColor: '#374151',
                                
                                // 次要颜色
                                secondaryColor: '#374151',
                                tertiaryColor: '#4b5563',
                                
                                // 线条和连接
                                lineColor: '#60a5fa',
                                edgeLabelBackground: '#1f2937',
                                
                                // 节点背景
                                mainBkg: '#1f2937',
                                nodeBkg: '#1f2937',
                                clusterBkg: '#374151',
                                
                                // 文本
                                nodeTextColor: '#e5e7eb',
                                textColor: '#e5e7eb',
                                labelTextColor: '#e5e7eb',
                                loopTextColor: '#e5e7eb',
                                noteTextColor: '#e5e7eb',
                                activationTextColor: '#e5e7eb',
                                
                                // 高对比度的活跃元素
                                fillType0: '#3b82f6',
                                fillType1: '#10b981',
                                fillType2: '#f59e0b',
                                fillType3: '#ef4444',
                                fillType4: '#8b5cf6',
                                fillType5: '#06b6d4',
                                fillType6: '#84cc16',
                                fillType7: '#f97316',
                                
                                // 字体设置
                                fontSize: '16px',
                                fontFamily: "-apple-system, 'SF Pro Text', 'Segoe UI', Arial, sans-serif",
                                lineHeight: '1.5'
                            } : {
                                primaryColor: '#ffffff',
                                primaryTextColor: '#24292f',
                                primaryBorderColor: '#d0d7de',
                                lineColor: '#0969da',
                                tertiaryColor: '#f6f8fa',
                                background: '#ffffff',
                                mainBkg: '#ffffff',
                                secondaryColor: '#f6f8fa',
                                fontSize: '16px',
                                fontFamily: "-apple-system, 'SF Pro Text', 'Segoe UI', Arial, sans-serif",
                                lineHeight: '1.5'
                            }
                        }
                    },
                    toolbar: ['outline'], // 只保留大纲展示按钮
                    after() {
                        // 编辑器初始化完成
                        console.log('🚨🚨🚨 VDITOR INITIALIZATION COMPLETE');
                        
                        // Debug: Check if Mermaid config was applied
                        console.log('🎨 DEBUG: Checking Mermaid configuration...');
                        if (window.mermaid) {
                            console.log('🎨 DEBUG: Mermaid exists:', !!window.mermaid);
                            console.log('🎨 DEBUG: Mermaid version:', window.mermaid.version || 'unknown');
                            try {
                                const config = window.mermaid.getConfig && window.mermaid.getConfig();
                                console.log('🎨 DEBUG: Current Mermaid config:', JSON.stringify(config, null, 2));
                            } catch(e) {
                                console.log('🎨 DEBUG: Could not get Mermaid config:', e);
                            }
                        } else {
                            console.log('🎨 DEBUG: Mermaid not found on window object');
                        }
                        
                        // Debug: Check Vditor's preview options
                        console.log('🎨 DEBUG: Vditor preview options:', JSON.stringify(vditor.vditor.options?.preview, null, 2));
                        
                        // Force initialize Mermaid with our theme immediately
                        setTimeout(() => {
                            console.log('🎨 DEBUG: Force initializing Mermaid with custom theme...');
                            const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
                            const customConfig = {
                                theme: isDark ? 'dark' : 'default',
                                startOnLoad: false,
                                securityLevel: 'loose',
                                fontFamily: "-apple-system, 'SF Pro Text', 'Segoe UI', Arial, sans-serif",
                                flowchart: { 
                                    useMaxWidth: true, 
                                    htmlLabels: true, 
                                    curve: 'basis', 
                                    padding: 12, 
                                    nodeSpacing: 50, 
                                    rankSpacing: 60
                                },
                                themeVariables: isDark ? {
                                    background: '#0d1117',
                                    primaryColor: '#1f2937',
                                    primaryTextColor: '#e5e7eb',
                                    primaryBorderColor: '#374151',
                                    secondaryColor: '#374151',
                                    tertiaryColor: '#4b5563',
                                    lineColor: '#60a5fa',
                                    mainBkg: '#1f2937',
                                    nodeBkg: '#1f2937',
                                    nodeTextColor: '#e5e7eb',
                                    textColor: '#e5e7eb',
                                    labelTextColor: '#e5e7eb',
                                    fillType0: '#3b82f6',
                                    fillType1: '#10b981',
                                    fillType2: '#f59e0b',
                                    fillType3: '#ef4444',
                                    fontSize: '16px'
                                } : {
                                    primaryColor: '#ffffff',
                                    primaryTextColor: '#24292f',
                                    primaryBorderColor: '#d0d7de',
                                    lineColor: '#0969da',
                                    tertiaryColor: '#f6f8fa',
                                    background: '#ffffff',
                                    fontSize: '16px'
                                }
                            };
                            
                            if (window.mermaid && window.mermaid.initialize) {
                                window.mermaid.initialize(customConfig);
                                console.log('🎨 DEBUG: Custom Mermaid initialization complete');
                            }
                        }, 500);
                        
                        window.webkit?.messageHandlers?.bridge?.postMessage({
                            type: 'ready'
                        });
                    },
                    input(value) {
                        // 内容变化回调 - 添加防抖以提高性能
                        console.log('🚨🚨🚨 VDITOR INPUT CALLBACK CALLED, value length:', value.length);
                        clearTimeout(window.inputTimeout);
                        window.inputTimeout = setTimeout(() => {
                            console.log('🚨🚨🚨 SENDING MESSAGE TO SWIFT');
                            window.webkit?.messageHandlers?.bridge?.postMessage({
                                type: 'change',
                                value: value
                            });
                        }, 300); // 300ms 防抖
                    }
                });
                
                // 暴露到全局，供 Swift 调用
                window.vditor = vditor;
                
                // 添加模式切换功能
                window.toggleVditorMode = function() {
                    if (vditor) {
                        const currentValue = vditor.getValue();
                        currentMode = currentMode === 'ir' ? 'sv' : 'ir';
                        
                        console.log('🔄 Switching Vditor mode to:', currentMode);
                        
                        // 销毁当前编辑器
                        vditor.destroy();
                        
                        // 重新创建编辑器
                        setTimeout(() => {
                            vditor = new Vditor('vditor', {
                                mode: currentMode,
                                theme: isDark ? 'dark' : 'classic',
                                value: currentValue,
                                width: '100%',
                                height: '100vh',
                                cache: { enable: false },
                                preview: {
                                    theme: {
                                        current: isDark ? 'dark' : 'github',
                                        path: 'https://fastly.jsdelivr.net/npm/vditor@3.10.4/dist/css/content-theme'
                                    },
                                    mermaid: {
                                        theme: isDark ? 'dark' : 'default',
                                        startOnLoad: false,
                                        securityLevel: 'loose',
                                        fontFamily: "-apple-system, 'SF Pro Text', 'Segoe UI', Arial, sans-serif",
                                        flowchart: { 
                                            useMaxWidth: true, 
                                            htmlLabels: true, 
                                            curve: 'basis', 
                                            padding: 12, 
                                            nodeSpacing: 50, 
                                            rankSpacing: 60,
                                            diagramPadding: 8
                                        },
                                        themeVariables: isDark ? {
                                            background: '#0d1117',
                                            primaryColor: '#1f2937',
                                            primaryTextColor: '#e5e7eb',
                                            primaryBorderColor: '#374151',
                                            secondaryColor: '#374151',
                                            tertiaryColor: '#4b5563',
                                            lineColor: '#60a5fa',
                                            edgeLabelBackground: '#1f2937',
                                            mainBkg: '#1f2937',
                                            nodeBkg: '#1f2937',
                                            clusterBkg: '#374151',
                                            nodeTextColor: '#e5e7eb',
                                            textColor: '#e5e7eb',
                                            labelTextColor: '#e5e7eb',
                                            fillType0: '#3b82f6',
                                            fillType1: '#10b981',
                                            fillType2: '#f59e0b',
                                            fillType3: '#ef4444',
                                            fillType4: '#8b5cf6',
                                            fontSize: '16px',
                                            fontFamily: "-apple-system, 'SF Pro Text', 'Segoe UI', Arial, sans-serif",
                                            lineHeight: '1.5'
                                        } : {
                                            primaryColor: '#ffffff',
                                            primaryTextColor: '#24292f',
                                            primaryBorderColor: '#d0d7de',
                                            lineColor: '#0969da',
                                            tertiaryColor: '#f6f8fa',
                                            background: '#ffffff',
                                            mainBkg: '#ffffff',
                                            secondaryColor: '#f6f8fa',
                                            fontSize: '16px',
                                            fontFamily: "-apple-system, 'SF Pro Text', 'Segoe UI', Arial, sans-serif",
                                            lineHeight: '1.5'
                                        }
                                    }
                                },
                                input(value) {
                                    clearTimeout(window.inputTimeout);
                                    window.inputTimeout = setTimeout(() => {
                                        window.webkit?.messageHandlers?.bridge?.postMessage({
                                            type: 'change',
                                            value: value
                                        });
                                    }, 300);
                                }
                            });
                            
                            window.vditor = vditor;
                            
                            window.webkit?.messageHandlers?.bridge?.postMessage({
                                type: 'modeChanged',
                                mode: currentMode
                            });
                        }, 100);
                    }
                };
                
                // 主题切换监听
                window.matchMedia('(prefers-color-scheme: dark)').addListener((e) => {
                    if (vditor) {
                        vditor.setTheme(e.matches ? 'dark' : 'classic');
                    }
                });
                
                // Native theme change handler called from Swift
                window.__applyNativeTheme = function(isDarkMode) {
                    const newTheme = isDarkMode ? 'dark' : 'classic';
                    if (vditor) {
                        vditor.setTheme(newTheme);
                        
                        // Update Vditor's Mermaid config with new theme
                        const mermaidConfig = {
                            theme: isDarkMode ? 'dark' : 'default',
                            startOnLoad: false,
                            securityLevel: 'loose',
                            fontFamily: "-apple-system, 'SF Pro Text', 'Segoe UI', Arial, sans-serif",
                            flowchart: { 
                                useMaxWidth: true, 
                                htmlLabels: true, 
                                curve: 'basis', 
                                padding: 12, 
                                nodeSpacing: 50, 
                                rankSpacing: 60,
                                diagramPadding: 8
                            },
                            themeVariables: isDarkMode ? {
                                background: '#0d1117',
                                primaryColor: '#1f2937',
                                primaryTextColor: '#e5e7eb',
                                primaryBorderColor: '#374151',
                                secondaryColor: '#374151',
                                tertiaryColor: '#4b5563',
                                lineColor: '#60a5fa',
                                edgeLabelBackground: '#1f2937',
                                mainBkg: '#1f2937',
                                nodeBkg: '#1f2937',
                                clusterBkg: '#374151',
                                nodeTextColor: '#e5e7eb',
                                textColor: '#e5e7eb',
                                labelTextColor: '#e5e7eb',
                                fillType0: '#3b82f6',
                                fillType1: '#10b981',
                                fillType2: '#f59e0b',
                                fillType3: '#ef4444',
                                fillType4: '#8b5cf6',
                                fontSize: '16px',
                                fontFamily: "-apple-system, 'SF Pro Text', 'Segoe UI', Arial, sans-serif",
                                lineHeight: '1.5'
                            } : {
                                primaryColor: '#ffffff',
                                primaryTextColor: '#24292f',
                                primaryBorderColor: '#d0d7de',
                                lineColor: '#0969da',
                                tertiaryColor: '#f6f8fa',
                                background: '#ffffff',
                                mainBkg: '#ffffff',
                                secondaryColor: '#f6f8fa',
                                fontSize: '16px',
                                fontFamily: "-apple-system, 'SF Pro Text', 'Segoe UI', Arial, sans-serif",
                                lineHeight: '1.5'
                            }
                        };
                        
                        // Re-initialize Mermaid with new configuration
                        if (window.mermaid && window.mermaid.initialize) {
                            console.log('🎨 DEBUG: Re-initializing Mermaid with config:', JSON.stringify(mermaidConfig, null, 2));
                            window.mermaid.initialize(mermaidConfig);
                            console.log('🎨 DEBUG: Mermaid re-initialized');
                        } else {
                            console.log('🎨 DEBUG: Mermaid.initialize not available');
                        }
                        
                        // Force re-render of current content to apply new theme
                        const currentValue = vditor.getValue();
                        if (currentValue) {
                            setTimeout(() => {
                                vditor.setValue(currentValue);
                            }, 100);
                        }
                    }
                };
            </script>
        </body>
        </html>
        """
    }
}

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
                /* 在编辑器内联预览 Mermaid（只展示，不拦截编辑） - 已移至后面的详细样式中 */
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
                
                /* 强制所有文本可见 - 直接解决输入不可见问题 */
                .ProseMirror * { color: inherit !important; }
                .milkdown pre * { color: inherit !important; }
                .milkdown code * { color: inherit !important; }
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

                /* Code - 明确设置代码文字颜色 */
                .milkdown pre,.milkdown code{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace}
                .milkdown pre{background:rgba(0,0,0,.05);border:0;border-radius:10px;padding:12px 14px;overflow:auto;color:#333 !important}
                .milkdown pre code{color:#333 !important}
                @media (prefers-color-scheme: dark){ 
                  .milkdown pre{background:rgba(255,255,255,.06);color:#d4d4d4 !important} 
                  .milkdown pre code{color:#d4d4d4 !important}
                }
                .milkdown code:not(pre code){background:rgba(0,0,0,.05);padding:2px 6px;border-radius:6px;color:#333 !important}
                @media (prefers-color-scheme: dark){ .milkdown code:not(pre code){background:rgba(255,255,255,.06);color:#d4d4d4 !important} }

                /* HR */
                .milkdown hr{border:0;border-top:1px solid rgba(0,0,0,.12);margin:2em 0}
                @media (prefers-color-scheme: dark){ .milkdown hr{border-top-color: rgba(255,255,255,.15)} }

                /* 内联 Mermaid 预览样式 - 修复定位问题 */
                .pm-mermaid-preview {
                  display: inline-block;
                  margin: 8px 0;
                  padding: 12px;
                  max-width: 100%;
                  max-height: 300px;
                  overflow: auto;
                  text-align: center;
                  border: 1px solid rgba(0,0,0,.12);
                  border-radius: 8px;
                  background: white;
                  box-shadow: 0 1px 3px rgba(0,0,0,.05);
                  cursor: pointer;
                  transition: all 0.2s ease;
                }

                @media (prefers-color-scheme: dark) {
                  .pm-mermaid-preview {
                    background: #1a1a1a;  /* 深色模式背景 */
                    border-color: rgba(255,255,255,.15);  /* 深色模式下的边框 */
                    box-shadow: 0 1px 3px rgba(0,0,0,.2);
                  }
                }

                .pm-mermaid-preview svg {
                  display: block;
                  max-width: 100%;
                  height: auto;
                  margin: 0 auto;
                  transform: scale(0.8);
                  transform-origin: center;
                }

                /* 隐藏被 Mermaid 图表替换的代码块 */
                .mermaid-hidden-code {
                  display: none !important;
                  height: 0 !important;
                  margin: 0 !important;
                  padding: 0 !important;
                  overflow: hidden !important;
                }

                /* Mermaid代码块 - 保持完全可见和可编辑 */
                .mermaid-code-transparent {
                  position: relative;
                  /* 完全移除透明度设置，保持正常显示 */
                }

                /* Debug 浮窗不拦截事件 */
                #debug-log { pointer-events: none !important; }

                /* Mermaid 右上角编辑按钮样式 */
                .mermaid-edit-btn {
                  position: absolute;
                  top: 8px;
                  right: 8px;
                  width: 24px;
                  height: 24px;
                  background: rgba(0, 0, 0, 0.6);
                  color: white;
                  border: none;
                  border-radius: 4px;
                  cursor: pointer;
                  font-size: 12px;
                  font-weight: bold;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  z-index: 10;
                  opacity: 0;
                  transition: opacity 0.2s ease;
                  pointer-events: auto;
                }

                .pm-mermaid-preview:hover {
                  border-color: rgba(0,0,0,.24);
                  box-shadow: 0 2px 8px rgba(0,0,0,.1);
                  transform: translateY(-1px);
                }

                .pm-mermaid-preview:hover .mermaid-edit-btn {
                  opacity: 1;
                }

                .mermaid-edit-btn:hover {
                  background: rgba(0, 0, 0, 0.8);
                  transform: scale(1.1);
                }

                @media (prefers-color-scheme: dark) {
                  .mermaid-edit-btn {
                    background: rgba(255, 255, 255, 0.15);
                    color: white;
                  }
                  .mermaid-edit-btn:hover {
                    background: rgba(255, 255, 255, 0.25);
                  }
                }

                /* 确保编辑器区域可滚动并撑满高度 */
                html, body { height: 100%; }
                #app, #root, .milkdown, .ProseMirror { min-height: 100%; }

                /* ===== Mermaid 护栏 ===== */
                .mmd-block { 
                  margin: 16px 0; 
                  clear: both;
                  position: relative !important;
                  isolation: isolate;
                  contain: layout paint;   /* 把布局与绘制限制在容器内，防逃逸 */
                  overflow: visible;
                }
                .mmd-block .mermaid {
                  display: block;
                  max-width: 100%;
                  /* 默认限制高度，避免吞版心；超过就滚动 */
                  max-height: 480px;
                  overflow: auto;
                  padding: 8px;
                  border: 1px solid rgba(125,125,125,.24);
                  border-radius: 8px;
                  background: rgba(125,125,125,.06);
                  position: relative !important;
                }
                .mmd-block .mermaid svg {
                  /* 关键：让 svg 服从容器宽度，而不是用自己的宽高撑爆布局 */
                  position: relative !important;
                  display: block !important;
                  width: 100% !important;
                  height: auto !important;
                }

                /* 展开时解除高度限制 */
                .mmd-block.is-expanded .mermaid { max-height: none; }

                /* 顶部说明 + 展开按钮 */
                .mmd-caption{
                  margin-top: 6px;
                  display: flex; align-items: center; justify-content: space-between; gap: 8px;
                  font: 12px -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Arial;
                  color: #666;
                }
                .mmd-toggle{
                  appearance: none;
                  border: 1px solid rgba(0,0,0,.2);
                  border-radius: 6px;
                  padding: 2px 8px;
                  background: transparent;
                  cursor: pointer;
                  font: 12px -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Arial;
                }
                /* 如果没有超限，就不显示"展开"按钮 */
                .mmd-block:not(.is-clamped) .mmd-toggle { display: none; }

                @media (prefers-color-scheme: dark){
                  .mmd-block .mermaid {
                    background: rgba(255,255,255,.04);
                    border-color: rgba(255,255,255,.18);
                    position: relative !important;
                  }
                  .mmd-caption {
                    color: #999;
                  }
                  .mmd-toggle {
                    border-color: rgba(255,255,255,.2);
                  }
                }

                /* 双保险：所有 mermaid svg 横向不可溢出 */
                .mermaid svg { 
                    max-width: 100%; 
                    height: auto; 
                    width: 100% !important;
                }
                
                /* Mermaid容器自适应大小 */
                .mermaid {
                    overflow: visible !important;
                    min-height: auto !important;
                    width: 100% !important;
                }
                
                /* 暗色模式下设置Mermaid背景，但让主题系统控制文字和颜色 */
                @media (prefers-color-scheme: dark) {
                    /* 只设置Mermaid容器背景，不强制文字颜色 */
                    .mermaid,
                    .pm-mermaid-preview,
                    .mmd-block {
                        background: transparent;
                        background-color: transparent;
                    }
                    
                    /* 仅在主题无法正常工作时的最后备选方案 */
                    .mermaid svg[style*="background-color: white"],
                    .mermaid svg[style*="background: white"] {
                        background: #0D1117 !important;
                        background-color: #0D1117 !important;
                    }
                }
                
                /* 浅色模式下保持透明背景 */
                @media (prefers-color-scheme: light) {
                    .mermaid,
                    .pm-mermaid-preview,
                    .mmd-block {
                        background: transparent !important;
                        background-color: transparent !important;
                    }
                }
                
                /* 确保Mermaid图表完整显示 */
                .mermaid svg {
                    overflow: visible !important;
                    max-width: none !important;
                    width: auto !important;
                    height: auto !important;
                }
                
                /* Mermaid文本大小适配 - 使用更合适的优先级 */
                .mermaid svg text,
                .mermaid svg tspan,
                .mermaid .nodeLabel,
                .mermaid .edgeLabel,
                .pm-mermaid-preview svg text,
                .pm-mermaid-preview svg tspan {
                    font-size: 13px;  /* 移除!important，让Mermaid有控制权 */
                    font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
                }
                
                /* 让Mermaid节点能够根据文本内容自动调整大小 */
                .mermaid .node rect,
                .mermaid rect,
                .pm-mermaid-preview .node rect,
                .pm-mermaid-preview rect {
                    /* 允许自动调整宽高，不强制固定 */
                    width: auto;
                    height: auto;
                }
                
                /* 确保Mermaid图表容器不被截断 */
                .pm-mermaid-preview,
                .mmd-block {
                    overflow: visible !important;
                    width: 100% !important;
                }
              </style>
              <script src="Resources/mermaid/mermaid.min.js">
              <script>
                (function(){
                  try{
                    let isDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
                    
                    function initializeMermaidWithTheme() {
                      const config = { 
                        startOnLoad: false, 
                        securityLevel: 'loose', 
                        theme: isDark ? 'dark' : 'default',
                        fontFamily: '-apple-system, BlinkMacSystemFont, system-ui, sans-serif',
                        darkMode: isDark,
                        themeVariables: isDark ? {
                          // Dark主题配色，与主要初始化保持一致
                          primaryColor: '#58A6FF',
                          primaryTextColor: '#F0F6FC',
                          primaryBorderColor: '#30363D',
                          secondaryColor: '#7C3AED',
                          tertiaryColor: '#F59E0B',
                          lineColor: '#30363D',
                          gridColor: '#21262D',
                          background: '#0D1117',
                          mainBkg: '#0D1117',
                          secondBkg: '#0D1117',
                          clusterBkg: '#0D1117',
                          defaultLinkColor: '#58A6FF',
                          nodeBkg: '#21262D',
                          nodeTextColor: '#F0F6FC',
                          tertiaryTextColor: '#F0F6FC',
                          taskTextColor: '#F0F6FC',
                          cScale0: '#58A6FF', cScale1: '#7C3AED', cScale2: '#10B981',
                          cScale3: '#F59E0B', cScale4: '#EF4444', cScale5: '#EC4899'
                        } : undefined
                      };
                      
                      console.log('🌙 Mermaid backup init with theme:', isDark ? 'dark' : 'default', config);
                      if (window.mermaid && window.mermaid.initialize) {
                        window.mermaid.initialize(config);
                      }
                    }
                    
                    // 初次初始化
                    initializeMermaidWithTheme();
                    
                    // 监听主题变化
                    const darkModeQuery = window.matchMedia('(prefers-color-scheme: dark)');
                    darkModeQuery.addListener(function(e) {
                      isDark = e.matches;
                      console.log('🎨 Backup Mermaid theme changed to:', isDark ? 'dark' : 'default');
                      initializeMermaidWithTheme();
                    });
                    
                  }catch(e){ console.warn('Mermaid backup init failed', e); }
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
                
                function buildMermaidDecorations(state, hiddenPreviews = new Set()) {
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
                        // 如果该位置被隐藏，跳过预览
                        if (hiddenPreviews.has(pos)) {
                          return;
                        }
                        // 清理代码（移除无关首行）
                        let cleanCode = text.replace(/\uFEFF/g, '').trim();
                        
                        const lines = cleanCode.split(/\r?\n/);
                        const firstDiagramIdx = lines.findIndex(l => mermaidStart.test(l.trim()) || /^%%\{/.test(l.trim()));
                        if (firstDiagramIdx > 0) cleanCode = lines.slice(firstDiagramIdx).join('\n');
                        
                        // 再次检查清理后的代码是否为空
                        if (!cleanCode || cleanCode.trim().length === 0) {
                          return; // 跳过清理后为空的代码块，不添加预览和不透明化代码块
                        }
                        
                        const dom = document.createElement('div');
                        dom.className = 'pm-mermaid-preview';
                        dom.setAttribute('data-source', cleanCode);
                        dom.textContent = cleanCode; // 先显示原始代码，稍后渲染
                        
                        // 添加右上角编辑按钮
                        const editBtn = document.createElement('button');
                        editBtn.className = 'mermaid-edit-btn';
                        editBtn.innerHTML = '✎';  // 编辑图标
                        editBtn.title = '点击编辑Mermaid代码';
                        editBtn.style.pointerEvents = 'all'; // 确保按钮可点击
                        
                        editBtn.addEventListener('click', (e) => {
                          e.preventDefault();
                          e.stopPropagation();
                          __mmdLog('Edit button clicked, switching to edit mode');
                          
                          if (!window.milkdownEditor) {
                            __mmdLog('Editor not available');
                            return;
                          }
                          
                          try {
                            window.milkdownEditor.action((ctx) => {
                              const view = ctx.get(editorViewCtx);
                              
                              // 隐藏当前位置的Mermaid预览
                              const tr = view.state.tr.setMeta('hideMermaidPreview', pos);
                              
                              // 选中代码块内容
                              const selection = TextSelection.create(view.state.doc, pos + 1, pos + node.nodeSize - 1);
                              tr.setSelection(selection);
                              
                              view.dispatch(tr);
                              view.focus();
                              
                              __mmdLog('Switched to edit mode at pos:', pos);
                            });
                          } catch (e) {
                            __mmdLog('Error switching to edit mode:', String(e?.message || e));
                          }
                        });
                        
                        dom.appendChild(editBtn);
                        
                        // 让整个预览区域都可以点击进入编辑模式
                        dom.addEventListener('click', (e) => {
                          // 如果点击的是编辑按钮，不重复处理
                          if (e.target.closest('.mermaid-edit-btn')) {
                            return;
                          }
                          
                          e.preventDefault();
                          e.stopPropagation();
                          __mmdLog('Preview area clicked, switching to edit mode');
                          
                          if (!window.milkdownEditor) {
                            __mmdLog('Editor not available');
                            return;
                          }
                          
                          try {
                            window.milkdownEditor.action((ctx) => {
                              const view = ctx.get(editorViewCtx);
                              
                              // 隐藏当前位置的Mermaid预览
                              const tr = view.state.tr.setMeta('hideMermaidPreview', pos);
                              
                              // 选中代码块内容
                              const selection = TextSelection.create(view.state.doc, pos + 1, pos + node.nodeSize - 1);
                              tr.setSelection(selection);
                              
                              view.dispatch(tr);
                              view.focus();
                              
                              __mmdLog('Switched to edit mode at pos:', pos);
                            });
                          } catch (e) {
                            __mmdLog('Error switching to edit mode:', String(e?.message || e));
                          }
                        });
                        
                        // 简化策略：直接在原代码块位置显示图表
                        // 1. 完全移除透明化逻辑，保持代码块完全可见可编辑
                        
                        // 2. 按 ProseMirror 官方最佳实践创建 widget
                        decos.push(Decoration.widget(pos, dom, { 
                          side: 1,  // 在位置之后，官方推荐
                          key: `mermaid-${pos}-${raw.slice(0, 20).replace(/\s+/g, '-')}`,
                          // 使用默认的 ignoreSelection: false 和 stopEvent: null
                        }));
                        
                        // 现在单击Mermaid图表就可以越过代码块了，不需要额外的间隔区域
                      }
                    }
                  });
                  
                  return DecorationSet.create(doc, decos);
                }
                
                const safeMermaidPlugin = new Plugin({
                  key: mermaidPreviewKey,
                  state: {
                    init() { return { decorations: DecorationSet.empty, hiddenPreviews: new Set() }; },
                    apply(tr, old, _oldState, newState) {
                      let { decorations, hiddenPreviews } = old;
                      
                      // 处理隐藏预览的请求
                      const hidePos = tr.getMeta('hideMermaidPreview');
                      if (typeof hidePos === 'number') {
                        hiddenPreviews = new Set(hiddenPreviews);
                        hiddenPreviews.add(hidePos);
                      }
                      
                      // 处理显示预览的请求
                      const showPos = tr.getMeta('showMermaidPreview');
                      if (typeof showPos === 'number') {
                        hiddenPreviews = new Set(hiddenPreviews);
                        hiddenPreviews.delete(showPos);
                      }
                      
                      // 文档变更时重建装饰器
                      if (tr.docChanged) {
                        decorations = buildMermaidDecorations(newState, hiddenPreviews);
                      } else {
                        decorations = decorations.map(tr.mapping, tr.doc);
                      }
                      
                      return { decorations, hiddenPreviews };
                    }
                  },
                  props: {
                    decorations(state) { return this.getState(state).decorations; }
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
                              
                              // 在暗色主题下强制设置背景和文字颜色 - 与主函数保持一致
                              if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
                                // 强制设置容器背景
                                el.style.background = 'rgba(28, 28, 30, 0.95)';
                                el.style.backgroundColor = 'rgba(28, 28, 30, 0.95)';
                                el.style.borderRadius = '8px';
                                el.style.padding = '16px';
                                
                                // 查找SVG并设置样式
                                const svgEl = el.querySelector('svg');
                                if (svgEl) {
                                  svgEl.style.background = 'rgba(28, 28, 30, 0.95)';
                                  svgEl.style.backgroundColor = 'rgba(28, 28, 30, 0.95)';
                                  
                                  // 强制所有图形元素使用深色背景
                                  const shapeElements = svgEl.querySelectorAll('rect, circle, ellipse, polygon');
                                  shapeElements.forEach(shape => {
                                    if (shape.getAttribute('fill') !== 'none') {
                                      shape.setAttribute('fill', 'rgba(58, 58, 60, 1)');
                                      shape.style.fill = 'rgba(58, 58, 60, 1)';
                                      shape.setAttribute('stroke', 'rgba(142, 142, 147, 1)');
                                      shape.style.stroke = 'rgba(142, 142, 147, 1)';
                                      shape.style.strokeWidth = '1.5px';
                                    }
                                  });
                                  
                                  // 强制所有文字使用白色
                                  const textElements = svgEl.querySelectorAll('text, tspan, .label, .nodeLabel, .edgeLabel');
                                  textElements.forEach(textEl => {
                                    textEl.setAttribute('fill', 'rgba(235, 235, 245, 1)');
                                    textEl.style.fill = 'rgba(235, 235, 245, 1)';
                                    textEl.style.color = 'rgba(235, 235, 245, 1)';
                                    textEl.style.fontWeight = '500';
                                  });
                                  
                                  // 强制连线颜色
                                  const lineElements = svgEl.querySelectorAll('path, line, polyline');
                                  lineElements.forEach(line => {
                                    if (line.getAttribute('fill') === 'none' || !line.getAttribute('fill')) {
                                      line.setAttribute('stroke', 'rgba(142, 142, 147, 1)');
                                      line.style.stroke = 'rgba(142, 142, 147, 1)';
                                      line.style.strokeWidth = '2px';
                                    }
                                  });
                                }
                                
                                console.log('🌙 内联Dark主题背景和文字设置完成');
                              }
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
                    
                    // 将editor设置为全局变量，供点击事件访问
                    window.milkdownEditor = editor;
                    __mmdLog('editor ready and set as global');
                    
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

