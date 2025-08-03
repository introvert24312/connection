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
    
    public static let shared = WordStore()
    
    private init() {
        setupInitialData()
        setupSearchBinding()
        setupExternalDataSync()
        setupDataPathChangeListener()
    }
    
    // MARK: - 初始化
    
    private func setupInitialData() {
        setupDefaultLayers()
        loadSampleData()
        
        // 尝试加载外部数据
        Task {
            do {
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
                    }
                }
            } catch {
                print("⚠️ 加载外部数据失败: \(error)")
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
                
                if self.externalDataManager.isDataPathSelected {
                    Task { @MainActor in
                        do {
                            try await self.externalDataService.saveAllData(store: self)
                            print("💾 数据已自动同步到外部存储")
                        } catch {
                            print("⚠️ 保存外部数据失败: \(error)")
                        }
                    }
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
            isLoading = true
            let (loadedLayers, loadedNodes) = try await externalDataService.loadAllData()
            
            if !loadedLayers.isEmpty {
                // 如果新路径有数据，替换当前数据
                layers = loadedLayers
                nodes = loadedNodes
                words.removeAll() // 清空旧的 words 数据，使用 nodes
                
                // 设置活跃层
                if let activeLayer = loadedLayers.first(where: { $0.isActive }) {
                    currentLayer = activeLayer
                } else if let firstLayer = loadedLayers.first {
                    currentLayer = firstLayer
                }
                
                print("📚 从新路径加载了 \(loadedNodes.count) 个节点，分布在 \(loadedLayers.count) 个层中")
            } else {
                // 如果新路径没有数据，保存当前数据到新路径
                print("💾 新路径为空，将当前数据保存到新位置...")
                try await externalDataService.saveAllData(store: self)
            }
            
            isLoading = false
            
        } catch {
            print("⚠️ 重新加载数据失败: \(error)")
            isLoading = false
            
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
        
        // 搜索words和nodes
        let wordResults = words.filter { word in
            word.text.localizedCaseInsensitiveContains(trimmedQuery) ||
            (word.meaning?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
            (word.phonetic?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
            word.tags.contains { $0.value.localizedCaseInsensitiveContains(trimmedQuery) }
        }
        
        let nodeResults = nodes.compactMap { node -> Word? in
            if node.text.localizedCaseInsensitiveContains(trimmedQuery) ||
               (node.meaning?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
               (node.phonetic?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
               node.tags.contains { $0.value.localizedCaseInsensitiveContains(trimmedQuery) } {
                return Word(text: node.text, phonetic: node.phonetic, meaning: node.meaning, tags: node.tags)
            }
            return nil
        }
        
        // 合并结果并去重
        var allResults = wordResults + nodeResults
        allResults = allResults.unique()
        
        searchResults = Array(allResults.prefix(50)) // 限制结果数量
        print("🔍 Store: Search completed, found \(searchResults.count) results")
    }
    
    // MARK: - 数据管理
    
    @MainActor
    public func addWord(_ word: Word) {
        words.append(word)
    }
    
    @MainActor
    public func addWord(_ text: String, phonetic: String?, meaning: String?) {
        let word = Word(text: text, phonetic: phonetic, meaning: meaning, tags: [])
        addWord(word)
    }
    
    @MainActor
    public func addNode(_ node: Node) {
        nodes.append(node)
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
        layers.removeAll { $0.id == layer.id }
        // 删除该层的所有节点
        nodes.removeAll { $0.layerId == layer.id }
        
        if currentLayer?.id == layer.id {
            currentLayer = layers.first
        }
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
        words.removeAll()
        nodes.removeAll()
        selectedWord = nil
        selectedNode = nil
        selectedTag = nil
        searchQuery = ""
        searchResults.removeAll()
    }
    
    @MainActor
    public func resetToSampleData() {
        clearAllData()
        createSampleData()
    }
    
    // MARK: - Missing methods for TagSidebarView
    
    public func getNodesInCurrentLayer() -> [Node] {
        guard let currentLayer = currentLayer else { return [] }
        return nodes.filter { $0.layerId == currentLayer.id }
    }
    
    public func getRelevantTags(for query: String) -> [Tag] {
        return searchTags(query: query)
    }
    
    public func selectTag(_ tag: Tag?) {
        setSelectedTag(tag)
    }
    
    public func findLocationTagByName(_ name: String) -> Tag? {
        return allTags.first { tag in
            tag.type == .location && tag.displayName == name
        }
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
        } catch {
            print("❌ 手动保存失败: \(error)")
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