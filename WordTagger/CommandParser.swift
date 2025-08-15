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
    case system = "系统"
    case layer = "层"
    
    public var icon: String {
        switch self {
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
        // 命令面板现在专门用于层管理，不显示任何默认命令
        // 用户通过搜索层名 + ⌘J/⌘⇧J 来管理层过滤器
        return []
    }
    
    // MARK: - Command Setup
    
    private func setupCommands() {
        allCommands = [
            // Layer commands - 动态生成，不使用硬编码
            // 注意：实际的层切换命令现在在 getDefaultCommands 和 findMatchingCommands 中动态生成
            CreateCompoundLayerCommand(),
            
            // System commands
            ResetSampleDataCommand()
        ]
    }
    
    // MARK: - Command Parsing Logic
    
    public func parseDirectCommand(_ input: String, context: CommandContext) -> Command? {
        let tokens = nlpProcessor.tokenize(input)
        let intent = nlpProcessor.detectIntent(from: tokens)
        
        
        switch intent {
        case .switchLayer(let layerName):
            return SwitchLayerCommand(layerName: layerName)
            
        case .createCompoundLayer(let layerName, let childLayers):
            return CreateCompoundLayerCommand(compoundLayerName: layerName, childLayerNames: childLayers)
            
        case .unknown:
            return nil
        }
    }
    
    private func findMatchingCommands(for input: String, context: CommandContext) async -> [Command] {
        // 命令面板现在专门用于层管理，不显示搜索结果
        // 用户通过输入层名 + ⌘J/⌘⇧J 来操作层过滤器
        return []
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
        
        var totalScore = 0.0
        var matchedTokens = 0
        
        for token1 in tokens1 {
            var bestScore = 0.0
            for token2 in tokens2 {
                // 支持模糊搜索
                let score = calculateFuzzyScore(token1, token2)
                bestScore = max(bestScore, score)
            }
            if bestScore > 0.3 { // 降低匹配阈值支持模糊搜索
                totalScore += bestScore
                matchedTokens += 1
            }
        }
        
        return matchedTokens > 0 ? totalScore / Double(tokens1.count) : 0
    }
    
    private func calculateFuzzyScore(_ query: String, _ target: String) -> Double {
        let queryLower = query.lowercased()
        let targetLower = target.lowercased()
        
        // 完全匹配
        if queryLower == targetLower {
            return 1.0
        }
        
        // 前缀匹配
        if targetLower.hasPrefix(queryLower) {
            return 0.9
        }
        
        // 包含匹配
        if targetLower.contains(queryLower) {
            return 0.8
        }
        
        // 字符顺序匹配（支持层名的部分输入）
        if containsInOrder(target: targetLower, query: queryLower) {
            return 0.7
        }
        
        // 使用原有的相似度算法作为后备
        let similarity = queryLower.similarity(to: targetLower)
        return similarity > 0.5 ? similarity : 0
    }
    
    private func containsInOrder(target: String, query: String) -> Bool {
        var targetIndex = target.startIndex
        let targetEnd = target.endIndex
        
        for queryChar in query {
            guard targetIndex < targetEnd else { return false }
            
            while targetIndex < targetEnd && target[targetIndex] != queryChar {
                targetIndex = target.index(after: targetIndex)
            }
            
            if targetIndex < targetEnd {
                targetIndex = target.index(after: targetIndex)
            } else {
                return false
            }
        }
        
        return true
    }
    
    private func calculateContextRelevance(command: Command, context: CommandContext) -> Double {
        // 只保留层相关的命令boost
        return 0
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
        
        // Layer switching patterns
        if tokens.contains("切换") || tokens.contains("进入") || tokens.contains("到") {
            let layerKeywords = tokens.filter { !["切换", "进入", "到", "层"].contains($0) }
            if !layerKeywords.isEmpty {
                let layerName = layerKeywords.joined(separator: " ")
                return .switchLayer(layerName: layerName)
            }
        }
        
        // Compound layer creation patterns
        if tokens.contains("复合层") || (tokens.contains("复合") && tokens.contains("层")) {
            return extractCreateCompoundLayerIntent(from: tokens)
        }
        
        // Simple compound layer syntax detection: "层C 层A 层B"
        // Check if input could be compound layer creation without keywords
        if tokens.count >= 2 {
            // If the first token could be a layer name and there are more tokens after it,
            // it might be the simple compound layer syntax
            // We'll let the parser try to interpret it as compound layer creation
            let compoundIntent = extractCreateCompoundLayerIntent(from: tokens)
            if case .createCompoundLayer(let name, let children) = compoundIntent,
               !name.isEmpty && !children.isEmpty {
                return compoundIntent
            }
        }
        
        return .unknown
    }
    
    
    private func extractCreateCompoundLayerIntent(from tokens: [String]) -> CommandIntent {
        // 解析复合层创建命令
        // 支持两种格式:
        // 1. 简单格式: "层C 层A 层B" - 第一个是复合层名，后面的是子层
        // 2. 传统格式: "复合层 [名称] 包含 [子层1] [子层2] ..."
        
        var layerName = ""
        var childLayers: [String] = []
        
        // 检查是否是传统格式
        if tokens.contains("复合层") || (tokens.contains("复合") && tokens.contains("层")) {
            // 使用传统解析逻辑
            var isParsingName = false
            var isParsingChildren = false
            
            for token in tokens {
                if token == "复合层" || (token == "复合" && tokens.contains("层")) {
                    isParsingName = true
                    continue
                }
                
                if token == "包含" || token == "含有" || token == "包括" {
                    isParsingName = false
                    isParsingChildren = true
                    continue
                }
                
                if ["创建", "新建", "添加", "层"].contains(token) {
                    continue
                }
                
                if isParsingName && !layerName.isEmpty {
                    layerName += " " + token
                } else if isParsingName {
                    layerName = token
                } else if isParsingChildren {
                    childLayers.append(token)
                }
            }
        } else {
            // 使用简单格式解析：第一个token是复合层名，其余是子层
            if tokens.count >= 2 {
                layerName = tokens[0]
                childLayers = Array(tokens[1...])
            } else if tokens.count == 1 {
                layerName = tokens[0]
            }
        }
        
        // 如果还是没有解析出内容，使用智能解析作为后备
        if layerName.isEmpty && childLayers.isEmpty {
            let relevantTokens = tokens.filter { 
                !["复合层", "复合", "层", "创建", "新建", "添加", "包含", "含有", "包括"].contains($0) 
            }
            
            if relevantTokens.count >= 2 {
                layerName = relevantTokens[0]
                childLayers = Array(relevantTokens[1...])
            } else if relevantTokens.count == 1 {
                layerName = relevantTokens[0]
            }
        }
        
        return .createCompoundLayer(layerName: layerName, childLayers: childLayers)
    }
}

// MARK: - Command Intent

private enum CommandIntent {
    case switchLayer(layerName: String)
    case createCompoundLayer(layerName: String, childLayers: [String])
    case unknown
}

// MARK: - Concrete Commands

public struct SwitchLayerCommand: Command {
    public let id = UUID()
    public let title: String
    public let description: String
    public let icon = "rectangle.stack"
    public let category = CommandCategory.layer
    public let keywords: [String]
    public let isChildLayer: Bool
    
    private let layerName: String
    
    public init(layerName: String, isChildLayer: Bool = false) {
        self.layerName = layerName
        self.isChildLayer = isChildLayer
        self.title = isChildLayer ? "  \(layerName)" : layerName  // 子层前面加两个空格缩进
        self.description = "切换到 \(layerName) 学科层"
        // 包含层名和相关关键词，支持模糊搜索
        self.keywords = ["切换", "层", "学科", "分类", layerName] + layerName.map { String($0) }
    }
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        // 完全阻止切换到名为"它"的层
        if layerName == "它" {
            return .success(message: "已忽略层切换")
        }
        
        // 检查目标层是否为复合层
        if let targetLayer = await context.store.layers.first(where: { $0.displayName == layerName || $0.name == layerName }) {
            if targetLayer.isCompound {
                // 复合层静默处理，不进行任何操作，返回成功状态
                return .success(message: "已忽略复合层切换")
            }
        }
        
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


// MARK: - 复合层命令

// MARK: - 层过滤命令

public struct AddToGraphFilterCommand: Command {
    public let id = UUID()
    public let title: String
    public let description: String
    public let icon = "plus.rectangle.on.rectangle"
    public let category = CommandCategory.layer
    public let keywords: [String]
    
    private let layerName: String
    
    public init(layerName: String) {
        self.layerName = layerName
        self.title = "添加到图谱: \(layerName)"
        self.description = "将 \(layerName) 层添加到图谱显示中"
        self.keywords = ["添加", "图谱", "过滤", "显示", layerName] + layerName.map { String($0) }
    }
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        // 通过通知将层添加到图谱过滤器中
        NotificationCenter.default.post(name: Notification.Name("addLayerToGraphFilter"), object: layerName)
        return .success(message: "已将 '\(layerName)' 添加到图谱显示")
    }
}

public struct RemoveFromGraphFilterCommand: Command {
    public let id = UUID()
    public let title: String
    public let description: String
    public let icon = "minus.rectangle"
    public let category = CommandCategory.layer
    public let keywords: [String]
    
    private let layerName: String
    
    public init(layerName: String) {
        self.layerName = layerName
        self.title = "从图谱移除: \(layerName)"
        self.description = "将 \(layerName) 层从图谱显示中移除"
        self.keywords = ["移除", "删除", "图谱", "过滤", "隐藏", layerName] + layerName.map { String($0) }
    }
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        // 通过通知将层从图谱过滤器中移除
        NotificationCenter.default.post(name: Notification.Name("removeLayerFromGraphFilter"), object: layerName)
        return .success(message: "已将 '\(layerName)' 从图谱显示中移除")
    }
}

public struct CreateCompoundLayerCommand: Command {
    public let id = UUID()
    public let title: String
    public let description: String
    public let icon = "square.stack.3d.up"
    public let category = CommandCategory.layer
    public let keywords: [String]
    
    private let compoundLayerName: String?
    private let childLayerNames: [String]
    
    public init(compoundLayerName: String? = nil, childLayerNames: [String] = []) {
        self.compoundLayerName = compoundLayerName
        self.childLayerNames = childLayerNames
        
        if let name = compoundLayerName {
            self.title = "创建复合层: \(name)"
            self.description = "创建包含 \(childLayerNames.count) 个子层的复合层"
            self.keywords = ["复合层", "创建", "compound", name] + childLayerNames
        } else {
            self.title = "创建复合层"
            self.description = "创建一个包含多个子层的复合层"
            self.keywords = ["复合层", "创建", "compound", "层组合"]
        }
    }
    
    public func execute(with context: CommandContext) async throws -> CommandResult {
        print("🏗️ CreateCompoundLayerCommand.execute - 开始执行")
        print("   复合层名: \(compoundLayerName ?? "nil")")
        print("   子层名: \(childLayerNames)")
        
        // 如果没有指定参数，返回错误提示用法
        guard let layerName = compoundLayerName, !childLayerNames.isEmpty else {
            return .error("用法: 层C 层A 层B  或  复合层 [复合层名称] 包含 [子层1] [子层2] ...")
        }
        
        // 查找子层
        let (foundChildLayerIds, notFoundLayers) = await findChildLayers(childLayerNames, in: context.store)
        
        // 检查是否所有子层都找到了
        if !notFoundLayers.isEmpty {
            return .error("未找到以下层: \(notFoundLayers.joined(separator: ", "))")
        }
        
        // 检查是否已存在同名层
        let existingLayer = await context.store.layers.first { 
            $0.name.lowercased() == layerName.lowercased() || 
            $0.displayName.lowercased() == layerName.lowercased() 
        }
        
        if existingLayer != nil {
            return .error("层 '\(layerName)' 已存在")
        }
        
        print("🏗️ 创建复合层...")
        // 创建复合层
        let compoundLayer = await MainActor.run {
            context.store.createCompoundLayer(
                name: layerName.lowercased(),
                displayName: layerName,
                childLayerIds: foundChildLayerIds,
                color: "purple"
            )
        }
        
        print("✅ 复合层创建成功: \(compoundLayer.displayName) (ID: \(compoundLayer.id))")
        
        // 切换到新创建的复合层
        await context.store.switchToLayer(compoundLayer)
        
        return .success(message: "成功创建复合层 '\(layerName)'，包含 \(foundChildLayerIds.count) 个子层")
    }
    
    private func findChildLayers(_ childLayerNames: [String], in store: NodeStore) async -> (foundIds: [UUID], notFound: [String]) {
        var childLayerIds: [UUID] = []
        var notFoundLayers: [String] = []
        
        print("🔍 查找子层...")
        for childLayerName in childLayerNames {
            if let childLayer = await store.layers.first(where: { 
                $0.name.lowercased() == childLayerName.lowercased() || 
                $0.displayName.lowercased() == childLayerName.lowercased() 
            }) {
                childLayerIds.append(childLayer.id)
                print("   ✅ 找到子层: \(childLayerName) -> \(childLayer.id)")
            } else {
                notFoundLayers.append(childLayerName)
                print("   ❌ 未找到子层: \(childLayerName)")
            }
        }
        
        return (childLayerIds, notFoundLayers)
    }
}