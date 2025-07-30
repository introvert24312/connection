import Foundation

public struct Tag: Identifiable, Hashable, Codable {
    public enum TagType: Codable, Hashable {
        case memory
        case location
        case root
        case shape
        case sound
        case custom(String)
        
        public var rawValue: String {
            switch self {
            case .memory: return "memory"
            case .location: return "location"
            case .root: return "root"
            case .shape: return "shape"
            case .sound: return "sound"
            case .custom(let name): return "custom_\(name)"
            }
        }
        
        public var displayName: String {
            switch self {
            case .memory: return "记忆"
            case .location: return "地点"
            case .root: return "词根"
            case .shape: return "形近"
            case .sound: return "音近"
            case .custom(let name): return name
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
        
        public static let predefinedCases: [TagType] = [.memory, .location, .root, .shape, .sound]
        
        public static var allCases: [TagType] {
            return predefinedCases
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            
            switch value {
            case "memory":
                self = .memory
            case "location":
                self = .location
            case "root":
                self = .root
            case "shape":
                self = .shape
            case "sound":
                self = .sound
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
        return type == .location && latitude != nil && longitude != nil
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