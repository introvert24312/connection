import Combine
import Foundation

public final class WordStore: ObservableObject {
    @Published public private(set) var words: [Word] = []
    @Published public private(set) var selectedWord: Word?
    @Published public private(set) var selectedTag: Tag?
    @Published public var searchQuery: String = ""
    @Published public private(set) var searchResults: [SearchResult] = []
    @Published public private(set) var isLoading: Bool = false
    
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
}