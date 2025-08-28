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
    
    // 窗口焦点管理
    @StateObject private var focusManager = WindowFocusManager.shared
    @State private var windowId = UUID()

    
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("toggleDetailPanelTab"))) { _ in
            // Command+D: 在图谱和详情标签间切换
            print("🎯 DetailPanel: 收到 toggleDetailPanelTab 通知，当前标签: \(tab.rawValue)")
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if tab == .related {
                        tab = .detail
                        print("✅ DetailPanel: 从图谱切换到详情")
                    } else if tab == .detail {
                        tab = .related
                        print("✅ DetailPanel: 从详情切换到图谱")
                    } else {
                        // 如果当前在地图标签，切换到详情
                        tab = .detail
                        print("✅ DetailPanel: 从地图切换到详情")
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("switchToMapTab"))) { notification in
            // 地图标注点击：切换到地图标签
            if let targetNode = notification.object as? Node,
               targetNode.id == currentNode.id {
                print("🗺️ DetailPanel: 收到 switchToMapTab 通知，切换到地图标签")
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        tab = .map
                        print("✅ DetailPanel: 已切换到地图标签")
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("toggleDetailEditMode"))) { notification in
            // 检查当前窗口是否应该响应此通知
            guard focusManager.shouldHandleNotification(for: windowId) else {
                print("🔔 DetailPanel: 忽略toggleDetailEditMode通知 - 窗口非活跃状态")
                return
            }
            
            // 收到全局Command+T通知，切换到详情页并切换编辑模式
            if let notificationNode = notification.object as? Node,
               notificationNode.id == node.id {
                // 异步修改状态避免在视图更新期间修改状态的警告
                DispatchQueue.main.async {
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
        .onKeyPress(.init("o"), phases: .down) { keyPress in
            if keyPress.modifiers == .command {
                print("🎯 DetailPanel: Command+O 检测到，切换到详情标签")
                handleSwitchToDetail()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.init("l"), phases: .down) { keyPress in
            if keyPress.modifiers == .command {
                print("🎯 DetailPanel: Command+L 检测到，切换到图谱标签")
                handleSwitchToGraph()
                return .handled
            }
            return .ignored
        }
        .focusable(false)
        .onAppear {
            // DetailPanel 是主窗口的组件，不需要单独注册窗口
            // 窗口注册由 WordTaggerApp 统一管理
            
            setupNotificationObservers()
        }
        .onDisappear {
            // 不需要单独注销窗口
        }
    }
    
    // MARK: - 快捷键处理方法
    private func handleSwitchToDetail() {
        // 异步修改状态避免在视图更新期间修改状态的警告
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                tab = .detail
            }
            // 焦点功能已移除
        }
    }
    
    private func handleSwitchToGraph() {
        // 异步修改状态避免在视图更新期间修改状态的警告
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                tab = .related
            }
            // 焦点功能已移除
        }
    }
    
    // MARK: - 通知监听
    private func setupNotificationObservers() {
        // 监听显示详情标签的通知 (Command+O触发)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("executeDetailTabSwitch"),
            object: nil,
            queue: .main
        ) { notification in
            print("🔔 DetailPanel: 收到executeDetailTabSwitch通知，切换到详情标签")
            DispatchQueue.main.async {
                self.handleSwitchToDetail()
            }
        }
        
        // 监听显示图谱标签的通知 (Command+L触发)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("executeGraphTabSwitch"),
            object: nil,
            queue: .main
        ) { notification in
            print("🔔 DetailPanel: 收到executeGraphTabSwitch通知，切换到图谱标签")
            DispatchQueue.main.async {
                self.handleSwitchToGraph()
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

    @State private var currentNodeId: UUID = UUID()
    @State private var isLoadingContent: Bool = false
    
    // 从store中获取最新的节点数据
    private var currentNode: Node {
        return store.nodes.first { $0.id == node.id } ?? node
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
            // 单一渲染管线：Vditor(IR) 负责 Markdown + Mermaid 的就地渲染（不再使用独立 MermaidWebView）
            VditorWebView(
                markdown: markdownText,
                nodeId: currentNode.id.uuidString,
                onChange: { [weak store] newValue in
                    // 防止在节点切换期间保存
                    guard !isLoadingContent else {
                        print("⚠️ 忽略onChange - 正在加载内容")
                        return
                    }
                    
                    // 确保使用当前的节点ID
                    guard currentNodeId == currentNode.id else {
                        print("⚠️ 忽略onChange - 节点ID不匹配")
                        return
                    }
                    
                    print("🚨🚨🚨 VDITOR ONCHANGE CALLED - length: \(newValue.count)")
                    print("🚨🚨🚨 CONTENT PREVIEW: \(newValue.prefix(200))")
                    print("🚨🚨🚨 CURRENT NODE: \(currentNode.text) (\(currentNode.id))")
                    
                    // 使用当前节点保存
                    if let latestNode = store?.nodes.first(where: { $0.id == currentNodeId }) {
                        instantSaveForNode(latestNode, content: newValue)
                    }
                    // 异步修改状态避免在视图更新期间修改状态的警告
                    DispatchQueue.main.async {
                        markdownText = newValue
                    }
                },
                coordinatorBinding: $vditorCoordinator
            )
            .id("vditor-\(currentNode.id)-\(colorScheme)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .zIndex(2)
            // 图片拖拽由 VditorWebView 内部的 JavaScript 处理，无需在这里重复处理
            .onAppear {
                print("🚨🚨🚨 VditorWebView onAppear CALLED for node: \(currentNode.text)")
            }

            
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            // 异步修改状态避免在视图更新期间修改状态的警告
            DispatchQueue.main.async {
                currentNodeId = currentNode.id
                loadMarkdown()
            }
        }
        .onChange(of: currentNode.id) { oldId, newId in
            print("🔄 节点ID发生变化: \(oldId) -> \(newId)")
            
            // 异步修改状态避免在视图更新期间修改状态的警告
            DispatchQueue.main.async {
                // 更新当前节点ID
                currentNodeId = newId
                isLoadingContent = true
                
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
                                isLoadingContent = false
                            }
                        }
                    }
                } else {
                    loadMarkdown()
                    // 确保编辑器内容也重新加载
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        vditorCoordinator?.setMarkdown(markdownText, forceUpdate: true)
                        isLoadingContent = false
                    }
                }
            }
        }
        .onChange(of: node.id) { oldId, newId in
            print("🔄 传入节点ID发生变化: \(oldId) -> \(newId)")
            // 异步修改状态避免在视图更新期间修改状态的警告
            DispatchQueue.main.async {
                currentNodeId = newId
                isLoadingContent = true
                // 当传入的node发生变化时，也要重新加载内容
                loadMarkdown()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    vditorCoordinator?.setMarkdown(markdownText, forceUpdate: true)
                    isLoadingContent = false
                }
            }
        }
        .onChange(of: isEditing) { _, newValue in
            if newValue {
                // 静默进入编辑模式
            }
        }
        .onChange(of: colorScheme) { _, newValue in
            print("🎨 主题变化: \(newValue == .dark ? "dark" : "light")")
            // 异步修改状态避免在视图更新期间修改状态的警告
            DispatchQueue.main.async {
                // 主题变化时立即强制刷新编辑器内容以应用新主题
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("imageInsertSuccess"))) { notification in
            // 图片插入成功后，同步编辑器内容到本地状态
            print("📸 收到图片插入成功通知，同步内容状态")
            if let fileName = notification.userInfo?["fileName"] as? String {
                print("📸 插入的图片: \(fileName)")
                
                // 延迟获取最新内容，确保图片链接已经插入
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if let coordinator = vditorCoordinator {
                        // 从编辑器获取最新内容并同步到本地状态
                        let getContentJS = """
                        try {
                            if (window.vditor && typeof window.vditor.getValue === 'function') {
                                window.vditor.getValue();
                            } else {
                                '';
                            }
                        } catch(e) {
                            '';
                        }
                        """
                        
                        coordinator.webView?.evaluateJavaScript(getContentJS) { result, error in
                            if let content = result as? String, !content.isEmpty {
                                print("📸 从编辑器获取最新内容: \(content.count)字符")
                                // 注意：由于NodeDetailView是struct，不需要weak引用
                                // 直接在main队列中更新状态和保存文件
                                DispatchQueue.main.async {
                                    // 通过通知来更新markdown内容，避免结构体捕获问题
                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("updateMarkdownContent"),
                                        object: nil,
                                        userInfo: ["content": content, "nodeId": node.id]
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("updateMarkdownContent"))) { notification in
            // 处理markdown内容更新通知
            if let content = notification.userInfo?["content"] as? String,
               let nodeId = notification.userInfo?["nodeId"] as? UUID,
               nodeId == node.id {
                print("📝 收到markdown内容更新通知，更新本地状态")
                markdownText = content
                // 立即保存到文件
                instantSaveForNode(node, content: content)
            }
        }
        .onDisappear {
            // 清理异步任务
            saveTask?.cancel()
        }
    }
    
    private func loadMarkdown() {
        Task {
            await loadMarkdownFromFile()
        }
    }
    
    private func saveMarkdown() {
        Task { @MainActor in
            store.updateNodeMarkdown(currentNode.id, markdown: markdownText)
        }
    }
    
    private func instantSave(_ newValue: String) {
        instantSaveForNode(currentNode, content: newValue)
    }
    
    private func instantSaveForNode(_ node: Node, content: String) {
        print("🚨🚨🚨 INSTANT SAVE CALLED!")
        print("🚨🚨🚨 NODE: \(node.text)")
        print("🚨🚨🚨 CONTENT LENGTH: \(content.count)")
        
        // 取消之前的任务避免重复保存
        saveTask?.cancel()
        
        // 立即更新内存中的数据
        store.updateNodeMarkdown(node.id, markdown: content)
        
        // 立即异步保存到文件
        let nodeToSave = node
        saveTask = Task {
            await saveMarkdownToFileForNode(nodeToSave, content: content)
        }
    }
    
    private func saveMarkdownToFile(_ content: String) async {
        await saveMarkdownToFileForNode(currentNode, content: content)
    }
    
    private func saveMarkdownToFileForNode(_ node: Node, content: String) async {
        print("🚨🚨🚨 SAVING MARKDOWN FILE...")
        print("🚨🚨🚨 为节点保存: \(node.text) (\(node.id))")
        
        // 强制使用外部数据管理器获取Markdown路径
        guard let markdownURL = await MainActor.run(body: { ExternalDataManager.shared.getMarkdownURL() }) else {
            print("❌ 必须先设置外部数据存储路径才能保存Markdown文件")
            return
        }
        
        // 确保外部数据管理器有访问权限
        guard await MainActor.run(body: { ExternalDataManager.shared.ensureAccess() }) else {
            print("❌ 无法访问外部数据存储路径")
            return
        }
        
        do {
            try FileManager.default.createDirectory(at: markdownURL, withIntermediateDirectories: true)
            
            // 创建安全的文件名（移除特殊字符）
            let safeFileName = node.text
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
    
    private func loadMarkdownFromFile() async {
        print("🚨🚨🚨 LOADING MARKDOWN FILE...")
        
        // 强制使用外部数据管理器获取Markdown路径
        var markdownURL: URL?
        var hasAccess: Bool = false
        
        await MainActor.run {
            markdownURL = ExternalDataManager.shared.getMarkdownURL()
            hasAccess = ExternalDataManager.shared.ensureAccess()
        }
        
        guard let markdownURL = markdownURL else {
            print("❌ 必须先设置外部数据存储路径才能加载Markdown文件")
            // 使用默认内容
            let defaultContent = currentNode.markdown
            markdownText = defaultContent
            DispatchQueue.main.async {
                self.vditorCoordinator?.setMarkdown(defaultContent, forceUpdate: true)
            }
            return
        }
        
        // 确保外部数据管理器有访问权限
        guard hasAccess else {
            print("❌ 无法访问外部数据存储路径")
            // 使用默认内容
            let defaultContent = currentNode.markdown
            markdownText = defaultContent
            DispatchQueue.main.async {
                self.vditorCoordinator?.setMarkdown(defaultContent, forceUpdate: true)
            }
            return
        }
        
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
            // 延迟到下一个运行循环，避免在视图更新期间修改状态
            DispatchQueue.main.async {
                print("📝 loadMarkdownFromFile: 设置编辑器内容")
                self.vditorCoordinator?.setMarkdown(content, forceUpdate: true)
            }
        } catch {
            print("📄 文件不存在或无法读取，使用默认内容: \(error)")
            // 文件不存在时使用Node的默认markdown内容
            let defaultContent = currentNode.markdown
            markdownText = defaultContent
            
            // 确保编辑器也更新默认内容
            DispatchQueue.main.async {
                print("📝 loadMarkdownFromFile: 设置默认内容到编辑器")
                self.vditorCoordinator?.setMarkdown(defaultContent, forceUpdate: true)
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
        print("🖼️ Inserting text at cursor: \(text)")
        
        // 计算新内容
        let newContent = markdownText.isEmpty ? text : markdownText + "\n" + text
        print("🖼️ New content length: \(newContent.count)")
        
        // 优先使用VditorWebView的coordinator来插入文本
        if let coordinator = vditorCoordinator {
            print("🖼️ Updating VditorWebView content via coordinator")
            coordinator.setMarkdown(newContent, forceUpdate: true)
            
            // 同时更新本地状态
            markdownText = newContent
            
            // 手动触发保存，因为coordinator.setMarkdown不会触发onChange
            print("🖼️ Manual save after coordinator update")
            instantSaveForNode(currentNode, content: newContent)
        } else {
            // 备选方案：直接修改状态（这会触发VditorWebView的onChange）
            print("🖼️ Coordinator not available, using fallback method")
            markdownText = newContent
            // 这种方式会自动触发onChange回调来保存
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
                                .onTapGesture {
                                    handleMapPinTap(tag: tag)
                                }
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
    
    // MARK: - Map Pin Interaction
    private func handleMapPinTap(tag: Tag) {
        print("🗺️ 地图标注被点击: \(tag.value)")
        
        // 1. 首先找到拥有这个地图标签的节点
        let nodeWithThisTag = findNodeWithLocationTag(tag)
        
        guard let targetNode = nodeWithThisTag else {
            print("⚠️ 未找到包含地图标签 '\(tag.value)' 的节点")
            return
        }
        
        print("🎯 找到目标节点: \(targetNode.text) (层ID: \(targetNode.layerId))")
        
        // 2. 找到节点所属的层
        guard let targetLayer = store.layers.first(where: { $0.id == targetNode.layerId }) else {
            print("⚠️ 未找到节点 '\(targetNode.text)' 所属的层")
            return
        }
        
        print("🎯 目标层: \(targetLayer.displayName)")
        
        // 3. 通过通知系统请求处理地图点击，让当前活跃的窗口来响应
        // 这样可以确保操作发生在正确的窗口上下文中
        let mapPinTapInfo: [String: Any] = [
            "targetNode": targetNode,
            "targetLayer": targetLayer,
            "locationTag": tag
        ]
        
        NotificationCenter.default.post(
            name: NSNotification.Name("handleMapPinTap"),
            object: nil,
            userInfo: mapPinTapInfo
        )
        
        print("📤 已发送地图标注点击通知，等待当前窗口处理")
    }
    
    private func findNodeWithLocationTag(_ tag: Tag) -> Node? {
        // 搜索所有节点，找到包含这个位置标签的节点
        return store.nodes.first { node in
            node.locationTags.contains { locationTag in
                locationTag.type == tag.type && 
                locationTag.value == tag.value &&
                locationTag.latitude == tag.latitude &&
                locationTag.longitude == tag.longitude
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
    internal var currentID: Int = 1000000 // 从一个大数开始避免冲突
    internal var tagIDMap: [String: Int] = [:] // 缓存标签的ID
    internal let lock = NSLock()
    
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
        
        // 构建更丰富的subtitle，包含音标和含义
        var subtitleParts: [String] = []
        if let phonetic = node.phonetic, !phonetic.isEmpty {
            subtitleParts.append(phonetic)
        }
        if let meaning = node.meaning, !meaning.isEmpty {
            subtitleParts.append(meaning)
        }
        self.subtitle = subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " • ")
        
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
    func getCachedGraphData(for node: Node, store: NodeStore) -> (nodes: [NodeGraphNode], edges: [NodeGraphEdge]) {
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
        let graphData = calculateGraphData(for: node, store: store)
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
    private func calculateGraphData(for node: Node, store: NodeStore) -> (nodes: [NodeGraphNode], edges: [NodeGraphEdge]) {
        let nodes = calculateGraphNodes(for: node, store: store)
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
    private func calculateGraphNodes(for node: Node, store: NodeStore) -> [NodeGraphNode] {
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
                    if let actualChildNode = store.nodes.first(where: { $0.text.lowercased() == childNodeName.lowercased() }) {
                        // 添加子节点本身
                        nodes.append(NodeGraphNode(node: actualChildNode, isCenter: false))
                        addedChildNodes.insert(childNodeName)
                        print("🔗 图谱中添加子节点: \(actualChildNode.text), 是否为复合节点: \(actualChildNode.isCompound)")
                        
                        // 递归添加子节点的结构，但保持层次关系
                        var visitedNodes: Set<String> = []
                        addChildNodeStructure(for: actualChildNode, addedTagKeys: &addedTagKeys, addedChildNodes: &addedChildNodes, nodes: &nodes, depth: 1, visitedNodes: &visitedNodes, store: store)
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
    private func addChildNodeStructure(for node: Node, addedTagKeys: inout Set<String>, addedChildNodes: inout Set<String>, nodes: inout [NodeGraphNode], depth: Int, visitedNodes: inout Set<String>, store: NodeStore) {
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
                    if let childNode = store.nodes.first(where: { $0.text.lowercased() == childNodeName.lowercased() }) {
                        // 添加子节点
                        nodes.append(NodeGraphNode(node: childNode, isCenter: false))
                        addedChildNodes.insert(childNodeName)
                        print("\(indentPrefix)  ↳ 添加子节点: \(childNode.text)")
                        
                        // 递归添加更深层的子节点结构
                        addChildNodeStructure(for: childNode, addedTagKeys: &addedTagKeys, addedChildNodes: &addedChildNodes, nodes: &nodes, depth: depth + 1, visitedNodes: &visitedNodes, store: store)
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
    private func addTagsRecursively(for node: Node, addedTagKeys: inout Set<String>, nodes: inout [NodeGraphNode], depth: Int, visitedNodes: inout Set<String>, store: NodeStore) {
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
                if let childNode = store.nodes.first(where: { $0.text.lowercased() == childNodeName.lowercased() }) {
                    print("\(indentPrefix)🔗 发现子节点: \(childNode.text)")
                    // 递归处理子节点
                    addTagsRecursively(for: childNode, addedTagKeys: &addedTagKeys, nodes: &nodes, depth: depth + 1, visitedNodes: &visitedNodes, store: store)
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
        let graphData = graphCache.getCachedGraphData(for: currentNode, store: store)
        
        VStack {
            // 直接显示图谱内容，无标题栏
            if graphData.nodes.count <= 1 {
                EmptyGraphView()
            } else {
                NodeContextGraphView(
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
                .environmentObject(store)
                .contextMenu {
                    Button("全屏显示 (⌘D) - 已禁用") {
                        Swift.print("🖥️ 右键菜单: 全屏功能已禁用用于调试")
                        // 禁用全屏功能来测试崩溃
                    }
                }
            }
        }
        .focusable(false)
        .onKeyPress(.init("d"), phases: .down) { keyPress in
            if keyPress.modifiers == .command {
                // Command+D in NodeGraphView should only handle fullscreen toggle, not tab switching
                // The tab switching is handled by the notification system from VditorWebView
                Swift.print("🎯 NodeGraphView: Command+D 检测到 - 仅处理全屏图谱功能")
                let windowManager = FullscreenGraphWindowManager.shared
                
                // 检查是否已经有全屏图谱窗口打开
                if windowManager.isWindowActive() {
                    Swift.print("📝 NodeGraphView: Command+D - 关闭现有全屏图谱窗口")
                    windowManager.hideFullscreenGraph()
                    return .handled
                }
                // 如果没有全屏窗口，不处理，让通知系统处理标签切换
                Swift.print("📝 NodeGraphView: 没有全屏窗口，忽略Command+D让其处理标签切换")
                return .ignored
            }
            return .ignored
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FullscreenGraphClosed"))) { _ in
            print("📝 通知: 收到 FullscreenGraphClosed 通知")
            // 异步修改状态避免在视图更新期间修改状态的警告
            DispatchQueue.main.async {
                showingFullscreenGraph = false
                print("📝 通知: showingFullscreenGraph 设置为 false")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("requestOpenFullscreenGraphFromDetail"))) { notification in
            if let node = notification.object as? Node,
               node.id == currentNode.id {
                print("📝 NodeGraphView: 收到Command+D触发的全屏图谱请求")
                
                let windowManager = FullscreenGraphWindowManager.shared
                if !windowManager.isWindowActive() {
                    print("📝 NodeGraphView: 打开全屏图谱")
                    let graphData = graphCache.getCachedGraphData(for: currentNode, store: store)
                    
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
                        .help("关闭 (ESC 或 Command+D)")
                    }
                    
                    Text("复合节点层级图谱 • 按 ESC 或 Command+D 关闭")
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
        .focusable(false)
        .onKeyPress(.escape) {
            Swift.print("🎯 FullscreenGraphView: ESC键按下，关闭窗口")
            closeWindow()
            return .handled
        }
        .onKeyPress(.init("d"), phases: .down) { keyPress in
            Swift.print("🎯 FullscreenGraphView: D键按下，修饰符: \(keyPress.modifiers)")
            if keyPress.modifiers == .command {
                Swift.print("🎯 FullscreenGraphView: Command+D检测到，关闭窗口")
                closeWindow()
                return .handled
            }
            return .ignored
        }
        .onAppear {
            Swift.print("🖥️ 全屏图谱视图已显示")
            
            // 焦点功能已移除
            
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
                // 焦点功能已移除
                FullscreenGraphWindowManager.shared.activateFullscreenWindow()
            }
            
            // 添加额外的焦点设置延迟
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Swift.print("🎯 第二次尝试激活全屏图谱窗口...")
                // 焦点功能已移除
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
    @FocusState private var focusedField: Field?
    
    enum Field {
        case text, phonetic, meaning
    }
    
    init(node: Node) {
        self.node = node
        self._text = State(initialValue: node.text)
        self._phonetic = State(initialValue: node.phonetic ?? "")
        self._meaning = State(initialValue: node.meaning ?? "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("编辑节点")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 表单内容
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 节点名称（只读显示）
                    VStack(alignment: .leading, spacing: 8) {
                        Text("节点名称")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(text)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(NSColor.controlBackgroundColor))
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    // Preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("例如：/ɪɡˈzæmpəl/", text: $phonetic)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .phonetic)
                            .font(.body)
                        
                        if !phonetic.isEmpty {
                            HStack {
                                Image(systemName: "speaker.wave.2")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                Text("音标预览：")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(phonetic)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.blue.opacity(0.1))
                            )
                        }
                    }
                    
                    // 解释
                    VStack(alignment: .leading, spacing: 8) {
                        Text("解释")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("输入节点解释", text: $meaning, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .meaning)
                            .lineLimit(3...6)
                            .font(.body)
                        
                        if !meaning.isEmpty {
                            HStack {
                                Image(systemName: "text.quote")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("解释预览：")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(meaning)
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .fontWeight(.medium)
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.green.opacity(0.1))
                            )
                        }
                    }
                    
                    // 预览区域
                    if !text.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("节点预览")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(text)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                if !phonetic.isEmpty {
                                    Text(phonetic)
                                        .font(.body)
                                        .foregroundColor(.blue)
                                        .fontWeight(.medium)
                                }
                                
                                if !meaning.isEmpty {
                                    Text(meaning)
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.controlBackgroundColor))
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            
            Divider()
            
            // 底部按钮
            HStack {
                Spacer()
                
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button("保存") {
                    store.updateNode(
                        node.id,
                        text: nil, // 不修改节点名称
                        phonetic: phonetic.isEmpty ? nil : phonetic,
                        meaning: meaning.isEmpty ? nil : meaning
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 400, height: 450)
        .onAppear {
            // 自动聚焦到第一个空字段
            if phonetic.isEmpty {
                focusedField = .phonetic
            } else if meaning.isEmpty {
                focusedField = .meaning
            } else {
                focusedField = .phonetic
            }
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(.return) {
            store.updateNode(
                node.id,
                text: nil, // 不修改节点名称
                phonetic: phonetic.isEmpty ? nil : phonetic,
                meaning: meaning.isEmpty ? nil : meaning
            )
            dismiss()
            return .handled
        }
    }
}





// MARK: - 图片管理器

class NodeImageManager: ObservableObject {
    static let shared = NodeImageManager()
    
    private init() {}
    
    @MainActor
    private var imagesDirectory: URL {
        // 强制使用外部数据管理器的Images路径，如果没有设置则使用临时目录
        guard let imagesURL = ExternalDataManager.shared.getImagesURL(),
              ExternalDataManager.shared.ensureAccess() else {
            // 如果没有外部路径，使用临时目录作为后备（这样用户会知道需要设置外部路径）
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("WordTagger_NodeImages")
            print("⚠️ 使用临时目录存储节点图片，请设置外部数据存储路径")
            return tempURL
        }
        
        // 确保目录存在
        if !FileManager.default.fileExists(atPath: imagesURL.path) {
            try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        }
        
        return imagesURL
    }
    
    @MainActor
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
    
    @MainActor
    func copyImageFromURL(_ sourceURL: URL) -> String? {
        return copyImageToAppDirectory(from: sourceURL)
    }
    
    @MainActor
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
    
    @MainActor
    func getImageURL(for fileName: String) -> URL {
        return imagesDirectory.appendingPathComponent(fileName)
    }
    
    @MainActor
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

