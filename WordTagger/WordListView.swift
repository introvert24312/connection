import SwiftUI
import CoreLocation
import MapKit

struct WordListView: View {
    @EnvironmentObject private var store: WordStore
    @Binding var selectedWord: Word?
    @State private var searchFilter = SearchFilter()
    @State private var sortOption: SortOption = .alphabetical
    @State private var selectedIndex: Int = 0
    @FocusState private var isListFocused: Bool
    @FocusState private var isSearchFieldFocused: Bool
    @State private var localSearchQuery: String = ""
    
    // 缓存机制，避免列表频繁重新渲染
    @State private var cachedDisplayWords: [Word] = []
    @State private var lastSearchQuery: String = ""
    @State private var lastSelectedTag: Tag? = nil
    @State private var lastSortOption: SortOption = .alphabetical
    @State private var updateTask: Task<Void, Never>?
    
    enum SortOption: String, CaseIterable {
        case alphabetical = "字母顺序"
        case tagCount = "标签数量"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 头部工具栏
            VStack(alignment: .leading, spacing: 12) {
                // 搜索栏
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("搜索单词、音标、含义...", text: $localSearchQuery)
                        .textFieldStyle(.plain)
                        .focused($isSearchFieldFocused)
                        .onSubmit {
                            // 搜索提交时的处理
                        }
                        .onChange(of: localSearchQuery) { oldValue, newValue in
                            handleSearchQueryChange(newValue)
                        }
                    
                    if !localSearchQuery.isEmpty {
                        Button(action: clearSearch) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                
                // 筛选和排序选项
                HStack {
                    Menu {
                        Button("全部标签") { searchFilter.tagType = nil }
                        Divider()
                        ForEach(Tag.TagType.allCases, id: \.self) { type in
                            Button(type.displayName) { searchFilter.tagType = type }
                        }
                    } label: {
                        HStack {
                            Text(searchFilter.tagType?.displayName ?? "全部标签")
                            Image(systemName: "chevron.down")
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    Menu {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Button(option.rawValue) { sortOption = option }
                        }
                    } label: {
                        HStack {
                            Text("排序: \(sortOption.rawValue)")
                            Image(systemName: "chevron.down")
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    Spacer()
                    
                    // 单词数量显示
                    Text("\(displayWords.count) 个单词")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 单词列表
            if store.isLoading {
                VStack {
                    Spacer()
                    ProgressView("搜索中...")
                        .scaleEffect(1.2)
                    Spacer()
                }
            } else if displayWords.isEmpty {
                EmptyStateView()
            } else {
                ScrollViewReader { proxy in
                    List(Array(displayWords.enumerated()), id: \.element.id) { index, word in
                        WordRowView(
                            word: word,
                            isSelected: selectedWord?.id == word.id || index == selectedIndex,
                            searchQuery: store.searchQuery
                        ) {
                            selectedWord = word
                            store.selectWord(word)
                            selectedIndex = index
                        }
                        .id(word.id)
                    }
                    .listStyle(.plain)
                    .focused($isListFocused)
                    .onKeyPress(.upArrow) {
                        if selectedIndex > 0 {
                            selectedIndex -= 1
                            selectWordAtIndex()
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(selectedIndex, anchor: .center)
                            }
                        }
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        if selectedIndex < displayWords.count - 1 {
                            selectedIndex += 1
                            selectWordAtIndex()
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(selectedIndex, anchor: .center)
                            }
                        }
                        return .handled
                    }
                    .onKeyPress(.return) {
                        selectWordAtIndex()
                        return .handled
                    }
                    .onChange(of: displayWords) { _, _ in
                        selectedIndex = min(selectedIndex, max(0, displayWords.count - 1))
                    }
                    .onAppear {
                        isListFocused = true
                        // 初始化时更新缓存
                        if cachedDisplayWords.isEmpty {
                            updateCachedDisplayWords()
                        }
                    }
                }
            }
        }
        .navigationTitle("单词")
        .onAppear {
            setupView()
        }
        .onChange(of: store.searchQuery, perform: handleStoreSearchQueryChange)
        .onChange(of: store.searchResults, perform: handleSearchResultsChange)
        .onChange(of: store.selectedTag?.id, perform: handleSelectedTagChange)
        .onChange(of: sortOption, perform: handleSortOptionChange)
    }
    
    private var displayWords: [Word] {
        return cachedDisplayWords
    }
    
    private func scheduleUpdate() {
        print("⏰ WordListView.scheduleUpdate called")
        
        // 取消之前的更新任务
        updateTask?.cancel()
        
        // 检查是否有实际变化
        let hasSearchQueryChange = lastSearchQuery != store.searchQuery
        let hasSelectedTagChange = lastSelectedTag?.id != store.selectedTag?.id
        let hasSortOptionChange = lastSortOption != sortOption
        
        print("🔄 Changes detected - searchQuery: \(hasSearchQueryChange), selectedTag: \(hasSelectedTagChange), sortOption: \(hasSortOptionChange)")
        print("🔄 Current state - searchQuery: '\(store.searchQuery)', lastSearchQuery: '\(lastSearchQuery)'")
        
        // 如果没有任何变化，不需要更新
        guard hasSearchQueryChange || hasSelectedTagChange || hasSortOptionChange else {
            print("⏭️ No changes detected, skipping update")
            return
        }
        
        // 立即更新，因为Store已经处理了防抖
        print("🔧 Executing immediate updateCachedDisplayWords")
        updateCachedDisplayWords()
    }
    
    private func updateCachedDisplayWords() {
        print("🔄 updateCachedDisplayWords started")
        print("📊 Current store state - searchQuery: '\(store.searchQuery)', searchResults count: \(store.searchResults.count)")
        
        let filteredWords: [Word]
        
        if !store.searchQuery.isEmpty {
            // 使用搜索结果，但同时考虑selectedTag过滤
            let searchResults = store.searchResults.map { $0.word }
            if let selectedTag = store.selectedTag {
                filteredWords = searchResults.filter { $0.hasTag(selectedTag) }
                print("🔍 Using search results filtered by tag: \(filteredWords.count) words")
            } else {
                filteredWords = searchResults
                print("🔍 Using search results: \(filteredWords.count) words")
            }
        } else if let selectedTag = store.selectedTag {
            // 如果选中了标签，只显示包含该标签的单词
            filteredWords = store.words(withTag: selectedTag)
            print("🏷️ Using tag filter: \(filteredWords.count) words")
        } else {
            // 应用过滤器
            filteredWords = store.search("", filter: searchFilter)
            print("📋 Using all words with filter: \(filteredWords.count) words")
        }
        
        // 应用排序并更新缓存
        let oldCount = cachedDisplayWords.count
        cachedDisplayWords = sortWords(filteredWords)
        let newCount = cachedDisplayWords.count
        
        print("✅ Cache updated: \(oldCount) → \(newCount) words")
        
        // 更新缓存状态
        lastSearchQuery = store.searchQuery
        lastSelectedTag = store.selectedTag
        lastSortOption = sortOption
        
        print("💾 Cache state updated - lastSearchQuery: '\(lastSearchQuery)'")
    }
    
    private func handleSearchQueryChange(_ newValue: String) {
        // 保持焦点在输入框
        DispatchQueue.main.async {
            isSearchFieldFocused = true
        }
        store.searchQuery = newValue
    }
    
    private func clearSearch() {
        localSearchQuery = ""
        store.searchQuery = ""
        // 保持焦点在输入框
        DispatchQueue.main.async {
            isSearchFieldFocused = true
        }
    }
    
    private func setupView() {
        // 初始化时同步搜索查询和设置焦点
        localSearchQuery = store.searchQuery
        isSearchFieldFocused = true
    }
    
    private func handleStoreSearchQueryChange(_ newValue: String) {
        print("🔍 WordListView: searchQuery changed to '\(newValue)'")
        scheduleUpdate()
        
        // 同步store的搜索查询到本地变量（避免删除键问题）
        if localSearchQuery != newValue {
            localSearchQuery = newValue
        }
    }
    
    private func handleSearchResultsChange(_ newValue: [SearchResult]) {
        print("📊 WordListView: searchResults changed to \(newValue.count) items")
        // 当搜索结果更新时，立即更新显示
        scheduleUpdate()
    }
    
    private func handleSelectedTagChange(_ newValue: UUID?) {
        let newStr = newValue?.uuidString ?? "nil"
        print("🏷️ WordListView: selectedTag changed to '\(newStr)'")
        scheduleUpdate()
    }
    
    private func handleSortOptionChange(_ newValue: SortOption) {
        print("📊 WordListView: sortOption changed to '\(newValue)'")
        scheduleUpdate()
    }
    
    private func sortWords(_ words: [Word]) -> [Word] {
        switch sortOption {
        case .alphabetical:
            return words.sorted { $0.text.lowercased() < $1.text.lowercased() }
        case .tagCount:
            return words.sorted { $0.tags.count > $1.tags.count }
        }
    }
    
    private func selectWordAtIndex() {
        guard selectedIndex < displayWords.count else { return }
        let word = displayWords[selectedIndex]
        selectedWord = word
        store.selectWord(word)
    }
    
}

// MARK: - 单词行视图

struct WordRowView: View {
    let word: Word
    let isSelected: Bool
    let searchQuery: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // 单词文本
                    HighlightedText(
                        text: word.text,
                        searchQuery: searchQuery,
                        font: .title2,
                        fontWeight: .semibold
                    )
                    
                    Spacer()
                    
                    // 音标
                    if let phonetic = word.phonetic {
                        Text(phonetic)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.1))
                            )
                    }
                }
                
                // 含义
                if let meaning = word.meaning {
                    HighlightedText(
                        text: meaning,
                        searchQuery: searchQuery,
                        font: .title3,
                        fontWeight: .regular
                    )
                    .foregroundColor(.secondary)
                }
                
                // 标签
                if !word.tags.isEmpty {
                    TagChipsView(tags: word.tags, searchQuery: searchQuery)
                }
                
                // 元数据
                HStack {
                    Text(word.createdAt.timeAgoDisplay())
                        .font(.caption2)
                        .foregroundColor(Color.secondary)
                    
                    Spacer()
                    
                    if word.updatedAt > word.createdAt {
                        Text("已编辑")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.15) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - 高亮文本

struct HighlightedText: View {
    let text: String
    let searchQuery: String
    let font: Font
    let fontWeight: Font.Weight
    
    var body: some View {
        if searchQuery.isEmpty {
            Text(text)
                .font(font)
                .fontWeight(fontWeight)
        } else {
            Text(highlightedAttributedString())
                .font(font)
                .fontWeight(fontWeight)
        }
    }
    
    private func highlightedAttributedString() -> AttributedString {
        var attributedString = AttributedString(text)
        
        if let range = text.range(of: searchQuery, options: .caseInsensitive) {
            let startIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: text.distance(from: text.startIndex, to: range.lowerBound))
            let endIndex = attributedString.index(startIndex, offsetByCharacters: searchQuery.count)
            
            attributedString[startIndex..<endIndex].backgroundColor = .yellow.opacity(0.3)
            attributedString[startIndex..<endIndex].foregroundColor = .primary
        }
        
        return attributedString
    }
}

// MARK: - 标签芯片视图

struct TagChipsView: View {
    let tags: [Tag]
    let searchQuery: String
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 120), spacing: 6)
        ], spacing: 6) {
            ForEach(tags.prefix(6), id: \.id) { tag in
                TagChip(tag: tag, searchQuery: searchQuery)
            }
            
            if tags.count > 6 {
                Text("+\(tags.count - 6)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.1))
                    )
            }
        }
    }
}

struct TagChip: View {
    let tag: Tag
    let searchQuery: String
    @State private var isHovered = false
    
    init(tag: Tag, searchQuery: String = "") {
        self.tag = tag
        self.searchQuery = searchQuery
    }
    
    var body: some View {
        Button(action: {
            // 标签点击行为 - 可以添加选择/过滤逻辑
        }) {
            HStack(spacing: 6) {
                // 更大的类型指示器
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.from(tagType: tag.type))
                    .frame(width: 3, height: 16)
                
                if searchQuery.isEmpty {
                    Text(tag.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)
                } else {
                    HighlightedText(
                        text: tag.displayName,
                        searchQuery: searchQuery,
                        font: .body,
                        fontWeight: .medium
                    )
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.primary)
                }
                
                // 添加标签类型指示
                Text("•")
                    .font(.caption2)
                    .foregroundColor(Color.from(tagType: tag.type))
                
                Text(tag.type.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isHovered ? 
                        Color.from(tagType: tag.type).opacity(0.2) :
                        Color.from(tagType: tag.type).opacity(0.1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                Color.from(tagType: tag.type).opacity(isHovered ? 0.4 : 0.2),
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .help("标签: \(tag.displayName) (\(tag.type.displayName))")
    }
}

// MARK: - 空状态视图

struct EmptyStateView: View {
    @EnvironmentObject private var store: WordStore
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: store.searchQuery.isEmpty ? "book" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text(store.searchQuery.isEmpty ? "暂无单词" : "未找到匹配的单词")
                .font(.title3)
                .foregroundColor(.secondary)
            
            if store.searchQuery.isEmpty {
                Text("开始添加你的第一个单词吧！")
                    .font(.body)
                    .foregroundColor(Color.secondary)
            } else {
                Text("尝试使用不同的关键词搜索")
                    .font(.body)
                    .foregroundColor(Color.secondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    WordListView(selectedWord: .constant(nil))
        .environmentObject(WordStore.shared)
}