import SwiftUI
import CoreLocation
import MapKit

struct TagSidebarView: View {
    @EnvironmentObject private var store: NodeStore
    @State private var filter: String = ""
    @State private var tagTypeSearchQuery: String = ""
    @State private var selectedTagTypes: Set<Tag.TagType> = []
    @State private var expandedGroups: Set<Tag.TagType> = []
    @State private var hiddenTagTypes: Set<Tag.TagType> = [] // 默认不隐藏任何标签
    @Binding var selectedNode: Node?
    @State private var selectedIndex: Int = -1
    @FocusState private var isListFocused: Bool
    @FocusState private var isTagTypeSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 当前层级指示器
            if let currentLayer = store.currentLayer {
                HStack {
                    Circle()
                        .fill(Color.from(currentLayer.color))
                        .frame(width: 12, height: 12)
                    
                    Text(currentLayer.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(store.getNodesInCurrentLayer().count) 个节点")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.from(currentLayer.color).opacity(0.1))
                
                Divider()
            }
            
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
                
                // 标签类型多选器
                VStack(alignment: .leading, spacing: 12) {
                    Text("选择标签类型")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    // 标签类型搜索框
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .font(.system(size: 12))
                        TextField("搜索标签类型...", text: $tagTypeSearchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .focused($isTagTypeSearchFocused)
                            .onChange(of: tagTypeSearchQuery) { _, newValue in
                                handleTagTypeSearch(newValue)
                            }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.1))
                    )
                    
                    // 隐藏选项
                    
                    // 搜索结果和添加按钮
                    if !tagTypeSearchQuery.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(searchableTagTypes, id: \.rawValue) { type in
                                    TagTypeSearchResultButton(
                                        type: type,
                                        isAlreadySelected: selectedTagTypes.contains(type),
                                        onAdd: {
                                            addTagType(type)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .frame(maxHeight: 40)
                    }
                    
                    // 已选择的标签类型
                    if !selectedTagTypes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("已选择的标签类型")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                                ForEach(Array(selectedTagTypes.sorted(by: { $0.displayName < $1.displayName })), id: \.self) { type in
                                    SelectedTagTypeChip(
                                        type: type,
                                        onRemove: {
                                            removeTagType(type)
                                        }
                                    )
                                }
                            }
                            
                            HStack {
                                Text("\(selectedTagTypes.count) 种标签类型")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button("清空") {
                                    selectedTagTypes.removeAll()
                                    expandedGroups.removeAll()
                                }
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 标签组列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if selectedTagTypes.isEmpty {
                        // 未选择标签类型时的提示
                        VStack(spacing: 16) {
                            Image(systemName: "tag.circle")
                                .font(.system(size: 48))
                                .foregroundColor(.gray.opacity(0.5))
                            
                            Text("请选择标签类型")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Text("选择上方的标签类型来查看相关标签")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        // 显示选中的标签类型组
                        ForEach(Array(selectedTagTypes.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { tagType in
                            TagGroupView(
                                tagType: tagType,
                                tags: getTagsForType(tagType),
                                isExpanded: expandedGroups.contains(tagType),
                                onToggleExpanded: {
                                    toggleGroup(tagType)
                                },
                                onSelectTag: { tag in
                                    selectTag(tag)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("标签")
            .focusable(false)
            .onKeyPress(.escape) {
                // 按ESC键隐藏标签管理侧边栏
                print("🔑 TagSidebarView: ESC键按下，隐藏标签管理")
                NotificationCenter.default.post(name: Notification.Name("toggleSidebar"), object: nil)
                return .handled
            }
            .onAppear {
                // 移除强制键盘焦点设置，避免干扰全局快捷键
                print("🔑 TagSidebarView 出现，不强制设置键盘焦点")
            }
            // 添加额外的ESC键处理层
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                print("🔑 窗口获得键盘焦点")
            }
        }
    }
    
    // 搜索匹配的标签类型 - 支持双语搜索
    private var searchableTagTypes: [Tag.TagType] {
        guard !tagTypeSearchQuery.isEmpty else { return [] }
        
        // 获取所有实际存在的标签类型（不仅仅是预定义的）
        let allExistingTypes = Set(store.allTags.map { $0.type })
        let tagManager = TagMappingManager.shared
        
        print("🔍 TagSidebarView: 搜索标签类型 '\(tagTypeSearchQuery)'")
        print("🔍 现有标签类型数量: \(allExistingTypes.count)")
        for type in allExistingTypes {
            print("  - \(type.displayName) (rawValue: \(type.rawValue))")
        }
        
        let matchingTypes = allExistingTypes.filter { tagType in
            // 过滤掉隐藏的标签类型
            guard !hiddenTagTypes.contains(tagType) else { 
                print("  ❌ 跳过隐藏标签类型: \(tagType.displayName)")
                return false 
            }
            
            let query = tagTypeSearchQuery.lowercased()
            
            // 1. 搜索displayName（显示名称，如"牛肉类型"）
            if tagType.displayName.localizedCaseInsensitiveContains(tagTypeSearchQuery) {
                print("  ✅ 匹配displayName: \(tagType.displayName)")
                return true
            }
            
            // 2. 搜索rawValue（标签代码，如"beef"）
            if tagType.rawValue.localizedCaseInsensitiveContains(tagTypeSearchQuery) {
                print("  ✅ 匹配rawValue: \(tagType.rawValue)")
                return true
            }
            
            // 3. 对于自定义标签类型，从TagMappingManager搜索所有相关映射
            if case .custom(let key) = tagType {
                print("  🔍 检查自定义标签类型: key=\(key)")
                
                // 搜索该key对应的所有可能的映射
                let matchingMappings = tagManager.tagMappings.filter { mapping in
                    mapping.key.lowercased() == key.lowercased()
                }
                
                print("    - 找到 \(matchingMappings.count) 个映射")
                for mapping in matchingMappings {
                    print("      映射: \(mapping.key) -> \(mapping.typeName)")
                }
                
                // 检查映射中的typeName是否匹配搜索查询
                for mapping in matchingMappings {
                    if mapping.typeName.localizedCaseInsensitiveContains(tagTypeSearchQuery) {
                        print("  ✅ 匹配映射typeName: \(mapping.typeName)")
                        return true
                    }
                    if mapping.key.localizedCaseInsensitiveContains(tagTypeSearchQuery) {
                        print("  ✅ 匹配映射key: \(mapping.key)")
                        return true
                    }
                }
                
                // 4. 额外搜索：检查该类型下是否有标签值匹配搜索查询
                let tagsOfThisType = store.allTags.filter { $0.type == tagType }
                for tag in tagsOfThisType {
                    if tag.value.localizedCaseInsensitiveContains(tagTypeSearchQuery) {
                        print("  ✅ 匹配标签值: \(tag.value)")
                        return true
                    }
                }
            }
            
            print("  ❌ 无匹配: \(tagType.displayName)")
            return false
        }.sorted { $0.displayName < $1.displayName }
        
        print("🔍 搜索结果: \(matchingTypes.count) 个匹配的标签类型")
        for type in matchingTypes {
            print("  ✅ \(type.displayName)")
        }
        
        return matchingTypes
    }
    
    private func addTagType(_ tagType: Tag.TagType) {
        selectedTagTypes.insert(tagType)
        expandedGroups.insert(tagType)
        // 清空搜索框
        tagTypeSearchQuery = ""
    }
    
    private func removeTagType(_ tagType: Tag.TagType) {
        selectedTagTypes.remove(tagType)
        expandedGroups.remove(tagType)
    }
    
    private func toggleTagType(_ tagType: Tag.TagType) {
        if selectedTagTypes.contains(tagType) {
            removeTagType(tagType)
        } else {
            addTagType(tagType)
        }
    }
    
    private func toggleGroup(_ tagType: Tag.TagType) {
        if expandedGroups.contains(tagType) {
            expandedGroups.remove(tagType)
        } else {
            expandedGroups.insert(tagType)
        }
    }
    
    private func getTagsForType(_ tagType: Tag.TagType) -> [Tag] {
        var tags: [Tag]
        
        // 根据搜索状态和当前层获取标签
        if !store.searchQuery.isEmpty {
            tags = store.getRelevantTags(for: store.searchQuery)
        } else if store.currentLayer != nil {
            tags = store.currentLayerTags
        } else {
            tags = store.allTags
        }
        
        // 按类型过滤
        tags = tags.filter { $0.type == tagType }
        
        // 过滤掉内部管理标签
        tags = tags.filter { tag in
            if case .custom(let key) = tag.type {
                return !(key == "compound" || key == "child")
            }
            return true
        }
        
        // 按本地搜索文本过滤
        if !filter.isEmpty {
            tags = tags.filter { $0.value.localizedCaseInsensitiveContains(filter) }
        }
        
        print("🏷️ TagSidebarView: getTagsForType(\(tagType.displayName)) 返回 \(tags.count) 个标签")
        for tag in tags {
            print("  - \(tag.value)")
        }
        
        // 按值排序
        return tags.sorted { $0.value < $1.value }
    }
    
    private func selectTag(_ tag: Tag) {
        DispatchQueue.main.async {
            store.selectTag(tag)
            let relatedNodes = store.nodes(withTag: tag)
            if let firstNode = relatedNodes.first {
                self.selectedNode = firstNode
                store.selectNode(firstNode)
            }
        }
    }
    
    // 处理标签类型搜索，自动智能选择相关标签类型
    private func handleTagTypeSearch(_ query: String) {
        print("🔍 TagSidebarView: handleTagTypeSearch('\(query)')")
        
        // 如果搜索查询为空，不做处理
        guard !query.isEmpty else { return }
        
        // 智能搜索：如果搜索的是标签值（如"里脊"），自动添加包含该标签值的标签类型
        let allTags = store.allTags
        let matchingTagsByValue = allTags.filter { tag in
            tag.value.localizedCaseInsensitiveContains(query)
        }
        
        print("🔍 找到 \(matchingTagsByValue.count) 个匹配标签值的标签")
        
        // 自动添加包含匹配标签值的标签类型
        for tag in matchingTagsByValue {
            if !selectedTagTypes.contains(tag.type) {
                print("🎯 自动添加标签类型: \(tag.type.displayName) (因为包含标签值 '\(tag.value)')")
                selectedTagTypes.insert(tag.type)
                expandedGroups.insert(tag.type)
            }
        }
    }
    
}

// MARK: - 标签类型搜索结果按钮

struct TagTypeSearchResultButton: View {
    let type: Tag.TagType
    let isAlreadySelected: Bool
    let onAdd: () -> Void
    
    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.from(tagType: type))
                    .frame(width: 8, height: 8)
                
                Text(type.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isAlreadySelected ? .secondary : .primary)
                
                if !isAlreadySelected {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isAlreadySelected ? Color.gray.opacity(0.1) : Color.blue.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isAlreadySelected ? Color.gray.opacity(0.3) : Color.blue, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isAlreadySelected)
    }
}

// MARK: - 已选择标签类型芯片

struct SelectedTagTypeChip: View {
    let type: Tag.TagType
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.from(tagType: type))
                .frame(width: 8, height: 8)
            
            Text(type.displayName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue, lineWidth: 1)
        )
    }
}

// MARK: - 标签类型多选按钮

struct TagTypeMultiSelectButton: View {
    let type: Tag.TagType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // 选择状态指示
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 20, height: 20)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.blue)
                    }
                }
                
                // 标签类型指示和名称
                Circle()
                    .fill(Color.from(tagType: type))
                    .frame(width: 12, height: 12)
                
                Text(type.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 标签组视图

struct TagGroupView: View {
    let tagType: Tag.TagType
    let tags: [Tag]
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onSelectTag: (Tag) -> Void
    @EnvironmentObject private var store: NodeStore
    
    var body: some View {
        VStack(spacing: 0) {
            // 组标题头部
            Button(action: onToggleExpanded) {
                HStack(spacing: 12) {
                    // 展开/折叠箭头
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    
                    // 标签类型指示器
                    Circle()
                        .fill(Color.from(tagType: tagType))
                        .frame(width: 12, height: 12)
                    
                    // 标签类型名称和数量
                    Text(tagType.displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("(\(tags.count))")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.05))
            }
            .buttonStyle(.plain)
            
            // 标签列表（展开时显示）
            if isExpanded {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tags.enumerated()), id: \.0) { index, tag in
                        TagValueRow(
                            tag: tag,
                            isSelected: store.selectedTag?.id == tag.id,
                            onSelect: { onSelectTag(tag) }
                        )

                        if index < tags.count - 1 {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }
}

// MARK: - 标签值行视图

struct TagValueRow: View {
    let tag: Tag
    let isSelected: Bool
    let onSelect: () -> Void
    @EnvironmentObject private var store: NodeStore
    
    private var nodeCount: Int {
        store.nodes(withTag: tag).count
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // 缩进空间
                Spacer()
                    .frame(width: 32)
                
                // 选择状态指示
                Circle()
                    .fill(isSelected ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
                
                // 标签值
                Text(tag.value)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? .blue : .primary)
                
                Spacer()
                
                // 节点数量
                Text("\(nodeCount)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.1))
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color.blue.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 标签行视图

struct TagRowView: View {
    let tag: Tag
    let isHighlighted: Bool
    let onTap: () -> Void
    @EnvironmentObject private var store: NodeStore
    
    init(tag: Tag, isHighlighted: Bool = false, onTap: @escaping () -> Void) {
        self.tag = tag
        self.isHighlighted = isHighlighted
        self.onTap = onTap
    }
    
    private var wordsCount: Int {
        store.nodes(withTag: tag).count
    }
    
    var body: some View {
        let isCurrentlySelected = store.selectedTag?.id == tag.id
        let _ = print("🏷️ TagRowView: 渲染标签 value='\(tag.value)', type=\(tag.type), displayName='\(tag.type.displayName)', selected=\(isCurrentlySelected), highlighted=\(isHighlighted)")
        return Button(action: onTap) {
            HStack(spacing: 16) {
                // 标签类型指示器
                Circle()
                    .fill(Color.from(tagType: tag.type))
                    .frame(width: 12, height: 12)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(tag.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack {
                        Text(tag.type.displayName)
                            .font(.system(size: 13, weight: .medium))
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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                    
                    Text("单词")
                        .font(.system(size: 11))
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
                    // 只有在有标签且实际选中时才高亮
                    (isHighlighted && !store.allTags.isEmpty) ? Color.blue.opacity(0.2) : 
                    (isCurrentlySelected ? Color.blue.opacity(0.1) : Color.clear)
                )
        )
    }
}

// Preview temporarily disabled due to @FocusState initialization complexity
// #Preview {
//     NavigationSplitView {
//         TagSidebarView(selectedNode: .constant(nil))
//             .environmentObject(NodeStore.shared)
//     } content: {
//         Text("Content")
//     } detail: {
//         Text("Detail")
//     }
// }
