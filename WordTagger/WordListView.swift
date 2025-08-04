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
    @State private var lastCurrentLayer: UUID? = nil
    @State private var lastSortOption: SortOption = .alphabetical
    @State private var updateTask: Task<Void, Never>?
    @State private var isUpdating: Bool = false
    
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
                        .onChange(of: isSearchFieldFocused) { _, newValue in
                            print("🎯 Focus changed: isSearchFieldFocused = \(newValue)")
                        }
                        .onSubmit {
                            // 回车键选中第一个搜索结果并转移焦点到列表
                            if !displayWords.isEmpty {
                                selectedIndex = 0
                                selectWordAtIndex()
                                print("🎯 Enter pressed: transferring focus to list")
                                isSearchFieldFocused = false
                                isListFocused = true
                            }
                        }
                        .onChange(of: localSearchQuery) { oldValue, newValue in
                            handleSearchQueryChange(newValue)
                        }
                        .id("search-field")  // 稳定的ID
                        .background(Color.clear)  // 确保有明确的背景
                        .onAppear {
                            // 当TextField出现时立即获取焦点
                            print("🎯 TextField onAppear: setting focus")
                            DispatchQueue.main.async {
                                print("🎯 TextField async: isSearchFieldFocused = true")
                                isSearchFieldFocused = true
                            }
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
                        Button("全部标签") { 
                            searchFilter.tagType = nil
                            store.selectTag(nil)
                        }
                        Divider()
                        ForEach(Tag.TagType.allCases, id: \.self) { type in
                            Button(type.displayName) { 
                                searchFilter.tagType = type
                                // 找到第一个匹配类型的标签并选中
                                if let firstTag = store.allTags.first(where: { $0.type == type }) {
                                    store.selectTag(firstTag)
                                }
                            }
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
                            isSelected: selectedWord?.id == word.id || (index == selectedIndex && selectedIndex >= 0),
                            searchQuery: store.searchQuery
                        ) {
                            selectedWord = word
                            store.selectWord(word)
                            selectedIndex = index
                        }
                        .id(word.id)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                    .listStyle(.plain)
                    .focused($isListFocused)
                    .onChange(of: isListFocused) { _, newValue in
                        print("📋 List focus changed: isListFocused = \(newValue)")
                    }
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
                        // 不自动选中第一个结果，只确保索引不越界
                        if selectedIndex >= displayWords.count {
                            selectedIndex = displayWords.count - 1
                        }
                        if displayWords.isEmpty {
                            selectedIndex = -1  // 没有结果时设为-1
                        }
                    }
                    .onAppear {
                        print("📋 List onAppear: NOT setting focus anymore")
                        // 不要自动获取List焦点，这会抢夺搜索框焦点
                        // isListFocused = true
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
        .onChange(of: store.currentLayer?.id, perform: handleCurrentLayerChange)
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
        let hasCurrentLayerChange = lastCurrentLayer != store.currentLayer?.id
        let hasSortOptionChange = lastSortOption != sortOption
        
        print("🔄 Changes detected - searchQuery: \(hasSearchQueryChange), selectedTag: \(hasSelectedTagChange), currentLayer: \(hasCurrentLayerChange), sortOption: \(hasSortOptionChange)")
        print("🔄 Current state - searchQuery: '\(store.searchQuery)', lastSearchQuery: '\(lastSearchQuery)'")
        
        // 如果没有任何变化，不需要更新
        guard hasSearchQueryChange || hasSelectedTagChange || hasCurrentLayerChange || hasSortOptionChange else {
            print("⏭️ No changes detected, skipping update")
            return
        }
        
        // 立即更新，因为Store已经处理了防抖
        print("🔧 Executing immediate updateCachedDisplayWords")
        updateCachedDisplayWords()
    }
    
    private func updateCachedDisplayWords() {
        // 防止重复更新
        guard !isUpdating else {
            print("⏭️ Update already in progress, skipping")
            return
        }
        
        isUpdating = true
        print("🔄 updateCachedDisplayWords started")
        print("📊 Current store state - searchQuery: '\(store.searchQuery)', searchResults count: \(store.searchResults.count)")
        
        let filteredWords: [Word]
        
        if !store.searchQuery.isEmpty {
            // 搜索时优先显示搜索结果，忽略标签过滤
            filteredWords = store.searchResults
            print("🔍 Using search results: \(filteredWords.count) words (tag filter ignored during search)")
        } else if let selectedTag = store.selectedTag {
            // 只有在没有搜索时才应用标签过滤，只在当前层中搜索
            filteredWords = store.wordsInCurrentLayer(withTag: selectedTag)
            print("🏷️ Using tag filter in current layer: \(filteredWords.count) words")
        } else {
            // 没有搜索也没有选中标签时，显示当前层的单词
            filteredWords = store.getWordsInCurrentLayer()
            print("📋 Using current layer words: \(filteredWords.count) words")
        }
        
        // 应用排序并更新缓存
        let oldCount = cachedDisplayWords.count
        let newWords = sortWords(filteredWords)
        
        // 使用动画更新缓存，减少视觉闪烁
        withAnimation(.easeInOut(duration: 0.2)) {
            cachedDisplayWords = newWords
        }
        
        let newCount = cachedDisplayWords.count
        print("✅ Cache updated: \(oldCount) → \(newCount) words")
        
        // 更新缓存状态
        lastSearchQuery = store.searchQuery
        lastSelectedTag = store.selectedTag
        lastCurrentLayer = store.currentLayer?.id
        lastSortOption = sortOption
        
        print("💾 Cache state updated - lastSearchQuery: '\(lastSearchQuery)'")
        
        // 重置更新标记
        isUpdating = false
    }
    
    private func handleSearchQueryChange(_ newValue: String) {
        // 直接更新store，让Store的debounce处理
        store.searchQuery = newValue
    }
    
    private func clearSearch() {
        localSearchQuery = ""
        store.searchQuery = ""
    }
    
    private func setupView() {
        print("🔧 setupView called")
        // 初始化时同步搜索查询和设置焦点
        localSearchQuery = store.searchQuery
        
        // 初始化时更新显示
        updateCachedDisplayWords()
        
        // 延迟设置焦点，确保TextField已经渲染完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("🎯 setupView delayed: setting isSearchFieldFocused = true")
            isSearchFieldFocused = true
        }
    }
    
    private func handleStoreSearchQueryChange(_ newValue: String) {
        print("🔍 WordListView: searchQuery changed to '\(newValue)'")
        
        // 如果是清空搜索，立即更新显示；否则等搜索结果完成后再更新
        if newValue.isEmpty {
            print("🧹 WordListView: Search cleared, updating display immediately")
            scheduleUpdate()
        }
        
        // 不要同步回localSearchQuery，避免循环更新
        // localSearchQuery由用户直接输入控制
    }
    
    private func handleSearchResultsChange(_ newValue: [Word]) {
        print("📊 WordListView: searchResults changed to \(newValue.count) items")
        // 搜索结果变化时总是更新显示
        scheduleUpdate()
    }
    
    private func handleSelectedTagChange(_ newValue: UUID?) {
        let newStr = newValue?.uuidString ?? "nil"
        print("🏷️ WordListView: selectedTag changed to '\(newStr)'")
        scheduleUpdate()
    }
    
    private func handleCurrentLayerChange(_ newValue: UUID?) {
        let newStr = newValue?.uuidString ?? "nil"
        print("🔄 WordListView: currentLayer changed to '\(newStr)'")
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
        guard selectedIndex >= 0 && selectedIndex < displayWords.count else { return }
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
        let _ = print("🏷️ TagChip: 渲染标签 value='\(tag.value)', type=\(tag.type), displayName='\(tag.type.displayName)'")
        return Button(action: {
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