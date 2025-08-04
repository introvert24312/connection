import Combine
import Foundation
import AppKit
import SwiftUI

@MainActor
public final class WordStore: ObservableObject {
    @Published public private(set) var words: [Word] = []
    @Published public private(set) var nodes: [Node] = []
    @Published public private(set) var layers: [Layer] = []
    @Published public private(set) var currentLayer: Layer?
    @Published public private(set) var selectedWord: Word?
    @Published public private(set) var selectedNode: Node?
    @Published public private(set) var selectedTag: Tag?
    @Published public var searchQuery: String = ""
    @Published public private(set) var searchResults: [Word] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isExporting: Bool = false
    @Published public private(set) var isImporting: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private let externalDataService = ExternalDataService.shared
    private let externalDataManager = ExternalDataManager.shared
    private var isLoadingFromExternal = false
    
    public static let shared = WordStore()
    
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
        loadSampleData()
        
        // 尝试加载外部数据
        Task {
            do {
                isLoadingFromExternal = true
                let (loadedLayers, loadedNodes, loadedWords) = try await externalDataService.loadAllData()
                
                await MainActor.run {
                    if !loadedLayers.isEmpty {
                        self.layers = loadedLayers
                        self.nodes = loadedNodes
                        self.words = loadedWords
                        
                        // 设置活跃层
                        if let activeLayer = loadedLayers.first(where: { $0.isActive }) {
                            self.currentLayer = activeLayer
                        } else if let firstLayer = loadedLayers.first {
                            self.currentLayer = firstLayer
                        }
                        
                        print("📚 从外部存储加载了 \(loadedNodes.count) 个节点和 \(loadedWords.count) 个单词，分布在 \(loadedLayers.count) 个层中")
                    }
                    self.isLoadingFromExternal = false
                }
            } catch {
                print("⚠️ 加载外部数据失败: \(error)")
                await MainActor.run {
                    self.isLoadingFromExternal = false
                }
                // 使用默认示例数据
                await MainActor.run {
                    if self.nodes.isEmpty {
                        self.loadSampleData()
                        print("📚 Created sample data with \(self.nodes.count) nodes across \(self.layers.count) layers")
                    }
                }
            }
        }
    }
    
    private func setupDefaultLayers() {
        var englishLayer = Layer(name: "english", displayName: "英语单词", color: "blue")
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
        Publishers.CombineLatest3($words, $nodes, $layers)
            .debounce(for: .milliseconds(800), scheduler: RunLoop.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (words, nodes, layers) in
                guard let self = self else { return }
                
                // 如果正在从外部存储加载数据，跳过自动同步
                if self.isLoadingFromExternal {
                    return
                }
                
                print("🔄 数据变化触发自动同步:")
                print("   - Words: \(words.count) 个")
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
            let (loadedLayers, loadedNodes, loadedWords) = try await externalDataService.loadAllData()
            
            if !loadedLayers.isEmpty {
                // 如果新路径有数据，替换当前数据
                layers = loadedLayers
                nodes = loadedNodes
                words = loadedWords
                
                // 设置活跃层
                if let activeLayer = loadedLayers.first(where: { $0.isActive }) {
                    currentLayer = activeLayer
                } else if let firstLayer = loadedLayers.first {
                    currentLayer = firstLayer
                }
                
                print("📚 从新路径加载了 \(loadedNodes.count) 个节点和 \(loadedWords.count) 个单词，分布在 \(loadedLayers.count) 个层中")
                
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
        
        // 搜索当前层的words和nodes
        guard let currentLayer = currentLayer else {
            print("⚠️ Store: 没有当前层，搜索结果为空")
            searchResults = []
            return
        }
        
        let wordResults = words.filter { word in
            // 只搜索当前层的单词
            word.layerId == currentLayer.id && (
                word.text.localizedCaseInsensitiveContains(trimmedQuery) ||
                (word.meaning?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
                (word.phonetic?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
                word.tags.contains { $0.value.localizedCaseInsensitiveContains(trimmedQuery) }
            )
        }
        
        let nodeResults = nodes.compactMap { node -> Word? in
            // 只搜索当前层的节点
            if node.layerId == currentLayer.id && (
               node.text.localizedCaseInsensitiveContains(trimmedQuery) ||
               (node.meaning?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
               (node.phonetic?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
               node.tags.contains { $0.value.localizedCaseInsensitiveContains(trimmedQuery) }) {
                return Word(text: node.text, phonetic: node.phonetic, meaning: node.meaning, layerId: node.layerId, tags: node.tags)
            }
            return nil
        }
        
        // 合并结果并去重
        var allResults = wordResults + nodeResults
        allResults = allResults.unique()
        
        searchResults = Array(allResults.prefix(50)) // 限制结果数量
        print("🔍 Store: Search completed in layer '\(currentLayer.displayName)', found \(searchResults.count) results")
    }
    
    // MARK: - 数据管理
    
    @Published public var duplicateWordAlert: DuplicateWordAlert?
    
    // 重复单词检测结果
    public struct DuplicateWordAlert {
        let message: String
        let isDuplicate: Bool
        let existingWord: Word?
        let newWord: Word
    }
    
    @MainActor
    public func addWord(_ word: Word) -> Bool {
        print("📝 Store: 添加单词 - \(word.text)")
        print("   - 音标: \(word.phonetic ?? "nil")")
        print("   - 含义: \(word.meaning ?? "nil")")
        print("   - 标签: \(word.tags.count) 个")
        
        // 检查是否存在相同的单词
        print("🔍 检查重复 - 新单词: '\(word.text)', 现有单词数量: \(words.count)")
        for (index, existingWord) in words.enumerated() {
            print("🔍 现有单词[\(index)]: '\(existingWord.text)' (小写: '\(existingWord.text.lowercased())')")
        }
        
        if let existingWord = words.first(where: { $0.text.lowercased() == word.text.lowercased() }) {
            print("⚠️ 发现重复单词: \(word.text)")
            print("⚠️ 现有单词: '\(existingWord.text)' 标签数: \(existingWord.tags.count)")
            print("⚠️ 新单词: '\(word.text)' 标签数: \(word.tags.count)")
            
            // 检查是否有相同的标签
            print("🏷️ 检查标签重复:")
            print("🏷️ 现有单词标签:")
            for (i, tag) in existingWord.tags.enumerated() {
                print("   [\(i)] \(tag.type.displayName): '\(tag.value)'")
            }
            print("🏷️ 新单词标签:")
            for (i, tag) in word.tags.enumerated() {
                print("   [\(i)] \(tag.type.displayName): '\(tag.value)'")
            }
            
            let duplicateTags = word.tags.filter { newTag in
                let isDuplicate = existingWord.tags.contains { existingTag in
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
                duplicateWordAlert = DuplicateWordAlert(
                    message: "单词 \"\(word.text)\" 已存在相同的标签: \(tagNames)",
                    isDuplicate: true,
                    existingWord: existingWord,
                    newWord: word
                )
                print("❌ 相同单词相同标签，不添加")
                return false
            } else {
                // 有不同标签，自动合并
                let newTags = word.tags.filter { newTag in
                    !existingWord.tags.contains { existingTag in
                        existingTag.type == newTag.type && existingTag.value.lowercased() == newTag.value.lowercased()
                    }
                }
                
                if !newTags.isEmpty {
                    // 添加新标签到现有单词
                    for tag in newTags {
                        addTag(to: existingWord.id, tag: tag)
                    }
                    
                    let tagNames = newTags.map { "\($0.type.displayName)-\($0.value)" }.joined(separator: ", ")
                    duplicateWordAlert = DuplicateWordAlert(
                        message: "已将新标签 \(tagNames) 合并到现有单词 \"\(word.text)\"",
                        isDuplicate: false,
                        existingWord: existingWord,
                        newWord: word
                    )
                    print("✅ 单词合并成功，添加了 \(newTags.count) 个新标签")
                    print("🚨 设置警告弹窗: \(duplicateWordAlert?.message ?? "nil")")
                    return true
                } else {
                    duplicateWordAlert = DuplicateWordAlert(
                        message: "单词 \"\(word.text)\" 已存在，且所有标签都相同",
                        isDuplicate: true,
                        existingWord: existingWord,
                        newWord: word
                    )
                    print("❌ 完全重复，不添加")
                    return false
                }
            }
        } else {
            // 新单词，直接添加
            print("✅ 未发现重复，直接添加新单词")
            
            // 确保单词与当前层关联
            var wordWithLayer = word
            if wordWithLayer.layerId == nil, let currentLayerId = currentLayer?.id {
                wordWithLayer.layerId = currentLayerId
                print("🔗 设置单词层ID: \(currentLayerId)")
            }
            
            words.append(wordWithLayer)
            print("✅ 单词添加成功，当前总数: \(words.count)")
            return true
        }
    }
    
    @MainActor
    public func addWord(_ text: String, phonetic: String?, meaning: String?) -> Bool {
        print("📝 Store: 添加单词(简化) - \(text)")
        let word = Word(text: text, phonetic: phonetic, meaning: meaning, tags: [])
        return addWord(word)
    }
    
    @MainActor
    public func addNode(_ node: Node) {
        print("🔗 Store: 添加节点 - \(node.text)")
        print("   - 层ID: \(node.layerId)")
        print("   - 音标: \(node.phonetic ?? "nil")")
        print("   - 含义: \(node.meaning ?? "nil")")
        print("   - 标签: \(node.tags.count) 个")
        nodes.append(node)
        print("✅ 节点添加成功，当前总数: \(nodes.count)")
    }
    
    @MainActor
    public func updateWord(_ word: Word) {
        if let index = words.firstIndex(where: { $0.id == word.id }) {
            words[index] = word
        }
    }
    
    @MainActor
    public func updateWord(_ wordId: UUID, text: String?, phonetic: String?, meaning: String?) {
        if let index = words.firstIndex(where: { $0.id == wordId }) {
            var updatedWord = words[index]
            if let text = text { updatedWord.text = text }
            if let phonetic = phonetic { updatedWord.phonetic = phonetic }
            if let meaning = meaning { updatedWord.meaning = meaning }
            updatedWord.updatedAt = Date()
            words[index] = updatedWord
        }
    }
    
    @MainActor
    public func updateNode(_ node: Node) {
        if let index = nodes.firstIndex(where: { $0.id == node.id }) {
            nodes[index] = node
        }
    }
    
    @MainActor
    public func deleteWord(_ word: Word) {
        words.removeAll { $0.id == word.id }
        if selectedWord?.id == word.id {
            selectedWord = nil
        }
    }
    
    @MainActor
    public func deleteWord(_ wordId: UUID) {
        words.removeAll { $0.id == wordId }
        if selectedWord?.id == wordId {
            selectedWord = nil
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
    public func setSelectedWord(_ word: Word?) {
        selectedWord = word
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
    
    public func selectWord(_ word: Word?) {
        setSelectedWord(word)
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
        // 更新所有层的活跃状态
        for i in layers.indices {
            layers[i].isActive = (layers[i].id == layer.id)
        }
        currentLayer = layer
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
        
        // 删除该层中的所有单词
        let wordsToDelete = words.filter { $0.layerId == layer.id }
        print("🗑️ 将删除 \(wordsToDelete.count) 个单词")
        words.removeAll { $0.layerId == layer.id }
        
        // 检查孤儿单词（layerId为nil的单词）
        let orphanWords = words.filter { $0.layerId == nil }
        if !orphanWords.isEmpty {
            print("⚠️ 发现 \(orphanWords.count) 个孤儿单词（无层关联）")
            for orphan in orphanWords {
                print("   - \(orphan.text)")
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
        
        print("✅ 层删除完成，剩余 \(layers.count) 个层，\(nodes.count) 个节点，\(words.count) 个单词")
    }
    
    // MARK: - 数据清理功能
    
    @MainActor
    public func fixOrphanWords() {
        let orphanWords = words.filter { $0.layerId == nil }
        guard !orphanWords.isEmpty else {
            print("✅ 没有发现孤儿单词")
            return
        }
        
        print("🔧 开始修复 \(orphanWords.count) 个孤儿单词...")
        
        // 如果有当前层，使用当前层；否则使用第一个可用层
        guard let targetLayer = currentLayer ?? layers.first else {
            print("❌ 无法修复孤儿单词：没有可用的层")
            return
        }
        
        var fixedCount = 0
        for i in 0..<words.count {
            if words[i].layerId == nil {
                words[i].layerId = targetLayer.id
                print("🔗 修复单词: '\(words[i].text)' -> 层: \(targetLayer.displayName)")
                fixedCount += 1
            }
        }
        
        print("✅ 已修复 \(fixedCount) 个孤儿单词，关联到层: \(targetLayer.displayName)")
        objectWillChange.send()
    }
    
    // MARK: - 标签功能
    
    public var allTags: [Tag] {
        let wordTags = words.flatMap { $0.tags }
        let nodeTags = nodes.flatMap { $0.tags }
        return (wordTags + nodeTags).unique()
    }
    
    public func searchTags(query: String) -> [Tag] {
        let allTags = self.allTags
        
        guard !query.isEmpty else { return [] }
        
        let lowercaseQuery = query.lowercased()
        
        // 直接匹配文本的单词
        let directMatches = words.compactMap { word -> (Word, Double, [Tag])? in
            let textMatch = word.text.lowercased().contains(lowercaseQuery) ? 1.0 : 0.0
            let meaningMatch = (word.meaning?.lowercased().contains(lowercaseQuery) ?? false) ? 0.8 : 0.0
            let phoneticMatch = (word.phonetic?.lowercased().contains(lowercaseQuery) ?? false) ? 0.6 : 0.0
            
            let maxMatch = max(textMatch, meaningMatch, phoneticMatch)
            if maxMatch > 0 {
                return (word, maxMatch, word.tags)
            }
            return nil
        }
        
        // 语义匹配的单词
        let semanticMatches = words.compactMap { word -> (Word, Double, [Tag])? in
            // 简单的语义匹配逻辑
            let semanticScore = calculateSemanticScore(query: lowercaseQuery, word: word)
            if semanticScore > 0.3 {
                return (word, semanticScore, word.tags)
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
    
    private func calculateSemanticScore(query: String, word: Word) -> Double {
        // 简化的语义匹配
        let components = query.components(separatedBy: .whitespaces)
        let textComponents = word.text.lowercased().components(separatedBy: .whitespaces)
        let meaningComponents = (word.meaning?.lowercased() ?? "").components(separatedBy: .whitespaces)
        
        let matches = components.compactMap { queryComponent in
            textComponents.first { $0.contains(queryComponent) } ??
            meaningComponents.first { $0.contains(queryComponent) }
        }
        
        return Double(matches.count) / Double(components.count)
    }
    
    public func words(withTag tag: Tag) -> [Word] {
        // 从 words 中获取
        let wordsWithTag = words.filter { $0.hasTag(tag) }
        
        // 从 nodes 中获取并转换为 Word
        let nodesWithTag = nodes.filter { $0.hasTag(tag) }
        let convertedWords = nodesWithTag.map { node in
            Word(text: node.text, phonetic: node.phonetic, meaning: node.meaning, tags: node.tags)
        }
        
        return wordsWithTag + convertedWords
    }
    
    public func wordsCount(forTagType type: Tag.TagType) -> Int {
        let wordCount = words.filter { word in
            word.tags.contains { $0.type == type }
        }.count
        
        let nodeCount = nodes.filter { node in
            node.tags.contains { $0.type == type }
        }.count
        
        return wordCount + nodeCount
    }
    
    // MARK: - 示例数据
    
    private func loadSampleData() {
        // 如果已有数据，先迁移现有单词数据到新的Layer-Node结构
        if !words.isEmpty {
            migrateWordsToNodes()
            return // 如果有现有数据，就不创建示例数据了
        }
        
        // 只有在没有数据时才创建示例数据
        createSampleData()
    }
    
    private func createSampleData() {
        // 创建一些示例标签
        let memoryTag1 = createTag(type: .memory, value: "联想记忆")
        let memoryTag2 = createTag(type: .memory, value: "图像记忆")
        let memoryTag3 = createTag(type: .memory, value: "概念记忆")
        let rootTag1 = createTag(type: .root, value: "spect")
        let rootTag2 = createTag(type: .root, value: "dict")
        let rootTag3 = createTag(type: .root, value: "psych")
        let locationTag1 = createTag(type: .location, value: "图书馆", latitude: 39.9042, longitude: 116.4074)
        let locationTag2 = createTag(type: .location, value: "咖啡厅", latitude: 40.7589, longitude: -73.9851)
        let locationTag3 = createTag(type: .location, value: "实验室", latitude: 39.9055, longitude: 116.4078)
        
        // 获取各个层级
        guard let englishLayer = layers.first(where: { $0.name == "english" }),
              let statsLayer = layers.first(where: { $0.name == "statistics" }),
              let psychologyLayer = layers.first(where: { $0.name == "psychology" }) else { return }
        
        // === 英语单词层 ===
        let englishNodes = [
            Node(text: "spectacular", phonetic: "/spekˈtækjələr/", meaning: "壮观的，惊人的", layerId: englishLayer.id, tags: [rootTag1, memoryTag1, locationTag1]),
            Node(text: "dictionary", phonetic: "/ˈdɪkʃəneri/", meaning: "字典", layerId: englishLayer.id, tags: [rootTag2, memoryTag2, locationTag2]),
            Node(text: "perspective", phonetic: "/pərˈspektɪv/", meaning: "观点，视角", layerId: englishLayer.id, tags: [rootTag1, memoryTag1]),
            Node(text: "predict", phonetic: "/prɪˈdɪkt/", meaning: "预测", layerId: englishLayer.id, tags: [rootTag2, memoryTag2]),
            Node(text: "analyze", phonetic: "/ˈænəˌlaɪz/", meaning: "分析", layerId: englishLayer.id, tags: [memoryTag3])
        ]
        
        // === 统计学层 ===
        let statisticsNodes = [
            Node(text: "regression", phonetic: "/rɪˈɡrɛʃən/", meaning: "回归分析", layerId: statsLayer.id, tags: [memoryTag1, locationTag3]),
            Node(text: "correlation", phonetic: "/ˌkɔːrəˈleɪʃən/", meaning: "相关性", layerId: statsLayer.id, tags: [memoryTag2]),
            Node(text: "hypothesis", phonetic: "/haɪˈpɑːθəsɪs/", meaning: "假设", layerId: statsLayer.id, tags: [memoryTag3]),
            Node(text: "variance", phonetic: "/ˈvɛriəns/", meaning: "方差", layerId: statsLayer.id, tags: [memoryTag1]),
            Node(text: "distribution", phonetic: "/ˌdɪstrəˈbjuːʃən/", meaning: "分布", layerId: statsLayer.id, tags: [memoryTag2, locationTag3])
        ]
        
        // === 教育心理学层 ===  
        let psychologyNodes = [
            Node(text: "cognitive", phonetic: "/ˈkɑːɡnətɪv/", meaning: "认知的", layerId: psychologyLayer.id, tags: [rootTag3, memoryTag3]),
            Node(text: "motivation", phonetic: "/ˌmoʊtəˈveɪʃən/", meaning: "动机", layerId: psychologyLayer.id, tags: [memoryTag1]),
            Node(text: "reinforcement", phonetic: "/ˌriːɪnˈfɔːrsmənt/", meaning: "强化", layerId: psychologyLayer.id, tags: [memoryTag2]),
            Node(text: "metacognition", phonetic: "/ˌmetəkɑːɡˈnɪʃən/", meaning: "元认知", layerId: psychologyLayer.id, tags: [rootTag3, memoryTag3, locationTag3]),
            Node(text: "scaffolding", phonetic: "/ˈskæfəldɪŋ/", meaning: "脚手架式教学", layerId: psychologyLayer.id, tags: [memoryTag1])
        ]
        
        // 添加所有节点到store
        nodes.append(contentsOf: englishNodes)
        nodes.append(contentsOf: statisticsNodes)
        nodes.append(contentsOf: psychologyNodes)
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
        // 标签会自动添加到单词/节点中，这里可以做一些全局标签管理
        // 暂时不需要特殊处理
    }
    
    public func addTag(to wordId: UUID, tag: Tag) {
        if let index = words.firstIndex(where: { $0.id == wordId }) {
            words[index].tags.append(tag)
        }
    }
    
    private func migrateWordsToNodes() {
        guard let defaultLayer = layers.first else { return }
        
        let newNodes = words.map { word in
            Node(
                text: word.text,
                phonetic: word.phonetic,
                meaning: word.meaning,
                layerId: defaultLayer.id,
                tags: word.tags
            )
        }
        
        nodes.append(contentsOf: newNodes)
        words.removeAll() // 清空旧的words数组
    }
    
    // MARK: - 数据清理
    
    @MainActor
    public func clearAllData() {
        print("🧹 开始彻底清理所有数据...")
        
        words.removeAll()
        nodes.removeAll()
        layers.removeAll()  // 清空所有层
        currentLayer = nil  // 清空当前层
        selectedWord = nil
        selectedNode = nil
        selectedTag = nil
        searchQuery = ""
        searchResults.removeAll()
        
        // 完全清空标签映射
        TagMappingManager.shared.clearAll()
        print("🏷️ 标签映射已完全清空")
        print("📂 所有层已清空")
        
        // 强制触发UI更新
        objectWillChange.send()
        
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
        words.removeAll()
        nodes.removeAll()
        layers.removeAll()  // 清空所有层
        currentLayer = nil  // 清空当前层
        selectedWord = nil
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
    
    public func getWordsInCurrentLayer() -> [Word] {
        guard let currentLayer = currentLayer else { 
            print("⚠️ getWordsInCurrentLayer: 没有当前层")
            return [] 
        }
        
        let layerWords = words.filter { $0.layerId == currentLayer.id }
        let orphanWords = words.filter { $0.layerId == nil }
        
        print("📊 getWordsInCurrentLayer: 当前层 '\(currentLayer.displayName)' 有 \(layerWords.count) 个单词")
        if !orphanWords.isEmpty {
            print("⚠️ getWordsInCurrentLayer: 发现 \(orphanWords.count) 个孤儿单词（layerId为nil）")
            for orphan in orphanWords {
                print("   - 孤儿单词: '\(orphan.text)'")
            }
        }
        
        return layerWords
    }
    
    public func wordsInCurrentLayer(withTag tag: Tag) -> [Word] {
        guard let currentLayer = currentLayer else { return [] }
        
        // 从当前层的 words 中获取有该标签的单词
        let wordsWithTag = words.filter { $0.layerId == currentLayer.id && $0.hasTag(tag) }
        
        // 从当前层的 nodes 中获取有该标签的节点并转换为 Word
        let nodesWithTag = nodes.filter { $0.layerId == currentLayer.id && $0.hasTag(tag) }
        let convertedWords = nodesWithTag.map { node in
            Word(text: node.text, phonetic: node.phonetic, meaning: node.meaning, layerId: node.layerId, tags: node.tags)
        }
        
        return wordsWithTag + convertedWords
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
    
    public func removeTag(from wordId: UUID, tagId: UUID) {
        if let index = words.firstIndex(where: { $0.id == wordId }) {
            words[index].tags.removeAll { $0.id == tagId }
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
        print("   - 单词总数: \(words.count)")
        print("   🔍 使用提供的key: '\(key)'")
        
        // 打印所有单词和标签的详细信息
        for (wordIndex, word) in words.enumerated() {
            print("   - 单词[\(wordIndex)]: '\(word.text)' 有 \(word.tags.count) 个标签")
            for (tagIndex, tag) in word.tags.enumerated() {
                print("     - 标签[\(tagIndex)]: type=\(tag.type), value='\(tag.value)'")
                if case .custom(let customKey) = tag.type {
                    print("       - 自定义标签key: '\(customKey)'")
                    print("       - 是否匹配目标key '\(key)': \(customKey == key)")
                }
            }
        }
        
        var updatedWords: [Word] = []
        var hasChanges = false
        
        for word in words {
            var updatedWord = word
            var wordHasChanges = false
            
            for (index, tag) in word.tags.enumerated() {
                // 通过key匹配，而不是typeName
                if case .custom(let customKey) = tag.type, customKey == key {
                    print("   ✅ 找到匹配的标签！更新单词 '\(word.text)' 的标签: key='\(key)', \(oldName) -> \(newName)")
                    // 保持key不变，只是TagType的displayName会通过TagMappingManager更新
                    // 这里实际上不需要更新Tag.type，因为displayName是通过TagMappingManager计算的
                    wordHasChanges = true
                    hasChanges = true
                }
            }
            
            if wordHasChanges {
                updatedWord.updatedAt = Date()
                updatedWords.append(updatedWord)
                print("   📝 单词 '\(word.text)' 已更新")
            } else {
                updatedWords.append(word)
            }
        }
        
        if hasChanges {
            print("✅ 标签类型名称更新完成，更新了 \(updatedWords.filter { $0.updatedAt > Date().addingTimeInterval(-1) }.count) 个单词")
            words = updatedWords
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
            print("   1. 没有使用key '\(key)' 的自定义标签类型的单词")
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