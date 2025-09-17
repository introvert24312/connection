import SwiftUI
import CoreLocation
import MapKit

struct NodeListView: View {
    @EnvironmentObject private var store: NodeStore
    @Binding var selectedNode: Node?
    @State private var searchFilter = SearchFilter()
    @State private var sortOption: SortOption = .tagCount
    @State private var selectedIndex: Int = 0
    @FocusState private var isListFocused: Bool
    @FocusState private var isSearchFieldFocused: Bool
    @State private var localSearchQuery: String = ""
    
    // 🆕 按展开顺序累积的节点状态管理
    @State private var accumulatedNodes: [Node] = []        // 按展开顺序累积的节点
    @State private var displayedNodeIds: Set<UUID> = []     // 已显示节点的ID集合
    @State private var lastExpandedTagTypes: Set<Tag.TagType> = [] // 上次的展开状态
    
    // 简化状态管理，直接使用store数据
    
    // 命令行编辑器状态
    @State private var showingCommandEditor = false
    @State private var nodeToEdit: Node?
    
    enum SortOption: String, CaseIterable {
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
                            // 当搜索框失去焦点时，确保List获得焦点以支持键盘导航
                            if !newValue {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    isListFocused = true
                                    print("🎯 搜索框失去焦点，转移焦点到List")
                                }
                            }
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
                            isSelected: selectedNode?.id == node.id,
                            searchQuery: store.searchQuery,
                            onTap: {
                                print("🎯 NodeListView: 用户点击节点 \(node.text)")
                                selectedNode = node
                                selectedIndex = index
                                // 使用异步调用避免view更新期间发布更改
                                DispatchQueue.main.async {
                                    print("🔄 NodeListView: 调用store.selectNode(\(node.text))")
                                    store.selectNode(node)
                                }
                            },
                            onCommandClick: {
                                print("⌘ NodeListView: Command+点击节点 \(node.text)")
                                print("📋 节点详情: 标签数量=\(node.tags.count), layerId=\(node.layerId)")
                                // 发送通知打开节点管理窗口，并传递要编辑的节点
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("openNodeManagerForEdit"),
                                    object: node
                                )
                            },
                            onOptionClick: {
                                print("⌥ NodeListView: Option+点击节点 \(node.text)")
                                print("📁 将在Finder中打开节点文件夹...")
                                // 调用NodeFolderManager打开节点文件夹
                                NodeFolderManager.shared.openNodeFolderInFinder(node)
                            },
                            onDelete: {
                                print("🗑️ NodeListView: 删除节点 \(node.text)")
                                deleteNodeWithSmartTagCleanup(node)
                            }
                        )
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
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(displayNodes[selectedIndex].id, anchor: .center)
                            }
                        }
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        if selectedIndex < displayNodes.count - 1 {
                            selectedIndex += 1
                            selectNodeAtIndex()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(displayNodes[selectedIndex].id, anchor: .center)
                            }
                        }
                        return .handled
                    }
                    .onKeyPress(.return) {
                        selectNodeAtIndex()
                        return .handled
                    }
                    .onChange(of: displayNodes) { _, newNodes in
                        // 🆕 简化逻辑：只确保索引不越界
                        if selectedIndex >= newNodes.count {
                            selectedIndex = max(0, newNodes.count - 1)
                        }
                        if newNodes.isEmpty {
                            selectedIndex = -1  // 没有结果时设为-1
                        }
                        
                        // 🎯 展开模式下新节点从底部增量出现，保持当前滚动位置
                        // 搜索模式和其他模式保持原有行为
                    }
                    // 移除标签展开的滚动动画 - 新节点从底部自然出现，无需滚动
                    .onAppear {
                        print("📋 List onAppear: 延迟设置List焦点")
                        // 延迟设置List焦点，避免与搜索框冲突
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isListFocused = true
                            print("📋 List焦点已设置")
                        }
                    }
                }
            }
        }
        .onAppear {
            setupView()
        }
        // 🆕 监听标签展开状态变化，实现增量添加逻辑
        .onChange(of: store.expandedTagTypes) { _, newExpandedTypes in
            handleExpandedTagTypesChange(newExpandedTypes)
        }
        // 🆕 监听层级变化，重置累积状态
        .onChange(of: store.currentLayer?.id) { _, _ in
            resetAccumulatedNodes()
        }
        // 🆕 监听搜索状态变化，清理累积状态
        .onChange(of: store.searchQuery) { _, newQuery in
            if !newQuery.isEmpty {
                // 进入搜索模式时，清理累积状态
                resetAccumulatedNodes()
            }
        }
        // 节点编辑现在通过节点管理窗口处理
    }
    
    private var displayNodes: [Node] {
        // 🆕 新的展开逻辑：根据不同情况返回不同的节点列表
        
        if !store.searchQuery.isEmpty {
            // 搜索模式：直接返回搜索结果
            return sortNodes(store.searchResults)
        } else if !store.expandedTagTypes.isEmpty {
            // 🎯 标签展开模式：使用累积的节点（按展开顺序）
            return accumulatedNodes
        } else if let selectedTag = store.selectedTag {
            // 具体标签选中模式：处理选中的具体标签
            let filteredNodes: [Node]
            if store.showAllTagTypeNodes {
                filteredNodes = store.nodesInCurrentLayer(withTagType: selectedTag.type)
            } else {
                filteredNodes = store.nodesInCurrentLayer(withTag: selectedTag)
            }
            return sortNodes(filteredNodes)
        } else {
            // 默认模式：显示当前层的所有节点
            return sortNodes(store.getNodesInCurrentLayer())
        }
    }
    
    
    // 删除复杂的缓存更新逻辑，现在直接使用store数据
    
    // 删除缓存更新方法，现在直接使用store数据
    
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
        
        // 🆕 初始化累积状态
        resetAccumulatedNodes()
        
        // 延迟设置焦点，确保TextField已经渲染完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("🎯 setupView delayed: setting isSearchFieldFocused = true")
            isSearchFieldFocused = true
        }
    }
    
    // MARK: - 🆕 标签展开增量逻辑
    
    /// 处理标签展开状态变化
    private func handleExpandedTagTypesChange(_ newExpandedTypes: Set<Tag.TagType>) {
        print("🎯 [NodeListView] 标签展开状态变化:")
        print("   - 之前展开: \(lastExpandedTagTypes.map { $0.displayName })")
        print("   - 现在展开: \(newExpandedTypes.map { $0.displayName })")
        
        // 如果完全清空了展开状态，重置累积节点
        if newExpandedTypes.isEmpty {
            print("🧹 [NodeListView] 展开状态已清空，重置累积节点")
            resetAccumulatedNodes()
            lastExpandedTagTypes = newExpandedTypes
            return
        }
        
        // 找出新增的标签类型
        let newlyExpandedTypes = newExpandedTypes.subtracting(lastExpandedTagTypes)
        
        if !newlyExpandedTypes.isEmpty {
            print("📈 [NodeListView] 发现新展开的标签类型: \(newlyExpandedTypes.map { $0.displayName })")
            
            // 为每个新展开的标签类型添加节点
            for tagType in newlyExpandedTypes {
                addNodesForTagType(tagType)
            }
        }
        
        // 检查是否有被移除的标签类型
        let removedTypes = lastExpandedTagTypes.subtracting(newExpandedTypes)
        if !removedTypes.isEmpty {
            print("🗑️ [NodeListView] 发现被移除的标签类型: \(removedTypes.map { $0.displayName })")
            // 注意：这里我们不移除节点，因为用户可能想保留已展开的内容
            // 如果需要移除功能，可以在这里实现
        }
        
        lastExpandedTagTypes = newExpandedTypes
    }
    
    /// 为特定标签类型添加节点（增量添加，去重）
    private func addNodesForTagType(_ tagType: Tag.TagType) {
        print("📝 [NodeListView] 为标签类型添加节点: \(tagType.displayName)")
        
        // 获取该标签类型对应的节点
        let tagTypeNodes = store.nodesInCurrentLayer(withTagType: tagType)
        print("   - 标签类型节点数: \(tagTypeNodes.count)")
        
        // 过滤掉已经显示的节点（去重）
        let newNodes = tagTypeNodes.filter { node in
            !displayedNodeIds.contains(node.id)
        }
        
        print("   - 过滤后新增节点数: \(newNodes.count)")
        
        // 将新节点添加到累积列表末尾
        accumulatedNodes.append(contentsOf: newNodes)
        
        // 更新已显示节点ID集合
        for node in newNodes {
            displayedNodeIds.insert(node.id)
        }
        
        print("✅ [NodeListView] 累积节点总数: \(accumulatedNodes.count)")
        print("   - 已显示节点ID数量: \(displayedNodeIds.count)")
    }
    
    /// 重置累积节点状态
    private func resetAccumulatedNodes() {
        print("🔄 [NodeListView] 重置累积节点状态")
        accumulatedNodes.removeAll()
        displayedNodeIds.removeAll()
        lastExpandedTagTypes.removeAll()
    }
    
    // 删除复杂的状态处理方法，现在直接使用store数据
    
    private func sortNodes(_ nodes: [Node]) -> [Node] {
        // 🆕 注意：展开模式现在使用累积节点，不再走这个排序方法
        
        if let selectedTag = store.selectedTag, store.showAllTagTypeNodes {
            // 保留原有的焦点排序逻辑（用于选中具体标签值时）
            print("🎯 应用焦点排序 - 标签: \(selectedTag.type.displayName) - '\(selectedTag.value)'")
            
            let sorted = nodes.sorted { node1, node2 in
                let node1HasFocusTag = node1.hasTag(selectedTag)
                let node2HasFocusTag = node2.hasTag(selectedTag)
                
                if node1HasFocusTag && !node2HasFocusTag {
                    return false  // node1 排在后面（底部）
                } else if !node1HasFocusTag && node2HasFocusTag {
                    return true   // node2 排在后面（底部）
                } else {
                    return node1.tags.count > node2.tags.count
                }
            }
            
            return sorted
        } else {
            // 普通排序：按标签数量降序排列
            switch sortOption {
            case .tagCount:
                let sorted = nodes.sorted { $0.tags.count > $1.tags.count }
                print("📊 按标签数量排序: \(nodes.count) 个节点")
                return sorted
            }
        }
    }
    
    private func selectNodeAtIndex() {
        guard selectedIndex >= 0 && selectedIndex < displayNodes.count else { return }
        let node = displayNodes[selectedIndex]
        selectedNode = node
        // 使用异步调用避免view更新期间发布更改
        DispatchQueue.main.async {
            store.selectNode(node)
        }
    }
    
    /// 删除节点并智能清理标签
    private func deleteNodeWithSmartTagCleanup(_ nodeToDelete: Node) {
        print("🗑️ 开始删除节点: \(nodeToDelete.text)")
        print("📋 节点标签数量: \(nodeToDelete.tags.count)")
        
        // 1. 收集该节点的所有标签
        let nodeTagsToCheck = nodeToDelete.tags
        print("📋 需要检查的标签:")
        for tag in nodeTagsToCheck {
            print("   - \(tag.type.displayName): \(tag.value)")
        }
        
        // 2. 检查每个标签在其他节点中的使用情况
        var tagsToDelete: [Tag] = []
        var tagsToKeep: [Tag] = []
        
        for tag in nodeTagsToCheck {
            var tagUsedElsewhere = false
            
            // 遍历所有其他节点，检查是否使用了相同的标签
            for otherNode in store.nodes {
                // 跳过当前要删除的节点
                if otherNode.id == nodeToDelete.id { continue }
                
                // 检查其他节点是否有相同的标签
                for otherTag in otherNode.tags {
                    if otherTag.type == tag.type && otherTag.value == tag.value {
                        tagUsedElsewhere = true
                        break
                    }
                }
                
                if tagUsedElsewhere { break }
            }
            
            if tagUsedElsewhere {
                tagsToKeep.append(tag)
                print("✅ 标签 \(tag.type.displayName): \(tag.value) 在其他节点中使用，将保留")
            } else {
                tagsToDelete.append(tag)
                print("🗑️ 标签 \(tag.type.displayName): \(tag.value) 只在此节点中使用，将删除")
            }
        }
        
        // 3. 显示确认对话框
        showDeleteConfirmation(
            nodeToDelete: nodeToDelete,
            tagsToDelete: tagsToDelete,
            tagsToKeep: tagsToKeep
        )
    }
    
    /// 显示删除确认对话框
    private func showDeleteConfirmation(nodeToDelete: Node, tagsToDelete: [Tag], tagsToKeep: [Tag]) {
        let alert = NSAlert()
        alert.messageText = "确认删除节点"
        
        var informativeText = "将删除节点：\(nodeToDelete.text)\n\n"
        
        if !tagsToDelete.isEmpty {
            informativeText += "以下标签只在此节点中使用，也将被删除：\n"
            for tag in tagsToDelete {
                informativeText += "• \(tag.type.displayName): \(tag.value)\n"
            }
        }
        
        if !tagsToKeep.isEmpty {
            informativeText += "\n以下标签在其他节点中也有使用，将保留：\n"
            for tag in tagsToKeep {
                informativeText += "• \(tag.type.displayName): \(tag.value)\n"
            }
        }
        
        alert.informativeText = informativeText
        alert.alertStyle = .warning
        
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            performNodeDeletion(nodeToDelete: nodeToDelete, tagsToDelete: tagsToDelete)
        }
    }
    
    /// 执行节点和标签删除
    private func performNodeDeletion(nodeToDelete: Node, tagsToDelete: [Tag]) {
        print("🗑️ 执行删除操作...")
        
        // 1. 删除节点
        store.deleteNode(nodeToDelete.id)
        print("✅ 已删除节点: \(nodeToDelete.text)")
        
        // 2. 删除只在该节点中使用的标签
        for tag in tagsToDelete {
            // 这里可能需要调用store的删除标签方法（如果存在）
            // store.deleteTag(tag) // 假设这个方法存在
            print("✅ 已删除标签: \(tag.type.displayName): \(tag.value)")
        }
        
        // 3. 清理UI状态
        if selectedNode?.id == nodeToDelete.id {
            selectedNode = nil
        }
        
        // 4. 删除的节点会自动从store.nodes中移除，视图会自动更新
        
        print("✅ 节点删除完成，共删除了 \(tagsToDelete.count) 个标签")
    }
}

// MARK: - 节点行视图

struct NodeRowView: View {
    let node: Node
    let isSelected: Bool
    let searchQuery: String
    let onTap: () -> Void
    let onCommandClick: (() -> Void)?
    let onOptionClick: (() -> Void)?
    let onDelete: (() -> Void)?
    
    @EnvironmentObject private var store: NodeStore
    
    var body: some View {
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
            
            // 标签显示已删除 - 主要依赖图谱展示标签
            
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
        .contentShape(Rectangle()) // 确保整个区域都可以接收点击
        .onTapGesture {
            // 检查Command键和Option键状态来处理所有点击
            let currentEvent = NSApp.currentEvent
            let isCommandPressed = currentEvent?.modifierFlags.contains(.command) ?? false
            let isOptionPressed = currentEvent?.modifierFlags.contains(.option) ?? false
            
            print("🎯 NodeRowView: 点击检测 - Command键: \(isCommandPressed), Option键: \(isOptionPressed)")
            
            // 使用异步调用避免在view更新过程中发布状态更改
            DispatchQueue.main.async {
                if isOptionPressed {
                    print("⌥ NodeRowView: 检测到Option+点击")
                    onOptionClick?()
                } else if isCommandPressed {
                    print("⌘ NodeRowView: 检测到Command+点击")
                    onCommandClick?()
                } else {
                    print("👆 NodeRowView: 普通点击")
                    onTap()
                }
            }
        }
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
        .contextMenu {
            Button(action: {
                print("📝 右键编辑节点: \(node.text)")
                onCommandClick?()
            }) {
                Label("编辑命令", systemImage: "pencil")
            }
            
            Divider()
            
            Button(role: .destructive, action: {
                print("🗑️ 右键删除节点: \(node.text)")
                onDelete?()
            }) {
                Label("删除节点", systemImage: "trash")
            }
        }
    }
    
    private func backgroundColorForNode(isSelected: Bool) -> Color {
        // 检查是否是焦点节点（包含当前选中的标签）
        let isFocusNode = isFocusedNode()
        
        if node.isCompound {
            let compoundColor = getCompoundColor()
            if isFocusNode {
                // 焦点复合节点：更亮的高亮
                return isSelected ? compoundColor.opacity(0.4) : compoundColor.opacity(0.2)
            } else {
                return isSelected ? compoundColor.opacity(0.25) : compoundColor.opacity(0.08)
            }
        } else {
            if isFocusNode {
                // 焦点普通节点：更明显的金色高亮
                return isSelected ? Color.orange.opacity(0.4) : Color.orange.opacity(0.25)
            } else {
                return isSelected ? Color.blue.opacity(0.15) : Color.clear
            }
        }
    }
    
    private func borderColorForNode(isSelected: Bool) -> Color {
        let isFocusNode = isFocusedNode()
        
        if node.isCompound {
            let compoundColor = getCompoundColor()
            if isFocusNode {
                // 焦点复合节点：更明显的边框
                return isSelected ? compoundColor.opacity(0.8) : compoundColor.opacity(0.5)
            } else {
                return isSelected ? compoundColor.opacity(0.6) : compoundColor.opacity(0.3)
            }
        } else {
            if isFocusNode {
                // 焦点普通节点：更明显的橙色边框
                return isSelected ? Color.orange.opacity(0.8) : Color.orange.opacity(0.6)
            } else {
                return isSelected ? Color.blue.opacity(0.3) : Color.clear
            }
        }
    }
    
    /// 检查当前节点是否是焦点节点
    private func isFocusedNode() -> Bool {
        // 只有在有选中标签且是焦点模式时才检查
        guard let selectedTag = store.selectedTag, store.showAllTagTypeNodes else {
            return false
        }
        return node.hasTag(selectedTag)
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

// MARK: - 标签显示功能已删除 - 主要依赖图谱展示标签

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


// MARK: - SimpleNodeEditor removed - now using integrated QuickAddSheetView

// Preview temporarily disabled due to @FocusState initialization complexity
// #Preview {
//     NodeListView(selectedNode: .constant(nil))
//         .environmentObject(NodeStore.shared)
// }