import SwiftUI

// MARK: - 全屏标签类型图谱视图

struct FullscreenTagTypeGraphView: View {
    @State private var currentTagType: Tag.TagType
    @EnvironmentObject private var store: NodeStore
    @State private var graphNodes: [TagTypeGraphNode] = []
    @State private var graphEdges: [TagTypeGraphEdge] = []
    @State private var isLoading = true
    @AppStorage("tagTypeGraphInitialScale") private var tagTypeGraphInitialScale: Double = 0.8
    
    init(tagType: Tag.TagType) {
        self._currentTagType = State(initialValue: tagType)
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
                    title: "标签类型图谱: \(currentTagType.displayName)",
                    initialScale: tagTypeGraphInitialScale,
                    onNodeSelected: { nodeId, commandPressed in
                        if commandPressed {
                            // Command+点击：进入节点（切换到主窗口并选中该节点）
                            if let selectedGraphNode = graphNodes.first(where: { $0.id == nodeId }),
                               case .contentNode(let contentNode) = selectedGraphNode.nodeType {
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("switchToMainWindowAndSelectNode"),
                                    object: contentNode
                                )
                            }
                        } else {
                            // 普通点击：标准选择行为
                            if let selectedGraphNode = graphNodes.first(where: { $0.id == nodeId }),
                               case .contentNode(let contentNode) = selectedGraphNode.nodeType {
                                store.selectNode(contentNode)
                            }
                        }
                    },
                    onNodeDeselected: {
                        print("🖱️ 取消选中标签类型图谱节点")
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
        .navigationTitle("标签类型图谱: \(currentTagType.displayName)")
        .onAppear {
            print("📊 FullscreenTagTypeGraphView appeared for: \(currentTagType.displayName)")
            loadGraphData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openTagTypeGraph"))) { notification in
            if let newTagType = notification.object as? Tag.TagType {
                print("🔄 FullscreenTagTypeGraphView: 接收到新的标签类型: \(newTagType.displayName)")
                print("🔄 当前标签类型: \(currentTagType.displayName)")
                if newTagType != currentTagType {
                    print("✅ FullscreenTagTypeGraphView: 标签类型已更改，重新加载数据")
                    currentTagType = newTagType
                    loadGraphData()
                } else {
                    print("ℹ️ FullscreenTagTypeGraphView: 标签类型相同，无需重新加载")
                }
            }
        }
    }
    
    // MARK: - 子视图
    
    private var toolbar: some View {
        HStack {
            Text("标签类型图谱: \(currentTagType.displayName)")
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
            
            Text("正在加载标签类型图谱...")
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