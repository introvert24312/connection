import SwiftUI
import AppKit

// MARK: - 节点图谱数据管理器 - 独立实例版本

/// 节点图谱数据管理器，支持独立实例以实现一一对应的窗口映射
@MainActor
class NodeGraphDataManager: ObservableObject {
    // 🆕 过滤状态 - 每个实例独立管理
    @Published var selectedNodeIds: Set<UUID> = []
    @Published var selectedLayerIds: Set<UUID> = []
    @Published var searchQuery: String = ""
    @Published var displayedNodes: [Node] = []
    
    // 🔒 图谱锁定状态 - 锁定后不再接收数据更新
    @Published var isLocked: Bool = false
    @Published var lockedNodes: [Node]?
    
    // 实例标识符，用于调试
    private let instanceId = UUID().uuidString.prefix(8)
    
    init() {
        print("🏗️ [节点图谱管理器-\(instanceId)] 创建新实例")
    }
    
    // MARK: - 图谱数据生成
    
    /// 生成节点图谱数据
    func generateGraphData(from store: NodeStore) -> (nodes: [NodeGraphNode], edges: [NodeGraphEdge]) {
        print("🔄 [节点图谱管理器-\(instanceId)] 开始生成图谱数据")
        
        var nodes: [NodeGraphNode] = []
        var edges: [NodeGraphEdge] = []
        var addedTagKeys: Set<String> = []
        
        // 🔒 根据锁定状态选择数据源
        let sourceNodes: [Node]
        if isLocked, let lockedData = lockedNodes {
            sourceNodes = lockedData
            print("🔒 [节点图谱管理器-\(instanceId)] 使用锁定数据: \(lockedData.count)个节点")
        } else {
            sourceNodes = store.nodes
            print("📊 [节点图谱管理器-\(instanceId)] 使用实时数据: \(sourceNodes.count)个节点")
        }
        
        // 首先根据层级筛选进行过滤
        let layerFilteredNodes: [Node]
        if selectedLayerIds.isEmpty {
            // 显示所有层的节点
            layerFilteredNodes = sourceNodes
        } else {
            // 只显示选中层的节点
            layerFilteredNodes = sourceNodes.filter { selectedLayerIds.contains($0.layerId) }
        }
        
        // 根据选择的节点ID和标签筛选来确定要显示的节点
        let nodesToShow: [Node]
        if !selectedNodeIds.isEmpty {
            nodesToShow = layerFilteredNodes.filter { selectedNodeIds.contains($0.id) }
        } else if !displayedNodes.isEmpty {
            // 搜索结果也需要应用层级筛选
            nodesToShow = displayedNodes.filter { selectedLayerIds.isEmpty || selectedLayerIds.contains($0.layerId) }
        } else if let selectedTag = store.selectedTag {
            // 🏷️ 标签筛选逻辑
            if store.showAllTagTypeNodes {
                // 显示该标签类型下的所有节点
                if store.expandedTagTypes.count > 1 {
                    nodesToShow = layerFilteredNodes.filter { node in
                        node.tags.contains { tag in store.expandedTagTypes.contains(tag.type) }
                    }
                } else {
                    nodesToShow = layerFilteredNodes.filter { node in
                        node.tags.contains { $0.type == selectedTag.type }
                    }
                }
            } else {
                // 显示该具体标签的节点
                nodesToShow = layerFilteredNodes.filter { $0.hasTag(selectedTag) }
            }
        } else {
            nodesToShow = layerFilteredNodes
        }
        
        var addedNodeIds: Set<UUID> = []
        
        // 首先添加所有顶级节点
        for node in nodesToShow {
            nodes.append(NodeGraphNode(node: node))
            addedNodeIds.insert(node.id)
            
            // 如果是复合节点，递归添加其子节点结构
            if node.isCompound {
                addChildNodesForGraph(
                    for: node,
                    store: store,
                    nodes: &nodes,
                    addedTagKeys: &addedTagKeys,
                    addedNodeIds: &addedNodeIds,
                    depth: 1
                )
            }
        }
        
        // 添加所有已添加节点的标签（去重），但过滤掉复合节点的管理标签
        let allAddedNodes = nodes.compactMap { $0.node }
        for node in allAddedNodes {
            for tag in node.tags {
                // 过滤掉复合节点的内部管理标签
                if case .custom(let key) = tag.type {
                    // 过滤掉复合节点管理标签
                    if key == "compound" ||
                       key == "child" ||
                       key.hasSuffix("复合节点") ||
                       key.hasSuffix("compound") {
                        continue
                    }
                }
                
                let tagKey = "\(tag.type.rawValue):\(tag.value)"
                if !addedTagKeys.contains(tagKey) {
                    nodes.append(NodeGraphNode(tag: tag))
                    addedTagKeys.insert(tagKey)
                }
            }
            
            // 添加位置标签
            for locationTag in node.locationTags {
                let locationTagKey = "\(locationTag.type.rawValue):\(locationTag.value)"
                if !addedTagKeys.contains(locationTagKey) {
                    nodes.append(NodeGraphNode(tag: locationTag))
                    addedTagKeys.insert(locationTagKey)
                }
            }
        }
        
        // 创建边连接
        let allProcessedNodes = nodes.compactMap { $0.node }
        for node in allProcessedNodes {
            guard let nodeGraphNode = nodes.first(where: { $0.node?.id == node.id }) else {
                continue
            }
            
            // 如果是复合节点，创建到子节点的连接
            if node.isCompound {
                let childReferenceTags = node.tags.filter {
                    if case .custom(let key) = $0.type, key == "child" {
                        return true
                    }
                    return false
                }
                
                for childRefTag in childReferenceTags {
                    let childNodeName = childRefTag.value
                    if let childNodeGraphNode = nodes.first(where: {
                        $0.node?.text.lowercased() == childNodeName.lowercased()
                    }) {
                        edges.append(NodeGraphEdge(
                            from: nodeGraphNode,
                            to: childNodeGraphNode,
                            relationshipType: "子节点"
                        ))
                    }
                }
            }
            
            // 创建节点到标签的连接
            for tag in node.tags {
                // 过滤掉复合节点的内部管理标签，不创建连接
                if case .custom(let key) = tag.type {
                    if key == "compound" ||
                       key == "child" ||
                       key.hasSuffix("复合节点") ||
                       key.hasSuffix("compound") {
                        continue
                    }
                }
                
                if let tagNode = nodes.first(where: {
                    $0.tag?.type.rawValue == tag.type.rawValue && $0.tag?.value == tag.value
                }) {
                    edges.append(NodeGraphEdge(
                        from: nodeGraphNode,
                        to: tagNode,
                        relationshipType: tag.type.displayName
                    ))
                }
            }
            
            // 创建节点到位置标签的连接
            for locationTag in node.locationTags {
                if let tagNode = nodes.first(where: {
                    $0.tag?.type.rawValue == locationTag.type.rawValue && $0.tag?.value == locationTag.value
                }) {
                    edges.append(NodeGraphEdge(
                        from: nodeGraphNode,
                        to: tagNode,
                        relationshipType: locationTag.type.displayName
                    ))
                }
            }
        }
        
        print("✅ [节点图谱管理器-\(instanceId)] 图谱数据生成完成:")
        print("   - 节点数: \(nodes.count)")
        print("   - 边数: \(edges.count)")
        
        return (nodes: nodes, edges: edges)
    }
    
    // MARK: - 过滤器管理
    
    /// 更新节点选择
    func updateSelectedNodes(_ nodeIds: Set<UUID>) {
        print("🔄 [节点图谱管理器-\(instanceId)] 更新选中节点: \(nodeIds.count)个")
        selectedNodeIds = nodeIds
    }
    
    /// 更新层级选择
    func updateSelectedLayers(_ layerIds: Set<UUID>) {
        print("🔄 [节点图谱管理器-\(instanceId)] 更新选中层级: \(layerIds.count)个")
        selectedLayerIds = layerIds
    }
    
    /// 更新搜索查询
    func updateSearchQuery(_ query: String) {
        print("🔄 [节点图谱管理器-\(instanceId)] 更新搜索查询: \(query)")
        searchQuery = query
    }
    
    /// 执行搜索
    func performSearch(in store: NodeStore) {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            displayedNodes = []
            return
        }
        
        // 清空节点选择，使用搜索模式
        selectedNodeIds = []
        
        // 搜索匹配的节点
        let matchedNodes = store.nodes.filter { node in
            node.text.localizedCaseInsensitiveContains(query) ||
            node.meaning?.localizedCaseInsensitiveContains(query) == true ||
            node.tags.contains { tag in
                tag.value.localizedCaseInsensitiveContains(query)
            }
        }
        
        // 获取相关节点（有共同标签的）
        var relatedNodes = Set<Node>()
        for matchedNode in matchedNodes {
            let nodeTags = Set(matchedNode.tags)
            let related = store.nodes.filter { otherNode in
                otherNode.id != matchedNode.id && !Set(otherNode.tags).isDisjoint(with: nodeTags)
            }
            relatedNodes.formUnion(related)
        }
        
        // 组合结果
        var finalNodes = Set(matchedNodes)
        finalNodes.formUnion(relatedNodes)
        
        displayedNodes = Array(finalNodes).sorted { $0.text < $1.text }
        
        print("🔍 [节点图谱管理器-\(instanceId)] 搜索完成: \(displayedNodes.count)个结果")
    }
    
    /// 清除所有过滤器
    func clearAllFilters() {
        print("🧹 [节点图谱管理器-\(instanceId)] 清除所有过滤器")
        selectedNodeIds = []
        selectedLayerIds = []
        searchQuery = ""
        displayedNodes = []
    }
    
    // MARK: - 锁定管理
    
    /// 切换锁定状态
    func toggleLockState(with store: NodeStore) {
        if isLocked {
            // 解锁：清除锁定的数据，恢复正常数据流
            print("🔓 [节点图谱管理器-\(instanceId)] 解锁图谱，恢复数据更新")
            isLocked = false
            lockedNodes = nil
        } else {
            // 锁定：保存当前数据状态
            print("🔒 [节点图谱管理器-\(instanceId)] 锁定图谱，冻结当前显示内容")
            isLocked = true
            lockedNodes = store.nodes
            
            // 打印锁定的数据信息
            print("🔒 锁定数据: \(lockedNodes?.count ?? 0)个节点")
        }
    }
    
    // MARK: - 辅助方法
    
    /// 递归添加复合节点的子节点结构
    private func addChildNodesForGraph(
        for node: Node,
        store: NodeStore,
        nodes: inout [NodeGraphNode],
        addedTagKeys: inout Set<String>,
        addedNodeIds: inout Set<UUID>,
        depth: Int
    ) {
        // 防止无限递归
        guard depth <= 10 else { return }
        
        // 查找子节点引用标签
        let childReferenceTags = node.tags.filter {
            if case .custom(let key) = $0.type, key == "child" {
                return true
            }
            return false
        }
        
        for childRefTag in childReferenceTags {
            let childNodeName = childRefTag.value
            
            // 从store中查找实际的子节点
            if let childNode = store.nodes.first(where: { $0.text.lowercased() == childNodeName.lowercased() }) {
                // 如果子节点还没被添加，则添加它
                if !addedNodeIds.contains(childNode.id) {
                    nodes.append(NodeGraphNode(node: childNode))
                    addedNodeIds.insert(childNode.id)
                    
                    // 如果子节点也是复合节点，递归添加其子节点
                    if childNode.isCompound {
                        addChildNodesForGraph(
                            for: childNode,
                            store: store,
                            nodes: &nodes,
                            addedTagKeys: &addedTagKeys,
                            addedNodeIds: &addedNodeIds,
                            depth: depth + 1
                        )
                    }
                }
            }
        }
    }
    
    deinit {
        print("🗑️ [节点图谱管理器-\(instanceId)] 实例被释放")
    }
}

// MARK: - 便利扩展

extension NodeGraphDataManager {
    /// 检查是否有有效的过滤条件
    var hasActiveFilters: Bool {
        return !selectedNodeIds.isEmpty || !selectedLayerIds.isEmpty || !displayedNodes.isEmpty
    }
    
    /// 构建过滤描述文本
    func buildFilterDescription(with store: NodeStore) -> String {
        var parts: [String] = []
        
        if !selectedLayerIds.isEmpty {
            let layerNames = store.layers
                .filter { selectedLayerIds.contains($0.id) }
                .map { $0.displayName }
            parts.append("层级: \(layerNames.joined(separator: ", "))")
        }
        
        if !selectedNodeIds.isEmpty {
            parts.append("节点: \(selectedNodeIds.count)个")
        }
        
        if !displayedNodes.isEmpty {
            parts.append("搜索结果: \(displayedNodes.count)个")
        }
        
        return parts.joined(separator: " | ")
    }
}