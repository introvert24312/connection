import Foundation

// MARK: - 分层系统模型

public struct Layer: Identifiable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var displayName: String
    public var color: String
    public var isActive: Bool
    public var createdAt: Date
    
    public init(name: String, displayName: String, color: String = "blue") {
        self.id = UUID()
        self.name = name
        self.displayName = displayName
        self.color = color
        self.isActive = false
        self.createdAt = Date()
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
    
    // 自定义解码器，确保向后兼容现有数据
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic)
        meaning = try container.decodeIfPresent(String.self, forKey: .meaning)
        layerId = try container.decode(UUID.self, forKey: .layerId)
        tags = try container.decode([Tag].self, forKey: .tags)
        isCompound = try container.decode(Bool.self, forKey: .isCompound)
        // 为markdown字段提供默认值，确保向后兼容
        markdown = try container.decodeIfPresent(String.self, forKey: .markdown) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
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
    
    public static func == (lhs: Node, rhs: Node) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct Tag: Identifiable, Hashable, Codable {
    public enum TagType: Codable, Hashable {
        case location
        case root
        case custom(String)
        
        public var rawValue: String {
            switch self {
            case .location: return "location"
            case .root: return "root"
            case .custom(let name): return "custom_\(name)"
            }
        }
        
        public var displayName: String {
            switch self {
            case .location: return "地点"
            case .root: return "词根"
            case .custom(let key): 
                // 从TagMappingManager获取最新的typeName
                let tagManager = TagMappingManager.shared
                if let mapping = tagManager.tagMappings.first(where: { $0.key == key }) {
                    return mapping.typeName
                }
                return key // fallback to key if not found
            }
        }
        
        public var color: String {
            switch self {
            case .location: return "red"
            case .root: return "blue"
            case .custom: return "purple"
            }
        }
        
        public static let predefinedCases: [TagType] = [.location, .root]
        
        public static var allCases: [TagType] {
            return predefinedCases
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            
            switch value {
            case "location":
                self = .location
            case "root":
                self = .root
            default:
                if value.hasPrefix("custom_") {
                    let customName = String(value.dropFirst(7))
                    self = .custom(customName)
                } else {
                    self = .custom(value)
                }
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }
    
    public let id: UUID
    public var type: TagType
    public var value: String
    public var latitude: Double?
    public var longitude: Double?
    public var createdAt: Date
    
    public init(type: TagType, value: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.id = UUID()
        self.type = type
        self.value = value
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = Date()
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
    
    // 显示名称：如果value包含[显示名]格式，则返回[]内的内容，否则返回原value
    public var displayName: String {
        if let startIndex = value.firstIndex(of: "["),
           let endIndex = value.firstIndex(of: "]"),
           startIndex < endIndex {
            let displayName = String(value[value.index(after: startIndex)..<endIndex])
            return displayName.isEmpty ? value : displayName
        }
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
        case text, phonetic, meaning, tagValue
    }
    
    public init(node: Node, score: Double, matchedFields: Set<MatchField>) {
        self.node = node
        self.score = score
        self.matchedFields = matchedFields
    }
    
}