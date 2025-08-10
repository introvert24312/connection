import SwiftUI
import CoreLocation
import MapKit

struct NodeListView: View {
    @EnvironmentObject private var store: NodeStore
    @Binding var selectedNode: Node?
    @State private var searchFilter = SearchFilter()
    @State private var sortOption: SortOption = .alphabetical
    @State private var selectedIndex: Int = 0
    @FocusState private var isListFocused: Bool
    @FocusState private var isSearchFieldFocused: Bool
    @State private var localSearchQuery: String = ""
    
    // 缓存机制，避免列表频繁重新渲染
    @State private var cachedDisplayNodes: [Node] = []
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
                    TextField("搜索节点、音标、含义...", text: $localSearchQuery)
                        .textFieldStyle(.plain)
                        .focused($isSearchFieldFocused)
                        .onChange(of: isSearchFieldFocused) { _, newValue in
                            print("🎯 Focus changed: isSearchFieldFocused = \(newValue)")
                        }
                        .onSubmit {
                            // 回车键选中第一个搜索结果并转移焦点到列表
                            if !displayNodes.isEmpty {
                                selectedIndex = 0
                                selectNodeAtIndex()
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
                    
                    // 节点数量显示
                    Text("\(displayNodes.count) 个节点")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 节点列表
            if store.isLoading {
                VStack {
                    Spacer()
                    ProgressView("搜索中...")
                        .scaleEffect(1.2)
                    Spacer()
                }
            } else if displayNodes.isEmpty {
                EmptyStateView()
            } else {
                ScrollViewReader { proxy in
                    List(Array(displayNodes.enumerated()), id: \.element.id) { index, node in
                        NodeRowView(
                            node: node,
                            isSelected: selectedNode?.id == node.id || (index == selectedIndex && selectedIndex >= 0),
                            searchQuery: store.searchQuery
                        ) {
                            print("🎯 NodeListView: 用户点击节点 \(node.text)")
                            selectedNode = node
                            selectedIndex = index
                            print("🔄 NodeListView: 调用store.selectNode(\(node.text))")
                            store.selectNode(node)
                        }
                        .id(node.id)
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
                            selectNodeAtIndex()
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(selectedIndex, anchor: .center)
                            }
                        }
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        if selectedIndex < displayNodes.count - 1 {
                            selectedIndex += 1
                            selectNodeAtIndex()
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(selectedIndex, anchor: .center)
                            }
                        }
                        return .handled
                    }
                    .onKeyPress(.return) {
                        selectNodeAtIndex()
                        return .handled
                    }
                    .onChange(of: displayNodes) { _, _ in
                        // 不自动选中第一个结果，只确保索引不越界
                        if selectedIndex >= displayNodes.count {
                            selectedIndex = displayNodes.count - 1
                        }
                        if displayNodes.isEmpty {
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
        .navigationTitle("节点")
        .onAppear {
            setupView()
        }
        .onChange(of: store.searchQuery) { _, newValue in
            handleStoreSearchQueryChange(newValue)
        }
        .onChange(of: store.searchResults) { _, newValue in
            handleSearchResultsChange(newValue)
        }
        .onChange(of: store.selectedTag?.id) { _, newValue in
            handleSelectedTagChange(newValue)
        }
        .onChange(of: store.currentLayer?.id) { _, newValue in
            handleCurrentLayerChange(newValue)
        }
        .onChange(of: sortOption) { _, newValue in
            handleSortOptionChange(newValue)
        }
        .onChange(of: store.nodes) { _, newNodes in
            print("📊 NodeListView: store.nodes changed, 节点数量: \(newNodes.count)")
            // 详细输出每个节点的标签信息
            for (index, node) in newNodes.enumerated() {
                print("  节点[\(index)]: '\(node.text)' - 标签数: \(node.tags.count)")
                for (tagIndex, tag) in node.tags.enumerated() {
                    print("    标签[\(tagIndex)]: \(tag.type.displayName) - '\(tag.value)'")
                }
            }
            // 强制立即更新缓存，不使用防抖
            print("🔄 强制立即更新缓存显示")
            updateCachedDisplayNodes()
        }
    }
    
    private var displayNodes: [Node] {
        return cachedDisplayNodes
    }
    
    private func scheduleUpdate() {
        print("⏰ NodeListView.scheduleUpdate called")
        
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
        print("🔧 Executing immediate updateCachedDisplayNodes")
        updateCachedDisplayNodes()
    }
    
    private func updateCachedDisplayNodes() {
        // 防止重复更新
        guard !isUpdating else {
            print("⏭️ Update already in progress, skipping")
            return
        }
        
        isUpdating = true
        print("🔄 updateCachedDisplayNodes started")
        print("📊 Current store state - searchQuery: '\(store.searchQuery)', searchResults count: \(store.searchResults.count)")
        
        let filteredNodes: [Node]
        
        if !store.searchQuery.isEmpty {
            // 搜索时优先显示搜索结果，忽略标签过滤
            filteredNodes = store.searchResults
            print("🔍 Using search results: \(filteredNodes.count) nodes (tag filter ignored during search)")
        } else if let selectedTag = store.selectedTag {
            // 只有在没有搜索时才应用标签过滤，只在当前层中搜索
            filteredNodes = store.nodesInCurrentLayer(withTag: selectedTag)
            print("🏷️ Using tag filter in current layer: \(filteredNodes.count) nodes")
            print("🏷️ Selected tag: \(selectedTag.type.displayName) - '\(selectedTag.value)'")
            // 详细调试：检查每个节点是否包含该标签
            for (index, node) in filteredNodes.enumerated() {
                let hasTag = node.hasTag(selectedTag)
                print("  过滤结果[\(index)]: '\(node.text)' - hasTag: \(hasTag), 标签数: \(node.tags.count)")
                if hasTag {
                    let matchingTags = node.tags.filter { $0.type == selectedTag.type && $0.value == selectedTag.value }
                    print("    匹配标签: \(matchingTags.count)个")
                }
            }
        } else {
            // 没有搜索也没有选中标签时，显示当前层的节点
            filteredNodes = store.getNodesInCurrentLayer()
            print("📋 Using current layer nodes: \(filteredNodes.count) nodes")
        }
        
        // 应用排序并更新缓存
        let oldCount = cachedDisplayNodes.count
        let newNodes = sortNodes(filteredNodes)
        
        // 使用动画更新缓存，减少视觉闪烁
        withAnimation(.easeInOut(duration: 0.2)) {
            cachedDisplayNodes = newNodes
        }
        
        let newCount = cachedDisplayNodes.count
        print("✅ Cache updated: \(oldCount) → \(newCount) nodes")
        
        // 详细输出缓存中每个节点的标签信息
        for (index, node) in cachedDisplayNodes.enumerated() {
            print("  缓存节点[\(index)]: '\(node.text)' - 标签数: \(node.tags.count)")
            if !node.tags.isEmpty {
                let tagSummary = node.tags.map { "\($0.type.displayName):\($0.value)" }.joined(separator: ", ")
                print("    标签: \(tagSummary)")
            }
        }
        
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
        updateCachedDisplayNodes()
        
        // 延迟设置焦点，确保TextField已经渲染完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("🎯 setupView delayed: setting isSearchFieldFocused = true")
            isSearchFieldFocused = true
        }
    }
    
    private func handleStoreSearchQueryChange(_ newValue: String) {
        print("🔍 NodeListView: searchQuery changed to '\(newValue)'")
        
        // 如果是清空搜索，立即更新显示；否则等搜索结果完成后再更新
        if newValue.isEmpty {
            print("🧹 NodeListView: Search cleared, updating display immediately")
            scheduleUpdate()
        }
        
        // 不要同步回localSearchQuery，避免循环更新
        // localSearchQuery由用户直接输入控制
    }
    
    private func handleSearchResultsChange(_ newValue: [Node]) {
        print("📊 NodeListView: searchResults changed to \(newValue.count) items")
        // 搜索结果变化时总是更新显示
        scheduleUpdate()
    }
    
    private func handleSelectedTagChange(_ newValue: UUID?) {
        let newStr = newValue?.uuidString ?? "nil"
        print("🏷️ NodeListView: selectedTag changed to '\(newStr)'")
        scheduleUpdate()
    }
    
    private func handleCurrentLayerChange(_ newValue: UUID?) {
        let newStr = newValue?.uuidString ?? "nil"
        print("🔄 NodeListView: currentLayer changed to '\(newStr)'")
        scheduleUpdate()
    }
    
    private func handleSortOptionChange(_ newValue: SortOption) {
        print("📊 NodeListView: sortOption changed to '\(newValue)'")
        scheduleUpdate()
    }
    
    private func sortNodes(_ nodes: [Node]) -> [Node] {
        switch sortOption {
        case .alphabetical:
            return nodes.sorted { $0.text.lowercased() < $1.text.lowercased() }
        case .tagCount:
            return nodes.sorted { $0.tags.count > $1.tags.count }
        }
    }
    
    private func selectNodeAtIndex() {
        guard selectedIndex >= 0 && selectedIndex < displayNodes.count else { return }
        let node = displayNodes[selectedIndex]
        selectedNode = node
        store.selectNode(node)
    }
    
}

// MARK: - 节点行视图

struct NodeRowView: View {
    let node: Node
    let isSelected: Bool
    let searchQuery: String
    let onTap: () -> Void
    
    @EnvironmentObject private var store: NodeStore
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // 节点文本
                    HighlightedText(
                        text: node.text,
                        searchQuery: searchQuery,
                        font: .title2,
                        fontWeight: .semibold
                    )
                    
                    Spacer()
                    
                    // 音标
                    if let phonetic = node.phonetic {
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
                if let meaning = node.meaning {
                    HighlightedText(
                        text: meaning,
                        searchQuery: searchQuery,
                        font: .title3,
                        fontWeight: .regular
                    )
                    .foregroundColor(.secondary)
                }
                
                // 标签 - 过滤掉内部使用的复合节点和子节点引用标签
                let displayTags = node.tags.filter { tag in
                    if case .custom(let key) = tag.type {
                        return !(key == "compound" || key == "child")
                    }
                    return true
                }
                if !displayTags.isEmpty {
                    TagChipsView(tags: displayTags, searchQuery: searchQuery)
                }
                
                // 元数据
                HStack {
                    Text(node.createdAt.timeAgoDisplay())
                        .font(.caption2)
                        .foregroundColor(Color.secondary)
                    
                    Spacer()
                    
                    if node.updatedAt > node.createdAt {
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
                .fill(backgroundColorForNode(isSelected: isSelected))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColorForNode(isSelected: isSelected), lineWidth: node.isCompound ? 2 : 1)
                )
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    private func backgroundColorForNode(isSelected: Bool) -> Color {
        if node.isCompound {
            let compoundColor = getCompoundColor()
            return isSelected ? compoundColor.opacity(0.25) : compoundColor.opacity(0.08)
        } else {
            return isSelected ? Color.blue.opacity(0.15) : Color.clear
        }
    }
    
    private func borderColorForNode(isSelected: Bool) -> Color {
        if node.isCompound {
            let compoundColor = getCompoundColor()
            return isSelected ? compoundColor.opacity(0.6) : compoundColor.opacity(0.3)
        } else {
            return isSelected ? Color.blue.opacity(0.3) : Color.clear
        }
    }
    
    private func getCompoundColor() -> Color {
        // 根据复合节点的嵌套深度返回不同颜色
        let depth = node.getCompoundDepth(allNodes: store.nodes)
        switch depth {
        case 1:
            return Color.purple      // 1级复合节点 - 紫色
        case 2:
            return Color.orange      // 2级复合节点 - 橙色  
        case 3:
            return Color.green       // 3级复合节点 - 绿色
        case 4:
            return Color.red         // 4级复合节点 - 红色
        default:
            return Color.indigo      // 5级及以上 - 靛蓝色
        }
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
        if tags.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if tags.count > 1 {
                    HStack {
                        Text("标签 (\(tags.count))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        if tags.count > 3 {
                            Text("← 滑动查看更多")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(tags, id: \.id) { tag in
                            TagChip(tag: tag, searchQuery: searchQuery)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxHeight: 50) // 进一步增加高度以容纳更大的字体
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
                // 类型指示器 - 更大
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.from(tagType: tag.type))
                    .frame(width: 4, height: 18)
                
                VStack(alignment: .leading, spacing: 2) {
                    if searchQuery.isEmpty {
                        Text(tag.value)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .foregroundColor(.primary)
                    } else {
                        HighlightedText(
                            text: tag.value,
                            searchQuery: searchQuery,
                            font: .title3,
                            fontWeight: .semibold
                        )
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    }
                    
                    // 类型标识
                    Text(tag.type.displayName)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .fixedSize() // 确保标签不会被压缩
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
    @EnvironmentObject private var store: NodeStore
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: store.searchQuery.isEmpty ? "book" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text(store.searchQuery.isEmpty ? "暂无节点" : "未找到匹配的节点")
                .font(.title3)
                .foregroundColor(.secondary)
            
            if store.searchQuery.isEmpty {
                Text("添加你的第一个节点")
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
    NodeListView(selectedNode: .constant(nil))
        .environmentObject(NodeStore.shared)
}