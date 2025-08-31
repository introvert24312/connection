import Foundation

// MARK: - 分层系统模型

public struct Layer: Identifiable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var displayName: String
    public var color: String
    public var isActive: Bool
    public var isCompound: Bool
    public var childLayerIds: [UUID]
    public var createdAt: Date
    
    public init(name: String, displayName: String, color: String = "blue", isCompound: Bool = false, childLayerIds: [UUID] = []) {
        self.id = UUID()
        self.name = name
        self.displayName = displayName
        self.color = color
        self.isActive = false
        self.isCompound = isCompound
        self.childLayerIds = childLayerIds
        self.createdAt = Date()
    }
    
    // 自定义解码器，确保向后兼容现有数据
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decode(String.self, forKey: .displayName)
        color = try container.decode(String.self, forKey: .color)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        // 为复合层字段提供默认值，确保向后兼容
        isCompound = try container.decodeIfPresent(Bool.self, forKey: .isCompound) ?? false
        childLayerIds = try container.decodeIfPresent([UUID].self, forKey: .childLayerIds) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
    
    // 编码键
    private enum CodingKeys: String, CodingKey {
        case id, name, displayName, color, isActive, isCompound, childLayerIds, createdAt
    }
    
    public static func == (lhs: Layer, rhs: Layer) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct Node: Identifiable, Hashable, Codable {
    public let id: UUID
    public var text: String
    public var phonetic: String?
    public var meaning: String?
    public var layerId: UUID
    public var tags: [Tag]
    public var isCompound: Bool
    public var markdown: String  // 新增Markdown字段
    public var createdAt: Date
    public var updatedAt: Date
    
    public init(text: String, phonetic: String? = nil, meaning: String? = nil, layerId: UUID, tags: [Tag] = [], isCompound: Bool = false, markdown: String = "") {
        self.id = UUID()
        self.text = text
        self.phonetic = phonetic
        self.meaning = meaning
        self.layerId = layerId
        self.tags = tags
        self.isCompound = isCompound
        self.markdown = markdown  // 初始化Markdown字段
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // 自定义解码器，确保向后兼容现有数据和数据清理
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        
        // 安全解码并清理text字段，防止corruption
        let rawText = try container.decode(String.self, forKey: .text)
        text = Self.sanitizeText(rawText)
        
        // 安全解码可选字段
        let rawPhonetic = try container.decodeIfPresent(String.self, forKey: .phonetic)
        phonetic = rawPhonetic.map { Self.sanitizeText($0) }
        
        let rawMeaning = try container.decodeIfPresent(String.self, forKey: .meaning)
        meaning = rawMeaning.map { Self.sanitizeText($0) }
        
        layerId = try container.decode(UUID.self, forKey: .layerId)
        
        // 安全解码标签，包含corruption检查
        let rawTags = try container.decode([Tag].self, forKey: .tags)
        tags = rawTags.compactMap { tag in
            // 过滤掉损坏的标签
            let sanitizedValue = Self.sanitizeText(tag.value)
            if sanitizedValue.isEmpty || Self.isCorruptedText(sanitizedValue) {
                print("⚠️ 发现并移除损坏的标签: '\(tag.value)' -> '\(sanitizedValue)'")
                return nil
            }
            // 创建清理后的标签
            return Tag(
                type: tag.type,
                value: sanitizedValue,
                latitude: tag.latitude,
                longitude: tag.longitude,
                isShortcutType: tag.isShortcutType
            )
        }
        
        isCompound = try container.decode(Bool.self, forKey: .isCompound)
        
        // 为markdown字段提供默认值，确保向后兼容
        let rawMarkdown = try container.decodeIfPresent(String.self, forKey: .markdown) ?? ""
        markdown = Self.sanitizeText(rawMarkdown)
        
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        
        // 如果检测到corruption，记录并更新时间戳
        if Self.isCorruptedText(rawText) {
            print("🔧 检测到节点corruption，已自动修复: '\(rawText)' -> '\(text)'")
            self.updatedAt = Date() // 标记为已修复
        }
    }
    
    // 编码键
    private enum CodingKeys: String, CodingKey {
        case id, text, phonetic, meaning, layerId, tags, isCompound, markdown, createdAt, updatedAt
    }
    
    public func tags(of type: Tag.TagType) -> [Tag] {
        return tags.filter { $0.type == type }
    }
    
    public func hasTag(_ tag: Tag) -> Bool {
        return tags.contains(tag)
    }
    
    public var locationTags: [Tag] {
        return tags.filter { $0.hasCoordinates }
    }
    
    // 计算复合节点的嵌套深度
    public func getCompoundDepth(allNodes: [Node]) -> Int {
        guard isCompound else { return 0 }
        
        // 获取所有子节点引用
        let childReferences = tags.filter { 
            if case .custom(let key) = $0.type {
                return key == "child"
            }
            return false
        }
        
        var maxChildDepth = 0
        
        // 检查每个子节点的深度
        for childRef in childReferences {
            let childName = childRef.value
            if let childNode = allNodes.first(where: { $0.text.lowercased() == childName.lowercased() }) {
                let childDepth = childNode.getCompoundDepth(allNodes: allNodes)
                maxChildDepth = max(maxChildDepth, childDepth)
            }
        }
        
        // 当前节点的深度 = 最大子节点深度 + 1
        return maxChildDepth + 1
    }
    
    /// 生成节点的命令行表示
    /// 格式：节点名 标签类型1 标签值1 标签类型2 标签值2 ...
    public var commandLineRepresentation: String {
        var components = [text]
        
        // 按标签类型分组
        let groupedTags = Dictionary(grouping: tags) { $0.type }
        
        // 按标签类型的rawValue排序，确保输出一致
        let sortedTagTypes = groupedTags.keys.sorted { $0.rawValue < $1.rawValue }
        
        for tagType in sortedTagTypes {
            let tagsOfType = groupedTags[tagType] ?? []
            for tag in tagsOfType.sorted(by: { $0.value < $1.value }) {
                components.append(tagType.rawValue)
                components.append(quoteValueIfNeeded(tag.value))
            }
        }
        
        return components.joined(separator: " ")
    }
    
    /// 生成规范化命令行表示，包含当前标签映射的注释
    /// 格式：节点名 标签类型1 标签值1 标签类型2 标签值2 ...  # type1=展示名1, type2=展示名2
    /// 对于复合节点，使用简洁的 "c 复合节点名 子节点1 子节点2" 格式
    public var canonicalCommandRepresentation: String {
        // 特殊处理复合节点：使用简洁的 c 格式
        if isCompound {
            // 提取所有子节点引用
            let childNodes = tags.compactMap { tag -> String? in
                if case .custom(let key) = tag.type, key == "child" {
                    return tag.value
                }
                return nil
            }
            
            if !childNodes.isEmpty {
                return "c \(text) \(childNodes.joined(separator: " "))"
            }
        }
        
        var components = [text]
        
        // 按标签类型分组
        let groupedTags = Dictionary(grouping: tags) { $0.type }
        
        // 按标签类型的rawValue排序，确保输出一致
        let sortedTagTypes = groupedTags.keys.sorted { $0.rawValue < $1.rawValue }
        
        for tagType in sortedTagTypes {
            let tagsOfType = groupedTags[tagType] ?? []
            
            for tag in tagsOfType.sorted(by: { $0.value < $1.value }) {
                // 获取原始的标签key，而不是displayName
                let tagCode: String
                let displayName: String
                let shouldUseRenameFormat: Bool
                
                if case .custom(let customKey) = tagType {
                    // 对于自定义标签，customKey应该就是原始key
                    tagCode = customKey
                    
                    // 从TagMappingManager查找对应的typeName
                    let tagManager = TagMappingManager.shared
                    if let mapping = tagManager.tagMappings.first(where: { $0.key == customKey }) {
                        displayName = mapping.typeName
                        shouldUseRenameFormat = true  // 强制所有标签都显示方括号
                    } else {
                        // 如果找不到映射，使用customKey作为fallback
                        displayName = customKey
                        shouldUseRenameFormat = true  // 强制所有标签都显示方括号
                    }
                } else {
                    // 对于预定义标签类型，直接使用rawValue
                    tagCode = tagType.rawValue
                    displayName = tagType.displayName
                    shouldUseRenameFormat = true  // 强制所有标签都显示方括号
                }
                
                // 使用重命名格式 key[displayName] 或简单格式 key
                if shouldUseRenameFormat {
                    components.append("\(tagCode)[\(displayName)]")
                } else {
                    components.append(tagCode)
                }
                
                components.append(quoteValueIfNeeded(tag.value))
            }
        }
        
        return components.joined(separator: " ")
    }
    
    /// 给包含空格的值添加引号
    private func quoteValueIfNeeded(_ value: String) -> String {
        if value.contains(" ") && !value.hasPrefix("\"") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return value
    }
    
    /// 生成带展示名的命令行表示（用于显式改名）
    /// 格式：节点名 标签类型1[展示名1] 标签值1 标签类型2[展示名2] 标签值2 ...
    public var commandRepresentationWithDisplayNames: String {
        var components = [text]
        
        // 按标签类型分组
        let groupedTags = Dictionary(grouping: tags) { $0.type }
        
        // 按标签类型的rawValue排序，确保输出一致
        let sortedTagTypes = groupedTags.keys.sorted { $0.rawValue < $1.rawValue }
        
        for tagType in sortedTagTypes {
            let tagsOfType = groupedTags[tagType] ?? []
            for tag in tagsOfType.sorted(by: { $0.value < $1.value }) {
                let tagCode = tagType.rawValue
                let displayName = tagType.displayName
                
                // 检查是否为带坐标的地理标签
                if tag.hasCoordinates, let lat = tag.latitude, let lng = tag.longitude {
                    // 地理标签格式：tagCode @latitude,longitude[displayName]
                    components.append("\(tagCode)")
                    components.append("@\(lat),\(lng)[\(tag.value)]")
                } else {
                    // 普通标签格式：tagCode[displayName] value
                    components.append("\(tagCode)[\(displayName)]")
                    components.append(quoteValueIfNeeded(tag.value))
                }
            }
        }
        
        return components.joined(separator: " ")
    }
    
    /// 从命令行字符串创建或更新节点
    /// 格式：节点名 标签类型1 标签值1 标签类型2 标签值2 ...
    /// 支持内联改名：类型[展示名] 值 - 会更新该类型的全局展示名
    public static func fromCommandLine(_ commandLine: String, layerId: UUID) -> Node? {
        // 移除行内注释
        let cleanCommandLine = removeInlineComments(commandLine)
        
        let components = cleanCommandLine.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }
        
        guard !components.isEmpty else { 
            return nil 
        }
        
        let nodeName = components[0]
        var tags: [Tag] = []
        
        // 解析标签：每两个组件为一对（类型，值）
        var i = 1
        while i < components.count - 1 {
            let tagTypeString = components[i]
            let tagValue = unquoteValue(components[i + 1])
            
            // 解析类型和可能的展示名
            let (tagCode, displayName) = parseTagTypeWithDisplayName(tagTypeString)
            
            // 如果有展示名，更新全局映射
            if let displayName = displayName {
                updateTagDisplayName(tagCode: tagCode, displayName: displayName)
            }
            
            let tagType: Tag.TagType
            if tagCode == "location" {
                tagType = .location
            } else {
                tagType = .custom(tagCode)
            }
            
            let tag = Tag(type: tagType, value: tagValue)
            tags.append(tag)
            
            i += 2
        }
        
        let result = Node(text: nodeName, layerId: layerId, tags: tags)
        return result
    }
    
    /// 更新节点的标签从命令行字符串
    public mutating func updateFromCommandLine(_ commandLine: String) {
        // 移除行内注释
        let cleanCommandLine = Self.removeInlineComments(commandLine)
        
        let components = cleanCommandLine.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }
        
        guard components.count >= 1 else { return }
        
        // 更新节点名
        self.text = components[0]
        
        // 清空现有标签
        self.tags.removeAll()
        
        // 解析新标签
        var i = 1
        while i < components.count - 1 {
            let tagTypeString = components[i]
            let tagValue = Self.unquoteValue(components[i + 1])
            
            // 解析类型和可能的展示名
            let (tagCode, displayName) = Self.parseTagTypeWithDisplayName(tagTypeString)
            
            // 如果有展示名，更新全局映射
            if let displayName = displayName {
                Self.updateTagDisplayName(tagCode: tagCode, displayName: displayName)
            }
            
            let tagType: Tag.TagType
            if tagCode == "location" {
                tagType = .location
            } else {
                tagType = .custom(tagCode)
            }
            
            let tag = Tag(type: tagType, value: tagValue)
            self.tags.append(tag)
            
            i += 2
        }
        
        self.updatedAt = Date()
    }
    
    public static func == (lhs: Node, rhs: Node) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    /// 修复节点中的标签类型，移除旧的custom_前缀
    public mutating func fixLegacyTagTypes() {
        var hasChanges = false
        
        for i in 0..<tags.count {
            let currentTag = tags[i]
            switch currentTag.type {
            case .custom(let name):
                if name.hasPrefix("custom_") {
                    let cleanName = String(name.dropFirst(7))
                    tags[i].type = .custom(cleanName)
                    hasChanges = true
                    print("🔧 修复标签类型: custom_\(cleanName) -> \(cleanName)")
                }
            case .location:
                break // location标签不需要修复
            }
        }
        
        if hasChanges {
            self.updatedAt = Date()
            print("✅ 节点 '\(self.text)' 的标签类型已修复")
        }
    }
    
    // MARK: - 数据清理和corruption检测方法
    
    /// 清理文本，移除非法字符和corruption
    private static func sanitizeText(_ text: String) -> String {
        // 如果文本为空或已经是正常的，直接返回
        if text.isEmpty || !isCorruptedText(text) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 清理各种可能的corruption
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
            #"\b[bcdfghjklmnpqrstvwxyz]{3,}\b"#, // 连续辅音
            #"\b[aeiou]{3,}\b"#, // 连续元音超过3个
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
        
        // 如果清理后为空或仍然corrupt，返回默认值
        if sanitized.isEmpty || isCorruptedText(sanitized) {
            return "[已修复]" // 标记已修复的节点
        }
        
        return sanitized
    }
    
    /// 检测文本是否存在corruption
    private static func isCorruptedText(_ text: String) -> Bool {
        // 空文本不算corruption
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
        
        // 如果有意义字符比例低于70%，认为是corruption
        if totalLength > 0 && Double(meaningfulChars) / Double(totalLength) < 0.7 {
            return true
        }
        
        // 检查是否包含过多连续的相同字符
        let consecutivePattern = #"(.)\1{5,}"# // 连续6个以上相同字符
        if text.range(of: consecutivePattern, options: .regularExpression) != nil {
            return true
        }
        
        return false
    }
    
    // MARK: - 命令行解析辅助方法
    
    /// 移除行内注释（# 之后的内容）
    private static func removeInlineComments(_ commandLine: String) -> String {
        if let hashIndex = commandLine.firstIndex(of: "#") {
            return String(commandLine[..<hashIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return commandLine
    }
    
    /// 移除值的引号包装
    private static func unquoteValue(_ value: String) -> String {
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            let unquoted = String(value.dropFirst().dropLast())
            return unquoted.replacingOccurrences(of: "\\\"", with: "\"")
        }
        return value
    }
    
    /// 解析标签类型和可能的展示名
    /// 输入: "a[展示名]" 或 "a"
    /// 输出: (tagCode: "a", displayName: "展示名") 或 (tagCode: "a", displayName: nil)
    private static func parseTagTypeWithDisplayName(_ typeString: String) -> (tagCode: String, displayName: String?) {
        let regex = try! NSRegularExpression(pattern: "^([A-Za-z]\\w*)(?:\\[(.+?)\\])?$", options: [])
        let range = NSRange(typeString.startIndex..., in: typeString)
        
        if let match = regex.firstMatch(in: typeString, options: [], range: range) {
            let tagCodeRange = match.range(at: 1)
            let displayNameRange = match.range(at: 2)
            
            let tagCode = String(typeString[Range(tagCodeRange, in: typeString)!])
            
            var displayName: String?
            if displayNameRange.location != NSNotFound {
                displayName = String(typeString[Range(displayNameRange, in: typeString)!])
            }
            
            return (tagCode: tagCode, displayName: displayName)
        }
        
        // 如果正则匹配失败，直接返回原字符串作为tagCode
        return (tagCode: typeString, displayName: nil)
    }
    
    /// 更新标签类型的全局展示名
    private static func updateTagDisplayName(tagCode: String, displayName: String) {
        print("🏷️ 更新标签类型展示名: \(tagCode) -> \(displayName)")
        
        Task { @MainActor in
            let tagManager = TagMappingManager.shared
            let normalizedKey = tagCode.lowercased() // 确保与TagMappingManager的key规范化一致
            
            // 查找现有映射（使用规范化的key）
            if let existingMapping = tagManager.tagMappings.first(where: { $0.key == normalizedKey }) {
                // 更新现有映射
                let updatedMapping = TagMapping(id: existingMapping.id, key: normalizedKey, typeName: displayName)
                tagManager.updateMapping(updatedMapping)
                print("✅ 已更新标签映射: \(normalizedKey) = \(displayName)")
            } else {
                // 创建新映射
                let newMapping = TagMapping(key: normalizedKey, typeName: displayName)
                tagManager.addMapping(newMapping)
                print("✅ 已创建标签映射: \(normalizedKey) = \(displayName)")
            }
            
            print("🔄 TagMappingManager将自动触发UI更新")
        }
    }
    
    /// 计算从当前节点到新命令的Diff
    public static func calculateCommandDiff(from originalNode: Node, to commandLine: String) -> CommandDiff {
        guard let newNode = Node.fromCommandLine(commandLine, layerId: originalNode.layerId) else {
            // 如果解析失败，返回空的diff
            return CommandDiff(updatedClasses: [], added: [], removed: [], unchanged: [])
        }
        
        let originalTags = Set(originalNode.tags)
        let newTags = Set(newNode.tags)
        
        let added = Array(newTags.subtracting(originalTags))
        let removed = Array(originalTags.subtracting(newTags))
        let unchanged = Array(originalTags.intersection(newTags))
        
        // 检查标签类型更新（这是一个简化版本，实际实现可能需要更复杂的逻辑）
        let updatedClasses: [CommandDiff.TagTypeUpdate] = []
        
        return CommandDiff(
            updatedClasses: updatedClasses,
            added: added.sorted { $0.type.rawValue < $1.type.rawValue },
            removed: removed.sorted { $0.type.rawValue < $1.type.rawValue },
            unchanged: unchanged.sorted { $0.type.rawValue < $1.type.rawValue }
        )
    }
}

public struct Tag: Identifiable, Hashable, Codable {
    public enum TagType: Codable, Hashable {
        case location
        case custom(String)
        
        public var rawValue: String {
            switch self {
            case .location: return "location"
            case .custom(let name): return name
            }
        }
        
        public var displayName: String {
            switch self {
            case .location: 
                return "地点"
            case .custom(let key): 
                // 从TagMappingManager获取最新的typeName
                let tagManager = TagMappingManager.shared
                let normalizedKey = key.lowercased() // 使用规范化的key进行查找
                
                if let mapping = tagManager.tagMappings.first(where: { $0.key == normalizedKey }) {
                    return mapping.typeName
                } else {
                    return key // fallback to key if not found
                }
            }
        }
        
        public var color: String {
            switch self {
            case .location: return "red"
            case .custom: return "purple"
            }
        }
        
        public static let predefinedCases: [TagType] = [.location]
        
        public static var allCases: [TagType] {
            return predefinedCases
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            
            switch value {
            case "location":
                self = .location
            default:
                if value.hasPrefix("custom_") {
                    // 向后兼容：移除custom_前缀
                    let customName = String(value.dropFirst(7))
                    self = .custom(customName)
                } else {
                    self = .custom(value)
                }
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            // 确保编码时不包含custom_前缀
            let encodingValue: String
            switch self {
            case .location:
                encodingValue = "location"
            case .custom(let name):
                // 确保移除任何可能存在的custom_前缀
                if name.hasPrefix("custom_") {
                    encodingValue = String(name.dropFirst(7))
                } else {
                    encodingValue = name
                }
            }
            try container.encode(encodingValue)
        }
    }
    
    public let id: UUID
    public var type: TagType
    public var value: String
    public var latitude: Double?
    public var longitude: Double?
    public var createdAt: Date
    public var isShortcutType: Bool // 标记是否来自快捷键格式 (tagType[displayName])
    
    public init(type: TagType, value: String, latitude: Double? = nil, longitude: Double? = nil, isShortcutType: Bool = false) {
        self.id = UUID()
        self.type = type
        self.value = value
        self.latitude = latitude
        self.longitude = longitude
        self.isShortcutType = isShortcutType
        self.createdAt = Date()
    }
    
    // 自定义解码器，确保向后兼容现有数据
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(TagType.self, forKey: .type)
        value = try container.decode(String.self, forKey: .value)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // 为新字段提供默认值，确保向后兼容
        isShortcutType = try container.decodeIfPresent(Bool.self, forKey: .isShortcutType) ?? false
    }
    
    // 编码键
    private enum CodingKeys: String, CodingKey {
        case id, type, value, latitude, longitude, createdAt, isShortcutType
    }
    
    // 是否为地点标签且有坐标
    public var hasCoordinates: Bool {
        return isLocationTag() && latitude != nil && longitude != nil
    }
    
    // 检查是否是地图/位置标签
    private func isLocationTag() -> Bool {
        if case .custom(let key) = type {
            let locationKeys = ["loc", "location", "地点", "位置"]
            return locationKeys.contains(key.lowercased())
        }
        return false
    }
    
    // 显示名称：直接返回完整的标签值，不进行任何解析
    public var displayName: String {
        return value
    }
    
    // 原始名称：不包含[]的完整值
    public var originalName: String {
        if let startIndex = value.firstIndex(of: "["),
           let endIndex = value.firstIndex(of: "]"),
           startIndex < endIndex {
            return String(value[..<startIndex])
        }
        return value
    }
    
    // MARK: - Hashable Implementation
    public static func == (lhs: Tag, rhs: Tag) -> Bool {
        return lhs.type == rhs.type && lhs.value == rhs.value
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(value)
    }
}


// MARK: - 命令Diff相关模型

public struct CommandDiff {
    public let updatedClasses: [TagTypeUpdate]
    public let added: [Tag]
    public let removed: [Tag]
    public let unchanged: [Tag]
    
    public struct TagTypeUpdate {
        public let code: String
        public let oldDisplayName: String?
        public let newDisplayName: String
    }
    
    public init(updatedClasses: [TagTypeUpdate], added: [Tag], removed: [Tag], unchanged: [Tag]) {
        self.updatedClasses = updatedClasses
        self.added = added
        self.removed = removed
        self.unchanged = unchanged
    }
    
    public var hasChanges: Bool {
        return !updatedClasses.isEmpty || !added.isEmpty || !removed.isEmpty
    }
}

// MARK: - 搜索相关模型

public struct SearchFilter {
    public var tagType: Tag.TagType?
    public var hasLocation: Bool?
    
    public init(tagType: Tag.TagType? = nil, hasLocation: Bool? = nil) {
        self.tagType = tagType
        self.hasLocation = hasLocation
    }
}

public struct SearchResult: Equatable {
    public let node: Node
    public let score: Double
    public let matchedFields: Set<MatchField>
    
    public enum MatchField: Equatable {
        case text, phonetic, meaning, tagValue, markdown
    }
    
    public init(node: Node, score: Double, matchedFields: Set<MatchField>) {
        self.node = node
        self.score = score
        self.matchedFields = matchedFields
    }
}

// MARK: - 批量操作相关模型

/// 批量删除操作结果
public struct BatchDeleteResult {
    public let affectedNodeCount: Int
    public let deletedTagCount: Int
    public let affectedNodes: [Node]
    
    public init(affectedNodeCount: Int, deletedTagCount: Int, affectedNodes: [Node]) {
        self.affectedNodeCount = affectedNodeCount
        self.deletedTagCount = deletedTagCount
        self.affectedNodes = affectedNodes
    }
}

/// 标签使用信息
public struct TagUsageInfo {
    public let tagType: Tag.TagType
    public let tagValue: String
    public var nodeCount: Int
    public var nodes: [Node]
    
    public init(tagType: Tag.TagType, tagValue: String, nodeCount: Int, nodes: [Node]) {
        self.tagType = tagType
        self.tagValue = tagValue
        self.nodeCount = nodeCount
        self.nodes = nodes
    }
    
    /// 创建一个用于显示的标签
    public var displayTag: Tag {
        return Tag(type: tagType, value: tagValue, latitude: nil, longitude: nil, isShortcutType: false)
    }
}

/// 标签批量操作模式
public enum TagBatchMode {
    case deleteByType           // 按标签类型删除
    case deleteSpecificTags     // 删除具体标签
    case deleteUnusedMappings   // 删除未使用的标签映射
}

/// 标签选择项（用于批量操作界面）
public struct TagSelectionItem: Identifiable, Hashable {
    public let id = UUID()
    public let tagType: Tag.TagType
    public let tagValue: String?  // nil表示选择整个类型
    public let nodeCount: Int
    public var isSelected: Bool = false
    
    public init(tagType: Tag.TagType, tagValue: String? = nil, nodeCount: Int, isSelected: Bool = false) {
        self.tagType = tagType
        self.tagValue = tagValue
        self.nodeCount = nodeCount
        self.isSelected = isSelected
    }
    
    /// 显示文本
    public var displayText: String {
        if let value = tagValue {
            return "\(tagType.displayName): \(value)"
        } else {
            return "\(tagType.displayName) (所有标签)"
        }
    }
    
    /// 是否为标签类型选择（而非具体标签）
    public var isTypeSelection: Bool {
        return tagValue == nil
    }
}