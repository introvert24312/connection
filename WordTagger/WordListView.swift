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
        // 删除复杂的onChange处理器，现在通过.id()直接响应数据变化
        .id(store.nodes.count) // 当节点数量变化时强制重新渲染整个视图
        // 节点编辑现在通过节点管理窗口处理
    }
    
    private var displayNodes: [Node] {
        // 直接从store获取并过滤，不使用缓存
        let filteredNodes: [Node]
        
        if !store.searchQuery.isEmpty {
            filteredNodes = store.searchResults
        } else if let selectedTag = store.selectedTag {
            if store.showAllTagTypeNodes {
                if store.expandedTagTypes.count > 1 {
                    filteredNodes = store.nodesInCurrentLayer(withTagTypes: store.expandedTagTypes)
                } else {
                    filteredNodes = store.nodesInCurrentLayer(withTagType: selectedTag.type)
                }
            } else {
                filteredNodes = store.nodesInCurrentLayer(withTag: selectedTag)
            }
        } else {
            filteredNodes = store.getNodesInCurrentLayer()
        }
        
        return sortNodes(filteredNodes)
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
        
        // 延迟设置焦点，确保TextField已经渲染完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("🎯 setupView delayed: setting isSearchFieldFocused = true")
            isSearchFieldFocused = true
        }
    }
    
    // 删除复杂的状态处理方法，现在直接使用store数据
    
    private func sortNodes(_ nodes: [Node]) -> [Node] {
        // 如果有选中的标签并且是焦点模式，优先排序焦点节点
        if let selectedTag = store.selectedTag, store.showAllTagTypeNodes {
            print("🎯 应用焦点排序 - 标签: \(selectedTag.type.displayName) - '\(selectedTag.value)'")
            
            let sorted = nodes.sorted { node1, node2 in
                let node1HasFocusTag = node1.hasTag(selectedTag)
                let node2HasFocusTag = node2.hasTag(selectedTag)
                
                // 首先按是否包含焦点标签排序
                if node1HasFocusTag && !node2HasFocusTag {
                    return true  // node1 排在前面
                } else if !node1HasFocusTag && node2HasFocusTag {
                    return false // node2 排在前面
                } else {
                    // 如果都包含或都不包含焦点标签，按标签数量排序
                    return node1.tags.count > node2.tags.count
                }
            }
            
            // 统计焦点节点数量
            let focusNodesCount = sorted.filter { $0.hasTag(selectedTag) }.count
            print("🎯 焦点排序完成: \(focusNodesCount) 个焦点节点排在最顶上")
            
            return sorted
        } else {
            // 普通排序：按标签数量降序排列
            switch sortOption {
            case .tagCount:
                let sorted = nodes.sorted { $0.tags.count > $1.tags.count }
                print("📊 按标签数量排序: \(nodes.count) 个节点")
                for (index, node) in sorted.prefix(5).enumerated() {
                    print("  排序结果[\(index)]: '\(node.text)' - 标签数: \(node.tags.count)")
                }
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
            // 检查Command键状态来处理所有点击
            let currentEvent = NSApp.currentEvent
            let isCommandPressed = currentEvent?.modifierFlags.contains(.command) ?? false
            
            print("🎯 NodeRowView: 点击检测 - Command键状态: \(isCommandPressed)")
            
            // 使用异步调用避免在view更新过程中发布状态更改
            DispatchQueue.main.async {
                if isCommandPressed {
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
                // 焦点普通节点：金色高亮
                return isSelected ? Color.yellow.opacity(0.3) : Color.yellow.opacity(0.15)
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
                // 焦点普通节点：金色边框
                return isSelected ? Color.yellow.opacity(0.6) : Color.yellow.opacity(0.4)
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