import SwiftUI
import AppKit

struct GraphView: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var dataManager = NodeGraphDataManager()  // 🆕 每个视图独立的数据管理器，就像GlobalTagGraphView
    @AppStorage("globalGraphInitialScale") private var globalGraphInitialScale: Double = 1.0
    @State private var cachedNodes: [NodeGraphNode] = []
    @State private var cachedEdges: [NodeGraphEdge] = []
    @State private var showingNodeSelector = false
    private let instanceId = String(UUID().uuidString.prefix(8))
    
    // 层级筛选状态
    @State private var showingLayerSelector = false
    
    // 保存预设对话框状态
    @State private var showingSavePresetDialog = false
    @State private var newPresetName = ""
    
    // 🆕 使用数据管理器生成图谱数据
    private func updateGraphData() {
        // 🔒 如果图谱被锁定，不更新数据
        guard !dataManager.isLocked else {
            print("🔒 [全局节点图谱-\(instanceId)] 图谱已锁定，跳过数据更新")
            return
        }
        
        print("📊 [全局节点图谱-\(instanceId)] 开始更新图谱数据")
        print("   - 选中节点: \(dataManager.selectedNodeIds.count)个")
        print("   - 选中层级: \(dataManager.selectedLayerIds.count)个")
        
        let data = dataManager.generateGraphData(from: store)
        cachedNodes = data.nodes
        cachedEdges = data.edges
        
        print("📊 [全局节点图谱-\(instanceId)] 图谱数据更新完成")
        print("   - 生成节点: \(cachedNodes.count)个")
        print("   - 生成边: \(cachedEdges.count)条")
    }
    
    var body: some View {
        ZStack {
            mainContent
        }
        .navigationTitle("全局节点图谱")
        .alert("保存节点图谱预设", isPresented: $showingSavePresetDialog) {
            savePresetAlert
        } message: {
            Text("为当前的节点和层级选择创建一个预设")
        }
        .modifier(EventHandlersModifier(
            instanceId: instanceId,
            dataManager: dataManager,
            store: store,
            updateGraphData: updateGraphData
        ))
    }
    
    // MARK: - 主内容视图
    
    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            toolbarView
            Divider()
            graphContent
        }
    }
    
    // MARK: - 图谱内容
    
    @ViewBuilder
    private var graphContent: some View {
        if cachedNodes.isEmpty {
            EmptyGraphView()
        } else {
            nodeContextGraph
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environmentObject(store)
        }
    }
    
    // MARK: - 节点上下文图谱
    
    private var nodeContextGraph: some View {
        NodeContextGraphView(
            nodes: cachedNodes,
            edges: cachedEdges,
            title: "全局节点图谱",
            initialScale: globalGraphInitialScale,
            onNodeSelected: handleNodeSelection
        )
    }
    
    // MARK: - 节点选择处理
    
    private func handleNodeSelection(nodeId: Int, commandPressed: Bool, optionPressed: Bool) {
        // 检测Option键，处理节点文件夹功能
        if optionPressed {
            print("⌥ Option+点击节点，ID: \(nodeId)")
            if let selectedGraphNode = cachedNodes.first(where: { $0.id == nodeId }),
               let selectedNode = selectedGraphNode.node {
                // 打开节点文件夹
                NodeFolderManager.shared.openNodeFolderInFinder(selectedNode)
            }
            return
        }
        
        // 当点击节点时，选择对应的节点（只有节点才会触发选择）
        if let selectedGraphNode = cachedNodes.first(where: { $0.id == nodeId }),
           let selectedNode = selectedGraphNode.node {
            store.selectNode(selectedNode)
        }
    
    // MARK: - 工具栏视图
    
    @ViewBuilder
    private var toolbarView: some View {
        HStack {
            // 左侧：过滤信息显示
            buildFilterInfoView()
            
            Spacer()
            
            // 预设和看板按钮组
            presetButtonGroup
            
            // 锁定按钮
            lockButton
            
            // 节点看板按钮
            nodeBoardButton
            
            // 重置按钮
            if dataManager.hasActiveFilters {
                resetButton
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - 工具栏按钮组件
    
    @ViewBuilder
    private var presetButtonGroup: some View {
        Group {
            // 图谱预设按钮
            Button("图谱预设") {
                showPresetManagerWindow()
                print("📚 [全局节点图谱] 打开预设管理")
            }
            .buttonStyle(.bordered)
            .help("管理图谱预设")
            
            // 保存为预设按钮
            Button("保存为预设") {
                showingSavePresetDialog = true
                print("💾 [全局节点图谱] 保存当前状态为预设")
            }
            .buttonStyle(.bordered)
            .help("保存当前状态为预设")
            .disabled(dataManager.selectedNodeIds.isEmpty && dataManager.selectedLayerIds.isEmpty)
        }
    }
    
    private var lockButton: some View {
        Button(dataManager.isLocked ? "🔓 解锁" : "🔒 锁定") {
            dataManager.toggleLockState(with: store)
            updateGraphData()
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(dataManager.isLocked ? Color.orange.opacity(0.2) : Color.blue.opacity(0.1))
        .foregroundColor(dataManager.isLocked ? .orange : .blue)
        .cornerRadius(6)
        .help(dataManager.isLocked ? "解锁图谱以接收数据更新" : "锁定图谱以固定当前显示内容")
    }
    
    private var nodeBoardButton: some View {
        Button("节点看板") {
            showNodeBoardWindow()
            print("📋 [全局节点图谱] 打开节点看板")
        }
        .buttonStyle(.borderedProminent)
        .help("打开节点看板 (⌘B)")
    }
    
    private var resetButton: some View {
        Button("显示全部") {
            dataManager.clearAllFilters()
            updateGraphData()
        }
    }
    
    // MARK: - Alert 内容
    
    @ViewBuilder
    private var savePresetAlert: some View {
        Group {
            TextField("预设名称", text: $newPresetName)
            Button("取消", role: .cancel) {
                newPresetName = ""
            }
            Button("保存") {
                if !newPresetName.isEmpty {
                    NodeGraphPresetManager.shared.saveCurrentAsPreset(
                        name: newPresetName,
                        description: nil,
                        selectedNodeIds: dataManager.selectedNodeIds,
                        selectedLayerIds: dataManager.selectedLayerIds
                    )
                    newPresetName = ""
                }
            }
        }
    }
    
    private func showPresetManagerWindow() {
        let presetManagerView = NodeGraphPresetManagerView(
            selectedNodeIds: Binding(
                get: { dataManager.selectedNodeIds },
                set: { dataManager.selectedNodeIds = $0 }
            ),
            selectedLayerIds: Binding(
                get: { dataManager.selectedLayerIds },
                set: { dataManager.selectedLayerIds = $0 }
            )
        )
        .environmentObject(store)
        
        let hostingView = NSHostingView(rootView: presetManagerView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.contentView = hostingView
        newWindow.title = "节点图谱预设管理"
        newWindow.setFrameAutosaveName("NodeGraphPresetManagerWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        
        print("🪟 [节点图谱预设管理] 窗口已创建")
    }
}

// MARK: - Empty Graph View

struct EmptyGraphView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "circle.hexagonpath")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("暂无图谱数据")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("添加一些节点来生成全局节点图谱")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Event Handlers Modifier

struct EventHandlersModifier: ViewModifier {
    let instanceId: String
    let dataManager: NodeGraphDataManager
    let store: NodeStore
    let updateGraphData: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                print("📋 [全局节点图谱] 视图出现，初始化数据管理器")
                
                if let presetData = NodeGraphPresetManager.shared.applyLastUsedPresetIfAvailable() {
                    dataManager.selectedNodeIds = presetData.selectedNodeIds
                    dataManager.selectedLayerIds = presetData.selectedLayerIds
                    print("✅ [全局节点图谱] 已应用上次使用的预设")
                } else {
                    print("ℹ️ [全局节点图谱] 没有上次使用的预设，使用默认状态")
                }
                
                updateGraphData()
            }
            .onChange(of: store.nodes) {
                updateGraphData()
            }
            .onChange(of: dataManager.selectedNodeIds) {
                print("📊 [全局节点图谱-\(instanceId)] 检测到selectedNodeIds变化: \(dataManager.selectedNodeIds.count)个")
                updateGraphData()
            }
            .onChange(of: dataManager.selectedLayerIds) {
                print("📊 [全局节点图谱-\(instanceId)] 检测到selectedLayerIds变化: \(dataManager.selectedLayerIds.count)个")
                updateGraphData()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("nodeSelectionChangedFromBoard"))) { notification in
                handleNodeSelectionNotification(notification)
            }
    }
    
    private func handleNodeSelectionNotification(_ notification: Notification) {
        print("📡 [全局节点图谱-\(instanceId)] 收到节点看板广播通知")
        
        guard let userInfo = notification.userInfo else {
            print("❌ [全局节点图谱-\(instanceId)] 通知没有userInfo")
            return
        }
        
        print("📡 [全局节点图谱-\(instanceId)] 收到通知userInfo: \(userInfo)")
        
        guard let sourceInstance = userInfo["sourceInstance"] as? String else {
            print("❌ [全局节点图谱-\(instanceId)] 无法解析sourceInstance，类型: \(type(of: userInfo["sourceInstance"]))")
            return
        }
        
        print("📡 [全局节点图谱-\(instanceId)] 广播来源: \(sourceInstance)")
        
        if dataManager.isLocked {
            print("🔒 [全局节点图谱-\(instanceId)] 图谱已锁定，忽略节点看板广播")
            return
        }
        
        if let selectedNodeIdStrings = userInfo["selectedNodeIds"] as? [String],
           let selectedLayerIdStrings = userInfo["selectedLayerIds"] as? [String] {
            
            let selectedNodeIds = Set(selectedNodeIdStrings.compactMap { UUID(uuidString: $0) })
            let selectedLayerIds = Set(selectedLayerIdStrings.compactMap { UUID(uuidString: $0) })
            
            print("📡 [全局节点图谱-\(instanceId)] 应用广播选择: 节点=\(selectedNodeIds.count), 层级=\(selectedLayerIds.count)")
            
            DispatchQueue.main.async {
                dataManager.updateSelectedNodes(selectedNodeIds)
                dataManager.updateSelectedLayers(selectedLayerIds)
                updateGraphData()
            }
        }
    }
}


#Preview {
    GraphView()
        .environmentObject(NodeStore.shared)
}

// MARK: - 全局节点图谱窗口管理器 - 支持多开版本

/// 全局节点图谱窗口管理器，支持多开模式，每个窗口都有独立的数据管理器
@MainActor
class NodeGraphWindowManager: ObservableObject {
    static let shared = NodeGraphWindowManager()
    
    private init() {
        print("🏗️ [节点图谱窗口管理器] 初始化，支持多开模式")
    }
    
    /// 显示全局节点图谱窗口 - 支持多开
    func showNodeGraphWindow() {
        print("🪟 [节点图谱窗口管理器] 创建新的节点图谱窗口")
        
        // 每次都创建新的GraphView实例，每个实例都有独立的数据管理器
        let contentView = GraphView()
            .environmentObject(NodeStore.shared)
        
        let hostingView = NSHostingView(rootView: contentView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.contentView = hostingView
        newWindow.title = "全局节点图谱"
        newWindow.setFrameAutosaveName("NodeGraphWindow")
        newWindow.isReleasedWhenClosed = false
        
        // 窗口关闭处理
        let delegate = NodeGraphWindowDelegate {
            print("🗑️ [节点图谱窗口] 窗口已关闭")
        }
        newWindow.delegate = delegate
        
        newWindow.makeKeyAndOrderFront(nil)
        
        print("✅ [节点图谱窗口管理器] 新窗口已创建并显示")
    }
}

// MARK: - 节点图谱窗口委托

private class NodeGraphWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
