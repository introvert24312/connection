// 修复WebView闪退的稳定DetailPanel版本
import SwiftUI
import CoreLocation
import MapKit

struct StableDetailPanel: View {
    let node: Node
    @EnvironmentObject private var store: NodeStore
    @StateObject private var updateManager = WebViewUpdateManager()
    
    @State private var tab: Tab = .related
    @State private var showingEditSheet = false
    
    // 稳定化的节点状态管理
    @State private var stableNode: Node
    @State private var stableNodeHash: String
    @State private var lastValidContent: String = ""
    
    // WebView生命周期管理
    @State private var vditorCoordinator: VditorWebView.Coordinator?
    @State private var webViewGeneration = UUID() // 用于强制重建WebView
    
    init(node: Node) {
        self.node = node
        self._stableNode = State(initialValue: node)
        // 使用更稳定的哈希算法
        let initialHash = Self.generateStableHash(for: node)
        self._stableNodeHash = State(initialValue: initialHash)
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
            
            // 内容区域 - 使用稳定的节点和哈希
            Group {
                switch tab {
                case .detail:
                    StableNodeDetailView(
                        node: stableNode,
                        coordinatorBinding: $vditorCoordinator,
                        updateManager: updateManager
                    )
                    .id("stable-detail-\(stableNodeHash)")
                case .map:
                    NodeMapView(node: stableNode)
                case .related:
                    StableNodeGraphView(node: stableNode)
                        .id("stable-graph-\(stableNodeHash)")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditNodeSheet(node: stableNode)
        }
        .onAppear {
            setupStableNode()
        }
        .onReceive(store.$selectedNode) { newSelectedNode in
            // 只在节点真正变化时更新
            if let newNode = newSelectedNode, newNode.id == node.id {
                updateStableNodeSafely(newNode)
            }
        }
        // 监听节点内容变化但限制更新频率
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("nodeUpdated"))
                .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        ) { notification in
            if let updatedNode = notification.object as? Node,
               updatedNode.id == node.id {
                updateStableNodeSafely(updatedNode)
            }
        }
    }
    
    // MARK: - 稳定节点管理
    
    private func setupStableNode() {
        let latestNode = store.nodes.first { $0.id == node.id } ?? node
        updateStableNodeSafely(latestNode)
    }
    
    private func updateStableNodeSafely(_ newNode: Node) {
        let newHash = Self.generateStableHash(for: newNode)
        
        // 只在哈希真正变化时才更新
        guard newHash != stableNodeHash else {
            print("⚡ StableDetailPanel: 哈希未变化，跳过更新")
            return
        }
        
        let hasSignificantContentChange = hasSignificantChange(
            from: stableNode.markdown,
            to: newNode.markdown
        )
        
        // 异步更新状态，避免在视图更新期间修改状态
        Task { @MainActor in
            if hasSignificantContentChange {
                print("🔄 StableDetailPanel: 检测到实质性内容变化，更新节点")
                
                // 渐进式更新：先更新哈希，再更新节点
                withAnimation(.easeInOut(duration: 0.2)) {
                    stableNodeHash = newHash
                }
                
                // 短暂延迟后更新节点内容
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    stableNode = newNode
                    
                    // 安全更新WebView内容
                    if tab == .detail {
                        updateManager.setMarkdownSafely(
                            coordinator: vditorCoordinator,
                            content: newNode.markdown
                        )
                    }
                }
            } else {
                // 非内容变化，直接更新
                stableNode = newNode
                stableNodeHash = newHash
            }
        }
    }
    
    /// 生成稳定的哈希值
    static func generateStableHash(for node: Node) -> String {
        // 使用多维度信息生成更稳定的哈希
        let contentHash = node.markdown.hash
        let structuralHash = "\(node.text)-\(node.tags.count)".hash
        let timeWindow = Int(node.updatedAt.timeIntervalSince1970 / 300) // 5分钟窗口
        
        return "\(contentHash)-\(structuralHash)-\(timeWindow)"
    }
    
    /// 检测是否为实质性变化
    private func hasSignificantChange(from oldContent: String, to newContent: String) -> Bool {
        // 去除空白后比较
        let oldTrimmed = oldContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTrimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 长度变化超过阈值
        let lengthDiff = abs(newTrimmed.count - oldTrimmed.count)
        if lengthDiff > 20 {
            return true
        }
        
        // 内容完全不同
        return oldTrimmed != newTrimmed
    }
}

// MARK: - 稳定的NodeDetailView
struct StableNodeDetailView: View {
    let node: Node
    @Binding var coordinatorBinding: VditorWebView.Coordinator?
    let updateManager: WebViewUpdateManager
    
    @EnvironmentObject private var store: NodeStore
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var markdownText: String = ""
    @State private var isContentReady = false
    @State private var contentLoadingTask: Task<Void, Never>?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 简洁的标题栏
            HStack {
                Text(node.text)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // 状态指示器
                if !isContentReady {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("加载中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            
            // 稳定的Vditor编辑器
            if isContentReady {
                VditorWebView(
                    markdown: markdownText,
                    nodeId: node.id.uuidString,
                    onChange: { newValue in
                        handleContentChange(newValue)
                    },
                    coordinatorBinding: $coordinatorBinding
                )
                .background(Color.clear)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            loadContent()
        }
        .onChange(of: node.id) { _, _ in
            reloadContent()
        }
        .onDisappear {
            contentLoadingTask?.cancel()
        }
    }
    
    // MARK: - 内容管理
    
    private func loadContent() {
        contentLoadingTask?.cancel()
        
        contentLoadingTask = Task { @MainActor in
            do {
                // 短暂延迟确保WebView稳定
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                
                markdownText = node.markdown
                isContentReady = true
                
                print("✅ StableNodeDetailView: 内容加载完成")
                
            } catch {
                if !Task.isCancelled {
                    print("⚠️ 内容加载被中断: \(error)")
                }
            }
        }
    }
    
    private func reloadContent() {
        isContentReady = false
        loadContent()
    }
    
    private func handleContentChange(_ newValue: String) {
        guard !newValue.isEmpty else { return }
        
        // 防抖处理
        let currentTime = Date()
        markdownText = newValue
        
        // 使用增强的NodeStore进行安全更新
        if let enhancedStore = store as? EnhancedNodeStore {
            Task {
                await enhancedStore.updateNodeSafely(node.id, markdown: newValue)
            }
        } else {
            // 回退到原始方式
            store.updateNodeMarkdown(node.id, markdown: newValue)
        }
    }
}

// MARK: - 稳定的NodeGraphView
struct StableNodeGraphView: View {
    let node: Node
    @EnvironmentObject private var store: NodeStore
    @StateObject private var graphCache = NodeGraphDataCache.shared
    
    @State private var cachedGraphData: (nodes: [NodeGraphNode], edges: [NodeGraphEdge])?
    @State private var lastUpdateTime: Date = Date()
    
    var body: some View {
        Group {
            if let graphData = cachedGraphData {
                if graphData.nodes.count <= 1 {
                    EmptyGraphView()
                } else {
                    NodeContextGraphView(
                        nodes: graphData.nodes,
                        edges: graphData.edges,
                        title: "稳定节点图谱",
                        onNodeSelected: { nodeId, commandPressed in
                            // 稳定的节点选择处理
                            handleNodeSelection(nodeId: nodeId, commandPressed: commandPressed)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProgressView("加载图谱...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            refreshGraphData()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("nodeUpdated"))
                .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
        ) { _ in
            refreshGraphDataIfNeeded()
        }
    }
    
    private func refreshGraphData() {
        let computed = graphCache.getCachedGraphData(for: node, store: store)
        cachedGraphData = computed
        lastUpdateTime = Date()
        print("🔄 StableNodeGraphView: 图谱数据已刷新")
    }
    
    private func refreshGraphDataIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) > 2.0 else { return } // 最少2秒间隔
        
        refreshGraphData()
    }
    
    private func handleNodeSelection(nodeId: Int, commandPressed: Bool) {
        // 稳定的节点选择逻辑，避免触发递归更新
        print("🎯 StableNodeGraphView: 节点选择 ID=\(nodeId), Command=\(commandPressed)")
        // 这里可以添加具体的节点选择逻辑，但要避免触发store状态变化
    }
}