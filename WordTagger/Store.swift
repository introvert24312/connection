import Combine
import Foundation
import AppKit

// MARK: - 导入导出辅助类型

public struct ImportValidationResult {
    public let validWords: [Word]
    public let warnings: [String]
    public let originalCount: Int
    public let validCount: Int
    
    public var hasWarnings: Bool {
        return !warnings.isEmpty
    }
    
    public var isValid: Bool {
        return validCount > 0
    }
}

public struct ExportSummary {
    public let totalWords: Int
    public let totalTags: Int
    public let uniqueTags: Int
    public let tagTypeCounts: [Tag.TagType: Int]
    public let wordsWithLocation: Int
}

public struct WordTaggerExportData: Codable {
    let version: String
    let exportDate: Date
    let words: [Word]
    let metadata: ExportMetadata
    
    struct ExportMetadata: Codable {
        let totalWords: Int
        let totalTags: Int
        let uniqueTags: Int
        let appVersion: String
        
        init(words: [Word]) {
            self.totalWords = words.count
            self.totalTags = words.flatMap { $0.tags }.count
            self.uniqueTags = Set(words.flatMap { $0.tags }).count
            self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        }
    }
    
    init(words: [Word]) {
        self.version = "1.0"
        self.exportDate = Date()
        self.words = words
        self.metadata = ExportMetadata(words: words)
    }
}

enum DataError: LocalizedError {
    case userCancelled
    case invalidFormat
    case fileNotFound
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "用户取消了操作"
        case .invalidFormat:
            return "文件格式无效，请确保这是一个有效的WordTagger数据文件"
        case .fileNotFound:
            return "找不到指定的文件"
        case .permissionDenied:
            return "没有权限访问该文件"
        }
    }
}

public final class WordStore: ObservableObject {
    @Published public private(set) var words: [Word] = []
    @Published public private(set) var selectedWord: Word?
    @Published public private(set) var selectedTag: Tag?
    @Published public var searchQuery: String = ""
    @Published public private(set) var searchResults: [SearchResult] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isExporting: Bool = false
    @Published public private(set) var isImporting: Bool = false
    
    private let searchThreshold: Double = 0.3
    private var cancellables = Set<AnyCancellable>()
    
    public static let shared = WordStore()
    
    private init() {
        setupSearchBinding()
        loadSampleData() // 加载示例数据
    }
    
    // MARK: - 单词管理
    
    public func addWord(_ text: String, phonetic: String? = nil, meaning: String? = nil) {
        let word = Word(text: text, phonetic: phonetic, meaning: meaning)
        words.append(word)
        objectWillChange.send()
    }
    
    public func addWord(_ word: Word) {
        words.append(word)
        objectWillChange.send()
    }
    
    public func updateWord(_ wordId: UUID, text: String? = nil, phonetic: String? = nil, meaning: String? = nil) {
        guard let index = words.firstIndex(where: { $0.id == wordId }) else { return }
        
        if let text = text { words[index].text = text }
        if let phonetic = phonetic { words[index].phonetic = phonetic }
        if let meaning = meaning { words[index].meaning = meaning }
        words[index].updatedAt = Date()
        
        objectWillChange.send()
    }
    
    public func deleteWord(_ wordId: UUID) {
        words.removeAll { $0.id == wordId }
        if selectedWord?.id == wordId {
            selectedWord = nil
        }
        objectWillChange.send()
    }
    
    // MARK: - 标签管理
    
    public func addTag(to wordId: UUID, tag: Tag) {
        guard let index = words.firstIndex(where: { $0.id == wordId }) else { return }
        
        // 避免重复标签
        if !words[index].tags.contains(tag) {
            words[index].tags.append(tag)
            words[index].updatedAt = Date()
            objectWillChange.send()
        }
    }
    
    public func removeTag(from wordId: UUID, tagId: UUID) {
        guard let index = words.firstIndex(where: { $0.id == wordId }) else { return }
        
        words[index].tags.removeAll { $0.id == tagId }
        words[index].updatedAt = Date()
        objectWillChange.send()
    }
    
    public func createTag(type: Tag.TagType, value: String, latitude: Double? = nil, longitude: Double? = nil) -> Tag {
        return Tag(type: type, value: value, latitude: latitude, longitude: longitude)
    }
    
    // MARK: - 位置标签管理
    
    public func getAllLocationTags() -> [Tag] {
        var locationTags: [Tag] = []
        for word in words {
            for tag in word.tags {
                if tag.type == .location && tag.hasCoordinates && !locationTags.contains(where: { $0.value == tag.value }) {
                    locationTags.append(tag)
                }
            }
        }
        return locationTags.sorted { $0.value.localizedCompare($1.value) == .orderedAscending }
    }
    
    public func findLocationTagByName(_ name: String) -> Tag? {
        for word in words {
            for tag in word.tags {
                if tag.type == .location && tag.hasCoordinates && tag.value.localizedCaseInsensitiveContains(name) {
                    return tag
                }
            }
        }
        return nil
    }
    
    // MARK: - 选择管理
    
    public func selectWord(_ word: Word?) {
        selectedWord = word
        objectWillChange.send()
    }
    
    public func selectTag(_ tag: Tag?) {
        selectedTag = tag
        objectWillChange.send()
    }
    
    // MARK: - 搜索功能
    
    private func setupSearchBinding() {
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] query in
                self?.performSearch(query)
            }
            .store(in: &cancellables)
    }
    
    private func performSearch(_ query: String) {
        if query.isEmpty {
            searchResults = []
            return
        }
        
        isLoading = true
        
        // 模拟异步搜索
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = self?.searchWords(query) ?? []
            
            DispatchQueue.main.async {
                self?.searchResults = results
                self?.isLoading = false
            }
        }
    }
    
    private func searchWords(_ query: String) -> [SearchResult] {
        var results: [SearchResult] = []
        
        for word in words {
            var matchedFields: Set<SearchResult.MatchField> = []
            var totalScore: Double = 0
            var matchCount = 0
            
            // 搜索单词文本
            if word.text.localizedCaseInsensitiveContains(query) {
                matchedFields.insert(.text)
                let similarity = word.text.similarity(to: query)
                totalScore += similarity * 2.0 // 文本匹配权重最高
                matchCount += 1
            }
            
            // 搜索音标
            if let phonetic = word.phonetic,
               phonetic.localizedCaseInsensitiveContains(query) {
                matchedFields.insert(.phonetic)
                let similarity = phonetic.similarity(to: query)
                totalScore += similarity * 1.5
                matchCount += 1
            }
            
            // 搜索含义
            if let meaning = word.meaning,
               meaning.localizedCaseInsensitiveContains(query) {
                matchedFields.insert(.meaning)
                let similarity = meaning.similarity(to: query)
                totalScore += similarity * 1.8
                matchCount += 1
            }
            
            // 搜索标签值
            for tag in word.tags {
                if tag.value.localizedCaseInsensitiveContains(query) {
                    matchedFields.insert(.tagValue)
                    let similarity = tag.value.similarity(to: query)
                    totalScore += similarity * 1.2
                    matchCount += 1
                }
            }
            
            if matchCount > 0 {
                let averageScore = totalScore / Double(matchCount)
                results.append(SearchResult(word: word, score: averageScore, matchedFields: matchedFields))
            }
        }
        
        // 按分数排序
        return results.sorted { $0.score > $1.score }
    }
    
    public func search(_ query: String, filter: SearchFilter = SearchFilter()) -> [Word] {
        if query.isEmpty && filter.tagType == nil && filter.hasLocation == nil {
            return words
        }
        
        var filteredWords = words
        
        // 应用过滤器
        if let tagType = filter.tagType {
            filteredWords = filteredWords.filter { word in
                word.tags.contains { $0.type == tagType }
            }
        }
        
        if let hasLocation = filter.hasLocation {
            filteredWords = filteredWords.filter { word in
                let hasLocationTags = !word.locationTags.isEmpty
                return hasLocationTags == hasLocation
            }
        }
        
        // 应用搜索查询
        if !query.isEmpty {
            let searchResults = searchWords(query)
            let resultWordIds = Set(searchResults.map { $0.word.id })
            filteredWords = filteredWords.filter { resultWordIds.contains($0.id) }
        }
        
        return filteredWords
    }
    
    // MARK: - 数据统计
    
    public var allTags: [Tag] {
        return words.flatMap { $0.tags }.unique()
    }
    
    public func words(withTag tag: Tag) -> [Word] {
        return words.filter { $0.hasTag(tag) }
    }
    
    public func wordsCount(forTagType type: Tag.TagType) -> Int {
        return words.filter { word in
            word.tags.contains { $0.type == type }
        }.count
    }
    
    // MARK: - 示例数据
    
    private func loadSampleData() {
        // 创建一些示例标签
        let memoryTag1 = createTag(type: .memory, value: "联想记忆")
        let memoryTag2 = createTag(type: .memory, value: "图像记忆")
        let rootTag1 = createTag(type: .root, value: "spect")
        let rootTag2 = createTag(type: .root, value: "dict")
        let locationTag1 = createTag(type: .location, value: "图书馆", latitude: 39.9042, longitude: 116.4074)
        let locationTag2 = createTag(type: .location, value: "咖啡厅", latitude: 40.7589, longitude: -73.9851)
        
        // 创建示例单词
        let word1 = Word(text: "spectacular", phonetic: "/spekˈtækjələr/", meaning: "壮观的，惊人的")
        words.append(word1)
        addTag(to: word1.id, tag: rootTag1)
        addTag(to: word1.id, tag: memoryTag1)
        addTag(to: word1.id, tag: locationTag1)
        
        let word2 = Word(text: "dictionary", phonetic: "/ˈdɪkʃəneri/", meaning: "字典")
        words.append(word2)
        addTag(to: word2.id, tag: rootTag2)
        addTag(to: word2.id, tag: memoryTag2)
        addTag(to: word2.id, tag: locationTag2)
        
        let word3 = Word(text: "perspective", phonetic: "/pərˈspektɪv/", meaning: "观点，视角")
        words.append(word3)
        addTag(to: word3.id, tag: rootTag1)
        addTag(to: word3.id, tag: memoryTag1)
        
        let word4 = Word(text: "predict", phonetic: "/prɪˈdɪkt/", meaning: "预测")
        words.append(word4)
        addTag(to: word4.id, tag: rootTag2)
        addTag(to: word4.id, tag: memoryTag2)
    }
    
    // MARK: - 数据导入导出
    
    public func exportData(completion: @escaping (Bool, String?) -> Void) {
        isExporting = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let exportData = WordTaggerExportData(words: self.words)
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                encoder.dateEncodingStrategy = .iso8601
                let jsonData = try encoder.encode(exportData)
                
                // 创建临时文件
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let dateString = dateFormatter.string(from: Date())
                let fileName = "WordTagger_Export_\(dateString).json"
                
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try jsonData.write(to: tempURL)
                
                DispatchQueue.main.async {
                    self.showSavePanel(for: tempURL, completion: completion)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isExporting = false
                    completion(false, "导出失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showSavePanel(for tempURL: URL, completion: @escaping (Bool, String?) -> Void) {
        let savePanel = NSSavePanel()
        savePanel.title = "导出单词数据"
        savePanel.message = "选择保存位置"
        savePanel.nameFieldStringValue = tempURL.lastPathComponent
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        
        savePanel.begin { [weak self] response in
            self?.isExporting = false
            
            if response == .OK, let url = savePanel.url {
                do {
                    // 如果目标文件已存在，删除它
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    
                    // 移动临时文件到目标位置
                    try FileManager.default.moveItem(at: tempURL, to: url)
                    completion(true, "数据导出成功！")
                } catch {
                    completion(false, "保存文件失败: \(error.localizedDescription)")
                }
            } else {
                // 清理临时文件
                try? FileManager.default.removeItem(at: tempURL)
                completion(false, "导出已取消")
            }
        }
    }
    
    public func importData(replaceExisting: Bool = false, completion: @escaping (Bool, String?, ImportValidationResult?) -> Void) {
        isImporting = true
        
        let openPanel = NSOpenPanel()
        openPanel.title = "导入单词数据"
        openPanel.message = "选择要导入的JSON文件"
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        openPanel.begin { [weak self] response in
            if response == .OK, let url = openPanel.url {
                self?.performImport(from: url, replaceExisting: replaceExisting, completion: completion)
            } else {
                DispatchQueue.main.async {
                    self?.isImporting = false
                    completion(false, "导入已取消", nil)
                }
            }
        }
    }
    
    private func performImport(from url: URL, replaceExisting: Bool, completion: @escaping (Bool, String?, ImportValidationResult?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let jsonData = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                var importedWords: [Word] = []
                
                // 尝试解析为完整的WordTaggerExportData格式
                if let exportData = try? decoder.decode(WordTaggerExportData.self, from: jsonData) {
                    importedWords = exportData.words
                } else if let words = try? decoder.decode([Word].self, from: jsonData) {
                    // 向后兼容：直接解析为Word数组
                    importedWords = words
                } else {
                    DispatchQueue.main.async {
                        self?.isImporting = false
                        completion(false, "文件格式无效，请确保这是一个有效的WordTagger数据文件", nil)
                    }
                    return
                }
                
                let validationResult = self?.validateImportedData(importedWords)
                
                guard let validationResult = validationResult, validationResult.isValid else {
                    DispatchQueue.main.async {
                        self?.isImporting = false
                        completion(false, "导入的数据无效或为空", validationResult)
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    if replaceExisting {
                        self?.words = validationResult.validWords
                    } else {
                        // 合并数据，避免重复
                        let existingTexts = Set(self?.words.map { $0.text.lowercased() } ?? [])
                        let newWords = validationResult.validWords.filter { word in
                            !existingTexts.contains(word.text.lowercased())
                        }
                        self?.words.append(contentsOf: newWords)
                    }
                    
                    self?.isImporting = false
                    self?.objectWillChange.send()
                    
                    let message = replaceExisting ? 
                        "成功导入 \(validationResult.validCount) 个单词，已替换原有数据" :
                        "成功导入 \(validationResult.validCount) 个单词"
                    
                    completion(true, message, validationResult)
                }
                
            } catch {
                DispatchQueue.main.async {
                    self?.isImporting = false
                    completion(false, "导入失败: \(error.localizedDescription)", nil)
                }
            }
        }
    }
    
    private func validateImportedData(_ words: [Word]) -> ImportValidationResult {
        var warnings: [String] = []
        var validWords: [Word] = []
        var duplicateCount = 0
        
        for word in words {
            // 检查必要字段
            if word.text.isEmpty {
                warnings.append("发现空单词文本，已跳过")
                continue
            }
            
            // 检查重复
            if validWords.contains(where: { $0.text.lowercased() == word.text.lowercased() }) {
                duplicateCount += 1
                continue
            }
            
            validWords.append(word)
        }
        
        if duplicateCount > 0 {
            warnings.append("跳过了 \(duplicateCount) 个重复单词")
        }
        
        return ImportValidationResult(
            validWords: validWords,
            warnings: warnings,
            originalCount: words.count,
            validCount: validWords.count
        )
    }
    
    public func clearAllData() {
        words.removeAll()
        selectedWord = nil
        selectedTag = nil
        searchQuery = ""
        searchResults.removeAll()
        objectWillChange.send()
    }
    
    public func getExportSummary() -> ExportSummary {
        let totalTags = words.flatMap { $0.tags }.count
        let uniqueTags = Set(words.flatMap { $0.tags }).count
        let tagTypes = Dictionary(grouping: words.flatMap { $0.tags }) { $0.type }
        
        var tagTypeCounts: [Tag.TagType: Int] = [:]
        for type in Tag.TagType.allCases {
            tagTypeCounts[type] = tagTypes[type]?.count ?? 0
        }
        
        return ExportSummary(
            totalWords: words.count,
            totalTags: totalTags,
            uniqueTags: uniqueTags,
            tagTypeCounts: tagTypeCounts,
            wordsWithLocation: words.filter { !$0.locationTags.isEmpty }.count
        )
    }
}
