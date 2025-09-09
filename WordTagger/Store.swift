import Combine
import Foundation
import AppKit
import SwiftUI

@MainActor
public final class NodeStore: ObservableObject {
    @Published public private(set) var nodes: [Node] = []
    @Published public private(set) var layers: [Layer] = []
    
    // 排序后的层列表：复合层在前，普通层在后
    public var sortedLayers: [Layer] {
        return layers.sorted { layer1, layer2 in
            if layer1.isCompound && !layer2.isCompound {
                return true  // 复合层在前
            } else if !layer1.isCompound && layer2.isCompound {
                return false // 普通层在后
            } else {
                return layer1.displayName < layer2.displayName // 同类型按名称排序
            }
        }
    }
    @Published public private(set) var currentLayer: Layer?
    @Published public private(set) var selectedNode: Node?
    @Published public private(set) var selectedTag: Tag?
    @Published public private(set) var showAllTagTypeNodes: Bool = false // 是否展示同标签类型的所有节点
    @Published public private(set) var expandedTagTypes: Set<Tag.TagType> = [] // 当前展开的标签类型
    @Published public var searchQuery: String = ""
    @Published public private(set) var searchResults: [Node] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isExporting: Bool = false
    @Published public private(set) var isImporting: Bool = false
    
    // MARK: - 标签筛选状态记忆机制
    private var savedTagFilterState: SavedTagFilterState?
    
    private var cancellables = Set<AnyCancellable>()
    private let externalDataService = ExternalDataService.shared
    private let externalDataManager = ExternalDataManager.shared
    private var isLoadingFromExternal = false
    
    public static let shared = NodeStore()
    
    // 标记是否为共享实例
    public let isSharedInstance: Bool
    
    // 工厂方法：创建独立的NodeStore实例（用于独立窗口）
    public static func createIndependentInstance() -> NodeStore {
        return NodeStore(isIndependent: true)
    }
    
    private init(isIndependent: Bool = false) {
        self.isSharedInstance = !isIndependent
        setupInitialData()
        setupSearchBinding()
        if !isIndependent {
            setupExternalDataSync()
            setupDataPathChangeListener()
            setupTagTypeNameChangeListener()
        }
    }
    
    // MARK: - 初始化
    
    private func setupInitialData() {
        setupDefaultLayers()
        
        // 尝试加载外部数据
        Task {
            do {
                isLoadingFromExternal = true
                let (loadedLayers, loadedNodes) = try await externalDataService.loadAllData()
                
                await MainActor.run {
                    if !loadedLayers.isEmpty {
                        self.layers = loadedLayers
                        self.nodes = loadedNodes
                        
                        // 修复旧的标签类型（移除custom_前缀）
                        self.fixLegacyTagTypesInAllNodes()
                        
                        // 检测并修复损坏的节点数据
                        let corruptionFixedCount = self.detectAndFixCorruptedNodes()
                        if corruptionFixedCount > 0 {
                            print("🔧 数据加载时自动修复了 \(corruptionFixedCount) 个损坏的节点")
                        }
                        
                        // 设置活跃层
                        if let activeLayer = loadedLayers.first(where: { $0.isActive }) {
                            self.currentLayer = activeLayer
                        } else if let firstLayer = loadedLayers.first {
                            self.currentLayer = firstLayer
                        }
                        
                        print("📚 从外部存储加载了 \(loadedNodes.count) 个节点，分布在 \(loadedLayers.count) 个层中")
                    } else {
                        // 只有在没有外部数据时才加载示例数据
                        self.loadSampleData()
                        print("📚 Created sample data with \(self.nodes.count) nodes across \(self.layers.count) layers")
                    }
                    self.isLoadingFromExternal = false
                }
            } catch {
                print("⚠️ 加载外部数据失败: \(error)")
                await MainActor.run {
                    self.isLoadingFromExternal = false
                    // 只有在没有外部数据时才加载示例数据
                    if self.nodes.isEmpty {
                        self.loadSampleData()
                        print("📚 Created sample data with \(self.nodes.count) nodes across \(self.layers.count) layers")
                    }
                }
            }
        }
    }
    
    private func setupDefaultLayers() {
        var englishLayer = Layer(name: "english", displayName: "英语节点", color: "blue")
        englishLayer.isActive = true
        
        layers = [
            englishLayer,
            Layer(name: "statistics", displayName: "统计学", color: "green"),
            Layer(name: "psychology", displayName: "教育心理学", color: "orange")
        ]
        currentLayer = layers.first
    }
    
    private func setupSearchBinding() {
        print("🔧 Store: Setting up search binding")
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                print("🔍 Store: searchQuery changed to '\(query)' (after debounce)")
                self?.performSearch(query: query)
            }
            .store(in: &cancellables)
    }
    
    private func setupExternalDataSync() {
        // 监听数据变化，自动保存到外部存储（缩短延迟时间）
        Publishers.CombineLatest($nodes, $layers)
            .debounce(for: .milliseconds(800), scheduler: RunLoop.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (nodes, layers) in
                guard let self = self else { return }
                
                // 如果正在从外部存储加载数据，跳过自动同步
                if self.isLoadingFromExternal {
                    return
                }
                
                print("🔄 数据变化触发自动同步:")
                print("   - Nodes: \(nodes.count) 个")
                print("   - Layers: \(layers.count) 个")
                print("   - 外部数据路径已选择: \(self.externalDataManager.isDataPathSelected)")
                
                if self.externalDataManager.isDataPathSelected {
                    Task { @MainActor in
                        do {
                            print("💾 开始自动同步数据...")
                            try await self.externalDataService.saveAllData(store: self)
                            print("✅ 数据已自动同步到外部存储")
                        } catch {
                            print("❌ 保存外部数据失败: \(error)")
                        }
                    }
                } else {
                    print("⚠️ 未选择外部数据路径，跳过自动同步")
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupDataPathChangeListener() {
        // 监听路径切换前的保存通知
        NotificationCenter.default.addObserver(
            forName: .saveCurrentDataBeforeSwitch,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            print("💾 收到保存请求，立即保存当前数据...")
            
            Task { @MainActor in
                do {
                    // 立即保存当前数据到旧路径
                    try await self.externalDataService.saveAllData(store: self)
                    print("✅ 切换前数据保存成功")
                } catch {
                    print("❌ 切换前数据保存失败: \(error)")
                }
            }
        }
        
        // 监听路径切换后的加载通知
        NotificationCenter.default.addObserver(
            forName: .dataPathChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            print("🔄 数据路径已更改，重新加载数据...")
            
            Task { @MainActor in
                await self.reloadDataFromExternalStorage()
            }
        }
    }
    
    @MainActor
    private func reloadDataFromExternalStorage() async {
        do {
            isLoadingFromExternal = true
            isLoading = true
            let (loadedLayers, loadedNodes) = try await externalDataService.loadAllData()
            
            if !loadedLayers.isEmpty {
                // 如果新路径有数据，替换当前数据
                layers = loadedLayers
                nodes = loadedNodes
                
                // 设置活跃层
                if let activeLayer = loadedLayers.first(where: { $0.isActive }) {
                    currentLayer = activeLayer
                } else if let firstLayer = loadedLayers.first {
                    currentLayer = firstLayer
                }
                
                print("📚 从新路径加载了 \(loadedNodes.count) 个节点，分布在 \(loadedLayers.count) 个层中")
                
                // 调试：打印每个节点的标签详情
                for (index, node) in loadedNodes.enumerated() {
                    print("🏷️ Node[\(index)]: \(node.text) - \(node.tags.count) 个标签")
                    for (tagIndex, tag) in node.tags.enumerated() {
                        print("   Tag[\(tagIndex)]: \(tag.type.displayName) = '\(tag.value)' (id: \(tag.id.uuidString.prefix(8)))")
                    }
                }
                
                // 重新加载标签映射
                await TagMappingManager.shared.reloadFromExternalStorage()
                
                // 修复节点中的错误标签类型
                TagMappingManager.shared.fixNodeTagTypes(store: self)
            } else {
                // 如果新路径没有数据，保存当前数据到新路径
                print("💾 新路径为空，将当前数据保存到新位置...")
                try await externalDataService.saveAllData(store: self)
            }
            
            isLoading = false
            isLoadingFromExternal = false
            
        } catch {
            print("⚠️ 重新加载数据失败: \(error)")
            isLoading = false
            isLoadingFromExternal = false
            
            // 如果加载失败，至少保存当前数据到新路径
            Task {
                try? await externalDataService.saveAllData(store: self)
            }
        }
    }
    
    // MARK: - 搜索功能
    
    @MainActor
    public func performSearch(query: String) {
        print("🔍 Store: performSearch called with query '\(query)'")
        
        if query.isEmpty {
            print("🧹 Store: Query is empty, clearing results")
            searchResults = []
            return
        }
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchResults = []
            return
        }
        
        // 搜索当前层的节点
        guard let currentLayer = currentLayer else {
            print("⚠️ Store: 没有当前层，搜索结果为空")
            searchResults = []
            return
        }
        
        let nodeResults = nodes.filter { node in
            // 只搜索当前层的节点
            node.layerId == currentLayer.id && (
                node.text.localizedCaseInsensitiveContains(trimmedQuery) ||
                (node.meaning?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
                (node.phonetic?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
                node.tags.contains { $0.value.localizedCaseInsensitiveContains(trimmedQuery) }
            )
        }
        
        searchResults = Array(nodeResults.prefix(50)) // 限制结果数量
        print("🔍 Store: Search completed in layer '\(currentLayer.displayName)', found \(searchResults.count) results")
    }
    
    // MARK: - 节点管理
    
    @Published public var duplicateNodeAlert: DuplicateNodeAlert?
    @Published public var tagTypeModificationAlert: TagTypeModificationAlert?
    
    /// 修复所有节点中的旧标签类型（移除custom_前缀）
    private func fixLegacyTagTypesInAllNodes() {
        var hasAnyChanges = false
        
        for i in 0..<nodes.count {
            let oldNode = nodes[i]
            var fixedNode = oldNode
            fixedNode.fixLegacyTagTypes()
            
            if fixedNode.updatedAt > oldNode.updatedAt {
                nodes[i] = fixedNode
                hasAnyChanges = true
            }
        }
        
        if hasAnyChanges {
            print("🔧 修复了节点中的旧标签类型，移除custom_前缀")
            
            // 保存修复后的数据
            Task {
                try? await externalDataService.saveAllData(store: self)
            }
        } else {
            print("✅ 所有节点的标签类型都是最新格式，无需修复")
        }
    }
    
    /// 检测并修复损坏的节点数据
    @MainActor
    public func detectAndFixCorruptedNodes() -> Int {
        print("🔍 开始检测和修复损坏的节点数据...")
        var fixedCount = 0
        var nodesToRemove: [Int] = []
        
        for i in 0..<nodes.count {
            let node = nodes[i]
            var needsUpdate = false
            var updatedNode = node
            
            // 检查节点文本corruption
            if isTextCorrupted(node.text) {
                let originalText = node.text
                updatedNode.text = sanitizeCorruptedText(node.text)
                print("🔧 修复节点文本: '\(originalText)' -> '\(updatedNode.text)'")
                needsUpdate = true
                fixedCount += 1
            }
            
            // 检查phonetic字段
            if let phonetic = node.phonetic, isTextCorrupted(phonetic) {
                let originalPhonetic = phonetic
                updatedNode.phonetic = sanitizeCorruptedText(phonetic).isEmpty ? nil : sanitizeCorruptedText(phonetic)
                print("🔧 修复音标: '\(originalPhonetic)' -> '\(updatedNode.phonetic ?? "nil")'")
                needsUpdate = true
                fixedCount += 1
            }
            
            // 检查meaning字段
            if let meaning = node.meaning, isTextCorrupted(meaning) {
                let originalMeaning = meaning
                updatedNode.meaning = sanitizeCorruptedText(meaning).isEmpty ? nil : sanitizeCorruptedText(meaning)
                print("🔧 修复含义: '\(originalMeaning)' -> '\(updatedNode.meaning ?? "nil")'")
                needsUpdate = true
                fixedCount += 1
            }
            
            // 检查标签值corruption
            var cleanedTags: [Tag] = []
            for tag in node.tags {
                if isTextCorrupted(tag.value) {
                    let sanitized = sanitizeCorruptedText(tag.value)
                    if !sanitized.isEmpty {
                        let cleanedTag = Tag(
                            type: tag.type,
                            value: sanitized,
                            latitude: tag.latitude,
                            longitude: tag.longitude,
                            isShortcutType: tag.isShortcutType
                        )
                        cleanedTags.append(cleanedTag)
                        print("🔧 修复标签值: '\(tag.value)' -> '\(sanitized)'")
                        needsUpdate = true
                        fixedCount += 1
                    } else {
                        print("⚠️ 移除无法修复的损坏标签: '\(tag.value)'")
                        needsUpdate = true
                        fixedCount += 1
                    }
                } else {
                    cleanedTags.append(tag)
                }
            }
            
            if needsUpdate {
                updatedNode.tags = cleanedTags
                updatedNode.updatedAt = Date()
                
                // 检查修复后的节点是否还有有效内容
                if updatedNode.text == "[已修复]" || updatedNode.text.isEmpty {
                    print("⚠️ 节点损坏严重，标记为删除: index \(i)")
                    nodesToRemove.append(i)
                } else {
                    nodes[i] = updatedNode
                }
            }
        }
        
        // 移除无法修复的损坏节点（从后向前删除以避免索引问题）
        for index in nodesToRemove.reversed() {
            let removedNode = nodes[index]
            nodes.remove(at: index)
            print("🗑️ 移除无法修复的损坏节点: '\(removedNode.text)' (原index: \(index))")
            fixedCount += 1
        }
        
        if fixedCount > 0 {
            print("✅ 数据修复完成，共修复/移除 \(fixedCount) 个问题")
            objectWillChange.send()
            
            // 自动保存修复后的数据
            if !isLoadingFromExternal {
                Task {
                    await forceSaveToExternalStorage()
                    print("💾 修复后的数据已自动保存")
                }
            }
        } else {
            print("✅ 未发现损坏的数据")
        }
        
        return fixedCount
    }
    
    /// 检查文本是否损坏
    private func isTextCorrupted(_ text: String) -> Bool {
        // 空文本不算损坏
        if text.isEmpty {
            return false
        }
        
        // 检查是否包含明显的random字符组合（如"kdf dlf sdfj"）
        let randomWordsPattern = #"(\b[a-z]{1,4}\s){2,}[a-z]{1,4}\b"#
        if text.range(of: randomWordsPattern, options: .regularExpression) != nil {
            return true
        }
        
        // 检查是否包含过多无意义字符
        let totalLength = text.count
        let meaningfulChars = text.filter { char in
            char.isLetter || char.isNumber || char.isWhitespace || "[](){}.,!?;:\"'-".contains(char)
        }.count
        
        // 如果有意义字符比例低于70%，认为是损坏
        if totalLength > 0 && Double(meaningfulChars) / Double(totalLength) < 0.7 {
            return true
        }
        
        return false
    }
    
    /// 清理损坏的文本
    private func sanitizeCorruptedText(_ text: String) -> String {
        var sanitized = text
        
        // 移除连续的随机字符（如"kdf dlf sdfj"）
        let randomPattern = #"(\b[a-z]{1,4}\s){2,}[a-z]{1,4}\b"#
        sanitized = sanitized.replacingOccurrences(
            of: randomPattern, 
            with: "", 
            options: .regularExpression
        )
        
        // 移除无意义的字符组合
        let meaninglessPatterns = [
            #"\b[bcdfghjklmnpqrstvwxyz]{4,}\b"#, // 连续辅音4个以上
            #"\b[aeiou]{4,}\b"#, // 连续元音4个以上
            #"[^\w\s\[\](){}.,!?;:\"'-]+"# // 非标准符号
        ]
        
        for pattern in meaninglessPatterns {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        
        // 清理多余的空白
        sanitized = sanitized.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        
        // 最终清理
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 如果清理后为空，返回默认值
        if sanitized.isEmpty {
            return "[已修复]"
        }
        
        return sanitized
    }
    
    // 重复节点检测结果
    public struct DuplicateNodeAlert {
        let message: String
        let isDuplicate: Bool
        let existingNode: Node?
        let newNode: Node
        let isContextConflict: Bool // 新增：标记是否为上下文冲突
        let conflictDetails: [String]? // 新增：冲突详细信息
        
        // 便利初始化方法保持向后兼容
        init(message: String, isDuplicate: Bool, existingNode: Node?, newNode: Node) {
            self.message = message
            self.isDuplicate = isDuplicate
            self.existingNode = existingNode
            self.newNode = newNode
            self.isContextConflict = false
            self.conflictDetails = nil
        }
        
        // 完整初始化方法
        init(message: String, isDuplicate: Bool, existingNode: Node?, newNode: Node, 
             isContextConflict: Bool, conflictDetails: [String]? = nil) {
            self.message = message
            self.isDuplicate = isDuplicate
            self.existingNode = existingNode
            self.newNode = newNode
            self.isContextConflict = isContextConflict
            self.conflictDetails = conflictDetails
        }
    }
    
    // 标签类型修改确认结果
    public struct TagTypeModificationAlert {
        let message: String
        let tagKey: String
        let oldTypeName: String
        let newTypeName: String
        let affectedNodesCount: Int
        let pendingCommand: String // 保存待执行的完整命令
        let onConfirm: () -> Void
        let onCancel: () -> Void
        
        init(message: String, tagKey: String, oldTypeName: String, newTypeName: String, 
             affectedNodesCount: Int, pendingCommand: String, 
             onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.message = message
            self.tagKey = tagKey
            self.oldTypeName = oldTypeName
            self.newTypeName = newTypeName
            self.affectedNodesCount = affectedNodesCount
            self.pendingCommand = pendingCommand
            self.onConfirm = onConfirm
            self.onCancel = onCancel
        }
    }
    
    // MARK: - 上下文边界检查
    
    /// 检查两个命令的上下文边界是否不同
    /// 这用于检测标签名相同但使用场景不同的冲突情况
    private func hasContextBoundaryConflict(_ command1: String, _ command2: String, tagName: String) -> Bool {
        // 提取标签周围的上下文（前后各3个词）
        let context1 = extractTagContext(command1, tagName: tagName)
        let context2 = extractTagContext(command2, tagName: tagName)
        
        // 如果上下文显著不同，则认为是冲突
        return !areContextsSimilar(context1, context2)
    }
    
    /// 提取标签周围的上下文
    private func extractTagContext(_ command: String, tagName: String) -> [String] {
        let words = command.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        // 找到包含标签的位置（可能在方括号中）
        var tagPosition = -1
        for (index, word) in words.enumerated() {
            if word.contains(tagName) || word.contains("[\(tagName)]") {
                tagPosition = index
                break
            }
        }
        
        if tagPosition == -1 { return [] }
        
        // 提取前后各3个词作为上下文
        let startIndex = max(0, tagPosition - 3)
        let endIndex = min(words.count - 1, tagPosition + 3)
        
        return Array(words[startIndex...endIndex])
    }
    
    /// 判断两个上下文是否相似
    private func areContextsSimilar(_ context1: [String], _ context2: [String]) -> Bool {
        // 如果任一上下文为空，认为不相似
        guard !context1.isEmpty && !context2.isEmpty else { return false }
        
        // 计算重叠单词数
        let set1 = Set(context1.map { $0.lowercased() })
        let set2 = Set(context2.map { $0.lowercased() })
        let intersection = set1.intersection(set2)
        
        // 如果重叠比例小于50%，认为是不同的上下文
        let similarity = Double(intersection.count) / Double(max(set1.count, set2.count))
        return similarity >= 0.5
    }

    @MainActor
    public func addNode(_ node: Node) -> Bool {
        print("📝 Store: 添加节点 - \(node.text)")
        print("   - 音标: \(node.phonetic ?? "nil")")
        print("   - 含义: \(node.meaning ?? "nil")")
        print("   - 标签: \(node.tags.count) 个")
        
        // 检查是否有可用的层
        guard !layers.isEmpty else {
            print("❌ 无法添加节点：没有可用的层！请先创建至少一个层。")
            duplicateNodeAlert = DuplicateNodeAlert(
                message: "无法添加节点：请先创建至少一个层",
                isDuplicate: false,
                existingNode: nil,
                newNode: node
            )
            return false
        }
        
        // 检查当前层是否有效
        guard let currentLayer = currentLayer else {
            print("❌ 无法添加节点：没有选中的当前层！")
            duplicateNodeAlert = DuplicateNodeAlert(
                message: "无法添加节点：请先选择一个层",
                isDuplicate: false,
                existingNode: nil,
                newNode: node
            )
            return false
        }
        
        // 检查是否是复合层，复合层不允许创建节点
        if currentLayer.isCompound {
            print("❌ 无法添加节点：复合层不支持创建节点！")
            duplicateNodeAlert = DuplicateNodeAlert(
                message: "复合层不支持创建节点，请选择普通层",
                isDuplicate: false,
                existingNode: nil,
                newNode: node
            )
            return false
        }
        
        // 安全地检查节点名称冲突，避免崩溃
        print("🔍 检查节点名称冲突 - 新节点: '\(node.text)', 现有节点数量: \(nodes.count)")
        
        // 使用安全的方式查找重复节点，只在当前层内查找
            let potentialDuplicates = nodes.filter { existingNode in
                existingNode.text.lowercased() == node.text.lowercased() && 
                existingNode.layerId == currentLayer.id
            }
            
            if let existingNode = potentialDuplicates.first {
                print("⚠️ 发现重复节点名称: \(node.text)")
                print("⚠️ 现有节点: '\(existingNode.text)' 标签数: \(existingNode.tags.count)")
                print("⚠️ 新节点: '\(node.text)' 标签数: \(node.tags.count)")
                
                // 检查标签冲突，包含上下文边界分析
                print("🏷️ 开始标签冲突检测:")
                print("🏷️ 现有节点标签:")
                for (i, tag) in existingNode.tags.enumerated() {
                    print("   [\(i)] \(tag.type.displayName): '\(tag.value)'")
                }
                print("🏷️ 新节点标签:")
                for (i, tag) in node.tags.enumerated() {
                    print("   [\(i)] \(tag.type.displayName): '\(tag.value)'")
                }
                
                // 检查是否有相同类型和值的标签
                var conflictingTags: [Tag] = []
                var contextConflicts: [String] = []
                
                for newTag in node.tags {
                    let matchingExistingTags = existingNode.tags.filter { existingTag in
                        let typeMatch = existingTag.type == newTag.type
                        let valueMatch = existingTag.value.lowercased() == newTag.value.lowercased()
                        return typeMatch && valueMatch
                    }
                    
                    if !matchingExistingTags.isEmpty {
                        conflictingTags.append(newTag)
                        
                        // 检查上下文边界冲突（这里我们假设有原始命令文本，实际中可能需要从其他地方获取）
                        // 由于当前架构限制，我们使用节点的基本信息来判断上下文
                        let existingContext = "\(existingNode.text) \(existingNode.meaning ?? "") \(existingNode.phonetic ?? "")"
                        let newContext = "\(node.text) \(node.meaning ?? "") \(node.phonetic ?? "")"
                        
                        if !areContextsSimilar(existingContext.components(separatedBy: .whitespacesAndNewlines), 
                                             newContext.components(separatedBy: .whitespacesAndNewlines)) {
                            contextConflicts.append("标签'\(newTag.value)'在不同上下文中使用")
                        }
                    }
                }
                
                print("🏷️ 冲突标签数量: \(conflictingTags.count)")
                print("🏷️ 上下文冲突数量: \(contextConflicts.count)")
                
                // 如果有上下文冲突，优先提示上下文冲突
                if !contextConflicts.isEmpty {
                    let conflictMessage = contextConflicts.joined(separator: "；")
                    duplicateNodeAlert = DuplicateNodeAlert(
                        message: "检测到标签使用冲突：\(conflictMessage)。请确认是否要继续添加？",
                        isDuplicate: true,
                        existingNode: existingNode,
                        newNode: node,
                        isContextConflict: true,
                        conflictDetails: contextConflicts
                    )
                    print("⚠️ 上下文冲突，需要用户确认")
                    return false
                }
                
                // 如果有完全相同的标签
                if !conflictingTags.isEmpty {
                    let tagNames = conflictingTags.map { "\($0.type.displayName)-\($0.value)" }.joined(separator: ", ")
                    duplicateNodeAlert = DuplicateNodeAlert(
                        message: "节点 \"\(node.text)\" 已存在相同的标签: \(tagNames)",
                        isDuplicate: true,
                        existingNode: existingNode,
                        newNode: node
                    )
                    print("❌ 相同节点相同标签，不添加")
                    return false
                } else {
                    // 有不同标签，询问用户是否要合并
                    let newTags = node.tags.filter { newTag in
                        !existingNode.tags.contains { existingTag in
                            existingTag.type == newTag.type && existingTag.value.lowercased() == newTag.value.lowercased()
                        }
                    }
                    
                    if !newTags.isEmpty {
                        let tagNames = newTags.map { "\($0.type.displayName)-\($0.value)" }.joined(separator: ", ")
                        duplicateNodeAlert = DuplicateNodeAlert(
                            message: "节点 \"\(node.text)\" 已存在。是否要将新标签 \(tagNames) 合并到现有节点？",
                            isDuplicate: true,
                            existingNode: existingNode,
                            newNode: node
                        )
                        print("❓ 发现同名节点，需要用户确认是否合并新标签")
                        return false
                    } else {
                        duplicateNodeAlert = DuplicateNodeAlert(
                            message: "节点 \"\(node.text)\" 已存在，且所有标签都相同",
                            isDuplicate: true,
                            existingNode: existingNode,
                            newNode: node
                        )
                        print("❌ 完全重复，不添加")
                        return false
                    }
                }
            } else {
                // 新节点，直接添加
                print("✅ 未发现重复，直接添加新节点")
                
                // 确保节点与当前层关联
                var nodeWithLayer = node
                nodeWithLayer.layerId = currentLayer.id
                print("🔗 设置节点层ID: \(currentLayer.id)")
                
                nodes.append(nodeWithLayer)
                print("✅ 节点添加成功，当前总数: \(nodes.count)")
                
                // 手动触发objectWillChange以确保UI更新
                objectWillChange.send()
                
                // 发送节点更新通知，触发自动同步
                NotificationCenter.default.post(
                    name: Notification.Name("nodeUpdated"),
                    object: nodeWithLayer
                )
                print("📡 已发送nodeUpdated通知，将触发Git自动同步")
                
                // 自动保存到外部存储
                if !isLoadingFromExternal {
                    Task {
                        await forceSaveToExternalStorage()
                        print("💾 节点添加后已自动保存到外部存储")
                    }
                }
                
                return true
            }
    }
    
    /// 强制添加节点（用户确认冲突后）
    @MainActor
    public func forceAddNode(_ node: Node, ignoreConflicts: Bool = false) -> Bool {
        print("🔥 Store: 强制添加节点 - \(node.text) (忽略冲突: \(ignoreConflicts))")
        
        // 检查基本条件
        guard !layers.isEmpty, let currentLayer = currentLayer, !currentLayer.isCompound else {
            duplicateNodeAlert = DuplicateNodeAlert(
                message: "无法强制添加节点：层设置无效",
                isDuplicate: false,
                existingNode: nil,
                newNode: node
            )
            return false
        }
        
        if ignoreConflicts {
            // 忽略所有冲突，直接添加
            var nodeWithLayer = node
            nodeWithLayer.layerId = currentLayer.id
            nodes.append(nodeWithLayer)
            
            print("✅ 节点强制添加成功，当前总数: \(nodes.count)")
            
            // 手动触发UI更新和保存
            objectWillChange.send()
            
            NotificationCenter.default.post(
                name: Notification.Name("nodeUpdated"),
                object: nodeWithLayer
            )
            
            if !isLoadingFromExternal {
                Task {
                    await forceSaveToExternalStorage()
                    print("💾 强制添加的节点已自动保存到外部存储")
                }
            }
            
            return true
        } else {
            // 使用正常的添加流程
            return addNode(node)
        }
    }
    
    @MainActor
    public func addNode(_ text: String, phonetic: String?, meaning: String?) -> Bool {
        print("📝 Store: 添加节点(简化) - \(text)")
        
        // 检查是否有可用的层
        guard !layers.isEmpty, let currentLayer = currentLayer else {
            print("❌ 无法添加节点：没有可用的层或未选中层！")
            duplicateNodeAlert = DuplicateNodeAlert(
                message: "无法添加节点：请先创建并选择一个层",
                isDuplicate: false,
                existingNode: nil,
                newNode: Node(text: text, phonetic: phonetic, meaning: meaning, layerId: UUID(), tags: [])
            )
            return false
        }
        
        let node = Node(text: text, phonetic: phonetic, meaning: meaning, layerId: currentLayer.id, tags: [])
        return addNode(node)
    }
    
    @MainActor
    public func updateNode(_ node: Node) {
        if let index = nodes.firstIndex(where: { $0.id == node.id }) {
            nodes[index] = node
            
            // 手动触发objectWillChange以确保UI更新
            objectWillChange.send()
            
            // 自动保存到外部存储
            if !isLoadingFromExternal {
                Task {
                    await forceSaveToExternalStorage()
                    print("💾 节点更新后已自动保存到外部存储")
                }
            }
        }
    }
    
    @MainActor
    public func updateNode(_ nodeId: UUID, text: String?, phonetic: String?, meaning: String?) {
        if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
            let oldNode = nodes[index]
            var updatedNode = oldNode
            if let text = text { updatedNode.text = text }
            if let phonetic = phonetic { updatedNode.phonetic = phonetic }
            if let meaning = meaning { updatedNode.meaning = meaning }
            updatedNode.updatedAt = Date()
            nodes[index] = updatedNode
            
            // 🔧 如果节点名称发生了变化，需要刷新引用该节点的复合节点
            if let newText = text, newText != oldNode.text {
                print("🔄 节点名称变化: '\(oldNode.text)' -> '\(newText)'")
                // 刷新引用旧名称的复合节点
                refreshCompoundNodesReferencingNode(oldNode.text)
                // 刷新引用新名称的复合节点
                refreshCompoundNodesReferencingNode(newText)
            } else {
                // 即使名称没变，也要刷新复合节点（因为phonetic或meaning可能影响显示）
                refreshCompoundNodesReferencingNode(updatedNode.text)
            }
            
            // 手动触发objectWillChange以确保UI更新
            objectWillChange.send()
            
            // 发送节点更新通知，触发自动同步
            NotificationCenter.default.post(
                name: Notification.Name("nodeUpdated"),
                object: updatedNode
            )
            print("📡 Store.updateNode: 已发送nodeUpdated通知，节点: '\(updatedNode.text)'")
            
            // 自动保存到外部存储
            if !isLoadingFromExternal {
                Task {
                    await forceSaveToExternalStorage()
                    print("💾 节点更新后已自动保存到外部存储")
                }
            }
        }
    }
    
    @MainActor
    public func updateNodeMarkdown(_ nodeId: UUID, markdown: String) {
        if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
            var updatedNode = nodes[index]
            updatedNode.markdown = markdown
            updatedNode.updatedAt = Date()
            nodes[index] = updatedNode
            
            // 如果当前选中的节点是这个节点，更新选中节点引用
            if selectedNode?.id == nodeId {
                selectedNode = updatedNode
                print("🔄 更新选中节点Markdown内容")
            }
            
            // 手动触发objectWillChange以确保UI更新
            objectWillChange.send()
            print("✅ Node markdown updated in memory")
        }
    }
    
    @MainActor
    public func updateNodeTags(_ nodeId: UUID, tags: [Tag]) {
        if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
            var updatedNode = nodes[index]
            updatedNode.tags = tags
            updatedNode.updatedAt = Date()
            nodes[index] = updatedNode
            print("📝 更新节点标签: \(updatedNode.text), 新标签数: \(tags.count)")
            
            // 🔧 触发依赖该节点的复合节点刷新
            refreshCompoundNodesReferencingNode(updatedNode.text)
            
            // 手动触发objectWillChange以确保UI更新
            objectWillChange.send()
            
            // 自动保存到外部存储
            if !isLoadingFromExternal {
                Task {
                    await forceSaveToExternalStorage()
                    print("💾 节点标签更新后已自动保存到外部存储")
                }
            }
        }
    }
    
    @MainActor
    public func deleteNode(_ node: Node) {
        print("🗑️ Store.deleteNode: 删除节点 '\(node.text)'")
        
        nodes.removeAll { $0.id == node.id }
        if selectedNode?.id == node.id {
            selectedNode = nil
        }
        
        // 手动触发objectWillChange以确保UI更新
        objectWillChange.send()
        
        // 发送节点删除通知，触发自动同步
        NotificationCenter.default.post(
            name: Notification.Name("nodeUpdated"),
            object: node
        )
        print("📡 Store.deleteNode: 已发送nodeUpdated通知，节点: '\(node.text)'")
        
        // 自动保存到外部存储
        if !isLoadingFromExternal {
            Task {
                await forceSaveToExternalStorage()
                print("💾 Store.deleteNode: 节点删除后已自动保存到外部存储")
            }
        }
    }
    
    @MainActor
    public func deleteNode(_ nodeId: UUID) {
        // 在删除前获取节点信息用于通知
        let nodeToDelete = nodes.first { $0.id == nodeId }
        
        print("🗑️ Store.deleteNode(UUID): 删除节点ID \(nodeId)")
        if let node = nodeToDelete {
            print("🗑️ Store.deleteNode(UUID): 找到节点 '\(node.text)'")
        }
        
        nodes.removeAll { $0.id == nodeId }
        if selectedNode?.id == nodeId {
            selectedNode = nil
        }
        
        // 手动触发objectWillChange以确保UI更新
        objectWillChange.send()
        
        // 发送节点删除通知，触发自动同步
        if let deletedNode = nodeToDelete {
            NotificationCenter.default.post(
                name: Notification.Name("nodeUpdated"),
                object: deletedNode
            )
            print("📡 Store.deleteNode(UUID): 已发送nodeUpdated通知，节点: '\(deletedNode.text)'")
        } else {
            // 即使没有找到节点，也发送通知（可能是其他操作导致的删除）
            NotificationCenter.default.post(
                name: Notification.Name("nodeUpdated"),
                object: nil
            )
            print("📡 Store.deleteNode(UUID): 未找到删除的节点，发送空通知")
        }
        
        // 自动保存到外部存储
        if !isLoadingFromExternal {
            Task {
                await forceSaveToExternalStorage()
                print("💾 Store.deleteNode(UUID): 节点删除后已自动保存到外部存储")
            }
        }
    }
    
    @MainActor
    public func setSelectedNode(_ node: Node?) {
        print("🔧 Store.setSelectedNode: 开始设置选中节点")
        print("🔧 设置前状态:")
        print("   - 当前selectedNode: '\(selectedNode?.text ?? "nil")' (id: \(selectedNode?.id.uuidString.prefix(8) ?? "nil"))")
        print("   - 当前selectedTag: '\(selectedTag?.value ?? "nil")' (类型: \(selectedTag?.type.displayName ?? "nil"))")
        print("   - 当前层: '\(currentLayer?.displayName ?? "nil")'")
        
        // 🔧 只在必要时保存标签筛选状态（避免干扰节点选择的状态同步）
        if selectedTag != nil || !expandedTagTypes.isEmpty || showAllTagTypeNodes {
            print("💾 Store.setSelectedNode: 检测到标签筛选状态，保存后清除")
            print("   - 即将设置的节点: '\(node?.text ?? "nil")'")
            print("   - 当前选中的节点: '\(selectedNode?.text ?? "nil")'")
            saveCurrentTagFilterState()
        }
        
        let oldText = selectedNode?.text ?? "nil"
        selectedNode = node
        
        print("🔧 Store.setSelectedNode: 节点设置完成")
        print("   - selectedNode 变更: \(oldText) → \(selectedNode?.text ?? "nil")")
        if let node = node {
            print("   - 新节点详情: id=\(node.id.uuidString.prefix(8)), 层=\(node.layerId.uuidString.prefix(8)), 标签数=\(node.tags.count)")
        }
    }
    
    @MainActor
    public func setSelectedTag(_ tag: Tag?) {
        print("🏷️ Store.setSelectedTag: 开始设置选中标签")
        print("🏷️ 设置前状态:")
        print("   - 当前selectedTag: '\(selectedTag?.value ?? "nil")' (类型: \(selectedTag?.type.displayName ?? "nil"))")
        print("   - showAllTagTypeNodes: \(showAllTagTypeNodes)")
        print("   - expandedTagTypes: \(expandedTagTypes.map { $0.displayName })")
        
        selectedTag = tag
        showAllTagTypeNodes = false // 重置为只显示具体标签的节点
        // 保持标签类型展开状态，不要清除expandedTagTypes
        
        print("🏷️ Store.setSelectedTag: 标签设置完成")
        print("   - selectedTag 变更为: '\(selectedTag?.value ?? "nil")' (类型: \(selectedTag?.type.displayName ?? "nil"))")
        print("   - showAllTagTypeNodes 重置为: \(showAllTagTypeNodes)")
        print("   - expandedTagTypes 保持为: \(expandedTagTypes.map { $0.displayName })")
    }
    
    @MainActor
    public func setSelectedTagWithTypeMode(_ tag: Tag?) {
        selectedTag = tag
        showAllTagTypeNodes = true // 设置为显示同标签类型的所有节点
    }
    
    // MARK: - 兼容性方法
    
    @MainActor 
    public func selectNode(_ node: Node?) {
        print("🔧 Store.selectNode 被调用: \(node?.text ?? "nil")")
        print("🔧 调用前 store.selectedNode: \(selectedNode?.text ?? "nil")")
        
        // 🔧 只在节点为空时清除标签筛选状态（如清除选择操作）
        // 普通节点选择不再自动清除标签筛选状态，保持用户的导航上下文
        if node == nil {
            print("🧹 清除节点选择，同时清除标签筛选状态")
            selectedTag = nil
            showAllTagTypeNodes = false
            expandedTagTypes.removeAll()
        } else {
            print("✅ 选择节点但保持标签筛选状态")
        }
        
        setSelectedNode(node)
        print("🔧 调用后 store.selectedNode: \(selectedNode?.text ?? "nil")")
    }
    
    public func createLayer(name: String, displayName: String, color: String = "blue") -> Layer {
        let layer = Layer(name: name, displayName: displayName, color: color)
        addLayer(layer)
        return layer
    }
    
    public func switchToLayer(_ layer: Layer) async {
        await MainActor.run {
            setCurrentLayer(layer)
        }
    }
    
    public func switchToLayer(named name: String) async {
        if let layer = layers.first(where: { $0.name == name || $0.displayName == name }) {
            await switchToLayer(layer)
        }
    }
    
    @MainActor
    public func setCurrentLayer(_ layer: Layer) {
        print("🔄 切换到层: \(layer.displayName) (ID: \(layer.id))")
        
        // 清理当前选择状态，避免跨层显示问题
        selectedNode = nil
        selectedTag = nil
        expandedTagTypes.removeAll()
        showAllTagTypeNodes = false
        searchQuery = ""
        searchResults.removeAll()
        
        // 更新所有层的活跃状态
        for i in layers.indices {
            layers[i].isActive = (layers[i].id == layer.id)
        }
        currentLayer = layer
        
        // 强制触发UI更新
        objectWillChange.send()
        
        // 执行数据一致性检查
        cleanupDataConsistency()
        
        print("✅ 层切换完成，当前层: \(layer.displayName)")
        print("   - 当前层节点数量: \(nodes.filter { $0.layerId == layer.id }.count)")
        print("   - 当前层标签数量: \(currentLayerTags.count)")
    }
    
    // MARK: - 层管理
    
    @MainActor
    public func addLayer(_ layer: Layer) {
        layers.append(layer)
    }
    
    @MainActor
    public func updateLayer(_ layer: Layer) {
        if let index = layers.firstIndex(where: { $0.id == layer.id }) {
            layers[index] = layer
        }
    }
    
    @MainActor
    public func updateLayerDisplayName(layer: Layer, newDisplayName: String, newColor: String? = nil) {
        print("📝 更新层信息: \(layer.displayName) -> \(newDisplayName)")
        
        // 更新层数组中的层
        if let index = layers.firstIndex(where: { $0.id == layer.id }) {
            // 直接修改现有层的属性
            layers[index].displayName = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let newColor = newColor {
                layers[index].color = newColor
            }
            
            // 如果更新的是当前层，也需要更新 currentLayer 引用
            if currentLayer?.id == layer.id {
                currentLayer = layers[index]
            }
            
            print("✅ 层信息更新成功")
        } else {
            print("❌ 未找到要更新的层")
        }
    }
    
    @MainActor
    public func deleteLayer(_ layer: Layer) {
        print("🗑️ 删除层: \(layer.displayName) (ID: \(layer.id))")
        
        // 如果是复合层，需要处理子层引用
        if layer.isCompound {
            print("   - 这是一个复合层，包含 \(layer.childLayerIds.count) 个子层")
        }
        
        // 删除该层中的所有节点
        let nodesToDelete = nodes.filter { $0.layerId == layer.id }
        print("🗑️ 将删除 \(nodesToDelete.count) 个节点")
        nodes.removeAll { $0.layerId == layer.id }
        
        // 从其他复合层中移除对此层的引用
        for i in layers.indices {
            if layers[i].isCompound && layers[i].childLayerIds.contains(layer.id) {
                layers[i].childLayerIds.removeAll { $0 == layer.id }
                print("   - 从复合层 '\(layers[i].displayName)' 中移除引用")
            }
        }
        
        // 检查孤儿节点（layerId不对应任何现有层的节点）
        let validLayerIds = Set(layers.map { $0.id })
        let orphanNodes = nodes.filter { !validLayerIds.contains($0.layerId) }
        if !orphanNodes.isEmpty {
            print("⚠️ 发现 \(orphanNodes.count) 个孤儿节点（层ID无效）")
            for orphan in orphanNodes {
                print("   - \(orphan.text) (layerId: \(orphan.layerId))")
            }
        }
        
        // 删除层
        layers.removeAll { $0.id == layer.id }
        
        // 如果删除的是当前层，切换到其他层
        if currentLayer?.id == layer.id {
            currentLayer = layers.first
            if let newLayer = currentLayer {
                print("🔄 切换到新的当前层: \(newLayer.displayName)")
            } else {
                print("⚠️ 没有剩余的层，当前层为空")
            }
        }
        
        // 强制触发UI更新
        objectWillChange.send()
        
        print("✅ 层删除完成，剩余 \(layers.count) 个层，\(nodes.count) 个节点")
        
        // 自动保存到外部存储
        if !isLoadingFromExternal {
            Task {
                await forceSaveToExternalStorage()
                print("💾 层删除后已自动保存到外部存储")
            }
        }
    }
    
    // MARK: - 复合层管理
    
    @MainActor
    public func createCompoundLayer(name: String, displayName: String, childLayerIds: [UUID], color: String = "purple") -> Layer {
        print("🏗️ 创建复合层: \(displayName)")
        print("   - 包含子层: \(childLayerIds.count) 个")
        
        let compoundLayer = Layer(
            name: name,
            displayName: displayName,
            color: color,
            isCompound: true,
            childLayerIds: childLayerIds
        )
        
        addLayer(compoundLayer)
        
        // 验证子层是否存在
        let validChildLayers = layers.filter { childLayerIds.contains($0.id) }
        print("   - 有效子层: \(validChildLayers.map { $0.displayName }.joined(separator: ", "))")
        
        return compoundLayer
    }
    
    @MainActor
    public func updateCompoundLayer(_ layer: Layer, childLayerIds: [UUID]) {
        guard layer.isCompound else {
            print("⚠️ 尝试更新非复合层的子层列表")
            return
        }
        
        if let index = layers.firstIndex(where: { $0.id == layer.id }) {
            layers[index].childLayerIds = childLayerIds
            print("🔄 更新复合层 '\(layer.displayName)' 的子层列表")
            print("   - 新子层数量: \(childLayerIds.count)")
        }
    }
    
    @MainActor
    public func getNodesInCompoundLayer(_ layer: Layer) -> [Node] {
        guard layer.isCompound else {
            // 如果不是复合层，返回该层的直接节点
            return nodes.filter { $0.layerId == layer.id }
        }
        
        var allNodes: [Node] = []
        
        // 收集所有子层的节点
        for childLayerId in layer.childLayerIds {
            let childNodes = nodes.filter { $0.layerId == childLayerId }
            allNodes.append(contentsOf: childNodes)
        }
        
        // 也包含复合层本身的直接节点（如果有的话）
        let directNodes = nodes.filter { $0.layerId == layer.id }
        allNodes.append(contentsOf: directNodes)
        
        return allNodes
    }
    
    @MainActor
    public func getChildLayers(of compoundLayer: Layer) -> [Layer] {
        guard compoundLayer.isCompound else { return [] }
        
        return layers.filter { compoundLayer.childLayerIds.contains($0.id) }
    }
    
    @MainActor
    public func isLayerUsedInCompound(_ layer: Layer) -> Bool {
        return layers.contains { compoundLayer in
            compoundLayer.isCompound && compoundLayer.childLayerIds.contains(layer.id)
        }
    }
    
    // MARK: - 数据替换功能
    
    @MainActor
    public func replaceAllData(layers: [Layer], nodes: [Node]) async {
        print("🔄 替换所有数据: \(layers.count) 个层, \(nodes.count) 个节点")
        
        // 替换数据
        self.layers = layers
        self.nodes = nodes
        
        // 设置活跃层
        if let activeLayer = layers.first(where: { $0.isActive }) {
            self.currentLayer = activeLayer
        } else if let firstLayer = layers.first {
            // 如果没有活跃层，激活第一个层
            self.currentLayer = firstLayer
            // 更新层状态
            for i in self.layers.indices {
                self.layers[i].isActive = (self.layers[i].id == firstLayer.id)
            }
        }
        
        // 强制触发UI更新
        objectWillChange.send()
        
        print("✅ 数据替换完成")
    }
    
    // MARK: - 数据清理功能
    
    @MainActor
    public func cleanupDataConsistency() {
        print("🧹 开始数据一致性检查和清理...")
        
        var cleanupCount = 0
        
        // 1. 清理孤儿节点（layerId不存在的层）
        let validLayerIds = Set(layers.map { $0.id })
        for i in nodes.indices.reversed() {
            let node = nodes[i]
            if !validLayerIds.contains(node.layerId) {
                if let currentLayer = currentLayer {
                    nodes[i].layerId = currentLayer.id
                    cleanupCount += 1
                    print("🔗 修复孤儿节点: '\(node.text)' -> 层: \(currentLayer.displayName)")
                } else {
                    nodes.remove(at: i)
                    cleanupCount += 1
                    print("🗑️ 删除无效节点: '\(node.text)'")
                }
            }
        }
        
        // 2. 清理不属于当前层的selectedNode
        if let selectedNode = selectedNode,
           let currentLayer = currentLayer,
           selectedNode.layerId != currentLayer.id {
            self.selectedNode = nil
            cleanupCount += 1
            print("🧹 清理跨层选中节点: '\(selectedNode.text)'")
        }
        
        // 3. 清理不属于当前层的selectedTag
        if let selectedTag = selectedTag {
            let tagExistsInCurrentLayer = currentLayerTags.contains { $0.id == selectedTag.id }
            if !tagExistsInCurrentLayer {
                self.selectedTag = nil
                cleanupCount += 1
                print("🧹 清理跨层选中标签: '\(selectedTag.value)'")
            }
        }
        
        if cleanupCount > 0 {
            objectWillChange.send()
            print("✅ 数据一致性清理完成，修复了 \(cleanupCount) 个问题")
        } else {
            print("✅ 数据一致性检查完成，没有发现问题")
        }
    }
    
    @MainActor
    public func fixOrphanNodes() {
        let validLayerIds = Set(layers.map { $0.id })
        let orphanNodes = nodes.filter { !validLayerIds.contains($0.layerId) }
        guard !orphanNodes.isEmpty else {
            print("✅ 没有发现孤儿节点")
            return
        }
        
        print("🔧 开始修复 \(orphanNodes.count) 个孤儿节点...")
        
        // 如果有当前层，使用当前层；否则使用第一个可用层
        guard let targetLayer = currentLayer ?? layers.first else {
            print("❌ 无法修复孤儿节点：没有可用的层")
            return
        }
        
        var fixedCount = 0
        for i in 0..<nodes.count {
            if !validLayerIds.contains(nodes[i].layerId) {
                nodes[i].layerId = targetLayer.id
                print("🔗 修复节点: '\(nodes[i].text)' -> 层: \(targetLayer.displayName)")
                fixedCount += 1
            }
        }
        
        print("✅ 已修复 \(fixedCount) 个孤儿节点，关联到层: \(targetLayer.displayName)")
        objectWillChange.send()
    }
    
    // MARK: - 标签功能
    
    public var allTags: [Tag] {
        let nodeTags = nodes.flatMap { $0.tags }
        let uniqueTags = nodeTags.unique()
        print("🏷️ allTags计算: 节点数=\(nodes.count), 总标签数=\(nodeTags.count), 唯一标签数=\(uniqueTags.count)")
        if !uniqueTags.isEmpty {
            print("🏷️ 标签详情:")
            for (i, tag) in uniqueTags.enumerated() {
                print("   [\(i)] \(tag.type.displayName): '\(tag.value)' (id: \(tag.id))")
            }
        }
        return uniqueTags
    }
    
    // 获取当前层的标签
    public var currentLayerTags: [Tag] {
        guard let currentLayer = currentLayer else { return [] }
        let currentLayerNodes = nodes.filter { $0.layerId == currentLayer.id }
        let nodeTags = currentLayerNodes.flatMap { $0.tags }
        return nodeTags.unique()
    }
    
    public func searchTags(query: String) -> [Tag] {
        let allTags = self.allTags
        
        guard !query.isEmpty else { return [] }
        
        let lowercaseQuery = query.lowercased()
        
        // 直接匹配文本的节点
        let directMatches = nodes.compactMap { node -> (Node, Double, [Tag])? in
            let textMatch = node.text.lowercased().contains(lowercaseQuery) ? 1.0 : 0.0
            let meaningMatch = (node.meaning?.lowercased().contains(lowercaseQuery) ?? false) ? 0.8 : 0.0
            let phoneticMatch = (node.phonetic?.lowercased().contains(lowercaseQuery) ?? false) ? 0.6 : 0.0
            
            let maxMatch = max(textMatch, meaningMatch, phoneticMatch)
            if maxMatch > 0 {
                return (node, maxMatch, node.tags)
            }
            return nil
        }
        
        // 语义匹配的节点
        let semanticMatches = nodes.compactMap { node -> (Node, Double, [Tag])? in
            // 简单的语义匹配逻辑
            let semanticScore = calculateSemanticScore(query: lowercaseQuery, node: node)
            if semanticScore > 0.3 {
                return (node, semanticScore, node.tags)
            }
            return nil
        }
        
        // 按优先级收集标签
        let directTags = directMatches.flatMap { $0.2 }.unique()
        let semanticTags = semanticMatches.flatMap { $0.2 }.unique()
        
        // 标签值直接匹配的标签（优先级最高）
        let directTagMatches = allTags.filter { tag in
            tag.value.localizedCaseInsensitiveContains(query)
        }
        
        // 按优先级合并：直接文本匹配的标签 > 语义匹配的标签 > 直接标签匹配
        var result: [Tag] = []
        result.append(contentsOf: directTags)
        result.append(contentsOf: semanticTags.filter { !result.contains($0) })
        result.append(contentsOf: directTagMatches.filter { !result.contains($0) })
        
        return result
    }
    
    private func calculateSemanticScore(query: String, node: Node) -> Double {
        // 简化的语义匹配
        let components = query.components(separatedBy: .whitespaces)
        let textComponents = node.text.lowercased().components(separatedBy: .whitespaces)
        let meaningComponents = (node.meaning?.lowercased() ?? "").components(separatedBy: .whitespaces)
        
        let matches = components.compactMap { queryComponent in
            textComponents.first { $0.contains(queryComponent) } ??
            meaningComponents.first { $0.contains(queryComponent) }
        }
        
        return Double(matches.count) / Double(components.count)
    }
    
    public func nodes(withTag tag: Tag) -> [Node] {
        return nodes.filter { $0.hasTag(tag) }
    }
    
    public func nodesCount(forTagType type: Tag.TagType) -> Int {
        return nodes.filter { node in
            node.tags.contains { $0.type == type }
        }.count
    }
    
    // MARK: - 示例数据
    
    private func loadSampleData() {
        // 只有在没有数据时才创建示例数据
        createSampleData()
    }
    
    private func createSampleData() {
        // 创建一些简单的示例标签，避免使用可能引起混淆的名称
        let rootTag1 = createTag(type: .custom("root"), value: "vis")
        let rootTag2 = createTag(type: .custom("root"), value: "log")
        let rootTag3 = createTag(type: .custom("root"), value: "cogn")
        let locationTag1 = createTag(type: .location, value: "教室A", latitude: 39.9042, longitude: 116.4074)
        let locationTag2 = createTag(type: .location, value: "办公室", latitude: 40.7589, longitude: -73.9851)
        let locationTag3 = createTag(type: .location, value: "会议室", latitude: 39.9055, longitude: 116.4078)
        
        // 获取各个层级
        guard let englishLayer = layers.first(where: { $0.name == "english" }),
              let statsLayer = layers.first(where: { $0.name == "statistics" }),
              let psychologyLayer = layers.first(where: { $0.name == "psychology" }) else { return }
        
        // === 英语节点层 ===
        let englishNodes = [
            Node(text: "visible", phonetic: "/ˈvɪzəbəl/", meaning: "可见的", layerId: englishLayer.id, tags: [rootTag1, rootTag1]),
            Node(text: "logic", phonetic: "/ˈlɑːdʒɪk/", meaning: "逻辑", layerId: englishLayer.id, tags: [rootTag2, rootTag3]),
            Node(text: "vision", phonetic: "/ˈvɪʒən/", meaning: "视觉，远见", layerId: englishLayer.id, tags: [rootTag1, rootTag1, locationTag1]),
            Node(text: "logical", phonetic: "/ˈlɑːdʒɪkəl/", meaning: "合乎逻辑的", layerId: englishLayer.id, tags: [rootTag2, rootTag3]),
            Node(text: "recognize", phonetic: "/ˈrekəɡnaɪz/", meaning: "识别，认出", layerId: englishLayer.id, tags: [rootTag3, rootTag2])
        ]
        
        // === 统计学层 ===
        let statisticsNodes = [
            Node(text: "regression", phonetic: "/rɪˈɡrɛʃən/", meaning: "回归分析", layerId: statsLayer.id, tags: [rootTag3, locationTag2]),
            Node(text: "correlation", phonetic: "/ˌkɔːrəˈleɪʃən/", meaning: "相关性", layerId: statsLayer.id, tags: [rootTag1]),
            Node(text: "hypothesis", phonetic: "/haɪˈpɑːθəsɪs/", meaning: "假设", layerId: statsLayer.id, tags: [rootTag2]),
            Node(text: "variance", phonetic: "/ˈvɛriəns/", meaning: "方差", layerId: statsLayer.id, tags: [rootTag3]),
            Node(text: "distribution", phonetic: "/ˌdɪstrəˈbjuːʃən/", meaning: "分布", layerId: statsLayer.id, tags: [rootTag1, locationTag3])
        ]
        
        // === 教育心理学层 ===  
        let psychologyNodes = [
            Node(text: "cognitive", phonetic: "/ˈkɑːɡnətɪv/", meaning: "认知的", layerId: psychologyLayer.id, tags: [rootTag3, rootTag2]),
            Node(text: "motivation", phonetic: "/ˌmoʊtəˈveɪʃən/", meaning: "动机", layerId: psychologyLayer.id, tags: [rootTag1]),
            Node(text: "reinforcement", phonetic: "/ˌriːɪnˈfɔːrsmənt/", meaning: "强化", layerId: psychologyLayer.id, tags: [rootTag3]),
            Node(text: "cognition", phonetic: "/kɑːɡˈnɪʃəɳ/", meaning: "认知", layerId: psychologyLayer.id, tags: [rootTag3, rootTag2, locationTag3]),
            Node(text: "learning", phonetic: "/ˈlɜːrnɪŋ/", meaning: "学习", layerId: psychologyLayer.id, tags: [rootTag1])
        ]
        
        // 添加所有节点到store
        nodes.append(contentsOf: englishNodes)
        nodes.append(contentsOf: statisticsNodes)
        nodes.append(contentsOf: psychologyNodes)
        
        print("✅ 示例数据创建完成:")
        print("   - 层数量: \(layers.count)")
        print("   - 节点数量: \(nodes.count)")
        print("   - 当前活跃层: \(currentLayer?.displayName ?? "无")")
    }
    
    public func createTag(type: Tag.TagType, value: String, latitude: Double? = nil, longitude: Double? = nil, isShortcutType: Bool = false) -> Tag {
        return Tag(
            type: type,
            value: value,
            latitude: latitude,
            longitude: longitude,
            isShortcutType: isShortcutType
        )
    }
    
    public func addTag(_ tag: Tag) {
        // 标签会自动添加到节点中，这里可以做一些全局标签管理
        // 暂时不需要特殊处理
    }
    
    public func addTag(to nodeId: UUID, tag: Tag) {
        if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
            // 创建新的节点副本并更新tags
            var updatedNode = nodes[index]
            updatedNode.tags.append(tag)
            updatedNode.updatedAt = Date()
            
            // 替换整个节点以确保触发@Published更新
            nodes[index] = updatedNode
            
            print("✅ 添加标签完成，节点已更新: \(tag.type.displayName) - \(tag.value)")
            print("📊 当前节点标签数: \(updatedNode.tags.count)")
            
            // 🔧 触发依赖该节点的复合节点刷新
            refreshCompoundNodesReferencingNode(updatedNode.text)
            
            // 手动触发objectWillChange以确保UI更新
            objectWillChange.send()
            
            // 发送节点更新通知以清除图谱缓存
            NotificationCenter.default.post(
                name: Notification.Name("nodeUpdated"),
                object: nil,
                userInfo: ["nodeId": nodeId]
            )
            
            // 自动保存到外部存储
            if !isLoadingFromExternal {
                Task {
                    await forceSaveToExternalStorage()
                    print("💾 标签添加后已自动保存到外部存储")
                }
            }
            
            // 如果当前选中的节点是这个节点，更新选中节点引用
            if selectedNode?.id == nodeId {
                selectedNode = updatedNode
                print("🔄 更新选中节点引用以确保UI刷新")
            }
            
            // 如果当前选中的标签与新添加的标签匹配，更新选中标签引用
            if let currentSelectedTag = selectedTag,
               currentSelectedTag.type == tag.type && currentSelectedTag.value == tag.value {
                print("🔄 更新选中标签引用以确保UI刷新")
                selectedTag = tag
            }
        }
    }
    
    // MARK: - 数据清理
    
    @MainActor
    public func clearAllData() {
        print("🧹 开始彻底清理所有数据...")
        print("🧹 清理前状态:")
        print("   - 节点数量: \(nodes.count)")
        print("   - 层数量: \(layers.count)")
        print("   - 当前层: \(currentLayer?.displayName ?? "nil")")
        print("   - 所有标签数量: \(allTags.count)")
        
        nodes.removeAll()
        layers.removeAll()  // 清空所有层
        currentLayer = nil  // 清空当前层
        selectedNode = nil
        selectedTag = nil
        searchQuery = ""
        searchResults.removeAll()
        
        print("🧹 清理后状态:")
        print("   - 节点数量: \(nodes.count)")
        print("   - 层数量: \(layers.count)")
        print("   - 当前层: \(currentLayer?.displayName ?? "nil")")
        print("   - 所有标签数量: \(allTags.count)")
        
        // 完全清空标签映射
        TagMappingManager.shared.clearAll()
        
        // 确保内置核心标签重新存在
        TagMappingManager.shared.ensureBuiltInCoreTags()
        print("🏷️ 标签映射已清空并重新添加内置核心标签")
        print("📂 所有层已清空")
        
        // 强制多次触发UI更新，确保所有视图都刷新
        objectWillChange.send()
        
        // 延迟再次触发，确保界面完全刷新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.objectWillChange.send()
            print("🔄 延迟UI刷新完成")
        }
        
        // 再次延迟触发，确保所有视图组件都收到更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.objectWillChange.send()
            print("🔄 第三次UI刷新完成")
        }
        
        // 如果需要，清理外部数据缓存
        if externalDataManager.isDataPathSelected {
            Task {
                do {
                    try await externalDataService.clearAllExternalData()
                    print("✅ 外部数据也已清理")
                } catch {
                    print("⚠️ 清理外部数据时出错: \(error)")
                }
            }
        }
        
        print("✅ 数据清理完成")
    }
    
    // 只清理数据但不加载示例数据
    @MainActor
    public func clearAllDataWithoutSample() {
        print("🧹 清理数据但不加载示例数据...")
        clearAllData()
        // 重新设置空的默认层
        setupDefaultLayers()
        print("✅ 数据清理完成，无示例数据")
    }
    
    // 强制刷新所有数据和界面
    @MainActor
    public func forceRefreshUI() {
        print("🔄 强制刷新UI...")
        objectWillChange.send()
        
        // 延迟再次触发，确保界面完全刷新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.objectWillChange.send()
            print("✅ UI刷新完成")
        }
    }
    
    @MainActor
    public func resetToSampleData() {
        // 清理数据但保留默认标签映射
        nodes.removeAll()
        layers.removeAll()  // 清空所有层
        currentLayer = nil  // 清空当前层
        selectedNode = nil
        selectedTag = nil
        searchQuery = ""
        searchResults.removeAll()
        
        // 重置标签映射为默认值（不是完全清空）
        TagMappingManager.shared.resetToDefaults()
        print("🏷️ 标签映射已重置为默认值")
        
        // 重新创建默认层
        setupDefaultLayers()
        createSampleData()
        
        // 如果有外部数据存储，保存新的示例数据到外部存储
        if externalDataManager.isDataPathSelected {
            Task {
                do {
                    try await externalDataService.saveAllData(store: self)
                    print("✅ 示例数据已保存到外部存储")
                } catch {
                    print("⚠️ 保存示例数据到外部存储失败: \(error)")
                }
            }
        }
    }
    
    // 完整清理数据（包括外部存储）
    @MainActor
    public func clearAllDataIncludingExternal() async {
        // 先清理内存数据
        clearAllData()
        
        // 如果有外部数据存储，也清理外部文件
        if externalDataManager.isDataPathSelected {
            do {
                try await externalDataService.clearAllExternalData()
                print("✅ 已完全清理所有数据（包括外部存储和标签设置）")
            } catch {
                print("⚠️ 清理外部存储失败: \(error)")
            }
        }
    }
    
    // MARK: - Missing methods for TagSidebarView
    
    public func getNodesInCurrentLayer() -> [Node] {
        guard let currentLayer = currentLayer else { return [] }
        return nodes.filter { $0.layerId == currentLayer.id }
    }
    
    public func nodesInCurrentLayer(withTag tag: Tag) -> [Node] {
        guard let currentLayer = currentLayer else { return [] }
        
        // 从当前层的 nodes 中获取有该标签的节点
        return nodes.filter { $0.layerId == currentLayer.id && $0.hasTag(tag) }
    }
    
    public func nodesInCurrentLayer(withTagType tagType: Tag.TagType) -> [Node] {
        guard let currentLayer = currentLayer else { return [] }
        
        // 从当前层的 nodes 中获取有该标签类型的节点
        return nodes.filter { node in
            node.layerId == currentLayer.id && node.tags.contains { $0.type == tagType }
        }
    }
    
    public func nodesInCurrentLayer(withTagTypes tagTypes: Set<Tag.TagType>) -> [Node] {
        guard let currentLayer = currentLayer else { return [] }
        guard !tagTypes.isEmpty else { return [] }
        
        // 从当前层的 nodes 中获取包含任一指定标签类型的节点
        return nodes.filter { node in
            node.layerId == currentLayer.id && node.tags.contains { tag in
                tagTypes.contains(tag.type)
            }
        }
    }
    
    public func getRelevantTags(for query: String) -> [Tag] {
        return searchTags(query: query)
    }
    
    @MainActor
    public func selectTag(_ tag: Tag?) {
        setSelectedTag(tag)
    }
    
    @MainActor
    public func selectTagType(_ tagType: Tag.TagType) {
        // 找到该标签类型下的第一个标签作为代表
        let representativeTag = allTags.first { $0.type == tagType }
        if let tag = representativeTag {
            setSelectedTagWithTypeMode(tag)
            print("🏷️ Store.selectTagType: 选择标签类型 \(tagType.displayName)，显示该类型下的所有节点")
        }
    }
    
    @MainActor
    public func selectTagWithFocus(_ tag: Tag) {
        // 使用标签类型模式显示所有同类型节点，但保持对特定标签的焦点
        setSelectedTagWithTypeMode(tag)
        print("🎯 Store.selectTagWithFocus: 显示 \(tag.type.displayName) 类型的所有节点，焦点在 '\(tag.value)'")
    }
    
    /// 处理地图节点点击，展开location标签类型并选中对应的地点标签
    /// 模拟完整的手动标签导航流程：
    /// 1. 展开"地点"标签类型（location tag type）
    /// 2. 选中该节点对应的具体地点标签（比如"养马岛租车"）
    /// 3. 显示所有带这个地点标签的节点列表
    /// 4. 在这个筛选结果中选中被点击的节点
    @MainActor
    public func expandLocationTagAndSelect(_ node: Node) {
        print("🗺️ Store.expandLocationTagAndSelect: 开始完整标签导航流程 '\(node.text)'")
        print("🗺️ Store类型: \(type(of: self)) - isSharedInstance: \(isSharedInstance)")
        print("🗺️ 当前节点总数: \(nodes.count), 层数: \(layers.count)")
        
        // 🔧 在清除状态之前，先保存当前的标签筛选状态
        print("💾 Store.expandLocationTagAndSelect: 保存当前标签筛选状态以便后续恢复")
        saveCurrentTagFilterState()
        
        // 🔧 首先彻底清除所有状态，包括窗口焦点状态和之前的选择状态
        print("🧹 Store.expandLocationTagAndSelect: 彻底清除所有选择状态和窗口焦点状态")
        clearTagFilter() // 这会清除所有标签筛选状态
        
        // 🔧 通过WindowFocusManager强制刷新窗口状态，确保没有残留的窗口上下文
        WindowFocusManager.shared.forceRefreshWindowState()
        print("🔄 Store.expandLocationTagAndSelect: 已强制刷新窗口焦点状态")
        
        // 0. 验证节点是否存在于当前store实例中
        let nodeExistsInStore = nodes.contains { $0.id == node.id }
        print("🔍 节点是否存在于当前store实例: \(nodeExistsInStore)")
        if !nodeExistsInStore {
            print("⚠️ 警告: 节点 '\(node.text)' 不存在于当前store实例中!")
            print("   当前store中的节点: \(nodes.map { $0.text })")
        }
        
        // 1. 找到该节点的第一个location标签
        guard let locationTag = node.locationTags.first else {
            print("⚠️ 节点 '\(node.text)' 没有location标签，回退到直接选择")
            // 如果没有location标签，直接选中节点但确保状态已清除
            setSelectedNode(node)
            return
        }
        
        print("📍 找到location标签: '\(locationTag.value)' (类型: \(locationTag.type.displayName))")
        
        // 2. 展开location标签类型（相当于在TagSidebarView中点击展开箭头）
        print("📂 展开location标签类型")
        expandedTagTypes.insert(locationTag.type)
        
        // 3. 选中该具体地点标签，显示所有带这个标签的节点（相当于点击具体标签值）
        print("🎯 选中具体地点标签: '\(locationTag.value)'")
        selectedTag = locationTag
        showAllTagTypeNodes = false // 显示该具体标签的节点，而不是整个标签类型
        
        // 5. 在筛选结果中选中被点击的节点
        print("✅ 在筛选结果中选中被点击的节点")
        setSelectedNode(node)
        
        print("✅ Store.expandLocationTagAndSelect 完整流程完成:")
        print("   - expandedTagTypes: \(expandedTagTypes.map { $0.displayName })")
        print("   - selectedTag: '\(selectedTag?.value ?? "nil")' (类型: \(selectedTag?.type.displayName ?? "nil"))")
        print("   - selectedNode: '\(selectedNode?.text ?? "nil")")
        print("   - showAllTagTypeNodes: \(showAllTagTypeNodes)")
        print("   📋 当前筛选结果: 显示所有包含'\(locationTag.value)'标签的节点")
    }
    
    @MainActor
    public func setExpandedTagTypes(_ tagTypes: Set<Tag.TagType>) {
        expandedTagTypes = tagTypes
        showAllTagTypeNodes = !tagTypes.isEmpty
        print("🔄 Store.setExpandedTagTypes: 设置展开的标签类型数量: \(tagTypes.count)")
        for tagType in tagTypes {
            print("   - \(tagType.displayName)")
        }
    }
    
    /// 添加展开的标签类型
    @MainActor
    public func addExpandedTagType(_ tagType: Tag.TagType) {
        expandedTagTypes.insert(tagType)
        showAllTagTypeNodes = !expandedTagTypes.isEmpty
        print("📂 Store.addExpandedTagType: 添加展开标签类型 \(tagType.displayName)")
    }
    
    /// 移除展开的标签类型
    @MainActor
    public func removeExpandedTagType(_ tagType: Tag.TagType) {
        expandedTagTypes.remove(tagType)
        showAllTagTypeNodes = !expandedTagTypes.isEmpty
        print("📁 Store.removeExpandedTagType: 移除展开标签类型 \(tagType.displayName)")
    }
    
    /// 切换标签类型展开状态
    @MainActor
    public func toggleExpandedTagType(_ tagType: Tag.TagType) {
        if expandedTagTypes.contains(tagType) {
            removeExpandedTagType(tagType)
        } else {
            addExpandedTagType(tagType)
        }
    }
    
    @MainActor
    public func clearTagFilter() {
        print("🧹 Store.clearTagFilter: 开始清除所有标签筛选状态")
        print("🧹 清除前状态:")
        print("   - selectedTag: '\(selectedTag?.value ?? "nil")' (类型: \(selectedTag?.type.displayName ?? "nil"))")
        print("   - selectedNode: '\(selectedNode?.text ?? "nil")'")
        print("   - expandedTagTypes: \(expandedTagTypes.map { $0.displayName })")
        print("   - showAllTagTypeNodes: \(showAllTagTypeNodes)")
        
        // 使用微小延迟确保完全脱离视图更新周期
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { [weak self] in
            self?.selectedTag = nil
            self?.expandedTagTypes.removeAll()
            self?.showAllTagTypeNodes = false
            self?.selectedNode = nil
            // @Published properties automatically trigger objectWillChange.send()
        }
        
        print("✅ Store.clearTagFilter: 标签筛选状态已彻底清除，回到初始状态")
        print("🔄 已触发UI强制刷新和清除通知")
    }
    
    // MARK: - 标签筛选状态记忆方法
    
    /// 保存当前的标签筛选状态（公共方法，用于测试）
    @MainActor
    public func saveCurrentTagFilterStatePublic() {
        print("🔧 手动保存标签筛选状态（测试用）")
        saveCurrentTagFilterState()
    }
    
    /// 保存当前的标签筛选状态
    @MainActor
    private func saveCurrentTagFilterState() {
        print("🔄 Store.saveCurrentTagFilterState: 开始保存状态")
        print("   - 保存前检查: selectedTag='\(selectedTag?.value ?? "nil")', expandedTagTypes=\(expandedTagTypes.map { $0.displayName }), showAllTagTypeNodes=\(showAllTagTypeNodes)")
        
        let newState = SavedTagFilterState(
            selectedTag: selectedTag,
            expandedTagTypes: expandedTagTypes,
            showAllTagTypeNodes: showAllTagTypeNodes
        )
        
        savedTagFilterState = newState
        
        print("✅ Store.saveCurrentTagFilterState: 已成功保存标签筛选状态!")
        print("   - 状态描述: \(newState.description)")
        print("   - selectedTag: '\(newState.selectedTag?.value ?? "nil")'")
        print("   - expandedTagTypes: \(newState.expandedTagTypes.map { $0.displayName })")
        print("   - showAllTagTypeNodes: \(newState.showAllTagTypeNodes)")
        print("   - 保存时间: \(newState.timestamp)")
    }
    
    /// 恢复上一次保存的标签筛选状态
    @MainActor
    public func restorePreviousTagFilterState() {
        guard let savedState = savedTagFilterState else {
            print("⚠️ Store.restorePreviousTagFilterState: 没有保存的标签筛选状态")
            print("🔍 当前状态调试:")
            print("   - 当前selectedTag: '\(selectedTag?.value ?? "nil")'")
            print("   - 当前expandedTagTypes: \(expandedTagTypes.map { $0.displayName })")
            print("   - 当前showAllTagTypeNodes: \(showAllTagTypeNodes)")
            print("💡 提示: 请先进行一些标签筛选操作，然后点击搜索结果，再尝试恢复")
            return
        }
        
        print("🔄 Store.restorePreviousTagFilterState: 开始恢复标签筛选状态")
        print("   - 恢复状态描述: \(savedState.description)")
        print("   - 保存时间: \(savedState.timestamp)")
        
        // 恢复状态
        selectedTag = savedState.selectedTag
        expandedTagTypes = savedState.expandedTagTypes
        showAllTagTypeNodes = savedState.showAllTagTypeNodes
        
        // 清除节点选择，让用户重新聚焦到标签筛选视图
        selectedNode = nil
        
        print("✅ Store.restorePreviousTagFilterState: 标签筛选状态恢复完成")
        print("   - selectedTag: '\(selectedTag?.value ?? "nil")' (类型: \(selectedTag?.type.displayName ?? "nil"))")
        print("   - expandedTagTypes: \(expandedTagTypes.map { $0.displayName })")
        print("   - showAllTagTypeNodes: \(showAllTagTypeNodes)")
        
        // 手动触发UI更新
        objectWillChange.send()
    }
    
    /// 检查是否有可恢复的标签筛选状态
    @MainActor
    public func hasSavedTagFilterState() -> Bool {
        return savedTagFilterState != nil
    }
    
    /// 获取保存的标签筛选状态描述（用于调试）
    @MainActor
    public func getSavedTagFilterStateDescription() -> String? {
        return savedTagFilterState?.description
    }
    
    public func findLocationTagByName(_ name: String) -> Tag? {
        return allTags.first { tag in
            isLocationTag(tag) && tag.displayName == name
        }
    }
    
    // 检查是否是地图/位置标签
    private func isLocationTag(_ tag: Tag) -> Bool {
        if case .custom(let key) = tag.type {
            let locationKeys = ["loc", "location", "地点", "位置"]
            return locationKeys.contains(key.lowercased())
        }
        return false
    }
    
    public func removeTag(from nodeId: UUID, tagId: UUID) {
        if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
            let removedTags = nodes[index].tags.filter { $0.id == tagId }
            
            // 创建新的节点副本并更新tags
            var updatedNode = nodes[index]
            updatedNode.tags.removeAll { $0.id == tagId }
            updatedNode.updatedAt = Date()
            
            // 替换整个节点以确保触发@Published更新
            nodes[index] = updatedNode
            
            // 🔧 触发依赖该节点的复合节点刷新
            refreshCompoundNodesReferencingNode(updatedNode.text)
            
            // 手动触发objectWillChange以确保UI更新
            objectWillChange.send()
            
            // 发送节点更新通知以清除图谱缓存
            NotificationCenter.default.post(
                name: Notification.Name("nodeUpdated"),
                object: nil,
                userInfo: ["nodeId": nodeId]
            )
            
            // 如果当前选中的节点是这个节点，更新选中节点引用
            if selectedNode?.id == nodeId {
                selectedNode = updatedNode
                print("🔄 更新选中节点引用以确保UI刷新")
            }
            
            if let removedTag = removedTags.first {
                print("✅ 删除标签完成，节点已更新: \(removedTag.type.displayName) - \(removedTag.value)")
                print("📊 当前节点标签数: \(updatedNode.tags.count)")
            }
            
            // 自动保存到外部存储
            if !isLoadingFromExternal {
                Task {
                    await forceSaveToExternalStorage()
                    print("💾 标签删除后已自动保存到外部存储")
                }
            }
        }
    }
    
    // MARK: - 批量标签操作
    
    /// 批量删除标签：从所有节点中删除指定的标签类型
    public func batchDeleteTagTypes(_ tagTypes: Set<Tag.TagType>) -> BatchDeleteResult {
        var affectedNodeCount = 0
        var deletedTagCount = 0
        var affectedNodes: [(Node, [Tag])] = []
        
        print("🗑️ 开始批量删除标签类型: \(tagTypes.map { $0.displayName })")
        
        // 遍历所有节点，删除匹配的标签
        for (index, node) in nodes.enumerated() {
            let tagsToRemove = node.tags.filter { tag in
                tagTypes.contains(tag.type)
            }
            
            if !tagsToRemove.isEmpty {
                var updatedNode = node
                updatedNode.tags.removeAll { tag in
                    tagTypes.contains(tag.type)
                }
                updatedNode.updatedAt = Date()
                
                nodes[index] = updatedNode
                affectedNodes.append((updatedNode, tagsToRemove))
                affectedNodeCount += 1
                deletedTagCount += tagsToRemove.count
                
                // 触发复合节点刷新
                refreshCompoundNodesReferencingNode(updatedNode.text)
                
                print("🗑️ 从节点 '\(node.text)' 删除 \(tagsToRemove.count) 个标签")
            }
        }
        
        // 更新选中节点引用
        if let selectedNode = selectedNode,
           let updatedSelectedNode = affectedNodes.first(where: { $0.0.id == selectedNode.id })?.0 {
            self.selectedNode = updatedSelectedNode
        }
        
        // 触发UI更新
        objectWillChange.send()
        
        // 发送批量更新通知
        NotificationCenter.default.post(
            name: Notification.Name("nodesBatchUpdated"),
            object: nil,
            userInfo: [
                "affectedNodeCount": affectedNodeCount,
                "deletedTagCount": deletedTagCount
            ]
        )
        
        // 自动保存到外部存储
        if !isLoadingFromExternal {
            Task {
                await forceSaveToExternalStorage()
                print("💾 批量标签删除后已自动保存到外部存储")
            }
        }
        
        let result = BatchDeleteResult(
            affectedNodeCount: affectedNodeCount,
            deletedTagCount: deletedTagCount,
            affectedNodes: affectedNodes.map { $0.0 }
        )
        
        print("✅ 批量删除完成: 影响 \(affectedNodeCount) 个节点，删除 \(deletedTagCount) 个标签")
        return result
    }
    
    /// 批量删除特定标签值：从所有节点中删除指定的标签
    public func batchDeleteSpecificTags(_ tagsToDelete: [Tag]) -> BatchDeleteResult {
        var affectedNodeCount = 0
        var deletedTagCount = 0
        var affectedNodes: [(Node, [Tag])] = []
        
        print("🗑️ 开始批量删除特定标签: \(tagsToDelete.count) 个")
        
        // 创建标签匹配条件（基于类型和值）
        let tagMatchers = tagsToDelete.map { targetTag in
            (type: targetTag.type, value: targetTag.value)
        }
        
        // 遍历所有节点，删除匹配的标签
        for (index, node) in nodes.enumerated() {
            let removedTags = node.tags.filter { tag in
                let isMatch = tagMatchers.contains { matcher in
                    // 🔧 修复TagType匹配问题：使用rawValue进行规范化比较而非直接枚举比较
                    let typeMatch: Bool
                    switch (tag.type, matcher.type) {
                    case (.location, .location):
                        typeMatch = true
                    case (.custom(let tagKey), .custom(let matcherKey)):
                        // 使用rawValue进行比较，避免因大小写等问题导致的匹配失败
                        typeMatch = tagKey.lowercased() == matcherKey.lowercased()
                    default:
                        typeMatch = false
                    }
                    
                    let valueMatch = tag.value == matcher.value
                    
                    return typeMatch && valueMatch
                }
                return isMatch
            }
            
            if !removedTags.isEmpty {
                var updatedNode = node
                updatedNode.tags.removeAll { tag in
                    tagMatchers.contains { matcher in
                        // 🔧 应用相同的修复：使用规范化比较
                        let typeMatch: Bool
                        switch (tag.type, matcher.type) {
                        case (.location, .location):
                            typeMatch = true
                        case (.custom(let tagKey), .custom(let matcherKey)):
                            typeMatch = tagKey.lowercased() == matcherKey.lowercased()
                        default:
                            typeMatch = false
                        }
                        return typeMatch && tag.value == matcher.value
                    }
                }
                updatedNode.updatedAt = Date()
                
                nodes[index] = updatedNode
                affectedNodes.append((updatedNode, removedTags))
                affectedNodeCount += 1
                deletedTagCount += removedTags.count
                
                // 触发复合节点刷新
                refreshCompoundNodesReferencingNode(updatedNode.text)
                
                print("🗑️ 从节点 '\(node.text)' 删除 \(removedTags.count) 个特定标签")
            }
        }
        
        // 更新选中节点引用
        if let selectedNode = selectedNode,
           let updatedSelectedNode = affectedNodes.first(where: { $0.0.id == selectedNode.id })?.0 {
            self.selectedNode = updatedSelectedNode
        }
        
        // 触发UI更新
        objectWillChange.send()
        
        // 发送批量更新通知
        NotificationCenter.default.post(
            name: Notification.Name("nodesBatchUpdated"),
            object: nil,
            userInfo: [
                "affectedNodeCount": affectedNodeCount,
                "deletedTagCount": deletedTagCount
            ]
        )
        
        // 自动保存到外部存储
        if !isLoadingFromExternal {
            Task {
                await forceSaveToExternalStorage()
                print("💾 特定标签批量删除后已自动保存到外部存储")
            }
        }
        
        let result = BatchDeleteResult(
            affectedNodeCount: affectedNodeCount,
            deletedTagCount: deletedTagCount,
            affectedNodes: affectedNodes.map { $0.0 }
        )
        
        print("✅ 特定标签批量删除完成: 影响 \(affectedNodeCount) 个节点，删除 \(deletedTagCount) 个标签")
        return result
    }
    
    /// 获取标签使用分析
    public func getTagUsageAnalysis() -> [TagUsageInfo] {
        var tagUsageMap: [String: TagUsageInfo] = [:]
        
        // 遍历所有节点的标签，统计使用情况
        for node in nodes {
            for tag in node.tags {
                let key = "\(tag.type.rawValue)|\(tag.value)"
                
                if var existingInfo = tagUsageMap[key] {
                    existingInfo.nodeCount += 1
                    existingInfo.nodes.append(node)
                    tagUsageMap[key] = existingInfo
                } else {
                    tagUsageMap[key] = TagUsageInfo(
                        tagType: tag.type,
                        tagValue: tag.value,
                        nodeCount: 1,
                        nodes: [node]
                    )
                }
            }
        }
        
        // 按使用频率排序
        return Array(tagUsageMap.values).sorted { $0.nodeCount > $1.nodeCount }
    }
    
    /// 获取特定层的标签使用分析
    public func getTagUsageAnalysisForLayer(_ layerId: UUID) -> [TagUsageInfo] {
        var tagUsageMap: [String: TagUsageInfo] = [:]
        
        // 只遍历指定层的节点
        let layerNodes = nodes.filter { $0.layerId == layerId }
        
        for node in layerNodes {
            for tag in node.tags {
                let key = "\(tag.type.rawValue)|\(tag.value)"
                
                if var existingInfo = tagUsageMap[key] {
                    existingInfo.nodeCount += 1
                    existingInfo.nodes.append(node)
                    tagUsageMap[key] = existingInfo
                } else {
                    tagUsageMap[key] = TagUsageInfo(
                        tagType: tag.type,
                        tagValue: tag.value,
                        nodeCount: 1,
                        nodes: [node]
                    )
                }
            }
        }
        
        // 按使用频率排序
        return Array(tagUsageMap.values).sorted { $0.nodeCount > $1.nodeCount }
    }
    
    /// 获取标签图谱数据
    public func getTagTypeGraphData(for tagType: Tag.TagType) -> TagTypeGraphData {
        let analysis = getTagUsageAnalysis()
        let filteredAnalysis = analysis.filter { $0.tagType == tagType }
        
        let tagValues = filteredAnalysis.map { usage in
            TagValueNode(
                value: usage.tagValue,
                nodes: usage.nodes,
                usageCount: usage.nodeCount
            )
        }
        
        return TagTypeGraphData(tagType: tagType, tagValues: tagValues)
    }
    
    /// 获取标签图谱的UniversalRelationshipGraphView数据
    public func getTagTypeUniversalGraphData(for tagType: Tag.TagType) -> (nodes: [TagTypeGraphNode], edges: [TagTypeGraphEdge]) {
        let data = getTagTypeGraphData(for: tagType)
        
        var nodes: [TagTypeGraphNode] = []
        var edges: [TagTypeGraphEdge] = []
        var nextId = 1
        
        // 1. 添加中心节点（标签类型）
        let centerNode = TagTypeGraphNode(
            id: nextId,
            label: tagType.displayName,
            subtitle: "标签类型",
            nodeType: .tagType(tagType)
        )
        nodes.append(centerNode)
        let centerNodeId = nextId
        nextId += 1
        
        // 2. 添加标签值节点和连接线
        for tagValue in data.tagValues.prefix(20) { // 限制显示数量避免过于复杂
            let tagValueNodeId = nextId
            let tagValueNode = TagTypeGraphNode(
                id: tagValueNodeId,
                label: tagValue.value,
                subtitle: "\(tagValue.usageCount)个节点",
                nodeType: .tagValue(tagValue.value, tagValue.usageCount)
            )
            nodes.append(tagValueNode)
            
            // 从中心节点到标签值的连接
            edges.append(TagTypeGraphEdge(fromId: centerNodeId, toId: tagValueNodeId))
            
            nextId += 1
            
            // 3. 为每个标签值添加部分内容节点（最多5个）
            for contentNode in tagValue.nodes.prefix(5) {
                let contentNodeId = nextId
                let contentGraphNode = TagTypeGraphNode(
                    id: contentNodeId,
                    label: String(contentNode.text.prefix(20)) + (contentNode.text.count > 20 ? "..." : ""),
                    subtitle: "内容节点",
                    nodeType: .contentNode(contentNode)
                )
                nodes.append(contentGraphNode)
                
                // 从标签值到内容节点的连接
                edges.append(TagTypeGraphEdge(fromId: tagValueNodeId, toId: contentNodeId))
                
                nextId += 1
            }
        }
        
        return (nodes: nodes, edges: edges)
    }
    
    /// 查找未使用的标签映射
    public func findUnusedTagMappings() -> [TagMapping] {
        let tagManager = TagMappingManager.shared
        let allMappings = tagManager.tagMappings
        let usedTagTypes = Set(allTags.map { $0.type })
        
        return allMappings.filter { mapping in
            // 过滤掉系统标签映射
            if isSystemTagMapping(mapping) {
                return false
            }
            
            return !usedTagTypes.contains(mapping.tagType)
        }
    }
    
    /// 查找在特定层未使用的标签映射
    public func findUnusedTagMappingsForLayer(_ layerId: UUID) -> [TagMapping] {
        let tagManager = TagMappingManager.shared
        let allMappings = tagManager.tagMappings
        
        // 获取指定层的所有标签类型
        let layerNodes = nodes.filter { $0.layerId == layerId }
        let usedTagTypesInLayer = Set(layerNodes.flatMap { $0.tags.map { $0.type } })
        
        return allMappings.filter { mapping in
            // 过滤掉系统标签映射
            if isSystemTagMapping(mapping) {
                return false
            }
            
            return !usedTagTypesInLayer.contains(mapping.tagType)
        }
    }
    
    /// 判断是否为系统标签映射
    private func isSystemTagMapping(_ mapping: TagMapping) -> Bool {
        let tagManager = TagMappingManager.shared
        
        // 检查是否是内置核心标签
        if tagManager.isBuiltInCoreTag(mapping.key) {
            return true
        }
        
        // 检查是否是应该隐藏的系统标签
        let systemTagsToHide = ["compound", "child", "loc"]
        return systemTagsToHide.contains(mapping.key.lowercased())
    }
    
    /// 从特定层批量删除未使用的标签映射对应的标签
    @MainActor
    public func batchDeleteUnusedMappingsFromLayer(_ mappings: [TagMapping], layerId: UUID) -> BatchDeleteResult {
        var affectedNodeCount = 0
        var deletedTagCount = 0
        var affectedNodes: [Node] = []
        
        print("🗑️ 开始从层删除未使用映射对应的标签: \(mappings.count) 个映射")
        
        // 获取该层的所有节点
        _ = nodes.filter { $0.layerId == layerId }
        
        // 创建要删除的标签类型集合
        let tagTypesToDelete = Set(mappings.map { $0.tagType })
        
        // 遍历该层的节点，删除匹配的标签
        for (index, node) in nodes.enumerated() {
            guard node.layerId == layerId else { continue }
            
            let tagsToRemove = node.tags.filter { tag in
                tagTypesToDelete.contains(tag.type)
            }
            
            if !tagsToRemove.isEmpty {
                var updatedNode = node
                updatedNode.tags.removeAll { tag in
                    tagTypesToDelete.contains(tag.type)
                }
                updatedNode.updatedAt = Date()
                
                nodes[index] = updatedNode
                affectedNodes.append(updatedNode)
                affectedNodeCount += 1
                deletedTagCount += tagsToRemove.count
                
                // 触发复合节点刷新
                refreshCompoundNodesReferencingNode(updatedNode.text)
                
                print("🗑️ 从节点 '\(node.text)' 删除 \(tagsToRemove.count) 个标签")
            }
        }
        
        // 更新选中节点引用
        if let selectedNode = selectedNode,
           let updatedSelectedNode = affectedNodes.first(where: { $0.id == selectedNode.id }) {
            self.selectedNode = updatedSelectedNode
        }
        
        // 触发UI更新
        objectWillChange.send()
        
        // 发送批量更新通知
        NotificationCenter.default.post(
            name: Notification.Name("nodesBatchUpdated"),
            object: nil,
            userInfo: [
                "affectedNodeCount": affectedNodeCount,
                "deletedTagCount": deletedTagCount,
                "layerId": layerId
            ]
        )
        
        // 自动保存到外部存储
        if !isLoadingFromExternal {
            Task {
                await forceSaveToExternalStorage()
                print("💾 层级标签删除后已自动保存到外部存储")
            }
        }
        
        let result = BatchDeleteResult(
            affectedNodeCount: affectedNodeCount,
            deletedTagCount: deletedTagCount,
            affectedNodes: affectedNodes
        )
        
        print("✅ 层级标签删除完成: 影响 \(affectedNodeCount) 个节点，删除 \(deletedTagCount) 个标签")
        return result
    }
    
    /// 从特定层删除特定标签
    @MainActor
    public func batchDeleteSpecificTagFromLayer(_ tagsToDelete: [Tag], layerId: UUID) -> BatchDeleteResult {
        var affectedNodeCount = 0
        var deletedTagCount = 0
        var affectedNodes: [Node] = []
        
        print("🗑️ 开始从层删除特定标签: \(tagsToDelete.count) 个标签")
        
        // 创建标签匹配条件（基于类型和值）
        let tagMatchers = tagsToDelete.map { targetTag in
            (type: targetTag.type, value: targetTag.value)
        }
        
        // 遍历该层的节点，删除匹配的标签
        for (index, node) in nodes.enumerated() {
            guard node.layerId == layerId else { continue }
            
            let removedTags = node.tags.filter { tag in
                tagMatchers.contains { matcher in
                    // 🔧 应用相同的TagType修复：使用规范化比较
                    let typeMatch: Bool
                    switch (tag.type, matcher.type) {
                    case (.location, .location):
                        typeMatch = true
                    case (.custom(let tagKey), .custom(let matcherKey)):
                        typeMatch = tagKey.lowercased() == matcherKey.lowercased()
                    default:
                        typeMatch = false
                    }
                    return typeMatch && tag.value == matcher.value
                }
            }
            
            if !removedTags.isEmpty {
                var updatedNode = node
                updatedNode.tags.removeAll { tag in
                    tagMatchers.contains { matcher in
                        // 🔧 应用相同的TagType修复：使用规范化比较
                        let typeMatch: Bool
                        switch (tag.type, matcher.type) {
                        case (.location, .location):
                            typeMatch = true
                        case (.custom(let tagKey), .custom(let matcherKey)):
                            typeMatch = tagKey.lowercased() == matcherKey.lowercased()
                        default:
                            typeMatch = false
                        }
                        return typeMatch && tag.value == matcher.value
                    }
                }
                updatedNode.updatedAt = Date()
                
                nodes[index] = updatedNode
                affectedNodes.append(updatedNode)
                affectedNodeCount += 1
                deletedTagCount += removedTags.count
                
                // 触发复合节点刷新
                refreshCompoundNodesReferencingNode(updatedNode.text)
                
                print("🗑️ 从节点 '\(node.text)' 删除 \(removedTags.count) 个特定标签")
            }
        }
        
        // 更新选中节点引用
        if let selectedNode = selectedNode,
           let updatedSelectedNode = affectedNodes.first(where: { $0.id == selectedNode.id }) {
            self.selectedNode = updatedSelectedNode
        }
        
        // 触发UI更新
        objectWillChange.send()
        
        // 发送批量更新通知
        NotificationCenter.default.post(
            name: Notification.Name("nodesBatchUpdated"),
            object: nil,
            userInfo: [
                "affectedNodeCount": affectedNodeCount,
                "deletedTagCount": deletedTagCount,
                "layerId": layerId
            ]
        )
        
        // 自动保存到外部存储
        if !isLoadingFromExternal {
            Task {
                await forceSaveToExternalStorage()
                print("💾 特定标签层级删除后已自动保存到外部存储")
            }
        }
        
        let result = BatchDeleteResult(
            affectedNodeCount: affectedNodeCount,
            deletedTagCount: deletedTagCount,
            affectedNodes: affectedNodes
        )
        
        print("✅ 特定标签层级删除完成: 影响 \(affectedNodeCount) 个节点，删除 \(deletedTagCount) 个标签")
        return result
    }
    
    // MARK: - 复合节点自动刷新机制
    
    /// 当子节点发生变化时，刷新所有引用该子节点的复合节点
    @MainActor
    private func refreshCompoundNodesReferencingNode(_ childNodeName: String) {
        print("🔄 [复合节点刷新] 开始刷新引用子节点 '\(childNodeName)' 的复合节点")
        
        // 查找所有引用该子节点的复合节点
        let referencingCompoundNodes = nodes.filter { node in
            guard node.isCompound else { return false }
            
            // 检查是否有子节点标签引用了该节点
            return node.tags.contains { tag in
                if case .custom(let key) = tag.type, key == "child" {
                    return tag.value.lowercased() == childNodeName.lowercased()
                }
                return false
            }
        }
        
        if referencingCompoundNodes.isEmpty {
            print("🔄 [复合节点刷新] 没有找到引用子节点 '\(childNodeName)' 的复合节点")
            return
        }
        
        print("🔄 [复合节点刷新] 找到 \(referencingCompoundNodes.count) 个引用复合节点：")
        for compoundNode in referencingCompoundNodes {
            print("   - \(compoundNode.text)")
        }
        
        // 更新每个复合节点的 updatedAt 时间戳以触发UI刷新
        for compoundNode in referencingCompoundNodes {
            if let index = nodes.firstIndex(where: { $0.id == compoundNode.id }) {
                var updatedCompoundNode = nodes[index]
                updatedCompoundNode.updatedAt = Date()
                nodes[index] = updatedCompoundNode
                
                print("🔄 [复合节点刷新] 已刷新复合节点: \(updatedCompoundNode.text)")
                
                // 发送复合节点更新通知
                NotificationCenter.default.post(
                    name: Notification.Name("compoundNodeRefreshed"),
                    object: nil,
                    userInfo: [
                        "compoundNodeId": updatedCompoundNode.id,
                        "compoundNodeName": updatedCompoundNode.text,
                        "childNodeName": childNodeName
                    ]
                )
            }
        }
        
        print("✅ [复合节点刷新] 完成刷新 \(referencingCompoundNodes.count) 个复合节点")
    }
    
    // MARK: - 手动保存功能
    
    @MainActor
    public func forceSaveToExternalStorage() async {
        guard externalDataManager.isDataPathSelected else { return }
        
        do {
            try await externalDataService.saveAllData(store: self)
            print("✅ 手动保存成功")
            
            // 保存成功后自动刷新数据，避免手动点击刷新按钮
            print("🔄 保存成功，自动触发界面刷新...")
            NotificationCenter.default.post(
                name: .dataPathChanged,
                object: externalDataManager,
                userInfo: ["newPath": externalDataManager.currentDataPath ?? URL(fileURLWithPath: "")]
            )
        } catch {
            print("❌ 手动保存失败: \(error)")
        }
    }
    
    // MARK: - 标签类型名称变化监听
    
    private func setupTagTypeNameChangeListener() {
        // 监听清除标签筛选通知
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("clearTagFilter"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clearTagFilter()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("tagTypeNameChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let oldName = userInfo["oldName"] as? String,
                  let newName = userInfo["newName"] as? String,
                  let key = userInfo["key"] as? String else { return }
            
            print("🔄 Store收到标签类型名称变化通知: \(oldName) -> \(newName), key: \(key)")
            Task {
                await self.updateTagTypeNames(from: oldName, to: newName, key: key)
            }
        }
        
        // 监听Command+点击选择节点的通知
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("selectNodeFromCommandClick"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            print("📥 Store收到selectNodeFromCommandClick通知")
            print("   - Store实例存在: \(self != nil)")
            
            Task { @MainActor [weak self] in
                guard let self = self else { 
                    print("❌ Store实例为nil")
                    return 
                }
                
                guard let contentNode = notification.object as? Node else {
                    print("❌ 通知对象不是Node类型: \(notification.object ?? "nil")")
                    return
                }
                
                print("⌘ Store开始处理Command+点击选择节点: \(contentNode.text)")
                print("   - 节点ID: \(contentNode.id)")
                print("   - 节点层ID: \(contentNode.layerId)")
                print("   - 当前层数量: \(self.layers.count)")
                print("   - 当前节点数量: \(self.nodes.count)")
                
                // 检查节点所属的层
                let nodeLayerId = contentNode.layerId
                let currentLayerId = self.currentLayer?.id
                
                print("🔍 节点层检查:")
                print("   - 节点层ID: \(nodeLayerId.uuidString.prefix(8))")
                print("   - 当前层ID: \(currentLayerId?.uuidString.prefix(8) ?? "nil")")
                print("   - 层匹配: \(nodeLayerId == currentLayerId)")
                
                // 验证节点是否在Store中存在
                let nodeExistsInStore = self.nodes.contains { $0.id == contentNode.id }
                print("   - 节点在Store中存在: \(nodeExistsInStore)")
                
                if !nodeExistsInStore {
                    print("⚠️ 节点不在当前Store中，可能需要从其他窗口实例获取")
                }
                
                // 如果节点不在当前层，先切换到节点所属的层
                if nodeLayerId != currentLayerId {
                    print("🔄 需要切换层...")
                    if let nodeLayer = self.layers.first(where: { $0.id == nodeLayerId }) {
                        print("🔄 切换到节点所属层: \(nodeLayer.displayName)")
                        self.setCurrentLayer(nodeLayer)
                        
                        // 给UI一点时间更新
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            print("✅ 层切换完成，现在选择节点...")
                            // 然后选择节点
                            self.selectNode(contentNode)
                            
                            // 清除所有标签筛选状态，让用户专注于选中的节点
                            self.clearTagFilter()
                            
                            print("✅ 已通过Command+点击切换层并选择节点: \(contentNode.text)")
                        }
                    } else {
                        print("❌ 找不到节点所属的层: \(nodeLayerId)")
                        print("   - 可用层列表: \(self.layers.map { "\($0.displayName)(\($0.id.uuidString.prefix(8)))" })")
                        // 如果找不到层，仍然尝试选择节点
                        self.selectNode(contentNode)
                        self.clearTagFilter()
                    }
                } else {
                    print("✅ 节点在当前层，直接选择...")
                    // 节点在当前层，直接选择
                    self.selectNode(contentNode)
                    
                    // 清除所有标签筛选状态，让用户专注于选中的节点
                    self.clearTagFilter()
                    
                    print("✅ 已通过Command+点击选择节点: \(contentNode.text)")
                }
            }
        }
    }
    
    private func updateTagTypeNames(from oldName: String, to newName: String, key: String) {
        print("🔄 开始更新标签类型名称: \(oldName) -> \(newName), key: \(key)")
        print("📊 当前Store状态:")
        print("   - 节点总数: \(nodes.count)")
        print("   🔍 使用提供的key: '\(key)'")
        
        // 检查是否有使用该key的标签
        var hasMatchingTags = false
        for node in nodes {
            for tag in node.tags {
                if case .custom(let customKey) = tag.type, customKey == key {
                    hasMatchingTags = true
                    print("   ✅ 找到匹配的标签！节点 '\(node.text)' 使用了key='\(key)'的标签")
                    break
                }
            }
            if hasMatchingTags { break }
        }
        
        if hasMatchingTags {
            print("🔄 强制触发UI刷新以更新标签显示名称")
            
            // 创建新的nodes数组来强制触发SwiftUI更新
            // 这样SwiftUI会重新计算所有标签的displayName
            let updatedNodes = nodes.map { node -> Node in
                var updatedNode = node
                for tag in node.tags {
                    if case .custom(let customKey) = tag.type, customKey == key {
                        // 标记节点已更新，但不改变标签本身
                        // displayName会通过TagType.displayName自动更新
                        updatedNode.updatedAt = Date()
                        break
                    }
                }
                return updatedNode
            }
            
            // 强制更新nodes数组以触发UI刷新
            nodes = updatedNodes
            print("✅ UI刷新已触发，标签显示名称将更新为: \(newName)")
            
            // 强制发送更新通知，确保所有UI组件都能收到变化
            objectWillChange.send()
            
            // 触发自动同步
            if !isLoadingFromExternal {
                Task {
                    await forceSaveToExternalStorage()
                }
            }
        } else {
            print("⚠️ 没有找到使用key '\(key)' 的标签，可能：")
            print("   1. 该标签映射没有被任何节点使用")
            print("   2. 标签key不匹配")
            print("   3. 标签类型不是 .custom 类型")
            
            // 即使没有匹配的标签，也强制触发一次UI刷新
            // 因为可能有其他UI组件（如标签管理界面）需要更新
            print("🔄 仍然触发UI刷新以确保所有相关界面更新")
            objectWillChange.send()
        }
    }
}

// MARK: - 扩展

extension Array where Element: Equatable {
    func unique() -> [Element] {
        var uniqueValues: [Element] = []
        forEach { item in
            if !uniqueValues.contains(item) {
                uniqueValues.append(item)
            }
        }
        return uniqueValues
    }
}

// MARK: - 标签筛选状态记忆结构

/// 保存的标签筛选状态
struct SavedTagFilterState {
    let selectedTag: Tag?
    let expandedTagTypes: Set<Tag.TagType>
    let showAllTagTypeNodes: Bool
    let timestamp: Date
    let description: String // 用于调试的状态描述
    
    init(selectedTag: Tag?, expandedTagTypes: Set<Tag.TagType>, showAllTagTypeNodes: Bool) {
        self.selectedTag = selectedTag
        self.expandedTagTypes = expandedTagTypes
        self.showAllTagTypeNodes = showAllTagTypeNodes
        self.timestamp = Date()
        
        // 生成状态描述
        if let tag = selectedTag {
            if showAllTagTypeNodes {
                self.description = "标签类型: \(tag.type.displayName)"
            } else {
                self.description = "具体标签: \(tag.type.displayName) - \(tag.value)"
            }
        } else if !expandedTagTypes.isEmpty {
            self.description = "展开的标签类型: \(expandedTagTypes.map { $0.displayName }.joined(separator: ", "))"
        } else {
            self.description = "无筛选状态"
        }
    }
}
