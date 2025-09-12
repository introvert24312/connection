import SwiftUI

// MARK: - 全屏标签图谱视图

struct FullscreenTagTypeGraphView: View {
    @StateObject private var windowManager = TagGraphWindowManager.shared
    @EnvironmentObject private var store: NodeStore
    @State private var graphNodes: [TagTypeGraphNode] = []
    @State private var graphEdges: [TagTypeGraphEdge] = []
    @State private var isLoading = true
    @AppStorage("tagTypeGraphInitialScale") private var tagTypeGraphInitialScale: Double = 0.8
    
    // 保留初始标签类型作为fallback
    private let initialTagType: Tag.TagType
    
    init(tagType: Tag.TagType) {
        self.initialTagType = tagType
    }
    
    // 计算当前应该使用的标签类型
    private var currentTagType: Tag.TagType {
        return windowManager.currentTagType ?? initialTagType
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            toolbar
            
            Divider()
            
            // 图谱主体
            if isLoading {
                loadingView
            } else if !graphNodes.isEmpty {
                // 使用UniversalRelationshipGraphView提供拖动和缩放功能
                UniversalRelationshipGraphView(
                    nodes: graphNodes,
                    edges: graphEdges,
                    title: "标签图谱: \(currentTagType.displayName)",
                    initialScale: tagTypeGraphInitialScale,
                    onNodeSelected: { nodeId, commandPressed, optionPressed in
                        if let selectedGraphNode = graphNodes.first(where: { $0.id == nodeId }),
                           case .contentNode(let contentNode) = selectedGraphNode.nodeType {
                            
                            if optionPressed {
                                // Option+点击：打开节点文件夹
                                print("⌥ Option+点击全屏标签图谱节点: \(contentNode.text)")
                                // TODO: 需要将NodeFolderManager.swift添加到Xcode项目中
                                // NodeFolderManager.shared.openNodeFolderInFinder(contentNode)
                                return
                            }
                            
                            if commandPressed {
                                // Command+点击：进入节点（切换到主窗口并选中该节点）
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("switchToMainWindowAndSelectNode"),
                                    object: contentNode
                                )
                            } else {
                                // 普通点击：标准选择行为
                                store.selectNode(contentNode)
                            }
                        }
                    },
                    onNodeDeselected: {
                        print("🖱️ 取消选中标签图谱节点")
                    },
                    onFitGraph: {
                        print("🔄 适应画布")
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyStateView
            }
        }
        .navigationTitle("标签图谱: \(currentTagType.displayName)")
        .onAppear {
            print("📊 FullscreenTagTypeGraphView appeared for: \(currentTagType.displayName)")
            
            // 标记窗口为可见
            windowManager.markWindowVisible()
            
            // 如果WindowManager有不同的标签类型，更新为WindowManager的类型
            if let managerTagType = windowManager.currentTagType, managerTagType != initialTagType {
                print("🔄 FullscreenTagTypeGraphView: 使用WindowManager的标签类型: \(managerTagType.displayName)")
                loadGraphData()
            } else if windowManager.currentTagType == nil {
                // 如果WindowManager没有标签类型，设置为初始类型
                print("🔄 FullscreenTagTypeGraphView: 设置WindowManager的标签类型为初始类型: \(initialTagType.displayName)")
                windowManager.updateTagType(initialTagType)
                loadGraphData()
            } else {
                loadGraphData()
            }
        }
        .onDisappear {
            print("📊 FullscreenTagTypeGraphView disappeared")
            windowManager.markWindowHidden()
        }
        .onReceive(windowManager.$currentTagType) { newTagType in
            guard let newTagType = newTagType else { return }
            
            print("🔄 FullscreenTagTypeGraphView: 接收到WindowManager标签类型更新: \(newTagType.displayName)")
            print("🔄 当前标签类型: \(currentTagType.displayName)")
            
            // 只有当标签类型真的改变时才重新加载
            if newTagType != currentTagType {
                print("✅ FullscreenTagTypeGraphView: 标签类型已更改，重新加载数据")
                loadGraphData()
            } else {
                print("ℹ️ FullscreenTagTypeGraphView: 标签类型相同，无需重新加载")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openTagTypeGraph"))) { notification in
            // 保留通知监听作为向后兼容性 - 但主要逻辑已转移到WindowManager
            if let newTagType = notification.object as? Tag.TagType {
                print("🔄 FullscreenTagTypeGraphView: 接收到openTagTypeGraph通知 (向后兼容): \(newTagType.displayName)")
                // WindowManager会处理这个通知，我们这里只做日志记录
            }
        }
    }
    
    // MARK: - 子视图
    
    private var toolbar: some View {
        HStack {
            Text("标签图谱: \(currentTagType.displayName)")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("重新加载") { 
                    loadGraphData()
                }
                .disabled(isLoading)
                
                Button("适应画布") { 
                    NotificationCenter.default.post(name: Notification.Name("fitGraph"), object: nil)
                    print("🔄 适应画布")
                }
                .disabled(graphNodes.isEmpty)
            }
        }
        .padding()
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("正在加载标签图谱...")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "network.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("暂无图谱数据")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            
            Text("该标签类型下没有可用的节点关系")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 数据加载
    
    private func loadGraphData() {
        isLoading = true
        
        Task { @MainActor in
            let universalData = store.getTagTypeUniversalGraphData(for: currentTagType)
            self.graphNodes = universalData.nodes
            self.graphEdges = universalData.edges
            self.isLoading = false
            print("🕸️ 图谱数据加载完成: \(currentTagType.displayName), 节点数量: \(universalData.nodes.count), 边数量: \(universalData.edges.count)")
        }
    }
}