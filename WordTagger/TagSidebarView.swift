import SwiftUI
import CoreLocation
import MapKit

struct TagSidebarView: View {
    @EnvironmentObject private var store: WordStore
    @State private var filter: String = ""
    @State private var selectedTagType: Tag.TagType?
    @Binding var selectedWord: Word?
    @State private var selectedIndex: Int = 0
    @FocusState private var isListFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("搜索标签...", text: $filter)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                
                // 标签类型过滤器
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        TagTypeFilterButton(
                            type: nil,
                            isSelected: selectedTagType == nil,
                            action: { selectedTagType = nil }
                        )
                        
                        ForEach(Tag.TagType.allCases, id: \.self) { type in
                            TagTypeFilterButton(
                                type: type,
                                isSelected: selectedTagType == type,
                                action: { 
                                    selectedTagType = selectedTagType == type ? nil : type
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 标签列表
            ScrollViewReader { proxy in
                List(Array(filteredTags.enumerated()), id: \.offset) { index, tag in
                    TagRowView(
                        tag: tag,
                        isHighlighted: index == selectedIndex
                    ) {
                        selectTagAtIndex(index)
                    }
                    .id(index)
                }
                .listStyle(.sidebar)
                .focused($isListFocused)
                .onKeyPress(.upArrow) {
                    if selectedIndex > 0 {
                        selectedIndex -= 1
                        selectTagAtIndex(selectedIndex)
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(selectedIndex, anchor: .center)
                        }
                    }
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    if selectedIndex < filteredTags.count - 1 {
                        selectedIndex += 1
                        selectTagAtIndex(selectedIndex)
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(selectedIndex, anchor: .center)
                        }
                    }
                    return .handled
                }
                .onKeyPress(.return) {
                    selectTagAtIndex(selectedIndex)
                    return .handled
                }
                .onChange(of: filteredTags) { _, _ in
                    selectedIndex = min(selectedIndex, max(0, filteredTags.count - 1))
                }
                .onAppear {
                    isListFocused = true
                }
            }
            .navigationTitle("标签")
        }
    }
    
    private var filteredTags: [Tag] {
        var tags = store.allTags
        
        // 按类型过滤
        if let selectedType = selectedTagType {
            tags = tags.filter { $0.type == selectedType }
        }
        
        // 按搜索文本过滤
        if !filter.isEmpty {
            tags = tags.filter { $0.value.localizedCaseInsensitiveContains(filter) }
        }
        
        // 按类型和值排序
        return tags.sorted { tag1, tag2 in
            if tag1.type != tag2.type {
                return tag1.type.rawValue < tag2.type.rawValue
            }
            return tag1.value < tag2.value
        }
    }
    
    private func selectTagAtIndex(_ index: Int) {
        guard index < filteredTags.count else { return }
        let tag = filteredTags[index]
        selectedIndex = index
        store.selectTag(tag)
        let relatedWords = store.words(withTag: tag)
        if let firstWord = relatedWords.first {
            selectedWord = firstWord
            store.selectWord(firstWord)
        }
    }
    
}

// MARK: - 标签类型过滤按钮

struct TagTypeFilterButton: View {
    let type: Tag.TagType?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let type = type {
                    Circle()
                        .fill(Color.from(tagType: type))
                        .frame(width: 8, height: 8)
                    Text(type.displayName)
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Text("全部")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 标签行视图

struct TagRowView: View {
    let tag: Tag
    let isHighlighted: Bool
    let onTap: () -> Void
    @EnvironmentObject private var store: WordStore
    
    init(tag: Tag, isHighlighted: Bool = false, onTap: @escaping () -> Void) {
        self.tag = tag
        self.isHighlighted = isHighlighted
        self.onTap = onTap
    }
    
    private var wordsCount: Int {
        store.words(withTag: tag).count
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // 标签类型指示器
                Circle()
                    .fill(Color.from(tagType: tag.type))
                    .frame(width: 12, height: 12)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(tag.value)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack {
                        Text(tag.type.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        if tag.hasCoordinates {
                            Image(systemName: "location.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Spacer()
                
                // 单词数量
                VStack {
                    Text("\(wordsCount)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    
                    Text("单词")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isHighlighted ? Color.blue.opacity(0.2) : 
                    (store.selectedTag?.id == tag.id ? Color.blue.opacity(0.1) : Color.clear)
                )
        )
    }
}

#Preview {
    NavigationSplitView {
        TagSidebarView(selectedWord: .constant(nil))
            .environmentObject(WordStore.shared)
    } content: {
        Text("Content")
    } detail: {
        Text("Detail")
    }
}