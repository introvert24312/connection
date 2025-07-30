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
                    TextField("搜索单词、音标、含义...", text: $store.searchQuery)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            // 搜索提交时的处理
                        }
                    
                    if !store.searchQuery.isEmpty {
                        Button(action: {
                            store.searchQuery = ""
                        }) {
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
                    List(Array(displayWords.enumerated()), id: \.offset) { index, word in
                        WordRowView(
                            word: word,
                            isSelected: selectedWord?.id == word.id || index == selectedIndex,
                            searchQuery: store.searchQuery
                        ) {
                            selectedWord = word
                            store.selectWord(word)
                            selectedIndex = index
                        }
                        .id(index)
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
                    }
                }
            }
        }
        .navigationTitle("单词")
    }
    
    private var displayWords: [Word] {
        let filteredWords: [Word]
        
        if !store.searchQuery.isEmpty {
            // 使用搜索结果，但同时考虑selectedTag过滤
            let searchResults = store.searchResults.map { $0.word }
            if let selectedTag = store.selectedTag {
                filteredWords = searchResults.filter { $0.hasTag(selectedTag) }
            } else {
                filteredWords = searchResults
            }
        } else if let selectedTag = store.selectedTag {
            // 如果选中了标签，只显示包含该标签的单词
            filteredWords = store.words(withTag: selectedTag)
        } else {
            // 应用过滤器
            filteredWords = store.search("", filter: searchFilter)
        }
        
        // 应用排序
        return sortWords(filteredWords)
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