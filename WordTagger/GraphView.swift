import SwiftUI
import AppKit

struct GraphView: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var dataManager = NodeGraphDataManager()  // 🆕 每个视图独立的数据管理器
    @AppStorage("globalGraphInitialScale") private var globalGraphInitialScale: Double = 1.0
    @State private var cachedNodes: [NodeGraphNode] = []
    @State private var cachedEdges: [NodeGraphEdge] = []
    @State private var showingNodeSelector = false
    
    // 层级筛选状态
    @State private var showingLayerSelector = false
    
    // 预设和看板状态
    @State private var showingPresetManager = false
    @State private var showingSavePresetDialog = false
    @State private var newPresetName = ""
    @State private var newPresetDescription = ""
    
    // 🆕 使用数据管理器生成图谱数据
    private func updateGraphData() {
        // 🔒 如果图谱被锁定，不更新数据
        guard !dataManager.isLocked else {
            print("🔒 [全局节点图谱] 图谱已锁定，跳过数据更新")
            return
        }
        
        let data = dataManager.generateGraphData(from: store)
        cachedNodes = data.nodes
        cachedEdges = data.edges
    }
    
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                // 左侧：过滤信息显示
                buildFilterInfoView()
                
                Spacer()
                
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
                
                // 🔒 锁定/解锁按钮
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
                
                // 节点看板按钮
                Button("节点看板") {
                    showNodeBoardWindow()
                    print("📋 [全局节点图谱] 打开节点看板")
                }
                .buttonStyle(.borderedProminent)
                .help("打开节点看板")
                
                // 重置按钮
                if dataManager.hasActiveFilters {
                    Button("显示全部") {
                        dataManager.clearAllFilters()
                        updateGraphData()
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 图谱内容
            if cachedNodes.isEmpty {
                EmptyGraphView()
            } else {
                NodeContextGraphView(
                    nodes: cachedNodes,
                    edges: cachedEdges,
                    title: "全局节点图谱",
                    initialScale: globalGraphInitialScale,
                    onNodeSelected: { nodeId, commandPressed, optionPressed in
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
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environmentObject(store)
            }
        }
        .sheet(isPresented: $showingNodeSelector) {
            NodeSelectorView(selectedNodeIds: $dataManager.selectedNodeIds)
                .environmentObject(store)
                .frame(width: 700, height: 600)
                .background(WindowAccessor())
        }
        .sheet(isPresented: $showingLayerSelector) {
            LayerSelectorView(selectedLayerIds: $dataManager.selectedLayerIds)
                .environmentObject(store)
                .frame(width: 600, height: 500)
                .background(LayerWindowAccessor())
        }
        .sheet(isPresented: $showingPresetManager) {
            NodeGraphPresetManagerView(
                selectedNodeIds: $dataManager.selectedNodeIds,
                selectedLayerIds: $dataManager.selectedLayerIds
            )
            .environmentObject(store)
            .frame(width: 800, height: 600)
        }
        .alert("保存节点图谱预设", isPresented: $showingSavePresetDialog) {
            TextField("预设名称", text: $newPresetName)
            TextField("描述（可选）", text: $newPresetDescription)
            
            Button("保存") {
                if !newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    saveCurrentAsPreset()
                    newPresetName = ""
                    newPresetDescription = ""
                }
            }
            .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            
            Button("取消", role: .cancel) {
                newPresetName = ""
                newPresetDescription = ""
            }
        } message: {
            Text("为当前的节点和层级筛选状态创建一个预设，以便后续快速加载。")
        }
        .onKeyPress(.init("k"), phases: .down) { _ in
            NotificationCenter.default.post(name: Notification.Name("fitGraph"), object: nil)
            return .handled
        }
        .onAppear {
            print("📋 [全局节点图谱] 视图出现，初始化数据管理器")
            updateGraphData()
        }
        .onChange(of: store.nodes) {
            updateGraphData()
        }
        .onChange(of: dataManager.selectedNodeIds) {
            updateGraphData()
        }
        .onChange(of: dataManager.selectedLayerIds) {
            updateGraphData()
        }
        .onChange(of: dataManager.displayedNodes) {
            updateGraphData()
        }
        .onChange(of: store.selectedTag) {
            updateGraphData()
        }
        .onChange(of: store.showAllTagTypeNodes) {
            updateGraphData()
        }
        .onChange(of: store.expandedTagTypes) {
            updateGraphData()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NodeBoardSelectionChanged"))) { notification in
            if let userInfo = notification.userInfo,
               let nodeIds = userInfo["selectedNodeIds"] as? [UUID],
               let layerIds = userInfo["selectedLayerIds"] as? [UUID] {
                
                print("🔄 GraphView: 收到节点看板选择变化通知")
                print("   - 节点: \(nodeIds.count) 个")
                print("   - 层级: \(layerIds.count) 个")
                
                // 更新数据管理器的选择状态
                dataManager.updateSelectedNodes(Set(nodeIds))
                dataManager.updateSelectedLayers(Set(layerIds))
                
                // 强制更新图谱数据
                updateGraphData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("compoundNodeRefreshed"))) { notification in
            print("📨 [GraphView] 收到复合节点刷新通知！")
            
            if let userInfo = notification.userInfo {
                print("   - 通知数据: \(userInfo)")
                if let compoundNodeId = userInfo["compoundNodeId"] as? UUID,
                   let compoundNodeName = userInfo["compoundNodeName"] as? String,
                   let childNodeName = userInfo["childNodeName"] as? String {
                    print("   - 复合节点: \(compoundNodeName) (ID: \(compoundNodeId))")
                    print("   - 子节点: \(childNodeName)")
                }
            }
            
            // 如果图谱被锁定，不进行更新
            if !dataManager.isLocked {
                print("🔄 GraphView: 开始更新图谱数据...")
                // 强制更新图谱数据以反映复合节点的最新状态
                updateGraphData()
                print("✅ GraphView: 图谱已更新以反映复合节点变化")
            } else {
                print("🔒 GraphView: 图谱已锁定，跳过更新")
            }
        }
        .navigationTitle("全局节点图谱")
    }
    
    // MARK: - 过滤信息显示
    
    @ViewBuilder
    private func buildFilterInfoView() -> some View {
        if dataManager.isLocked {
            // 🔒 锁定状态显示
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                
                Text("图谱已锁定")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fontWeight(.medium)
                
                Text("(\(dataManager.lockedNodes?.count ?? 0) 个节点)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if dataManager.hasActiveFilters {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                Text(dataManager.buildFilterDescription(with: store))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "circle.hexagonpath")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                Text("节点: \(store.nodes.count) | 层级: \(store.layers.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    
    // MARK: - 预设和看板功能
    
    private func showNodeBoardWindow() {
        // 创建节点看板窗口
        let nodeBoardView = NodeBoardView()
        .environmentObject(store)
        
        let hostingView = NSHostingView(rootView: nodeBoardView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.contentView = hostingView
        newWindow.title = "节点看板"
        newWindow.setFrameAutosaveName("NodeBoardWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        
        print("🪟 [节点看板] 窗口已创建")
    }
    
    private func saveCurrentAsPreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = newPresetDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !name.isEmpty else { return }
        
        // 创建并保存节点图谱预设
        let preset = NodeGraphPreset(
            name: name,
            description: description.isEmpty ? nil : description,
            selectedNodeIds: dataManager.selectedNodeIds,
            selectedLayerIds: dataManager.selectedLayerIds,
            createdAt: Date(),
            lastUsed: Date()
        )
        
        NodeGraphPresetManager.shared.savePreset(preset)
        
        print("💾 保存节点图谱预设: \(name)")
        print("   - 选中节点数: \(dataManager.selectedNodeIds.count)")
        print("   - 选中层数: \(dataManager.selectedLayerIds.count)")
        print("   - 描述: \(description.isEmpty ? "无" : description)")
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

// MARK: - 全局节点图谱窗口管理器 - 支持多开版本

/// 全局节点图谱窗口管理器，支持多开模式，每个窗口都有独立的数据管理器
@MainActor
class NodeGraphWindowManager: ObservableObject {
    static let shared = NodeGraphWindowManager()
    
    // 不再保存窗口引用，每次都创建新窗口以支持多开
    private init() {
        print("🏗️ [节点图谱窗口管理器] 初始化，支持多开模式")
    }
    
    /// 显示全局节点图谱窗口 - 支持多开
    func showNodeGraphWindow() {
        print("🪟 [节点图谱窗口管理器] 创建新的节点图谱窗口")
        
        // 🆕 每次都创建新的GraphView实例，每个实例都有独立的数据管理器
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
        
        // 窗口关闭处理 - 不保存窗口引用
        let delegate = NodeGraphWindowDelegate {
            print("🗑️ [节点图谱窗口] 窗口已关闭")
        }
        newWindow.delegate = delegate
        
        // 🆕 多开支持：不再保存窗口引用，每次都创建新窗口
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