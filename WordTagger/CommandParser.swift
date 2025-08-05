import Foundation
import CoreLocation

public protocol Command {
    var id: UUID { get }
    var title: String { get }
    var description: String { get }
    var icon: String { get }
    var category: CommandCategory { get }
    var keywords: [String] { get }
    
    func execute(with context: CommandContext) async throws -> CommandResult
}

public enum CommandCategory: String, CaseIterable {
    case node = "节点"
    case tag = "标签"
    case search = "搜索"
    case navigation = "导航"
    case system = "系统"
    case layer = "层"
    
    public var icon: String {
        switch self {
        case .node: return "textbook"
        case .tag: return "tag"
        case .search: return "magnifyingglass"
        case .navigation: return "map"
        case .system: return "gear"
        case .layer: return "rectangle.stack"
        }
    }
}

public struct CommandContext {
    public let store: NodeStore
    public let currentNode: Node?
    public let selectedTag: Tag?
    
    public init(store: NodeStore, currentNode: Node? = nil, selectedTag: Tag? = nil) {
        self.store = store
        self.currentNode = currentNode
        self.selectedTag = selectedTag
    }
}

public enum CommandResult {
    case success(message: String)
    case nodeCreated(Node)
    case nodeSelected(Node)
    case tagAdded(Tag, to: Node)
    case searchPerformed(results: [SearchResult])
    case navigationRequested(destination: NavigationDestination)
    case layerSwitched(Layer)
    case error(String)
}

public enum NavigationDestination {
    case map
    case graph
    case settings
    case node(UUID)
}

public final class CommandParser: ObservableObject {
    @Published public private(set) var suggestions: [Command] = []
    @Published public private(set) var isProcessing = false
    
    private let nlpProcessor = NLPProcessor()
    private var allCommands: [Command] = []
    
    public static let shared = CommandParser()
    
    private init() {
        setupCommands()
    }
    
    // MARK: - Public API
    
    @MainActor public func parse(_ input: String, context: CommandContext) async -> [Command] {
        let cleanInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanInput.isEmpty else { 
            return await getDefaultCommands(context: context) 
        }
        
        // Try to detect command intent
        if let directCommand = parseDirectCommand(cleanInput, context: context) {
            return [directCommand]
        }
        
        // Use fuzzy matching for suggestions
        return await findMatchingCommands(for: cleanInput, context: context)
    }
    
    @MainActor public func updateSuggestions(for input: String, context: CommandContext) {
        Task {
            suggestions = await parse(input, context: context)
        }
    }
    
    public func getDefaultCommands(context: CommandContext? = nil) async -> [Command] {
        guard let context = context else {
            return [
                SwitchLayerCommand(layerName: "英语单词"),
                SwitchLayerCommand(layerName: "统计学"),
                SwitchLayerCommand(layerName: "教育心理学")
            ]
        }
        
        // 动态获取所有层
        return await context.store.layers.map { layer in
            SwitchLayerCommand(layerName: layer.displayName)
        }
    }
    
    // MARK: - Command Setup
    
    private func setupCommands() {
        allCommands = [
            // Node commands
            AddNodeCommand(),
            DeleteNodeCommand(),
            EditNodeCommand(),
            DuplicateNodeCommand(),
            
            // Tag commands
            AddTagCommand(nodeId: UUID()),
            RemoveTagCommand(),
            EditTagCommand(),
            AddLocationTagCommand(),
            
            // Search commands
            SearchNodesCommand(),
            SearchByTagCommand(),
            SearchByLocationCommand(),
            // FindSimilarNodesCommand(), // 临时注释
            
            // Navigation commands
            OpenMapCommand(),
            OpenGraphCommand(),
            ShowSettingsCommand(),
            SelectWordCommand(),
            
            // Layer commands
            SwitchLayerCommand(layerName: "英语单词"),
            SwitchLayerCommand(layerName: "统计学"),
            SwitchLayerCommand(layerName: "教育心理学"),
            
            // System commands
            ClearCacheCommand(),
            ExportDataCommand(),
            ImportDataCommand(),
            ShowStatsCommand(),
            ResetSampleDataCommand()
        ]
    }
    
    // MARK: - Command Parsing Logic
    
    private func parseDirectCommand(_ input: String, context: CommandContext) -> Command? {
        let tokens = nlpProcessor.tokenize(input)
        let intent = nlpProcessor.detectIntent(from: tokens)
        
        // 首先检查是否包含标签重命名语法
        if input.contains("[") && input.contains("]") {
            return TagRenameCommand(input: input)
        }
        
        switch intent {
        case .addNode(let text, let meaning, let phonetic):
            return AddNodeCommand(text: text, meaning: meaning, phonetic: phonetic)
            
        case .searchNode(let query):
            return SearchNodesCommand(query: query)
            
        case .addTag(let tagType, let value):
            guard let currentNode = context.currentNode else { return nil }
            return AddTagCommand(nodeId: currentNode.id, tagType: tagType, value: value)
            
        case .navigateTo(let destination):
            return NavigationCommand(destination: destination)
            
        case .switchLayer(let layerName):
            return SwitchLayerCommand(layerName: layerName)
            
        case .unknown:
            return nil
        }
    }
    
    private func findMatchingCommands(for input: String, context: CommandContext) async -> [Command] {
        let searchTokens = nlpProcessor.tokenize(input)
        
        // 动态获取所有层切换命令
        let layerCommands = await context.store.layers.map { layer in
            SwitchLayerCommand(layerName: layer.displayName)
        }
        
        var scoredCommands: [(Command, Double)] = []
        
        for command in layerCommands {
            let score = calculateMatchScore(command: command, tokens: searchTokens, context: context)
            if score > 0.3 {
                scoredCommands.append((command, score))
            }
        }
        
        return scoredCommands
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }
    
    private func calculateMatchScore(command: Command, tokens: [String], context: CommandContext) -> Double {
        var score: Double = 0
        
        // Title match
        let titleTokens = nlpProcessor.tokenize(command.title)
        score += calculateTokenSimilarity(tokens, titleTokens) * 2.0
        
        // Description match
        let descTokens = nlpProcessor.tokenize(command.description)
        score += calculateTokenSimilarity(tokens, descTokens) * 1.0
        
        // Keywords match
        let keywordTokens = command.keywords.flatMap { nlpProcessor.tokenize($0) }
        score += calculateTokenSimilarity(tokens, keywordTokens) * 1.5
        
        // Context relevance boost
        score += calculateContextRelevance(command: command, context: context)
        
        return min(score, 1.0)
    }
    
    private func calculateTokenSimilarity(_ tokens1: [String], _ tokens2: [String]) -> Double {
        guard !tokens1.isEmpty && !tokens2.isEmpty else { return 0 }
        
        var matches = 0
        for token1 in tokens1 {
            for token2 in tokens2 {
                if token1.similarity(to: token2) > 0.7 {
                    matches += 1
                    break
                }
            }
        }
        
        return Double(matches) / Double(max(tokens1.count, tokens2.count))
    }
    
    private func calculateContextRelevance(command: Command, context: CommandContext) -> Double {
        var boost: Double = 0
        
        // Boost node-related commands if a node is selected
        if context.currentNode != nil && command.category == .node {
            boost += 0.2
        }
        
        // Boost tag-related commands if a tag is selected
        if context.selectedTag != nil && command.category == .tag {
            boost += 0.2
        }
        
        return boost
    }
}

// MARK: - NLP Processor

private class NLPProcessor {
    func tokenize(_ text: String) -> [String] {
        return text.lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { !$0.isEmpty }
    }
    
    func detectIntent(from tokens: [String]) -> CommandIntent {
        // Simple intent detection based on keywords
        _ = tokens.joined(separator: " ")
        
        // Add node patterns
        if tokens.contains("添加") || tokens.contains("新增") || tokens.contains("创建") {
            if tokens.contains("节点") || tokens.contains("词") {
                return extractAddNodeIntent(from: tokens)
            }
            if tokens.contains("标签") {
                return extractAddTagIntent(from: tokens)
            }
        }
        
        // Search patterns
        if tokens.contains("搜索") || tokens.contains("查找") || tokens.contains("找") {
            let query = tokens.filter { !["搜索", "查找", "找", "节点"].contains($0) }.joined(separator: " ")
            return .searchNode(query: query.isEmpty ? nil : query)
        }
        
        // Navigation patterns
        if tokens.contains("打开") || tokens.contains("显示") || tokens.contains("转到") {
            if tokens.contains("地图") {
                return .navigateTo(.map)
            }
            if tokens.contains("图谱") || tokens.contains("关系图") {
                return .navigateTo(.graph)
            }
            if tokens.contains("设置") {
                return .navigateTo(.settings)
            }
        }
        
        // Layer switching patterns
        if tokens.contains("切换") || tokens.contains("进入") || tokens.contains("到") {
            let layerKeywords = tokens.filter { !["切换", "进入", "到", "层"].contains($0) }
            if !layerKeywords.isEmpty {
                let layerName = layerKeywords.joined(separator: " ")
                return .switchLayer(layerName: layerName)
            }
        }
        
        // Direct layer name detection - for commands like "英语单词", "统计学", etc.
        let possibleLayerNames = ["英语", "英语单词", "统计学", "教育心理学", "数学", "物理", "化学", "生物"]
        for layerName in possibleLayerNames {
            let layerTokens = layerName.components(separatedBy: .whitespaces)
            if layerTokens.allSatisfy({ tokens.contains($0) }) {
                return .switchLayer(layerName: layerName)
            }
        }
        
        return .unknown
    }
    
    private func extractAddNodeIntent(from tokens: [String]) -> CommandIntent {
        // Simple extraction - in real app, use more sophisticated NLP
        let relevantTokens = tokens.filter { !["添加", "新增", "创建", "节点", "词"].contains($0) }
        
        if let firstToken = relevantTokens.first {
            return .addNode(text: firstToken, meaning: nil, phonetic: nil)
        }
        
        return .addNode(text: nil, meaning: nil, phonetic: nil)
    }
    
    private func extractAddTagIntent(from tokens: [String]) -> CommandIntent {
        // Extract tag type and value
        var tagType: Tag.TagType?
        var value: String?
        
        for token in tokens {
            if let type = Tag.TagType.predefinedCases.first(where: { $0.displayName.contains(token) || $0.rawValue == token }) {
                tagType = type
                break
            }
        }
        
        let valueTokens = tokens.filter { token in
            !["添加", "新增", "创建", "标签"].contains(token) &&
            !Tag.TagType.predefinedCases.contains { $0.displayName.contains(token) || $0.rawValue == token }
        }
        
        if !valueTokens.isEmpty {
            value = valueTokens.joined(separator: " ")
        }
        
        return .addTag(tagType: tagType, value: value)
    }
}

// MARK: - Command Intent

private enum CommandIntent {
    case addNode(text: String?, meaning: String?, phonetic: String?)
    case searchNode(query: String?)
    case addTag(tagType: Tag.TagType?, value: String?)
    case navigateTo(NavigationDestination)
    case switchLayer(layerName: String)
    case unknown
}

// MARK: - Concrete Commands

public struct AddNodeCommand: Command {
    public let id = UUID()
    public let title: String
    public let description: String
    public let icon = "plus.circle"
    public let category = CommandCategory.node
    public let keywords = ["添加", "新增", "创建", "节点", "词汇"]
    
    private let text: String?
    private let meaning: String?
    private let phonetic: String?
    
    public init(text: String? = nil, meaning: String? = nil, phonetic: String? = nil) {
        self.text = text
        self.meaning = meaning
        self.phonetic = phonetic
        
        if let text = text {
            self.title = "添加节点: \(text)"
            self.description = "创建新节点 '\(text)'"
        } else {
            self.title = "添加节点"
            self.description = "创建一个新的节点条目"
        }
    }
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        guard let nodeText = text, !nodeText.isEmpty else {
            return .error("请提供节点文本")
        }
        
        let success = await context.store.addNode(nodeText, phonetic: phonetic, meaning: meaning)
        
        if !success {
            return .error("节点添加被拒绝（可能是重复）")
        }
        
        if let newNode = await context.store.nodes.first(where: { $0.text == nodeText }) {
            return .nodeCreated(newNode)
        } else {
            return .error("创建节点失败")
        }
    }
}

public struct SearchNodesCommand: Command {
    public let id = UUID()
    public let title: String
    public let description: String
    public let icon = "magnifyingglass"
    public let category = CommandCategory.search
    public let keywords = ["搜索", "查找", "检索"]
    
    private let query: String?
    
    public init(query: String? = nil) {
        self.query = query
        
        if let query = query {
            self.title = "搜索: \(query)"
            self.description = "搜索包含 '\(query)' 的节点"
        } else {
            self.title = "搜索节点"
            self.description = "在所有节点中进行搜索"
        }
    }
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        guard let searchQuery = query, !searchQuery.isEmpty else {
            return .error("请提供搜索关键词")
        }
        
        await MainActor.run {
            context.store.searchQuery = searchQuery
        }
        
        // Wait a bit for the search to process
        try await Task.sleep(nanoseconds: 300_000_000)
        
        return .searchPerformed(results: await context.store.searchResults.map { node in
            return SearchResult(node: node, score: 1.0, matchedFields: [.text])
        })
    }
}

public struct OpenMapCommand: Command {
    public let id = UUID()
    public let title = "打开地图"
    public let description = "显示节点地点标签的地图视图"
    public let icon = "map"
    public let category = CommandCategory.navigation
    public let keywords = ["地图", "位置", "地点"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .navigationRequested(destination: .map)
    }
}

public struct OpenGraphCommand: Command {
    public let id = UUID()
    public let title = "打开全局图谱"
    public let description = "显示全局的节点关系图谱"
    public let icon = "circle.hexagonpath"
    public let category = CommandCategory.navigation
    public let keywords = ["图谱", "关系", "网络", "连接"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .navigationRequested(destination: .graph)
    }
}

public struct ShowSettingsCommand: Command {
    public let id = UUID()
    public let title = "设置"
    public let description = "打开应用程序设置"
    public let icon = "gear"
    public let category = CommandCategory.system
    public let keywords = ["设置", "配置", "偏好"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .navigationRequested(destination: .settings)
    }
}

// Additional command implementations...
public struct AddTagCommand: Command {
    public let id = UUID()
    public let title: String
    public let description: String
    public let icon = "tag.circle"
    public let category = CommandCategory.tag
    public let keywords = ["标签", "添加", "分类"]
    
    private let nodeId: UUID
    private let tagType: Tag.TagType?
    private let value: String?
    
    public init(nodeId: UUID, tagType: Tag.TagType? = nil, value: String? = nil) {
        self.nodeId = nodeId
        self.tagType = tagType
        self.value = value
        
        if let value = value {
            self.title = "添加标签: \(value)"
            self.description = "为当前节点添加标签 '\(value)'"
        } else {
            self.title = "添加标签"
            self.description = "为当前节点添加新标签"
        }
    }
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        guard let tagType = tagType,
              let value = value,
              !value.isEmpty else {
            return .error("请提供标签类型和值")
        }
        
        let tag = await context.store.createTag(type: tagType, value: value)
        await context.store.addTag(tag)
        
        if let node = await context.store.nodes.first(where: { $0.id == nodeId }) {
            return .tagAdded(tag, to: node)
        } else {
            return .error("未找到指定节点")
        }
    }
}

// Placeholder commands for the remaining functionality
public struct DeleteNodeCommand: Command {
    public let id = UUID()
    public let title = "删除节点"
    public let description = "删除当前选择的节点"
    public let icon = "trash"
    public let category = CommandCategory.node
    public let keywords = ["删除", "移除"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .error("功能待实现")
    }
}

public struct EditNodeCommand: Command {
    public let id = UUID()
    public let title = "编辑节点"
    public let description = "编辑当前选择的节点"
    public let icon = "pencil"
    public let category = CommandCategory.node
    public let keywords = ["编辑", "修改"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .error("功能待实现")
    }
}

public struct DuplicateNodeCommand: Command {
    public let id = UUID()
    public let title = "复制节点"
    public let description = "复制当前选择的节点"
    public let icon = "doc.on.doc"
    public let category = CommandCategory.node
    public let keywords = ["复制", "重复"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .error("功能待实现")
    }
}

public struct RemoveTagCommand: Command {
    public let id = UUID()
    public let title = "移除标签"
    public let description = "从当前节点移除标签"
    public let icon = "tag.slash"
    public let category = CommandCategory.tag
    public let keywords = ["移除", "删除", "标签"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .error("功能待实现")
    }
}

public struct EditTagCommand: Command {
    public let id = UUID()
    public let title = "编辑标签"
    public let description = "编辑标签内容"
    public let icon = "tag.circle.fill"
    public let category = CommandCategory.tag
    public let keywords = ["编辑", "修改", "标签"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .error("功能待实现")
    }
}

public struct AddLocationTagCommand: Command {
    public let id = UUID()
    public let title = "添加地点标签"
    public let description = "为节点添加地理位置标签"
    public let icon = "location.circle"
    public let category = CommandCategory.tag
    public let keywords = ["地点", "位置", "标签"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .error("功能待实现")
    }
}

public struct SearchByTagCommand: Command {
    public let id = UUID()
    public let title = "按标签搜索"
    public let description = "根据标签类型搜索单词"
    public let icon = "tag.fill"
    public let category = CommandCategory.search
    public let keywords = ["标签", "搜索", "分类"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .error("功能待实现")
    }
}

public struct SearchByLocationCommand: Command {
    public let id = UUID()
    public let title = "按位置搜索"
    public let description = "根据地理位置搜索单词"
    public let icon = "location.magnifyingglass"
    public let category = CommandCategory.search
    public let keywords = ["位置", "地点", "搜索"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .error("功能待实现")
    }
}

public struct FindSimilarWordsCommand: Command {
    public let id = UUID()
    public let title = "查找相似单词"
    public let description = "查找与当前单词相似的单词"
    public let icon = "waveform"
    public let category = CommandCategory.search
    public let keywords = ["相似", "类似", "关联"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .error("功能待实现")
    }
}

public struct SelectWordCommand: Command {
    public let id = UUID()
    public let title = "选择单词"
    public let description = "选择特定单词"
    public let icon = "hand.point.up.left"
    public let category = CommandCategory.navigation
    public let keywords = ["选择", "选中"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .error("功能待实现")
    }
}

public struct ClearCacheCommand: Command {
    public let id = UUID()
    public let title = "清除缓存"
    public let description = "清除应用程序缓存"
    public let icon = "trash.circle"
    public let category = CommandCategory.system
    public let keywords = ["缓存", "清除", "清理"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .error("功能待实现")
    }
}

public struct ExportDataCommand: Command {
    public let id = UUID()
    public let title = "导出数据"
    public let description = "导出单词数据"
    public let icon = "square.and.arrow.up"
    public let category = CommandCategory.system
    public let keywords = ["导出", "备份"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .error("功能待实现")
    }
}

public struct ImportDataCommand: Command {
    public let id = UUID()
    public let title = "导入数据"
    public let description = "导入单词数据"
    public let icon = "square.and.arrow.down"
    public let category = CommandCategory.system
    public let keywords = ["导入", "恢复"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .error("功能待实现")
    }
}

public struct ShowStatsCommand: Command {
    public let id = UUID()
    public let title = "显示统计"
    public let description = "显示应用使用统计"
    public let icon = "chart.bar"
    public let category = CommandCategory.system
    public let keywords = ["统计", "数据", "分析"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .error("功能待实现")
    }
}

public struct NavigationCommand: Command {
    public let id = UUID()
    public let title: String
    public let description: String
    public let icon: String
    public let category = CommandCategory.navigation
    public let keywords: [String]
    
    private let destination: NavigationDestination
    
    public init(destination: NavigationDestination) {
        self.destination = destination
        
        switch destination {
        case .map:
            self.title = "打开地图"
            self.description = "切换到地图视图"
            self.icon = "map"
            self.keywords = ["地图", "位置"]
        case .graph:
            self.title = "打开关系图"
            self.description = "切换到关系图视图"
            self.icon = "circle.hexagonpath"
            self.keywords = ["图谱", "关系"]
        case .settings:
            self.title = "打开设置"
            self.description = "打开应用设置"
            self.icon = "gear"
            self.keywords = ["设置", "配置"]
        case .node(_):
            self.title = "选择单词"
            self.description = "选择指定单词"
            self.icon = "textbook"
            self.keywords = ["选择", "单词"]
        }
    }
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        return .navigationRequested(destination: destination)
    }
}

public struct SwitchLayerCommand: Command {
    public let id = UUID()
    public let title: String
    public let description: String
    public let icon = "rectangle.stack"
    public let category = CommandCategory.layer
    public let keywords = ["切换", "层", "学科", "分类"]
    
    private let layerName: String
    
    public init(layerName: String) {
        self.layerName = layerName
        self.title = "切换到 \(layerName)"
        self.description = "切换到 \(layerName) 学科层"
    }
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        await context.store.switchToLayer(named: layerName)
        
        if let currentLayer = await context.store.currentLayer {
            return .layerSwitched(currentLayer)
        } else {
            return .error("切换层失败")
        }
    }
}

public struct ResetSampleDataCommand: Command {
    public let id = UUID()
    public let title = "重置示例数据"
    public let description = "清除所有数据并重新创建示例数据"
    public let icon = "arrow.clockwise.circle"
    public let category = CommandCategory.system
    public let keywords = ["重置", "示例", "数据", "清除"]
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        await context.store.resetToSampleData()
        return .success(message: "已重置为示例数据")
    }
}

public struct TagRenameCommand: Command {
    public let id = UUID()
    public let title: String
    public let description: String
    public let icon = "tag.circle"
    public let category = CommandCategory.tag
    public let keywords = ["重命名", "标签", "修改"]
    
    private let input: String
    
    public init(input: String) {
        self.input = input
        self.title = "标签重命名"
        self.description = "重命名标签类型显示名称"
    }
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        let tagManager = TagMappingManager.shared
        let components = input.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        var renamedCount = 0
        
        // 检查每个component是否包含重命名语法
        for component in components {
            if component.contains("[") && component.contains("]") {
                if let startBracket = component.firstIndex(of: "["),
                   let endBracket = component.firstIndex(of: "]"),
                   startBracket < endBracket {
                    
                    let actualTagKey = String(component[..<startBracket])
                    let newTypeName = String(component[component.index(after: startBracket)..<endBracket])
                    
                    print("🏷️ CommandParser: 检测到标签重命名 - key: '\(actualTagKey)', newName: '\(newTypeName)'")
                    
                    // 处理标签重命名
                    if let existingMapping = tagManager.tagMappings.first(where: { $0.key == actualTagKey }) {
                        let oldTypeName = existingMapping.typeName
                        print("🔄 CommandParser: 更新标签映射 - \(oldTypeName) -> \(newTypeName)")
                        
                        // 创建更新后的映射
                        let updatedMapping = TagMapping(
                            id: existingMapping.id,
                            key: actualTagKey,
                            typeName: newTypeName
                        )
                        
                        // 保存到TagManager，会自动触发UI更新
                        await MainActor.run {
                            tagManager.saveMapping(updatedMapping)
                        }
                        
                        renamedCount += 1
                        print("✅ CommandParser: 标签重命名完成")
                    } else {
                        print("⚠️ CommandParser: 未找到key '\(actualTagKey)' 对应的映射")
                        // 创建新映射
                        let newMapping = TagMapping(key: actualTagKey, typeName: newTypeName)
                        await MainActor.run {
                            tagManager.saveMapping(newMapping)
                        }
                        renamedCount += 1
                        print("✅ CommandParser: 创建新标签映射: \(actualTagKey) -> \(newTypeName)")
                    }
                }
            }
        }
        
        if renamedCount > 0 {
            return .success(message: "成功重命名 \(renamedCount) 个标签")
        } else {
            return .error("未找到可重命名的标签")
        }
    }
}