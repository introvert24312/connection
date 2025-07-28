import Foundation

public struct Tag: Identifiable, Hashable, Codable {
    public enum TagType: String, Codable, CaseIterable {
        case memory = "memory"
        case location = "location"
        case root = "root"
        case shape = "shape"
        case sound = "sound"
        case custom = "custom"
        
        public var displayName: String {
            switch self {
            case .memory: return "记忆"
            case .location: return "地点"
            case .root: return "词根"
            case .shape: return "形近"
            case .sound: return "音近"
            case .custom: return "自定义"
            }
        }
        
        public var color: String {
            switch self {
            case .memory: return "pink"
            case .location: return "red"
            case .root: return "blue"
            case .shape: return "green"
            case .sound: return "orange"
            case .custom: return "purple"
            }
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
        return type == .location && latitude != nil && longitude != nil
    }
}

public struct Word: Identifiable, Hashable, Codable {
    public let id: UUID
    public var text: String
    public var phonetic: String?
    public var meaning: String?
    public var tags: [Tag]
    public var createdAt: Date
    public var updatedAt: Date
    
    public init(text: String, phonetic: String? = nil, meaning: String? = nil, tags: [Tag] = []) {
        self.id = UUID()
        self.text = text
        self.phonetic = phonetic
        self.meaning = meaning
        self.tags = tags
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // 获取特定类型的标签
    public func tags(of type: Tag.TagType) -> [Tag] {
        return tags.filter { $0.type == type }
    }
    
    // 是否包含特定标签
    public func hasTag(_ tag: Tag) -> Bool {
        return tags.contains(tag)
    }
    
    // 地点标签（有坐标的）
    public var locationTags: [Tag] {
        return tags.filter { $0.hasCoordinates }
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

public struct SearchResult {
    public let word: Word
    public let score: Double
    public let matchedFields: Set<MatchField>
    
    public enum MatchField {
        case text, phonetic, meaning, tagValue
    }
    
    public init(word: Word, score: Double, matchedFields: Set<MatchField>) {
        self.word = word
        self.score = score
        self.matchedFields = matchedFields
    }
}