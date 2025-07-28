import SwiftUI
import CoreLocation
import MapKit

struct TagSidebarView: View {
    @EnvironmentObject private var store: WordStore
    @State private var filter: String = ""
    @State private var selectedTagType: Tag.TagType?
    @Binding var selectedWord: Word?
    
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
            List(filteredTags, id: \.id) { tag in
                TagRowView(tag: tag) {
                    // 选择标签时，显示相关单词
                    store.selectTag(tag)
                    let relatedWords = store.words(withTag: tag)
                    if let firstWord = relatedWords.first {
                        selectedWord = firstWord
                        store.selectWord(firstWord)
                    }
                }
            }
            .listStyle(.sidebar)
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
                        .font(.caption)
                } else {
                    Text("全部")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 标签行视图

struct TagRowView: View {
    let tag: Tag
    let onTap: () -> Void
    @EnvironmentObject private var store: WordStore
    
    private var wordsCount: Int {
        store.words(withTag: tag).count
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 标签类型指示器
                Circle()
                    .fill(Color.from(tagType: tag.type))
                    .frame(width: 12, height: 12)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(tag.value)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack {
                        Text(tag.type.displayName)
                            .font(.caption)
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
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(store.selectedTag?.id == tag.id ? Color.blue.opacity(0.1) : Color.clear)
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