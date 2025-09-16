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
    
    // 预设和看板状态
    @State private var showingPresetManager = false
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
        mainContentView
            .onAppear(perform: handleOnAppear)
            .onChange(of: store.nodes) { _, _ in
                updateGraphData()
            }
            .onChange(of: dataManager.selectedNodeIds) { _, _ in
                print("📊 [全局节点图谱-\(instanceId)] 检测到selectedNodeIds变化: \(dataManager.selectedNodeIds.count)个")
                updateGraphData()
            }
            .onChange(of: dataManager.selectedLayerIds) { _, _ in
                print("📊 [全局节点图谱-\(instanceId)] 检测到selectedLayerIds变化: \(dataManager.selectedLayerIds.count)个")
                updateGraphData()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("nodeSelectionChangedFromBoard"))) { notification in
                handleBroadcastNotification(notification)
            }
            .navigationTitle("全局节点图谱")
            .alert("保存节点图谱预设", isPresented: $showingSavePresetDialog, actions: {
                savePresetAlertContent
            }, message: {
                Text("请输入预设名称，保存当前的节点和层级选择状态。")
            })
            .sheet(isPresented: $showingPresetManager) {
                NodeGraphPresetManagerView()
                    .frame(minWidth: 600, minHeight: 400)
            }
    }
    
    // MARK: - 主要内容视图
    
    @ViewBuilder
    private var mainContentView: some View {
        VStack(spacing: 0) {
            toolbarView
            Divider()
            graphContentView
        }
    }
    
    // MARK: - 工具栏视图
    
    @ViewBuilder
    private var toolbarView: some View {
        HStack {
            buildFilterInfoView()
            Spacer()
            presetButtonsView
            lockToggleButton
            nodeBoardButton
            resetButton
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - 预设按钮组
    
    @ViewBuilder
    private var presetButtonsView: some View {
        // 图谱预设按钮
        Button("图谱预设") {
            showingPresetManager = true
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
    
    // MARK: - 锁定切换按钮
    
    @ViewBuilder
    private var lockToggleButton: some View {
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
    
    // MARK: - 节点看板按钮
    
    @ViewBuilder
    private var nodeBoardButton: some View {
        Button("节点看板") {
            showNodeBoardWindow()
            print("📋 [全局节点图谱] 打开节点看板")
        }
        .buttonStyle(.borderedProminent)
        .help("打开节点看板 (⌘B)")
    }
    
    // MARK: - 重置按钮
    
    @ViewBuilder
    private var resetButton: some View {
        if dataManager.hasActiveFilters {
            Button("显示全部") {
                dataManager.clearAllFilters()
                updateGraphData()
            }
        }
    }
    
    // MARK: - 图谱内容视图
    
    @ViewBuilder
    private var graphContentView: some View {
        if cachedNodes.isEmpty {
            EmptyGraphView()
        } else {
            NodeContextGraphView(
                nodes: cachedNodes,
                edges: cachedEdges,
                title: "全局节点图谱",
                initialScale: globalGraphInitialScale,
                onNodeSelected: handleNodeSelection
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environmentObject(store)
        }
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
    }
    
    // MARK: - 事件处理函数
    
    private func handleOnAppear() {
        print("📋 [全局节点图谱] 视图出现，初始化数据管理器")
        
        // 🆕 尝试应用上次使用的预设
        if let presetData = NodeGraphPresetManager.shared.applyLastUsedPresetIfAvailable() {
            dataManager.selectedNodeIds = presetData.selectedNodeIds
            dataManager.selectedLayerIds = presetData.selectedLayerIds
            print("✅ [全局节点图谱] 已应用上次使用的预设")
        } else {
            print("ℹ️ [全局节点图谱] 没有上次使用的预设，使用默认状态")
        }
        
        updateGraphData()
    }
    
    private func handleBroadcastNotification(_ notification: Notification) {
        // 🆕 接收节点看板的广播选择（一对多模式）
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
        
        // 🆕 只有在解锁状态时才接收广播（按你的要求）
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
    
    // MARK: - Alert内容
    
    @ViewBuilder
    private var savePresetAlertContent: some View {
        TextField("预设名称", text: $newPresetName)
        
        Button("保存") {
            let trimmedName = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
            print("🚀 [全局节点图谱-\(instanceId)] 保存按钮点击 - 预设名称: '\(trimmedName)'")
            print("🔍 [全局节点图谱-\(instanceId)] 当前选择状态:")
            print("   - 选中节点: \(dataManager.selectedNodeIds.count)个")
            print("   - 选中层级: \(dataManager.selectedLayerIds.count)个")
            
            if !trimmedName.isEmpty {
                print("📝 [全局节点图谱-\(instanceId)] 开始调用saveCurrentAsPreset...")
                NodeGraphPresetManager.shared.saveCurrentAsPreset(
                    name: trimmedName,
                    selectedNodeIds: dataManager.selectedNodeIds,
                    selectedLayerIds: dataManager.selectedLayerIds
                )
                print("✅ [全局节点图谱-\(instanceId)] saveCurrentAsPreset调用完成")
                
                // 清空输入框
                newPresetName = ""
            } else {
                print("⚠️ [全局节点图谱-\(instanceId)] 预设名称为空，跳过保存")
            }
        }
        .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        
        Button("取消", role: .cancel) {
            newPresetName = ""
        }
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

#Preview {
    GraphView()
        .environmentObject(NodeStore.shared)
}
