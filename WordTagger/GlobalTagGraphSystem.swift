import SwiftUI
import Combine

// MARK: - 全局标签系统数据模型

/// 全局标签索引项
struct GlobalTagItem: Identifiable, Codable {
    let id: UUID
    let tagType: String         // 标签类型显示名
    let tagValue: String        // 标签值
    let layerNames: [String]    // 所属层名称列表
    let nodeCount: Int          // 包含此标签的节点数量
    let nodes: [String]         // 节点名称列表（用于显示）
    
    init(id: UUID = UUID(), tagType: String, tagValue: String, layerNames: [String], nodeCount: Int, nodes: [String]) {
        self.id = id
        self.tagType = tagType
        self.tagValue = tagValue
        self.layerNames = layerNames
        self.nodeCount = nodeCount
        self.nodes = nodes
    }
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
    
    // 🚫 已废弃：全局标签图谱不再使用根节点，直接以标签类型为中心
    
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
    // 🆕 移除单例模式，每个窗口独立创建实例
    
    @Published var filteredLayers: Set<String> = []
    @Published var filteredTagTypes: Set<Tag.TagType> = []
    @Published var filteredTagValues: Set<String> = []
    
    private(set) var cachedTagItems: [GlobalTagItem] = []
    private var cachedGraphData: (nodes: [GlobalTagGraphNode], edges: [GlobalTagGraphEdge])?
    private let instanceId = UUID().uuidString.prefix(8)  // 🆕 实例标识符
    
    // 🆕 图谱预设管理
    @Published var graphPresets: [GraphPreset] = []
    @Published var currentPreset: GraphPreset?
    
    // 🆕 持久化保存上次使用的预设
    private static let lastUsedPresetKey = "GlobalTagGraph_LastUsedPresetId"
    
    // 持久化存储文件路径 - 使用外部数据存储系统
    private static let presetsFileName = "GlobalTagGraph_Presets.json"
    
    private static var presetsFileURL: URL? {
        // 图谱预设文件路径
        guard let basePath = ExternalDataManager.shared.currentDataPath else {
            let documentDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            return documentDir.appendingPathComponent(presetsFileName)
        }
        let metadataDir = basePath.appendingPathComponent("data/metadata")
        return metadataDir.appendingPathComponent(presetsFileName)
    }
    
    init() {
        print("🏗️ [全局标签管理器-\(instanceId)] 创建新实例")
        loadGraphPresets()     // 加载图谱预设
        print("🔍 [调试-\(instanceId)] 初始化后的状态:")
        print("   - 预设数量: \(graphPresets.count)")
        setupNotifications()
        loadLastUsedPreset()   // 🆕 加载上次使用的预设
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
        print("🔔 [全局标签管理器-\(instanceId)] 收到通知: \(notification.name)")
        print("🔔 [全局标签管理器-\(instanceId)] userInfo: \(notification.userInfo ?? [:])")
        
        guard let userInfo = notification.userInfo else {
            print("❌ [全局标签管理器-\(instanceId)] userInfo为空")
            return
        }
        
        let selectedLayers = userInfo["selectedLayers"] as? Set<String> ?? Set<String>()
        let selectedTagTypes = userInfo["selectedTagTypes"] as? Set<Tag.TagType> ?? Set<Tag.TagType>()
        let selectedTagValues = userInfo["selectedTagValues"] as? Set<String> ?? Set<String>()
        
        print("✅ [全局标签管理器-\(instanceId)] 成功解析选择数据")
        print("   - 选中层级: \(selectedLayers)")
        print("   - 选中标签类型: \(selectedTagTypes.map { $0.displayName })")
        print("   - 选中标签值: \(selectedTagValues)")
        
        // 🚨 调试：检查是否有标签值但没有清空标签类型
        if !selectedTagValues.isEmpty && !selectedTagTypes.isEmpty {
            print("⚠️ [调试-\(instanceId)] 检测到同时有标签值和标签类型！这会导致冲突!")
            print("   - 标签值: \(selectedTagValues)")
            print("   - 标签类型: \(selectedTagTypes.map { $0.displayName })")
        }
        
        // 更新过滤器
        filteredLayers = selectedLayers
        filteredTagTypes = selectedTagTypes
        filteredTagValues = selectedTagValues
        
        print("🔄 [全局标签管理器-\(instanceId)] 过滤器已更新")
        print("   - filteredLayers: \(filteredLayers)")
        print("   - filteredTagTypes: \(filteredTagTypes.map { $0.displayName })")
        print("   - filteredTagValues: \(filteredTagValues)")
        
        print("🔄 [全局标签管理器-\(instanceId)] 过滤器已更新")
        
        // 清除缓存以触发重新计算
        cachedGraphData = nil
        
        print("🗑️ [全局标签管理器-\(instanceId)] 图谱缓存已清除")
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
                        id: existingItem.id,
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
                        id: existingItem.id,
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
    
    /// 生成全局标签图谱数据 - 三层结构：标签类型 → 标签值 → 节点名称
    /// 这是专门用于展示标签分类和使用情况的图谱，与节点图谱（节点 → 标签）形成互补
    func generateGlobalGraphData(from store: NodeStore) -> (nodes: [GlobalTagGraphNode], edges: [GlobalTagGraphEdge]) {
        print("🏗️ [全局标签管理器] 生成三层标签图谱：标签类型 → 标签值 → 节点名称")
        
        var nodes: [GlobalTagGraphNode] = []
        var edges: [GlobalTagGraphEdge] = []
        
        // 获取当前标签索引数据
        let tagItems = cachedTagItems.isEmpty ? generateTagIndexData(from: store) : cachedTagItems
        print("🔍 [全局标签管理器] 标签项总数: \(tagItems.count)")
        
        // 应用过滤器
        let filteredItems = applyFilters(to: tagItems, store: store)
        print("🔍 [全局标签管理器] 过滤后数量: \(filteredItems.count)")
        
        // 使用过滤结果，没有过滤条件时显示所有数据
        let itemsToShow: [GlobalTagItem]
        let hasAnyFilter = !filteredLayers.isEmpty || !filteredTagTypes.isEmpty || !filteredTagValues.isEmpty
        
        if hasAnyFilter {
            // 有过滤条件时，使用过滤结果
            itemsToShow = filteredItems
            print("🌟 [全局标签管理器] 使用过滤结果: \(itemsToShow.count) 个项目")
            print("   - 过滤条件: 层级(\(filteredLayers.count)) + 类型(\(filteredTagTypes.count)) + 值(\(filteredTagValues.count))")
        } else {
            // 没有过滤条件时，显示前20个项目作为默认展示
            itemsToShow = Array(tagItems.prefix(20))
            print("🌟 [全局标签管理器] 无过滤条件，显示前20个项目: \(itemsToShow.count)")
        }
        
        if itemsToShow.isEmpty {
            print("⚠️ [全局标签管理器] 无可显示数据")
            return (nodes: [], edges: [])
        }
        
        // 📊 三层图谱结构：标签类型(第1层) → 标签值(第2层) → 节点名称(第3层)
        let groupedByType = Dictionary(grouping: itemsToShow) { $0.tagType }
        
        // 🔧 节点去重：使用字典避免重复创建相同节点
        var createdNodes: [String: GlobalTagGraphNode] = [:]
        
        // 🏷️ 第1层：创建标签类型节点（中心层）
        for (tagTypeName, items) in groupedByType {
            guard let tagType = findTagType(by: tagTypeName, in: store) else { continue }
            
            let tagTypeNode = GlobalTagGraphNode(tagType: tagType, usageCount: items.count)
            nodes.append(tagTypeNode)
            print("🏷️ [全局标签管理器] 第1层 - 标签类型: \(tagTypeName)")
            
            // 🔖 第2层：为每个标签值创建节点
            for item in items.prefix(10) {
                let tagValueNode = GlobalTagGraphNode(
                    tagValue: item.tagValue,
                    tagType: tagType,
                    nodeCount: item.nodeCount
                )
                nodes.append(tagValueNode)
                
                // 连接：标签类型 → 标签值
                edges.append(GlobalTagGraphEdge(from: tagTypeNode, to: tagValueNode))
                print("🔗 [全局标签管理器] 第1层→第2层: \(tagTypeName) → \(item.tagValue)")
                
                // 📄 第3层：添加具体的节点名称（去重处理）
                for nodeName in item.nodes.prefix(3) {
                    if let node = store.nodes.first(where: { $0.text == nodeName }) {
                        // 🔧 使用节点唯一标识符避免重复创建
                        let nodeKey = node.id.uuidString
                        
                        let contentNode: GlobalTagGraphNode
                        if let existingNode = createdNodes[nodeKey] {
                            contentNode = existingNode
                            print("🔄 [去重] 复用已存在的节点: \(nodeName)")
                        } else {
                            contentNode = GlobalTagGraphNode(node: node)
                            nodes.append(contentNode)
                            createdNodes[nodeKey] = contentNode
                            print("🆕 [新建] 创建新的内容节点: \(nodeName)")
                        }
                        
                        // 连接：标签值 → 节点名称
                        edges.append(GlobalTagGraphEdge(from: tagValueNode, to: contentNode))
                        print("🔗 [全局标签管理器] 第2层→第3层: \(item.tagValue) → \(nodeName)")
                    }
                }
            }
        }
        
        let result = (nodes: nodes, edges: edges)
        cachedGraphData = result
        
        print("✅ [全局标签管理器] 标签图谱生成完成: \(nodes.count)个节点, \(edges.count)条边")
        print("🎯 [全局标签管理器] 图谱结构: 标签类型(\(groupedByType.count)) → 标签值 → 节点名称")
        return result
    }
    
    // MARK: - 私有辅助方法
    
    private func applyFilters(to items: [GlobalTagItem], store: NodeStore) -> [GlobalTagItem] {
        print("🔍 [全局标签管理器] 开始过滤，原始项目: \(items.count)")
        print("🔍 [全局标签管理器] 过滤条件:")
        print("   - 层级: \(filteredLayers)")  
        print("   - 标签类型: \(filteredTagTypes.map { $0.displayName })")
        print("   - 标签值: \(filteredTagValues)")
        
        var filtered = items
        
        // 如果没有任何过滤条件，返回原始数据
        if filteredLayers.isEmpty && filteredTagTypes.isEmpty && filteredTagValues.isEmpty {
            print("🔍 [全局标签管理器] 无过滤条件，返回原始数据")
            return filtered
        }
        
        // 层级过滤
        if !filteredLayers.isEmpty {
            let beforeCount = filtered.count
            filtered = filtered.filter { item in
                !Set(item.layerNames).isDisjoint(with: filteredLayers)
            }
            print("🔍 [全局标签管理器] 层级过滤: \(beforeCount) → \(filtered.count)")
        }
        
        // 🔧 修复：当有标签值过滤时，优先使用标签值过滤，标签类型作为辅助
        if !filteredTagValues.isEmpty {
            let beforeCount = filtered.count
            
            // 修复逻辑：如果有选中的标签值，直接过滤出这些标签值的项目
            // 不再依赖标签类型过滤，因为用户直接选择了具体的标签值
            filtered = filtered.filter { item in
                let match = filteredTagValues.contains(item.tagValue)
                if !match {
                    print("   - 排除: \(item.tagType):\(item.tagValue) (不在选中值中)")
                }
                return match
            }
            print("🔍 [全局标签管理器] 标签值过滤: \(beforeCount) → \(filtered.count)")
            print("   - 最终保留的项目: \(filtered.map { $0.tagType + ":" + $0.tagValue })")
        } else if !filteredTagTypes.isEmpty {
            // 仅当没有标签值过滤时，才应用标签类型过滤
            let beforeCount = filtered.count
            let filteredTypeNames = Set(filteredTagTypes.map { $0.displayName })
            filtered = filtered.filter { filteredTypeNames.contains($0.tagType) }
            print("🔍 [全局标签管理器] 标签类型过滤: \(beforeCount) → \(filtered.count)")
            print("   - 通过类型过滤的项目: \(filtered.map { $0.tagType + ":" + $0.tagValue })")
        }
        
        print("✅ [全局标签管理器] 过滤完成: \(items.count) → \(filtered.count)")
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
    
    
    /// 将TagType转换为字符串用于存储
    private func tagTypeToString(_ tagType: Tag.TagType) -> String {
        switch tagType {
        case .location:
            return "location"
        case .custom(let name):
            return "custom:\(name)"
        }
    }
    
    /// 从字符串解析TagType
    private func parseTagTypeFromString(_ string: String) -> Tag.TagType? {
        switch string {
        case "location":
            return .location
        default:
            if string.hasPrefix("custom:") {
                let customName = String(string.dropFirst("custom:".count))
                return .custom(customName)
            }
            return nil
        }
    }
    
    // MARK: - 🆕 图谱预设管理
    
    /// 保存当前过滤状态为新预设
    func saveCurrentAsPreset(name: String, description: String? = nil) {
        print("💾 [全局标签管理器-\(instanceId)] 保存当前状态为预设: \(name)")
        
        let preset = GraphPreset(
            name: name,
            description: description,
            filteredLayers: Array(filteredLayers),
            filteredTagTypes: filteredTagTypes.map { tagTypeToString($0) },
            filteredTagValues: Array(filteredTagValues)
        )
        
        // 检查是否已存在同名预设
        if let existingIndex = graphPresets.firstIndex(where: { $0.name == name }) {
            graphPresets[existingIndex] = preset
            print("🔄 [全局标签管理器-\(instanceId)] 更新现有预设: \(name)")
        } else {
            graphPresets.append(preset)
            print("🆕 [全局标签管理器-\(instanceId)] 创建新预设: \(name)")
        }
        
        currentPreset = preset
        saveGraphPresets()
    }
    
    /// 加载指定预设
    func loadPreset(_ preset: GraphPreset) {
        print("📖 [全局标签管理器-\(instanceId)] 加载预设: \(preset.name)")
        
        // 更新当前过滤状态
        filteredLayers = Set(preset.filteredLayers)
        filteredTagValues = Set(preset.filteredTagValues)
        
        // 恢复标签类型
        var restoredTypes: Set<Tag.TagType> = []
        for typeString in preset.filteredTagTypes {
            if let tagType = parseTagTypeFromString(typeString) {
                restoredTypes.insert(tagType)
            }
        }
        filteredTagTypes = restoredTypes
        
        // 更新当前预设
        currentPreset = preset
        
        // 🆕 保存为上次使用的预设
        saveAsLastUsedPreset(preset)
        
        // 清除缓存以触发重新计算
        cachedGraphData = nil
        
        print("✅ [全局标签管理器-\(instanceId)] 预设加载完成")
        print("   - 层级: \(filteredLayers.count) 个")
        print("   - 标签类型: \(filteredTagTypes.count) 个")
        print("   - 标签值: \(filteredTagValues.count) 个")
    }
    
    /// 删除预设
    func deletePreset(_ preset: GraphPreset) {
        print("🗑️ [全局标签管理器-\(instanceId)] 删除预设: \(preset.name)")
        
        graphPresets.removeAll { $0.id == preset.id }
        
        if currentPreset?.id == preset.id {
            currentPreset = nil
        }
        
        saveGraphPresets()
    }
    
    /// 加载所有图谱预设
    private func loadGraphPresets() {
        print("📖 [全局标签管理器-\(instanceId)] 加载图谱预设")
        
        guard let fileURL = Self.presetsFileURL else {
            print("❌ [全局标签管理器-\(instanceId)] 无法获取预设文件路径")
            return
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("ℹ️ [全局标签管理器-\(instanceId)] 预设文件不存在，使用默认空列表")
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601  // 🔧 修复：添加日期解码策略
            let collection = try decoder.decode(GraphPresetCollection.self, from: data)
            
            graphPresets = collection.presets
            print("✅ [全局标签管理器-\(instanceId)] 成功加载 \(graphPresets.count) 个预设")
            
        } catch {
            print("❌ [全局标签管理器-\(instanceId)] 加载预设失败: \(error)")
        }
    }
    
    /// 保存所有图谱预设
    private func saveGraphPresets() {
        print("💾 [全局标签管理器-\(instanceId)] 保存图谱预设到外部存储")
        
        guard let fileURL = Self.presetsFileURL else {
            print("❌ [全局标签管理器-\(instanceId)] 无法获取预设文件路径")
            return
        }
        
        let collection = GraphPresetCollection(presets: graphPresets)
        
        do {
            // 确保metadata文件夹存在
            let metadataDir = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: metadataDir.path) {
                try FileManager.default.createDirectory(at: metadataDir, withIntermediateDirectories: true, attributes: nil)
                print("📁 [全局标签管理器-\(instanceId)] 创建metadata文件夹")
            }
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            
            let data = try encoder.encode(collection)
            try data.write(to: fileURL)
            
            print("✅ [全局标签管理器-\(instanceId)] 成功保存 \(graphPresets.count) 个预设")
            
            // 触发自动同步到Git
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("TriggerAutoSync"),
                    object: nil,
                    userInfo: ["reason": "GraphPresetsChanged"]
                )
            }
            
        } catch {
            print("❌ [全局标签管理器-\(instanceId)] 保存预设失败: \(error)")
        }
    }
    
    // MARK: - 🆕 上次使用预设管理
    
    /// 保存预设为上次使用的预设
    private func saveAsLastUsedPreset(_ preset: GraphPreset) {
        UserDefaults.standard.set(preset.id, forKey: Self.lastUsedPresetKey)
        print("💾 [全局标签管理器-\(instanceId)] 保存上次使用的预设: \(preset.name) (ID: \(preset.id))")
    }
    
    /// 加载上次使用的预设
    private func loadLastUsedPreset() {
        guard let lastUsedPresetId = UserDefaults.standard.string(forKey: Self.lastUsedPresetKey) else {
            print("ℹ️ [全局标签管理器-\(instanceId)] 没有找到上次使用的预设")
            return
        }
        
        guard let lastUsedPreset = graphPresets.first(where: { $0.id == lastUsedPresetId }) else {
            print("⚠️ [全局标签管理器-\(instanceId)] 上次使用的预设不存在: \(lastUsedPresetId)")
            // 清除无效的引用
            UserDefaults.standard.removeObject(forKey: Self.lastUsedPresetKey)
            return
        }
        
        print("🔄 [全局标签管理器-\(instanceId)] 恢复上次使用的预设: \(lastUsedPreset.name)")
        
        // 静默加载预设，不触发保存操作
        filteredLayers = Set(lastUsedPreset.filteredLayers)
        filteredTagValues = Set(lastUsedPreset.filteredTagValues)
        
        // 恢复标签类型
        var restoredTypes: Set<Tag.TagType> = []
        for typeString in lastUsedPreset.filteredTagTypes {
            if let tagType = parseTagTypeFromString(typeString) {
                restoredTypes.insert(tagType)
            }
        }
        filteredTagTypes = restoredTypes
        
        // 设置为当前预设（但不再次保存）
        currentPreset = lastUsedPreset
        
        // 清除缓存以触发重新计算
        cachedGraphData = nil
        
        print("✅ [全局标签管理器-\(instanceId)] 上次使用的预设已恢复")
        print("   - 层级: \(filteredLayers.count) 个")
        print("   - 标签类型: \(filteredTagTypes.count) 个")  
        print("   - 标签值: \(filteredTagValues.count) 个")
    }
}

// MARK: - 数据模型

/// 图谱预设数据结构
struct GraphPreset: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let filteredLayers: [String]
    let filteredTagTypes: [String]
    let filteredTagValues: [String]
    let createdAt: Date
    let lastUsed: Date
    
    init(id: String = UUID().uuidString, name: String, description: String? = nil, 
         filteredLayers: [String], filteredTagTypes: [String], filteredTagValues: [String]) {
        self.id = id
        self.name = name
        self.description = description
        self.filteredLayers = filteredLayers
        self.filteredTagTypes = filteredTagTypes
        self.filteredTagValues = filteredTagValues
        self.createdAt = Date()
        self.lastUsed = Date()
    }
}

/// 图谱预设集合
struct GraphPresetCollection: Codable {
    var presets: [GraphPreset]
    let lastModified: Date
    
    init(presets: [GraphPreset] = []) {
        self.presets = presets
        self.lastModified = Date()
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