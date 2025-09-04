import SwiftUI
import Combine

// MARK: - 全局标签系统数据模型

/// 全局标签索引项
struct GlobalTagItem: Identifiable, Codable {
    let id = UUID()
    let tagType: String         // 标签类型显示名
    let tagValue: String        // 标签值
    let layerNames: [String]    // 所属层名称列表
    let nodeCount: Int          // 包含此标签的节点数量
    let nodes: [String]         // 节点名称列表（用于显示）
}

/// 全局标签图谱节点
struct GlobalTagGraphNode: UniversalGraphNode {
    let id: Int
    let label: String
    let subtitle: String?
    let nodeType: NodeType
    let isCenter: Bool
    
    enum NodeType {
        case root                           // 根节点（全局标签）
        case tagType(Tag.TagType)          // 标签类型节点
        case tagValue(String, Int)         // 标签值节点（值，使用次数）
        case contentNode(Node)             // 内容节点
    }
    
    init(tagType: Tag.TagType, usageCount: Int) {
        self.id = abs(tagType.hashValue)
        self.label = tagType.displayName
        self.subtitle = "\(usageCount)个标签值"
        self.nodeType = .tagType(tagType)
        self.isCenter = false
    }
    
    init(tagValue: String, tagType: Tag.TagType, nodeCount: Int) {
        self.id = abs("\(tagType.displayName):\(tagValue)".hashValue)
        self.label = tagValue
        self.subtitle = "\(nodeCount)个节点"
        self.nodeType = .tagValue(tagValue, nodeCount)
        self.isCenter = false
    }
    
    init(node: Node) {
        self.id = abs(node.id.hashValue)
        self.label = node.text
        self.subtitle = nil
        self.nodeType = .contentNode(node)
        self.isCenter = false
    }
    
    static func createRootNode() -> GlobalTagGraphNode {
        return GlobalTagGraphNode(
            id: 0,
            label: "全局标签",
            subtitle: "标签类型总览",
            nodeType: .root,
            isCenter: true
        )
    }
    
    private init(id: Int, label: String, subtitle: String?, nodeType: NodeType, isCenter: Bool) {
        self.id = id
        self.label = label
        self.subtitle = subtitle
        self.nodeType = nodeType
        self.isCenter = isCenter
    }
}

/// 全局标签图谱边
struct GlobalTagGraphEdge: UniversalGraphEdge {
    let fromId: Int
    let toId: Int
    let label: String?
    
    init(from: GlobalTagGraphNode, to: GlobalTagGraphNode, relationshipType: String = "") {
        self.fromId = from.id
        self.toId = to.id
        self.label = relationshipType.isEmpty ? nil : relationshipType
    }
}

// MARK: - 全局标签数据管理器

@MainActor
class GlobalTagDataManager: ObservableObject {
    static let shared = GlobalTagDataManager()
    
    @Published var filteredLayers: Set<String> = []
    @Published var filteredTagTypes: Set<Tag.TagType> = []
    @Published var filteredTagValues: Set<String> = []
    
    private(set) var cachedTagItems: [GlobalTagItem] = []
    private var cachedGraphData: (nodes: [GlobalTagGraphNode], edges: [GlobalTagGraphEdge])?
    
    private init() {
        setupNotifications()
    }
    
    private func setupNotifications() {
        // 监听标签索引面板的选择变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectionChanged),
            name: .tagIndexSelectionChanged,
            object: nil
        )
    }
    
    @objc private func handleSelectionChanged(_ notification: Notification) {
        print("🔔 [全局标签管理器] 收到通知: \(notification.name)")
        print("🔔 [全局标签管理器] userInfo: \(notification.userInfo ?? [:])")
        
        guard let userInfo = notification.userInfo else {
            print("❌ [全局标签管理器] userInfo为空")
            return
        }
        
        let selectedLayers = userInfo["selectedLayers"] as? Set<String> ?? Set<String>()
        let selectedTagTypes = userInfo["selectedTagTypes"] as? Set<Tag.TagType> ?? Set<Tag.TagType>()
        let selectedTagValues = userInfo["selectedTagValues"] as? Set<String> ?? Set<String>()
        
        print("✅ [全局标签管理器] 成功解析选择数据")
        print("   - 选中层级: \(selectedLayers)")
        print("   - 选中标签类型: \(selectedTagTypes.map { $0.displayName })")
        print("   - 选中标签值: \(selectedTagValues)")
        
        // 更新过滤器
        filteredLayers = selectedLayers
        filteredTagTypes = selectedTagTypes
        filteredTagValues = selectedTagValues
        
        print("🔄 [全局标签管理器] 过滤器已更新")
        
        // 清除缓存以触发重新计算
        cachedGraphData = nil
        
        print("🗑️ [全局标签管理器] 图谱缓存已清除")
    }
    
    /// 生成全局标签索引数据
    func generateTagIndexData(from store: NodeStore) -> [GlobalTagItem] {
        print("📊 [全局标签管理器] 开始生成全局标签索引数据")
        print("   - 输入节点数: \(store.nodes.count)")
        print("   - 输入层级数: \(store.layers.count)")
        
        var tagUsageMap: [String: GlobalTagItem] = [:]
        let layerMap = Dictionary(uniqueKeysWithValues: store.layers.map { ($0.id, $0.displayName) })
        print("   - 层级映射: \(layerMap.values.joined(separator: ", "))")
        
        var totalTagsFound = 0
        // 遍历所有节点收集标签信息
        for node in store.nodes {
            let layerName = layerMap[node.layerId] ?? "未知层级"
            
            // 处理普通标签
            totalTagsFound += node.tags.count
            for tag in node.tags {
                let key = "\(tag.type.displayName):\(tag.value)"
                
                if var existingItem = tagUsageMap[key] {
                    // 更新现有项目
                    existingItem = GlobalTagItem(
                        tagType: existingItem.tagType,
                        tagValue: existingItem.tagValue,
                        layerNames: Array(Set(existingItem.layerNames + [layerName])),
                        nodeCount: existingItem.nodeCount + 1,
                        nodes: Array(Set(existingItem.nodes + [node.text]))
                    )
                    tagUsageMap[key] = existingItem
                } else {
                    // 创建新项目
                    tagUsageMap[key] = GlobalTagItem(
                        tagType: tag.type.displayName,
                        tagValue: tag.value,
                        layerNames: [layerName],
                        nodeCount: 1,
                        nodes: [node.text]
                    )
                }
            }
            
            // 处理位置标签
            for locationTag in node.locationTags {
                let key = "\(locationTag.type.displayName):\(locationTag.value)"
                
                if var existingItem = tagUsageMap[key] {
                    existingItem = GlobalTagItem(
                        tagType: existingItem.tagType,
                        tagValue: existingItem.tagValue,
                        layerNames: Array(Set(existingItem.layerNames + [layerName])),
                        nodeCount: existingItem.nodeCount + 1,
                        nodes: Array(Set(existingItem.nodes + [node.text]))
                    )
                    tagUsageMap[key] = existingItem
                } else {
                    tagUsageMap[key] = GlobalTagItem(
                        tagType: locationTag.type.displayName,
                        tagValue: locationTag.value,
                        layerNames: [layerName],
                        nodeCount: 1,
                        nodes: [node.text]
                    )
                }
            }
        }
        
        let result = Array(tagUsageMap.values).sorted { $0.nodeCount > $1.nodeCount }
        cachedTagItems = result
        
        print("✅ [全局标签管理器] 生成完成")
        print("   - 处理的标签总数: \(totalTagsFound)")
        print("   - 唯一标签项: \(result.count)")
        
        if result.isEmpty {
            print("⚠️ [全局标签管理器] 警告：没有找到任何标签数据！")
            // 调试：检查前几个节点的标签情况
            for (i, node) in store.nodes.prefix(3).enumerated() {
                print("   - 节点\(i): '\(node.text)' 有 \(node.tags.count) 个标签")
                for tag in node.tags {
                    print("     - \(tag.type.displayName): \(tag.value)")
                }
            }
        } else {
            print("   - 前3个标签项: \(result.prefix(3).map { "\($0.tagType):\($0.tagValue)" }.joined(separator: ", "))")
        }
        
        return result
    }
    
    /// 生成全局标签图谱数据
    func generateGlobalGraphData(from store: NodeStore) -> (nodes: [GlobalTagGraphNode], edges: [GlobalTagGraphEdge]) {
        print("🏗️ [全局标签管理器] 开始生成全局图谱数据")
        
        var nodes: [GlobalTagGraphNode] = []
        var edges: [GlobalTagGraphEdge] = []
        
        // 获取当前标签索引数据
        let tagItems = cachedTagItems.isEmpty ? generateTagIndexData(from: store) : cachedTagItems
        print("🔍 [全局标签管理器] 标签项总数: \(tagItems.count)")
        
        // 应用过滤器
        let filteredItems = applyFilters(to: tagItems, store: store)
        print("🔍 [全局标签管理器] 过滤后数量: \(filteredItems.count)")
        
        // 如果没有过滤器且有数据，显示前20个项目避免图谱过于复杂
        let itemsToShow: [GlobalTagItem]
        if filteredLayers.isEmpty && filteredTagTypes.isEmpty && filteredTagValues.isEmpty {
            itemsToShow = Array(tagItems.prefix(20))
            print("🌟 [全局标签管理器] 无过滤器，显示前20个项目: \(itemsToShow.count)")
        } else {
            itemsToShow = filteredItems
        }
        
        if itemsToShow.isEmpty {
            print("⚠️ [全局标签管理器] 无可显示数据")
            return (nodes: [], edges: [])
        }
        
        // 1. 创建根节点
        let rootNode = GlobalTagGraphNode.createRootNode()
        nodes.append(rootNode)
        
        // 2. 按标签类型分组
        let groupedByType = Dictionary(grouping: itemsToShow) { $0.tagType }
        
        // 3. 创建标签类型节点
        for (tagTypeName, items) in groupedByType {
            // 找到对应的TagType
            guard let tagType = findTagType(by: tagTypeName, in: store) else { continue }
            
            let tagTypeNode = GlobalTagGraphNode(tagType: tagType, usageCount: items.count)
            nodes.append(tagTypeNode)
            
            // 连接根节点到标签类型节点
            edges.append(GlobalTagGraphEdge(from: rootNode, to: tagTypeNode))
            
            // 4. 为每个标签值创建节点（限制显示数量）
            for item in items.prefix(10) {
                let tagValueNode = GlobalTagGraphNode(
                    tagValue: item.tagValue,
                    tagType: tagType,
                    nodeCount: item.nodeCount
                )
                nodes.append(tagValueNode)
                
                // 连接标签类型到标签值
                edges.append(GlobalTagGraphEdge(from: tagTypeNode, to: tagValueNode))
                
                // 5. 添加部分内容节点（每个标签值最多3个节点）
                for nodeName in item.nodes.prefix(3) {
                    if let node = store.nodes.first(where: { $0.text == nodeName }) {
                        let contentNode = GlobalTagGraphNode(node: node)
                        nodes.append(contentNode)
                        
                        // 连接标签值到内容节点
                        edges.append(GlobalTagGraphEdge(from: tagValueNode, to: contentNode))
                    }
                }
            }
        }
        
        let result = (nodes: nodes, edges: edges)
        cachedGraphData = result
        
        print("✅ [全局标签管理器] 图谱生成完成: \(nodes.count)个节点, \(edges.count)条边")
        return result
    }
    
    // MARK: - 私有辅助方法
    
    private func applyFilters(to items: [GlobalTagItem], store: NodeStore) -> [GlobalTagItem] {
        var filtered = items
        
        // 层级过滤
        if !filteredLayers.isEmpty {
            filtered = filtered.filter { item in
                !Set(item.layerNames).isDisjoint(with: filteredLayers)
            }
        }
        
        // 标签类型过滤
        if !filteredTagTypes.isEmpty {
            let filteredTypeNames = Set(filteredTagTypes.map { $0.displayName })
            filtered = filtered.filter { filteredTypeNames.contains($0.tagType) }
        }
        
        // 标签值过滤
        if !filteredTagValues.isEmpty {
            filtered = filtered.filter { filteredTagValues.contains($0.tagValue) }
        }
        
        print("🔍 [全局标签管理器] 过滤结果: \(items.count) → \(filtered.count)")
        return filtered
    }
    
    private func findTagType(by displayName: String, in store: NodeStore) -> Tag.TagType? {
        // 检查预定义类型
        switch displayName {
        case "地点": return .location
        default: break
        }
        
        // 检查自定义类型
        for node in store.nodes {
            for tag in node.tags + node.locationTags {
                if tag.type.displayName == displayName {
                    return tag.type
                }
            }
        }
        
        return nil
    }
}

// MARK: - 通知扩展

extension NSNotification.Name {
    static let tagIndexSelectionChanged = NSNotification.Name("tagIndexSelectionChanged")
}

// MARK: - 标签索引选择模型

struct TagIndexSelection: Codable {
    let type: String    // "layer", "tagType", "tagValue"
    let value: String   // 对应的值
}