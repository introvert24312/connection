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
                .help("打开节点看板 (⌘B)")
                
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
        .onAppear {
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
        .navigationTitle("全局节点图谱")
        .alert("保存节点图谱预设", isPresented: $showingSavePresetDialog) {
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
        } message: {
            Text("请输入预设名称，保存当前的节点和层级选择状态。")
        }
        .sheet(isPresented: $showingPresetManager) {
            NodeGraphPresetManagerView()
                .frame(minWidth: 600, minHeight: 400)
        }
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
    
    private func showNodeBoardWindow() {
        // 🆕 完全照抄GlobalTagGraphView.showAssociatedTagIndexWindow的逻辑
        let associatedNodeBoardView = NodeBoardView(
            associatedDataManager: dataManager  // 传递当前窗口的数据管理器
        )
        .environmentObject(NodeStore.shared)
        
        let hostingView = NSHostingView(rootView: associatedNodeBoardView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.contentView = hostingView
        newWindow.title = "节点看板"
        newWindow.setFrameAutosaveName("AssociatedNodeBoardWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        
        print("🪟 [节点看板] 关联窗口已创建")
        print("🔗 [全局节点图谱-\(instanceId)] 打开关联节点看板")
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
    
    private init() {
        print("🏗️ [节点图谱窗口管理器] 初始化，支持多开模式")
    }
    
    /// 显示节点图谱窗口 - 支持多开，每个窗口独立
    func showNodeGraphWindow() {
        print("🪟 [节点图谱窗口管理器] 创建节点图谱窗口")
        
        // 🆕 简化实现：每次都创建新的GraphView，就像GlobalTagGraphView一样
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
        
        print("✅ [节点图谱窗口管理器] 窗口已创建并显示")
    }
    
}

// MARK: - 窗口委托

private class NodeGraphPresetWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        print("🗑️ [节点图谱预设管理] 窗口已关闭")
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