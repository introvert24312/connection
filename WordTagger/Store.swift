import Combine
import Foundation
import AppKit
import SwiftUI

@MainActor
public final class NodeStore: ObservableObject {
    @Published public private(set) var nodes: [Node] = []
    @Published public private(set) var layers: [Layer] = []
    @Published public private(set) var currentLayer: Layer?
    @Published public private(set) var selectedNode: Node?
    @Published public private(set) var selectedTag: Tag?
    @Published public var searchQuery: String = ""
    @Published public private(set) var searchResults: [Node] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isExporting: Bool = false
    @Published public private(set) var isImporting: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private let externalDataService = ExternalDataService.shared
    private let externalDataManager = ExternalDataManager.shared
    private var isLoadingFromExternal = false
    
    public static let shared = NodeStore()
    
    private init() {
        setupInitialData()
        setupSearchBinding()
        setupExternalDataSync()
        setupDataPathChangeListener()
        setupTagTypeNameChangeListener()
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
                
                // 重新加载标签映射
                await TagMappingManager.shared.reloadFromExternalStorage()
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
    
    // 重复节点检测结果
    public struct DuplicateNodeAlert {
        let message: String
        let isDuplicate: Bool
        let existingNode: Node?
        let newNode: Node
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
        
        // 检查是否存在相同的节点
        print("🔍 检查重复 - 新节点: '\(node.text)', 现有节点数量: \(nodes.count)")
        for (index, existingNode) in nodes.enumerated() {
            print("🔍 现有节点[\(index)]: '\(existingNode.text)' (小写: '\(existingNode.text.lowercased())')")
        }
        
        if let existingNode = nodes.first(where: { $0.text.lowercased() == node.text.lowercased() }) {
            print("⚠️ 发现重复节点: \(node.text)")
            print("⚠️ 现有节点: '\(existingNode.text)' 标签数: \(existingNode.tags.count)")
            print("⚠️ 新节点: '\(node.text)' 标签数: \(node.tags.count)")
            
            // 检查是否有相同的标签
            print("🏷️ 检查标签重复:")
            print("🏷️ 现有节点标签:")
            for (i, tag) in existingNode.tags.enumerated() {
                print("   [\(i)] \(tag.type.displayName): '\(tag.value)'")
            }
            print("🏷️ 新节点标签:")
            for (i, tag) in node.tags.enumerated() {
                print("   [\(i)] \(tag.type.displayName): '\(tag.value)'")
            }
            
            let duplicateTags = node.tags.filter { newTag in
                let isDuplicate = existingNode.tags.contains { existingTag in
                    let typeMatch = existingTag.type == newTag.type
                    let valueMatch = existingTag.value.lowercased() == newTag.value.lowercased()
                    print("🏷️ 比较: \(existingTag.type.displayName):'\(existingTag.value)' vs \(newTag.type.displayName):'\(newTag.value)' -> type:\(typeMatch), value:\(valueMatch)")
                    return typeMatch && valueMatch
                }
                return isDuplicate
            }
            
            print("🏷️ 重复标签数量: \(duplicateTags.count)")
            
            if !duplicateTags.isEmpty {
                // 有相同标签，提示用户
                let tagNames = duplicateTags.map { "\($0.type.displayName)-\($0.value)" }.joined(separator: ", ")
                duplicateNodeAlert = DuplicateNodeAlert(
                    message: "节点 \"\(node.text)\" 已存在相同的标签: \(tagNames)",
                    isDuplicate: true,
                    existingNode: existingNode,
                    newNode: node
                )
                print("❌ 相同节点相同标签，不添加")
                return false
            } else {
                // 有不同标签，自动合并
                let newTags = node.tags.filter { newTag in
                    !existingNode.tags.contains { existingTag in
                        existingTag.type == newTag.type && existingTag.value.lowercased() == newTag.value.lowercased()
                    }
                }
                
                if !newTags.isEmpty {
                    // 添加新标签到现有节点
                    for tag in newTags {
                        addTag(to: existingNode.id, tag: tag)
                    }
                    
                    let tagNames = newTags.map { "\($0.type.displayName)-\($0.value)" }.joined(separator: ", ")
                    duplicateNodeAlert = DuplicateNodeAlert(
                        message: "已将新标签 \(tagNames) 合并到现有节点 \"\(node.text)\"",
                        isDuplicate: false,
                        existingNode: existingNode,
                        newNode: node
                    )
                    print("✅ 节点合并成功，添加了 \(newTags.count) 个新标签")
                    print("🚨 设置警告弹窗: \(duplicateNodeAlert?.message ?? "nil")")
                    return true
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
            return true
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
        }
    }
    
    @MainActor
    public func updateNode(_ nodeId: UUID, text: String?, phonetic: String?, meaning: String?) {
        if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
            var updatedNode = nodes[index]
            if let text = text { updatedNode.text = text }
            if let phonetic = phonetic { updatedNode.phonetic = phonetic }
            if let meaning = meaning { updatedNode.meaning = meaning }
            updatedNode.updatedAt = Date()
            nodes[index] = updatedNode
        }
    }
    
    @MainActor
    public func deleteNode(_ node: Node) {
        nodes.removeAll { $0.id == node.id }
        if selectedNode?.id == node.id {
            selectedNode = nil
        }
    }
    
    @MainActor
    public func deleteNode(_ nodeId: UUID) {
        nodes.removeAll { $0.id == nodeId }
        if selectedNode?.id == nodeId {
            selectedNode = nil
        }
    }
    
    @MainActor
    public func setSelectedNode(_ node: Node?) {
        selectedNode = node
    }
    
    @MainActor
    public func setSelectedTag(_ tag: Tag?) {
        selectedTag = tag
    }
    
    // MARK: - 兼容性方法
    
    public func selectNode(_ node: Node?) {
        setSelectedNode(node)
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
    public func deleteLayer(_ layer: Layer) {
        print("🗑️ 删除层: \(layer.displayName) (ID: \(layer.id))")
        
        // 删除该层中的所有节点
        let nodesToDelete = nodes.filter { $0.layerId == layer.id }
        print("🗑️ 将删除 \(nodesToDelete.count) 个节点")
        nodes.removeAll { $0.layerId == layer.id }
        
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
        let rootTag1 = createTag(type: .root, value: "vis")
        let rootTag2 = createTag(type: .root, value: "log")
        let rootTag3 = createTag(type: .root, value: "cogn")
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
    
    public func createTag(type: Tag.TagType, value: String, latitude: Double? = nil, longitude: Double? = nil) -> Tag {
        return Tag(
            type: type,
            value: value,
            latitude: latitude,
            longitude: longitude
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
        print("🏷️ 标签映射已完全清空")
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
    
    public func getRelevantTags(for query: String) -> [Tag] {
        return searchTags(query: query)
    }
    
    public func selectTag(_ tag: Tag?) {
        setSelectedTag(tag)
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
        }
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
    }
    
    private func updateTagTypeNames(from oldName: String, to newName: String, key: String) {
        print("🔄 开始更新标签类型名称: \(oldName) -> \(newName), key: \(key)")
        print("📊 当前Store状态:")
        print("   - 节点总数: \(nodes.count)")
        print("   🔍 使用提供的key: '\(key)'")
        
        // 打印所有节点和标签的详细信息
        for (nodeIndex, node) in nodes.enumerated() {
            print("   - 节点[\(nodeIndex)]: '\(node.text)' 有 \(node.tags.count) 个标签")
            for (tagIndex, tag) in node.tags.enumerated() {
                print("     - 标签[\(tagIndex)]: type=\(tag.type), value='\(tag.value)'")
                if case .custom(let customKey) = tag.type {
                    print("       - 自定义标签key: '\(customKey)'")
                    print("       - 是否匹配目标key '\(key)': \(customKey == key)")
                }
            }
        }
        
        var updatedNodes: [Node] = []
        var hasChanges = false
        
        for node in nodes {
            var updatedNode = node
            var nodeHasChanges = false
            
            for (_, tag) in node.tags.enumerated() {
                // 通过key匹配，而不是typeName
                if case .custom(let customKey) = tag.type, customKey == key {
                    print("   ✅ 找到匹配的标签！更新节点 '\(node.text)' 的标签: key='\(key)', \(oldName) -> \(newName)")
                    // 保持key不变，只是TagType的displayName会通过TagMappingManager更新
                    // 这里实际上不需要更新Tag.type，因为displayName是通过TagMappingManager计算的
                    nodeHasChanges = true
                    hasChanges = true
                }
            }
            
            if nodeHasChanges {
                updatedNode.updatedAt = Date()
                updatedNodes.append(updatedNode)
                print("   📝 节点 '\(node.text)' 已更新")
            } else {
                updatedNodes.append(node)
            }
        }
        
        if hasChanges {
            print("✅ 标签类型名称更新完成，更新了 \(updatedNodes.filter { $0.updatedAt > Date().addingTimeInterval(-1) }.count) 个节点")
            nodes = updatedNodes
            print("🔄 触发UI更新和自动同步")
            
            // 触发自动同步
            if !isLoadingFromExternal {
                Task {
                    await forceSaveToExternalStorage()
                }
            }
        } else {
            print("❌ 没有找到需要更新的标签")
            print("🔍 可能的原因:")
            print("   1. 没有使用key '\(key)' 的自定义标签类型的节点")
            print("   2. 标签类型不是 .custom 类型")
            print("   3. 自定义标签key不匹配")
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