import SwiftUI

struct WordManagerView: View {
    @EnvironmentObject private var store: WordStore
    @State private var selectedWords: Set<UUID> = []
    @State private var searchQuery: String = ""
    @State private var showingDeleteAlert = false
    @State private var sortOption: SortOption = .alphabetical
    @State private var filterOption: FilterOption = .all
    
    enum SortOption: String, CaseIterable {
        case alphabetical = "按字母排序"
        case createdDate = "按创建时间"
        case updatedDate = "按修改时间"
        case tagCount = "按标签数量"
    }
    
    enum FilterOption: String, CaseIterable {
        case all = "全部单词"
        case withTags = "有标签的"
        case withoutTags = "无标签的"
        case withMeaning = "有释义的"
        case withoutMeaning = "无释义的"
    }
    
    var filteredAndSortedWords: [Word] {
        var words = store.words
        
        // 应用过滤器
        switch filterOption {
        case .all:
            break
        case .withTags:
            words = words.filter { !$0.tags.isEmpty }
        case .withoutTags:
            words = words.filter { $0.tags.isEmpty }
        case .withMeaning:
            words = words.filter { $0.meaning != nil && !$0.meaning!.isEmpty }
        case .withoutMeaning:
            words = words.filter { $0.meaning == nil || $0.meaning!.isEmpty }
        }
        
        // 应用搜索
        if !searchQuery.isEmpty {
            words = words.filter { word in
                word.text.localizedCaseInsensitiveContains(searchQuery) ||
                (word.meaning?.localizedCaseInsensitiveContains(searchQuery) ?? false) ||
                word.tags.contains { $0.value.localizedCaseInsensitiveContains(searchQuery) }
            }
        }
        
        // 应用排序
        switch sortOption {
        case .alphabetical:
            words.sort { $0.text.localizedCompare($1.text) == .orderedAscending }
        case .createdDate:
            words.sort { $0.createdAt > $1.createdAt }
        case .updatedDate:
            words.sort { $0.updatedAt > $1.updatedAt }
        case .tagCount:
            words.sort { $0.tags.count > $1.tags.count }
        }
        
        return words
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("单词管理")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("搜索单词、释义或标签...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .frame(width: 200)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                
                // 过滤器
                Menu {
                    ForEach(FilterOption.allCases, id: \.self) { option in
                        Button(action: {
                            filterOption = option
                        }) {
                            HStack {
                                Text(option.rawValue)
                                if filterOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(filterOption.rawValue)
                    }
                    .foregroundColor(.blue)
                }
                .help("过滤选项")
                
                // 排序选项
                Menu {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button(action: {
                            sortOption = option
                        }) {
                            HStack {
                                Text(option.rawValue)
                                if sortOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(sortOption.rawValue)
                    }
                    .foregroundColor(.blue)
                }
                .help("排序选项")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 操作栏
            HStack {
                Text("选中 \(selectedWords.count) / \(filteredAndSortedWords.count) 个单词")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 全选/取消全选
                Button(action: {
                    if selectedWords.count == filteredAndSortedWords.count {
                        selectedWords.removeAll()
                    } else {
                        selectedWords = Set(filteredAndSortedWords.map { $0.id })
                    }
                }) {
                    Text(selectedWords.count == filteredAndSortedWords.count ? "取消全选" : "全选")
                        .font(.caption)
                }
                .disabled(filteredAndSortedWords.isEmpty)
                
                // 批量删除按钮
                Button(action: {
                    showingDeleteAlert = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("删除选中")
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                .disabled(selectedWords.isEmpty)
                .alert("确认删除", isPresented: $showingDeleteAlert) {
                    Button("取消", role: .cancel) { }
                    Button("删除", role: .destructive) {
                        batchDeleteWords()
                    }
                } message: {
                    Text("确定要删除选中的 \(selectedWords.count) 个单词吗？此操作不可撤销。")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // 单词列表
            if filteredAndSortedWords.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
                    Text(searchQuery.isEmpty ? "暂无单词" : "未找到匹配的单词")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    if !searchQuery.isEmpty {
                        Button("清除搜索") {
                            searchQuery = ""
                        }
                        .foregroundColor(.blue)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredAndSortedWords, id: \.id) { word in
                            WordManagerRowView(
                                word: word,
                                isSelected: selectedWords.contains(word.id),
                                onToggleSelection: {
                                    if selectedWords.contains(word.id) {
                                        selectedWords.remove(word.id)
                                    } else {
                                        selectedWords.insert(word.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
        }
        .navigationTitle("单词管理")
    }
    
    private func batchDeleteWords() {
        for wordId in selectedWords {
            store.deleteWord(wordId)
        }
        selectedWords.removeAll()
    }
}

// MARK: - Word Manager Row View

struct WordManagerRowView: View {
    let word: Word
    let isSelected: Bool
    let onToggleSelection: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 选择框
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            
            // 单词信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    // 单词文本
                    Text(word.text)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    // 音标
                    if let phonetic = word.phonetic {
                        Text(phonetic)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.1))
                            )
                    }
                    
                    Spacer()
                    
                    // 标签数量
                    if !word.tags.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "tag.fill")
                                .font(.caption2)
                            Text("\(word.tags.count)")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                // 释义
                if let meaning = word.meaning, !meaning.isEmpty {
                    Text(meaning)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // 标签
                if !word.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(word.tags.prefix(5), id: \.id) { tag in
                                Text(tag.value)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.from(tagType: tag.type).opacity(0.2))
                                    )
                                    .foregroundColor(Color.from(tagType: tag.type))
                            }
                            
                            if word.tags.count > 5 {
                                Text("+\(word.tags.count - 5)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // 时间信息
                HStack(spacing: 12) {
                    Text("创建: \(word.createdAt.timeAgoDisplay())")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if word.updatedAt > word.createdAt {
                        Text("修改: \(word.updatedAt.timeAgoDisplay())")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleSelection()
        }
    }
}

#Preview {
    WordManagerView()
        .environmentObject(WordStore.shared)
}