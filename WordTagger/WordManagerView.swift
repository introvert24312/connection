import SwiftUI
import MapKit
import CoreLocation

struct NodeManagerView: View {
    @EnvironmentObject private var store: NodeStore
    @Binding var nodeToEdit: Node?
    @State private var selectedNodes: Set<UUID> = []
    @State private var localSearchQuery: String = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var showingDeleteAlert = false
    @State private var sortOption: SortOption = .createdDate
    @State private var selectedLayerIds: Set<UUID> = []
    @State private var selectedTagTypes: Set<Tag.TagType> = []
    @State private var selectedTagValues: Set<String> = []
    @State private var showingLayerPopover = false
    @State private var showingTagTypePopover = false
    @State private var showingTagValuePopover = false
    @State private var showingSortPopover = false
    @State private var layerSearchQuery = ""
    @State private var tagTypeSearchQuery = ""
    @State private var tagValueSearchQuery = ""
    @State private var showingCommandPalette = false
    @State private var commandPaletteNode: Node?
    @State private var isSelectionMode = false
    @FocusState private var isSearchFieldFocused: Bool
    
    enum SortOption: String, CaseIterable {
        case createdDate = "按创建时间"
        case updatedDate = "按修改时间"
        case tagCount = "按标签数量"
    }
    
    // 获取所有可用的标签类型
    var availableTagTypes: [Tag.TagType] {
        let allTypes = store.nodes.flatMap { $0.tags.map { $0.type } }
        let uniqueTypes = Array(Set(allTypes))
        return uniqueTypes.sorted { $0.displayName < $1.displayName }
    }
    
    // 获取选中标签类型下的所有标签值
    var availableTagValues: [String] {
        guard !selectedTagTypes.isEmpty else { return [] }
        let allValues = store.nodes.flatMap { node in
            node.tags.filter { selectedTagTypes.contains($0.type) }.map { $0.value }
        }
        let uniqueValues = Array(Set(allValues))
        return uniqueValues.sorted()
    }
    
    // 过滤后的层级列表
    var filteredLayers: [Layer] {
        if layerSearchQuery.isEmpty {
            return store.layers
        } else {
            return store.layers.filter { layer in
                layer.displayName.localizedCaseInsensitiveContains(layerSearchQuery)
            }
        }
    }
    
    // 过滤后的标签类型列表
    var filteredTagTypes: [Tag.TagType] {
        if tagTypeSearchQuery.isEmpty {
            return availableTagTypes
        } else {
            return availableTagTypes.filter { tagType in
                tagType.displayName.localizedCaseInsensitiveContains(tagTypeSearchQuery)
            }
        }
    }
    
    // 过滤后的标签值列表
    var filteredTagValues: [String] {
        if tagValueSearchQuery.isEmpty {
            return availableTagValues
        } else {
            return availableTagValues.filter { value in
                value.localizedCaseInsensitiveContains(tagValueSearchQuery)
            }
        }
    }
    
    // 按钮组件
    @ViewBuilder
    var filterButtons: some View {
        layerButton
        tagTypeButton
        tagValueButton
        sortButton
        modeButton
    }
    
    @ViewBuilder
    var layerButton: some View {
        Button(action: {
            showingLayerPopover.toggle()
        }) {
            HStack {
                Image(systemName: "folder")
                Text(selectedLayerIds.isEmpty ? "全部层级" : "层级(\(selectedLayerIds.count))")
            }
            .foregroundColor(.orange)
        }
        .help("层级筛选")
        .popover(isPresented: $showingLayerPopover) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("选择层级")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button("清除所有") {
                        selectedLayerIds.removeAll()
                        showingLayerPopover = false
                        layerSearchQuery = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(selectedLayerIds.isEmpty)
                }
                .padding(.bottom, 8)
                
                TextField("搜索层级...", text: $layerSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredLayers, id: \.id) { layer in
                            Button(action: {
                                if selectedLayerIds.contains(layer.id) {
                                    selectedLayerIds.remove(layer.id)
                                } else {
                                    selectedLayerIds.insert(layer.id)
                                }
                            }) {
                                HStack {
                                    Image(systemName: selectedLayerIds.contains(layer.id) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(selectedLayerIds.contains(layer.id) ? .orange : .secondary)
                                    Text(layer.displayName)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding()
            .frame(width: 250)
            .frame(maxHeight: 400)
        }
    }
    
    @ViewBuilder
    var tagTypeButton: some View {
        Button(action: {
            showingTagTypePopover.toggle()
        }) {
            HStack {
                Image(systemName: "tag")
                Text(selectedTagTypes.isEmpty ? "标签类型" : "类型(\(selectedTagTypes.count))")
            }
            .foregroundColor(.blue)
        }
        .help("标签类型筛选")
        .popover(isPresented: $showingTagTypePopover) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("选择标签类型")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button("清除所有") {
                        selectedTagTypes.removeAll()
                        selectedTagValues.removeAll()
                        showingTagTypePopover = false
                        tagTypeSearchQuery = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(selectedTagTypes.isEmpty)
                }
                .padding(.bottom, 8)
                
                TextField("搜索标签类型...", text: $tagTypeSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredTagTypes, id: \.rawValue) { tagType in
                            Button(action: {
                                if selectedTagTypes.contains(tagType) {
                                    selectedTagTypes.remove(tagType)
                                    if selectedTagTypes.isEmpty {
                                        selectedTagValues.removeAll()
                                    }
                                } else {
                                    selectedTagTypes.insert(tagType)
                                }
                            }) {
                                HStack {
                                    Image(systemName: selectedTagTypes.contains(tagType) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(selectedTagTypes.contains(tagType) ? .blue : .secondary)
                                    Text(tagType.displayName)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding()
            .frame(width: 250)
            .frame(maxHeight: 400)
        }
    }
    
    @ViewBuilder
    var tagValueButton: some View {
        Button(action: {
            showingTagValuePopover.toggle()
        }) {
            HStack {
                Image(systemName: "textformat")
                Text(selectedTagValues.isEmpty ? "标签值" : "值(\(selectedTagValues.count))")
            }
            .foregroundColor(.green)
        }
        .help("标签值筛选")
        .disabled(selectedTagTypes.isEmpty)
        .popover(isPresented: $showingTagValuePopover) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("选择标签值")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button("清除所有") {
                        selectedTagValues.removeAll()
                        showingTagValuePopover = false
                        tagValueSearchQuery = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(selectedTagValues.isEmpty)
                }
                .padding(.bottom, 8)
                
                TextField("搜索标签值...", text: $tagValueSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .disabled(availableTagValues.isEmpty)
                
                Divider()
                
                if availableTagValues.isEmpty {
                    Text("请先选择标签类型")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(filteredTagValues, id: \.self) { tagValue in
                                Button(action: {
                                    if selectedTagValues.contains(tagValue) {
                                        selectedTagValues.remove(tagValue)
                                    } else {
                                        selectedTagValues.insert(tagValue)
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: selectedTagValues.contains(tagValue) ? "checkmark.square.fill" : "square")
                                            .foregroundColor(selectedTagValues.contains(tagValue) ? .green : .secondary)
                                        Text(tagValue)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(width: 250)
            .frame(maxHeight: 400)
        }
    }
    
    @ViewBuilder
    var sortButton: some View {
        Button(action: {
            showingSortPopover.toggle()
        }) {
            HStack {
                Image(systemName: "arrow.up.arrow.down")
                Text(sortOption.rawValue)
            }
            .foregroundColor(.blue)
        }
        .help("排序选项")
        .popover(isPresented: $showingSortPopover) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("选择排序方式")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                .padding(.bottom, 8)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button(action: {
                            sortOption = option
                            showingSortPopover = false
                        }) {
                            HStack {
                                Image(systemName: sortOption == option ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(sortOption == option ? .blue : .secondary)
                                Text(option.rawValue)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding()
            .frame(width: 200)
        }
    }
    
    @ViewBuilder
    var modeButton: some View {
        Button(action: {
            isSelectionMode.toggle()
            if !isSelectionMode {
                selectedNodes.removeAll()
            }
        }) {
            HStack {
                Image(systemName: isSelectionMode ? "checkmark.circle.fill" : "cursor.rays")
                Text(isSelectionMode ? "选择模式" : "编辑模式")
            }
            .foregroundColor(isSelectionMode ? .orange : .blue)
        }
        .help(isSelectionMode ? "点击切换到编辑模式" : "点击切换到选择模式")
    }
    
    var filteredAndSortedNodes: [Node] {
        var nodes = store.nodes
        
        // 层级筛选
        if !selectedLayerIds.isEmpty {
            nodes = nodes.filter { selectedLayerIds.contains($0.layerId) }
        }
        
        // 如果有搜索查询，优先显示搜索结果，忽略selectedTag过滤
        if !localSearchQuery.isEmpty {
            nodes = nodes.filter { node in
                node.text.localizedCaseInsensitiveContains(localSearchQuery) ||
                (node.meaning?.localizedCaseInsensitiveContains(localSearchQuery) ?? false) ||
                (node.phonetic?.localizedCaseInsensitiveContains(localSearchQuery) ?? false) ||
                node.tags.contains { tag in
                    tag.value.localizedCaseInsensitiveContains(localSearchQuery) ||
                    tag.type.displayName.localizedCaseInsensitiveContains(localSearchQuery) ||
                    tag.type.rawValue.localizedCaseInsensitiveContains(localSearchQuery)
                }
            }
        } else if let selectedTag = store.selectedTag {
            // 只在没有搜索查询时应用selectedTag过滤
            nodes = nodes.filter { $0.hasTag(selectedTag) }
        }
        
        // 应用标签类型过滤
        if !selectedTagTypes.isEmpty {
            nodes = nodes.filter { node in
                node.tags.contains { selectedTagTypes.contains($0.type) }
            }
        }
        
        // 应用标签值过滤
        if !selectedTagValues.isEmpty {
            nodes = nodes.filter { node in
                node.tags.contains { selectedTagValues.contains($0.value) }
            }
        }
        
        // 应用排序
        switch sortOption {
        case .createdDate:
            nodes.sort { $0.createdAt > $1.createdAt }
        case .updatedDate:
            nodes.sort { $0.updatedAt > $1.updatedAt }
        case .tagCount:
            nodes.sort { $0.tags.count > $1.tags.count }
        }
        
        return nodes
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            VStack(spacing: 8) {
                // 第一行：搜索框和筛选按钮
                HStack(alignment: .top) {
                    // 搜索框 (灵活占用空间)
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("搜索节点、释义、音标或标签...", text: $localSearchQuery)
                            .textFieldStyle(.plain)
                            .focused($isSearchFieldFocused)
                            .onChange(of: localSearchQuery) { oldValue, newValue in
                                print("🔤 NodeManagerView: localSearchQuery changed from '\(oldValue)' to '\(newValue)'")
                                
                                // 取消之前的搜索任务
                                searchTask?.cancel()
                                
                                // 立即更新store的搜索查询，让Store的防抖机制处理重复请求
                                print("🔄 NodeManagerView: Immediately updating store.searchQuery to '\(newValue)'")
                                store.searchQuery = newValue
                                
                                // 保持焦点在输入框
                                DispatchQueue.main.async {
                                    isSearchFieldFocused = true
                                }
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .frame(minWidth: 150)  // 只设置最小宽度
                    .layoutPriority(0)    // 设置为低优先级，让筛选按钮先显示
                    
                    Spacer(minLength: 8)
                    
                    // 筛选按钮组 (响应式换行)
                    ViewThatFits {
                        // 尝试单行显示
                        HStack(spacing: 4) {
                            filterButtons
                        }
                        
                        // 空间不足时换行显示
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 4) {
                                layerButton
                                tagTypeButton
                                tagValueButton
                            }
                            HStack(spacing: 4) {
                                sortButton
                                modeButton
                            }
                        }
                    }
                    .layoutPriority(1)  // 给筛选按钮更高优先级，确保完整显示
                }
                
                // 第二行：状态显示（仅在有状态时显示）
                if !localSearchQuery.isEmpty || store.selectedTag != nil {
                    HStack {
                        if !localSearchQuery.isEmpty {
                            HStack(spacing: 4) {
                                Text("搜索: \"\(localSearchQuery)\" - 忽略标签过滤")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                
                                Button("✕") {
                                    localSearchQuery = ""
                                }
                                .font(.caption)
                                .foregroundColor(.green)
                                .buttonStyle(.plain)
                                .help("清除搜索")
                            }
                        } else if let selectedTag = store.selectedTag {
                            HStack(spacing: 4) {
                                Text("过滤: \(selectedTag.type.displayName) - \(selectedTag.value)")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                
                                Button("✕") {
                                    store.selectTag(nil)
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                                .buttonStyle(.plain)
                                .help("清除标签过滤")
                            }
                        }
                        
                        Spacer()
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 操作栏（只在选择模式下显示）
            if isSelectionMode {
                HStack {
                Text("选中 \(selectedNodes.count) / \(filteredAndSortedNodes.count) 个节点")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 全选/取消全选
                Button(action: {
                    if selectedNodes.count == filteredAndSortedNodes.count {
                        selectedNodes.removeAll()
                    } else {
                        selectedNodes = Set(filteredAndSortedNodes.map { $0.id })
                    }
                }) {
                    Text(selectedNodes.count == filteredAndSortedNodes.count ? "取消全选" : "全选")
                        .font(.caption)
                }
                .disabled(filteredAndSortedNodes.isEmpty)
                
                // 批量删除按钮
                Button(action: {
                    showingDeleteAlert = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("删除选中节点")
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                .disabled(selectedNodes.isEmpty)
                .alert("确认删除", isPresented: $showingDeleteAlert) {
                    Button("取消", role: .cancel) { }
                    Button("删除", role: .destructive) {
                        batchDeleteNodes()
                    }
                } message: {
                    Text("确定要删除选中的 \(selectedNodes.count) 个节点吗？此操作不可撤销。")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            }
            
            // 节点列表
            if filteredAndSortedNodes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
                    Group {
                        if localSearchQuery.isEmpty {
                            if store.selectedTag != nil {
                                Text("当前标签下暂无节点")
                            } else {
                                Text("暂无节点")
                            }
                        } else {
                            Text("未找到匹配 \"\(localSearchQuery)\" 的节点")
                        }
                    }
                    .font(.title3)
                    .foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        if !localSearchQuery.isEmpty {
                            Button("清除搜索") {
                                localSearchQuery = ""
                            }
                            .foregroundColor(.blue)
                        }
                        
                        if store.selectedTag != nil && localSearchQuery.isEmpty {
                            Button("清除标签过滤") {
                                store.selectTag(nil)
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredAndSortedNodes, id: \.id) { node in
                            NodeManagerRowView(
                                node: node,
                                isSelected: selectedNodes.contains(node.id),
                                isSelectionMode: isSelectionMode,
                                onToggleSelection: {
                                    if selectedNodes.contains(node.id) {
                                        selectedNodes.remove(node.id)
                                    } else {
                                        selectedNodes.insert(node.id)
                                    }
                                },
                                onNodeEdit: { node in
                                    commandPaletteNode = node
                                    showingCommandPalette = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
        }
        .navigationTitle("节点管理")
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("clearTagFilterFromKeyboard"))) { _ in
            print("🔑 NodeManagerView: 收到Command+T清除筛选器通知")
            clearAllFilters()
        }
        .sheet(item: Binding<Node?>(
            get: { showingCommandPalette ? commandPaletteNode : nil },
            set: { newValue in
                if newValue == nil {
                    showingCommandPalette = false
                    commandPaletteNode = nil
                }
            }
        )) { node in
            TagEditCommandView(node: node)
                .environmentObject(store)
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .onAppear {
            // 检查是否有待编辑的节点
            if let nodeToEdit = nodeToEdit {
                print("📝 NodeManagerView: 检测到待编辑节点: \(nodeToEdit.text)")
                // 自动打开编辑界面
                commandPaletteNode = nodeToEdit
                showingCommandPalette = true
                // 清除待编辑节点
                DispatchQueue.main.async {
                    self.nodeToEdit = nil
                }
            }
        }
        .onChange(of: nodeToEdit) { _, newNode in
            // 处理运行时设置的待编辑节点
            if let node = newNode {
                print("📝 NodeManagerView: onChange检测到待编辑节点: \(node.text)")
                commandPaletteNode = node
                showingCommandPalette = true
                // 清除待编辑节点
                DispatchQueue.main.async {
                    self.nodeToEdit = nil
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("nodeManagerEditNode"))) { notification in
            // 直接处理从其他窗口发送的编辑节点请求
            if let node = notification.object as? Node {
                print("📝 NodeManagerView: 收到直接编辑节点通知: \(node.text)")
                // 延迟一点时间确保视图已完全加载
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    print("📝 NodeManagerView: 延迟处理编辑节点请求: \(node.text)")
                    commandPaletteNode = node
                    showingCommandPalette = true
                }
            }
        }
    }
    
    private func batchDeleteNodes() {
        for nodeId in selectedNodes {
            store.deleteNode(nodeId)
        }
        selectedNodes.removeAll()
    }
    
    // 清除所有筛选器
    private func clearAllFilters() {
        selectedLayerIds.removeAll()
        selectedTagTypes.removeAll()
        selectedTagValues.removeAll()
        localSearchQuery = ""
        store.selectTag(nil)
        
        // 清除搜索查询
        layerSearchQuery = ""
        tagTypeSearchQuery = ""
        tagValueSearchQuery = ""
        
        print("🧹 已清除所有筛选器")
    }
}

// MARK: - Node Manager Row View

struct NodeManagerRowView: View {
    let node: Node
    let isSelected: Bool
    let isSelectionMode: Bool
    let onToggleSelection: () -> Void
    let onNodeEdit: (Node) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 选择框（只在选择模式下显示）
            if isSelectionMode {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .blue : .secondary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }
            
            // 节点信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    // 节点文本
                    Text(node.text)
                        .font(.system(size: 18, weight: .semibold, design: .default))
                        .foregroundColor(.primary)
                    
                    // 音标
                    if let phonetic = node.phonetic {
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
                    if !node.tags.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "tag.fill")
                                .font(.caption2)
                            Text("\(node.tags.count)")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                // 释义
                if let meaning = node.meaning, !meaning.isEmpty {
                    Text(meaning)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // 标签
                if !node.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(node.tags.prefix(5), id: \.id) { tag in
                                Group {
                                    if case .custom(let key) = tag.type, TagMappingManager.shared.isLocationTagKey(key), tag.hasCoordinates {
                                        // 位置标签添加点击预览功能
                                        Button(action: {
                                            previewLocation(tag: tag)
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "location.fill")
                                                    .font(.caption2)
                                                Text(tag.displayName)
                                                    .font(.caption)
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color.from(tagType: tag.type).opacity(0.2))
                                            )
                                            .foregroundColor(Color.from(tagType: tag.type))
                                        }
                                        .buttonStyle(.plain)
                                        .help("点击预览位置")
                                    } else {
                                        Text(tag.displayName)
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color.from(tagType: tag.type).opacity(0.2))
                                            )
                                            .foregroundColor(Color.from(tagType: tag.type))
                                    }
                                }
                            }
                            
                            if node.tags.count > 5 {
                                Text("+\(node.tags.count - 5)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // 时间信息
                HStack(spacing: 12) {
                    Text("创建: \(node.createdAt.timeAgoDisplay())")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if node.updatedAt > node.createdAt {
                        Text("修改: \(node.updatedAt.timeAgoDisplay())")
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
            if isSelectionMode {
                onToggleSelection()
            } else {
                onNodeEdit(node)
            }
        }
        .allowsHitTesting(true)
    }
    
    private func previewLocation(tag: Tag) {
        guard let latitude = tag.latitude,
              let longitude = tag.longitude else { return }
        
        print("🎯 Previewing location: \(tag.displayName) at (\(latitude), \(longitude))")
        
        // 打开地图窗口
        NotificationCenter.default.post(name: NSNotification.Name("openMapWindow"), object: nil)
        
        // 延迟发送位置预览通知，给地图窗口时间打开
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let previewData: [String: Any] = [
                "latitude": latitude,
                "longitude": longitude,
                "name": tag.displayName,
                "isPreview": true
            ]
            
            NotificationCenter.default.post(
                name: NSNotification.Name("previewLocation"),
                object: previewData
            )
        }
    }
}

// MARK: - Tag Edit Command View

struct TagEditCommandView: View {
    let node: Node
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    @State private var commandText: String = ""
    @State private var selectedIndex: Int = 0
    @State private var showingLocationPicker = false
    @StateObject private var commandParser = CommandParser.shared
    @State private var showingDuplicateAlert = false
    @State private var showingMappingConflictAlert = false
    @State private var mappingConflictMessage = ""
    @State private var refreshTrigger = false  // 用于强制刷新UI
    
    // 从store获取最新的节点数据
    private var currentNode: Node {
        return store.nodes.first { $0.id == node.id } ?? node
    }
    
    private var initialCommand: String {
        // 使用最新的节点数据和带展示名的命令表示
        let currentNodeData = currentNode
        
        // 使用refreshTrigger来强制重新计算（当复合节点需要刷新时）
        _ = refreshTrigger
        
        // 🔧 使用动态版本显示标签展示名，包含实时的子节点信息  
        // 格式：节点名 @节点1 @节点2 标签类型1[展示名1] 标签值1 标签类型2[展示名2] 标签值2 ...
        return currentNodeData.dynamicCommandRepresentationWithDisplayNames(allNodes: store.nodes)
    }
    
    @State private var availableCommands: [Command] = []
    
    @MainActor
    private func updateAvailableCommands() {
        let context = CommandContext(store: store, currentNode: node)
        Task {
            availableCommands = await commandParser.parse(commandText, context: context)
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // 标题栏
            HStack {
                Text("编辑节点: \(node.text)")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("执行") {
                    executeCommand()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("e", modifiers: [.command])
            }
            .padding()
            
            Divider()
            
            // 命令输入框
            VStack(alignment: .leading, spacing: 12) {
                Text("输入标签命令:")
                    .font(.headline)
                
                TextField("例如: memory 记忆法 root dict", text: $commandText)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onSubmit {
                        executeCommand()
                    }
                    .onChange(of: commandText) { _, _ in
                        updateAvailableCommands()
                    }
                    .onKeyPress(.tab) {
                        handleTabCompletion()
                        return .handled
                    }
                
                Text("当前命令: \(commandText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // 当前标签显示
            VStack(alignment: .leading, spacing: 8) {
                Text("当前标签 (\(node.tags.count)个):")
                    .font(.headline)
                
                if node.tags.isEmpty {
                    Text("暂无标签")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(node.tags, id: \.id) { tag in
                                HStack(spacing: 4) {
                                    Text(tag.type.displayName)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text(tag.value)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.from(tagType: tag.type).opacity(0.2))
                                )
                                .foregroundColor(Color.from(tagType: tag.type))
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
            .padding()
            
            Divider()
            
            // 使用说明
            VStack(alignment: .leading, spacing: 8) {
                Text("💡 使用提示:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• 格式: 标签类型 标签值")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("• 多个标签用空格分隔")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                        
                    Text("• 示例: memory 记忆法 root dict shape 长方形")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Spacer()
        }
        .frame(minWidth: 500, maxWidth: 600, minHeight: 400, maxHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            print("📝 TagEditCommandView onAppear")
            print("📝 传入节点: \(node.text), 标签数: \(node.tags.count)")
            let currentNodeData = currentNode
            print("📝 最新节点: \(currentNodeData.text), 标签数: \(currentNodeData.tags.count)")
            for (index, tag) in currentNodeData.tags.enumerated() {
                print("📝   标签[\(index)]: \(tag.type.displayName) = '\(tag.value)' (rawValue: '\(tag.type.rawValue)')")
            }
            print("📝 生成的初始命令: '\(initialCommand)'")
            commandText = initialCommand
            updateAvailableCommands()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("compoundNodeRefreshed"))) { notification in
            handleCompoundNodeRefreshed(notification)
        }
        .onKeyPress(.init("r"), phases: .down) { _ in
            if NSEvent.modifierFlags.contains(.command) && !NSEvent.modifierFlags.contains(.shift) {
                executeCommand()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .background(
            Button("") {
                openMapForLocationSelection()
            }
            .keyboardShortcut("p", modifiers: [.command])
            .hidden()
        )
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("locationSelected"))) { notification in
            if let locationData = notification.object as? [String: Any],
               let latitude = locationData["latitude"] as? Double,
               let longitude = locationData["longitude"] as? Double {
                
                // 如果有地名信息，使用地名；否则让用户自己输入
                let locationCommand: String
                if let locationName = locationData["name"] as? String {
                    locationCommand = "loc @\(latitude),\(longitude)[\(locationName)]"
                    print("🎯 NodeManager: Using location with name: \(locationName)")
                } else {
                    locationCommand = "loc @\(latitude),\(longitude)[]"
                    print("🎯 NodeManager: Using coordinates only, user needs to fill name")
                }
                
                if commandText.isEmpty || commandText == initialCommand {
                    commandText = "\(node.text) \(locationCommand)"
                } else {
                    commandText += " \(locationCommand)"
                }
            }
        }
        .alert("重复检测", isPresented: $showingDuplicateAlert) {
            if let alert = store.duplicateNodeAlert {
                if alert.isContextConflict {
                    // 上下文冲突：提供强制添加选项
                    Button("取消", role: .cancel) { 
                        store.duplicateNodeAlert = nil
                    }
                    Button("忽略冲突，强制添加") {
                        // 强制添加节点
                        _ = store.forceAddNode(alert.newNode, ignoreConflicts: true)
                        store.duplicateNodeAlert = nil
                    }
                } else if alert.isDuplicate && alert.existingNode != nil {
                    // 节点重复，询问是否合并
                    Button("取消", role: .cancel) { 
                        store.duplicateNodeAlert = nil
                    }
                    Button("合并标签") {
                        // 执行标签合并
                        if let existingNode = alert.existingNode {
                            let newTags = alert.newNode.tags.filter { newTag in
                                !existingNode.tags.contains { existingTag in
                                    existingTag.type == newTag.type && existingTag.value.lowercased() == newTag.value.lowercased()
                                }
                            }
                            
                            for tag in newTags {
                                store.addTag(to: existingNode.id, tag: tag)
                            }
                        }
                        store.duplicateNodeAlert = nil
                    }
                    Button("创建新节点") {
                        // 强制添加新节点
                        _ = store.forceAddNode(alert.newNode, ignoreConflicts: true)
                        store.duplicateNodeAlert = nil
                    }
                } else {
                    // 其他错误或信息
                    Button("确定") { 
                        store.duplicateNodeAlert = nil
                    }
                }
            } else {
                Button("确定") { }
            }
        } message: {
            if let alert = store.duplicateNodeAlert {
                Text(alert.message)
            }
        }
        .alert("标签映射冲突", isPresented: $showingMappingConflictAlert) {
            Button("确定", role: .cancel) {
                // 用户确认错误后，保持窗口打开让用户修改命令
                // 不关闭窗口，只关闭alert
            }
        } message: {
            Text(mappingConflictMessage)
        }
        .onReceive(store.$duplicateNodeAlert) { alert in
            if alert != nil {
                showingDuplicateAlert = true
                // 延迟清除alert以避免立即触发下一次
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    store.duplicateNodeAlert = nil
                }
            }
        }
    }
    
    private func handleTabCompletion() {
        print("🔍 Tab补全触发")
        
        // 获取光标位置和当前单词
        let words = commandText.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard !words.isEmpty else { return }
        
        let currentWord = words.last ?? ""
        print("🔍 当前单词: '\(currentWord)'")
        
        // 检查是否是@节点引用格式
        if currentWord.hasPrefix("@") {
            let partialNodeName = String(currentWord.dropFirst())
            print("🔗 检测到节点引用补全: '\(partialNodeName)'")
            
            // 查找匹配的节点名
            let matchingNodes = store.nodes.filter { node in
                node.text.lowercased().contains(partialNodeName.lowercased())
            }.map { $0.text }
            
            if let firstMatch = matchingNodes.first {
                // 替换当前单词
                var newWords = words.dropLast()
                newWords.append("@\(firstMatch)")
                commandText = newWords.joined(separator: " ")
                print("✅ 节点名补全完成: @\(firstMatch)")
            } else {
                print("❌ 未找到匹配的节点名")
            }
        } else {
            // 标签补全（保持原有逻辑）
            let mappings = TagMappingManager.shared.tagMappings
            let matchingKeys = mappings.filter { mapping in
                mapping.key.lowercased().hasPrefix(currentWord.lowercased())
            }
            
            if let firstMatch = matchingKeys.first {
                var newWords = words.dropLast()
                newWords.append(firstMatch.key)
                commandText = newWords.joined(separator: " ")
                print("✅ 标签补全完成: \(firstMatch.key)")
            } else {
                print("❌ 未找到匹配的标签")
            }
        }
    }
    
    private func executeCommand() {
        print("🚀 executeCommand() 被调用")
        print("🚀 当前命令文本: '\(commandText)'")
        
        let trimmedText = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🚀 去除空格后的命令: '\(trimmedText)'")
        
        guard !trimmedText.isEmpty else { 
            print("⚠️ 命令为空，直接关闭窗口")
            dismiss()
            return 
        }
        
        print("🔧 执行节点编辑命令: \(trimmedText)")
        
        Task {
            // 使用新的批量标签解析器
            let success = await parseBatchTagCommand(trimmedText)
            
            await MainActor.run {
                if success {
                    DispatchQueue.main.async {
                        store.objectWillChange.send()
                    }
                    print("✅ 标签批量更新成功")
                    print("🚪 关闭节点编辑窗口")
                    dismiss()
                } else {
                    print("❌ 标签批量更新失败")
                    // 如果失败了，检查是否有映射冲突alert正在显示
                    if showingMappingConflictAlert {
                        print("⚠️ 有映射冲突alert正在显示，保持窗口打开")
                        // 不关闭窗口，让用户看到错误提示
                    } else {
                        print("🚪 关闭节点编辑窗口")
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func parseBatchTagCommand(_ input: String) async -> Bool {
        print("🔧 parseBatchTagCommand 开始解析: '\(input)'")
        
        // 分词：按空格分割
        let tokens = input.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        print("🔧 分词结果: \(tokens)")
        print("🔧 分词详情:")
        for (index, token) in tokens.enumerated() {
            print("   [\(index)]: '\(token)'")
        }
        
        guard tokens.count >= 1 else { 
            print("❌ Token数量不足: \(tokens.count) < 1")
            return false 
        }
        
        // 第一个token是新的节点名（可以重命名）
        let newNodeName = tokens[0]
        let needsRename = newNodeName != node.text
        
        if needsRename {
            print("🔄 检测到重命名: '\(node.text)' -> '\(newNodeName)'")
        } else {
            print("✅ 节点名保持不变: \(newNodeName)")
        }
        
        // 如果只有节点名（1个token）
        if tokens.count == 1 {
            await MainActor.run {
                if needsRename {
                    print("🔄 只重命名，保持标签不变: '\(node.text)' -> '\(newNodeName)'")
                    store.updateNode(node.id, text: newNodeName, phonetic: nil, meaning: nil)
                    DispatchQueue.main.async {
                        store.objectWillChange.send()
                    }
                    // 延迟强制刷新，确保所有UI组件都收到更新
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        store.forceRefreshUI()
                        // 发送通知强制刷新NodeListView
                        NotificationCenter.default.post(name: NSNotification.Name("forceRefreshNodeList"), object: nil)
                        print("🔄 强制UI刷新完成（重命名）")
                    }
                    print("✅ 节点重命名完成")
                } else {
                    print("🧹 只有节点名且名称相同，清空所有标签")
                    let currentNode = store.nodes.first { $0.id == node.id }
                    if let existingNode = currentNode {
                        print("🗑️ 清空现有的 \(existingNode.tags.count) 个标签")
                        for tag in existingNode.tags {
                            store.removeTag(from: node.id, tagId: tag.id)
                        }
                        print("✅ 所有标签已清空")
                    } else {
                        print("❌ 未找到对应节点")
                    }
                }
            }
            return true
        }
        
        // 解析剩余的标签token
        var newTags: [Tag] = []
        var i = 1
        
        print("🔧 开始解析标签tokens，从索引 \(i) 开始")
        
        while i < tokens.count {
            let token = tokens[i]
            print("🔧 [主循环] 处理token [\(i)]: '\(token)'，总token数: \(tokens.count)")
            
            // 检查是否是节点引用（@节点名格式）
            if token.hasPrefix("@") {
                let referencedNodeName = String(token.dropFirst()) // 去掉@前缀
                print("🔗 检测到节点引用: '\(referencedNodeName)'")
                print("🔍 当前所有节点名: \(store.nodes.map { $0.text })")
                
                // 查找被引用的节点
                if let referencedNode = store.nodes.first(where: { $0.text == referencedNodeName }) {
                    print("✅ 找到引用节点: '\(referencedNodeName)', 标签数: \(referencedNode.tags.count)")
                    
                    // 添加子节点标签
                    let childTag = Tag(type: .custom("child"), value: referencedNodeName)
                    newTags.append(childTag)
                    print("🏷️ 添加子节点标签: child = '\(referencedNodeName)'")
                    
                    // 不再聚合引用节点的标签，保持命令行简洁
                } else {
                    print("❌ 未找到引用节点: '\(referencedNodeName)'")
                    print("❌ 跳过创建child标签，因为引用的节点不存在")
                    // 不创建任何标签，直接跳过这个token
                }
                
                i += 1
                continue
            }
            
            // 检查是否是标签类型关键词
            if let tagType = mapTokenToTagType(token) {
                print("✅ 识别标签类型: '\(token)' -> \(tagType)")
                let tagKey = token  // 保存原始token作为key
                
                // 检查是否是 tagType[displayName] 格式，如果是则需要处理显示名
                var customDisplayName: String? = nil
                if token.contains("[") && token.contains("]") {
                    if let bracketStart = token.firstIndex(of: "["),
                       let bracketEnd = token.firstIndex(of: "]"),
                       bracketStart < bracketEnd && token.index(after: bracketStart) <= bracketEnd {
                        
                        let displayName = String(token[token.index(after: bracketStart)..<bracketEnd])
                        customDisplayName = displayName
                        print("🏷️ 检测到标签类型自定义显示名: '\(displayName)'")
                        
                        // 为该标签类型设置自定义显示名
                        let baseTagKey = String(token[..<bracketStart])
                        print("🔧 准备添加映射: key='\(baseTagKey)', typeName='\(displayName)'")
                        
                        // 检查映射冲突
                        let conflictResult = TagMappingManager.shared.checkMappingConflict(key: baseTagKey, typeName: displayName)
                        switch conflictResult {
                        case .conflict(let existing, let requested):
                            print("🔄 映射更新请求：快捷键 '\(baseTagKey)' 从 '\(existing.typeName)' 更新到 '\(requested)'")
                            // 继续创建标签，映射更新由 Node.updateTagDisplayName 处理
                            break
                        case .noConflict(_), .canCreate:
                            let success = TagMappingManager.shared.addMappingIfNeeded(key: baseTagKey, typeName: displayName)
                            if !success {
                                print("❌ 添加映射失败: key='\(baseTagKey)', typeName='\(displayName)'")
                                return false
                            }
                            print("🔧 映射添加完成，当前映射数量: \(TagMappingManager.shared.tagMappings.count)")
                        }
                    }
                }
                
                i += 1
                
                // 收集这个标签类型的值
                var values: [String] = []
                print("🔧 收集标签值，从索引 \(i) 开始")
                
                // 特殊处理位置标签：如果是位置标签，需要特别处理坐标格式
                if TagMappingManager.shared.isLocationTagKey(tagKey) {
                    // 对于位置标签，可能有多种格式，需要更智能的解析
                    // 1. 单个完整坐标token: @lat,lng[name]
                    // 2. 分离的tokens: name @lat,lng 或其他组合
                    while i < tokens.count {
                        let nextToken = tokens[i]
                        print("🔧 检查位置标签值 [\(i)]: '\(nextToken)'")
                        
                        // 如果遇到下一个标签类型（但排除坐标格式），停止
                        if mapTokenToTagType(nextToken) != nil {
                            print("🔧 遇到下一个标签类型: '\(nextToken)'，停止收集位置标签值")
                            break
                        }
                        
                        values.append(nextToken)
                        print("🔧 添加位置标签值: '\(nextToken)'，当前值列表: \(values)")
                        
                        // 如果当前token是完整的坐标格式（包含@和[]），这是完整的位置标签值
                        if nextToken.hasPrefix("@") && nextToken.contains("[") && nextToken.contains("]") {
                            print("🔧 检测到完整坐标格式，这是位置标签的完整值")
                            print("🔧 当前索引 i = \(i)，即将跳出位置标签值收集循环")
                            i += 1
                            break
                        }
                        
                        i += 1
                    }
                } else {
                    // 普通标签的值收集逻辑：标签类型 标签值 配对模式
                    if i < tokens.count {
                        let nextToken = tokens[i]
                        print("🔧 检查标签值 [\(i)]: '\(nextToken)'")
                        
                        // 检查是否是 value[displayName] 格式
                        if nextToken.contains("[") && nextToken.contains("]"),
                           let bracketStart = nextToken.firstIndex(of: "["),
                           let bracketEnd = nextToken.firstIndex(of: "]"),
                           bracketStart < bracketEnd && nextToken.index(after: bracketStart) <= bracketEnd {
                            
                            let tagValue = String(nextToken[..<bracketStart])
                            let displayName = String(nextToken[nextToken.index(after: bracketStart)..<bracketEnd])
                            
                            print("🔧 检测到value[displayName]格式: value='\(tagValue)', displayName='\(displayName)'")
                            
                            // 检查是否是快捷键格式：tagValue是快捷键，displayName是类型名
                            // 如果TagMappingManager中已存在该快捷键映射，则这是快捷键格式
                            let isShortcutFormat = TagMappingManager.shared.tagMappings.contains { mapping in
                                mapping.key.lowercased() == tagValue.lowercased() && mapping.typeName == displayName
                            }
                            
                            let customTagType: Tag.TagType
                            let isShortcut: Bool
                            
                            if isShortcutFormat {
                                // 快捷键格式：beef[牛肉种类] -> 使用tagValue作为type的key
                                customTagType = Tag.TagType.custom(tagValue)
                                isShortcut = true
                                print("🔧 识别为快捷键格式: key='\(tagValue)', typeName='\(displayName)'")
                            } else {
                                // 普通value[displayName]格式 -> 使用displayName作为type的key
                                customTagType = Tag.TagType.custom(displayName)
                                isShortcut = false
                                
                                // 检查映射冲突
                                let conflictResult = TagMappingManager.shared.checkMappingConflict(key: displayName, typeName: displayName)
                                switch conflictResult {
                                case .conflict(let existing, let requested):
                                    print("🔄 映射更新请求：快捷键 '\(displayName)' 从 '\(existing.typeName)' 更新到 '\(requested)'")
                                    // 继续创建标签，映射更新由 Node.updateTagDisplayName 处理
                                    break
                                case .noConflict(_), .canCreate:
                                    let success = TagMappingManager.shared.addMappingIfNeeded(key: displayName, typeName: displayName)
                                    if !success {
                                        print("❌ 添加映射失败: key='\(displayName)', typeName='\(displayName)'")
                                        i += 1
                                        continue
                                    }
                                }
                                
                                print("🔧 识别为普通格式: key='\(displayName)', value='\(tagValue)'")
                            }
                            
                            // 创建标签
                            let tag = store.createTag(type: customTagType, value: tagValue, isShortcutType: isShortcut)
                            newTags.append(tag)
                            print("✅ 创建自定义标签: \(displayName) - \(tagValue)")
                            
                            i += 1
                            continue // 跳过后续的普通处理逻辑
                        } else {
                            // 普通标签值处理
                            values.append(nextToken)
                            print("🔧 添加标签值: '\(nextToken)'")
                            i += 1
                        }
                    }
                }
                
                print("🔧 收集的值: \(values)")
                print("🔧 标签值收集完成，当前索引 i = \(i)，下一个token: \(i < tokens.count ? tokens[i] : "超出范围")")
                
                // 创建标签
                let value: String
                if !values.isEmpty {
                    value = values.joined(separator: " ")
                    print("🔧 创建标签，类型: \(tagType)，值: '\(value)'")
                } else {
                    // 如果没有收集到值，使用标签类型的显示名称作为值
                    value = tagType.displayName
                    print("🔧 创建无值标签，类型: \(tagType)，使用显示名称作为值: '\(value)'")
                }
                
                // 如果有自定义显示名，创建自定义标签类型
                let finalTagType: Tag.TagType
                if let customDisplayName = customDisplayName {
                    finalTagType = Tag.TagType.custom(customDisplayName)
                    print("🏷️ 使用自定义标签类型: \(customDisplayName)")
                } else {
                    finalTagType = tagType
                }
                    
                    // 检查是否是地图标签（通过key识别）
                    if TagMappingManager.shared.isLocationTagKey(tagKey) {
                        var locationName: String = ""
                        var lat: Double = 0
                        var lng: Double = 0
                        var parsed = false
                        
                        // 格式1: 名称@纬度,经度 (如: 天马广场@37.45,121.61)
                        if value.contains("@") && !value.hasPrefix("@") {
                            let components = value.split(separator: "@", maxSplits: 1)
                            if components.count == 2 {
                                locationName = String(components[0])
                                let coordString = String(components[1])
                                let coords = coordString.split(separator: ",")
                                
                                if coords.count == 2,
                                   let latitude = Double(coords[0]),
                                   let longitude = Double(coords[1]) {
                                    lat = latitude
                                    lng = longitude
                                    parsed = true
                                }
                            }
                        }
                        // 格式2: @纬度,经度[名称] (如: @37.45,121.61[天马广场])
                        else if value.hasPrefix("@") && value.contains("[") && value.contains("]") {
                            print("🔍 解析格式2坐标: \(value)")
                            // 提取坐标部分 @纬度,经度
                            if let atIndex = value.firstIndex(of: "@"),
                               let bracketIndex = value.firstIndex(of: "["),
                               atIndex < bracketIndex && value.index(after: atIndex) <= bracketIndex {
                                let coordString = String(value[value.index(after: atIndex)..<bracketIndex])
                                print("🔍 提取的坐标字符串: '\(coordString)'")
                                let coords = coordString.split(separator: ",")
                                print("🔍 分割后的坐标: \(coords)")
                                
                                if coords.count == 2 {
                                    let latString = String(coords[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                                    let lngString = String(coords[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                                    print("🔍 纬度字符串: '\(latString)', 经度字符串: '\(lngString)'")
                                    
                                    if let latitude = Double(latString),
                                       let longitude = Double(lngString) {
                                        lat = latitude
                                        lng = longitude
                                        print("🔍 坐标解析成功: lat=\(lat), lng=\(lng)")
                                        
                                        // 提取名称部分 [名称]
                                        if let startBracket = value.firstIndex(of: "["),
                                           let endBracket = value.firstIndex(of: "]"),
                                           startBracket < endBracket && value.index(after: startBracket) <= endBracket {
                                            locationName = String(value[value.index(after: startBracket)..<endBracket])
                                            print("🔍 地名解析成功: '\(locationName)'")
                                            parsed = true
                                        } else {
                                            print("❌ 地名解析失败")
                                        }
                                    } else {
                                        print("❌ 坐标转换为Double失败")
                                    }
                                } else {
                                    print("❌ 坐标分割后不是2个部分")
                                }
                            } else {
                                print("❌ 找不到@或[符号")
                            }
                        }
                        // 格式3: 简单地名引用 (如: 武功山) - 新增功能
                        else if !value.contains("@") && !value.contains("[") && !value.contains("]") {
                            // 尝试在已有的位置标签中查找匹配的地名
                            if let existingTag = store.findLocationTagByName(value) {
                                locationName = existingTag.value
                                if let existingLat = existingTag.latitude, let existingLng = existingTag.longitude {
                                    lat = existingLat
                                    lng = existingLng
                                    parsed = true
                                    print("🎯 找到已有位置标签: \(locationName) (\(lat), \(lng))")
                                }
                            }
                        }
                        
                        if parsed && !locationName.isEmpty {
                            // 对于成功解析的位置标签，只保存地名作为value，坐标保存在专门字段中
                            let tag = store.createTag(type: finalTagType, value: locationName, latitude: lat, longitude: lng, isShortcutType: customDisplayName != nil)
                            newTags.append(tag)
                            print("✅ 创建位置标签: \(locationName) (\(lat), \(lng))")
                            print("✅ 标签详情: type=\(tag.type.rawValue), value=\(tag.value), hasCoords=\(tag.hasCoordinates)")
                            print("✅ 坐标验证: lat=\(tag.latitude?.description ?? "nil"), lng=\(tag.longitude?.description ?? "nil")")
                        } else if TagMappingManager.shared.isLocationTagKey(tagKey) && !value.contains("@") {
                            // 如果是location标签但没有找到匹配的位置，提示用户
                            print("⚠️ 未找到位置标签: \(value)，请使用完整格式或确保该位置已存在")
                            // 创建无坐标的位置标签作为fallback
                            let tag = store.createTag(type: finalTagType, value: value, isShortcutType: customDisplayName != nil)
                            newTags.append(tag)
                        } else if TagMappingManager.shared.isLocationTagKey(tagKey) {
                            // 如果是location标签但解析失败，打印详细错误信息
                            print("❌ 位置标签解析失败: \(value)")
                            print("❌   parsed: \(parsed), locationName: '\(locationName)', lat: \(lat), lng: \(lng)")
                            // 创建无坐标的位置标签作为fallback
                            let tag = store.createTag(type: finalTagType, value: value, isShortcutType: customDisplayName != nil)
                            newTags.append(tag)
                        } else {
                            // 普通标签
                            let tag = store.createTag(type: finalTagType, value: value, isShortcutType: customDisplayName != nil)
                            newTags.append(tag)
                        }
                    } else {
                        // 普通标签 - 检查是否是快捷键类型
                        // 如果tagType来自映射查找且不同于原始token，则这是快捷键
                        let isShortcut = customDisplayName != nil || TagMappingManager.shared.tagMappings.contains { mapping in
                            mapping.key.lowercased() == tagKey.lowercased() && finalTagType.displayName == mapping.key
                        }
                        let tag = store.createTag(type: finalTagType, value: value, isShortcutType: isShortcut)
                        newTags.append(tag)
                        print("✅ 创建标签: \(finalTagType.displayName) - \(value)")
                    }
                print("🔧 标签处理完成，当前索引 i = \(i)，准备继续主循环")
            } else {
                // 检查是否是独立的 value[displayName] 格式（不需要前置标签类型）
                if token.contains("[") && token.contains("]"),
                   let bracketStart = token.firstIndex(of: "["),
                   let bracketEnd = token.firstIndex(of: "]"),
                   bracketStart < bracketEnd && token.index(after: bracketStart) <= bracketEnd {
                    
                    let tagValue = String(token[..<bracketStart])
                    let displayName = String(token[token.index(after: bracketStart)..<bracketEnd])
                    
                    print("🔧 检测到独立的value[displayName]格式: value='\(tagValue)', displayName='\(displayName)'")
                    
                    // 检查是否是快捷键格式：tagValue是快捷键，displayName是类型名
                    let isShortcut = TagMappingManager.shared.tagMappings.contains { mapping in
                        mapping.key.lowercased() == tagValue.lowercased() && mapping.typeName == displayName
                    }
                    
                    let customTagType: Tag.TagType
                    if isShortcut {
                        // 快捷键格式：beef[牛肉种类] -> 使用tagValue作为type的key
                        customTagType = Tag.TagType.custom(tagValue)
                        print("🔧 独立快捷键格式: key='\(tagValue)', typeName='\(displayName)'")
                    } else {
                        // 普通value[displayName]格式 -> 使用displayName作为type的key
                        customTagType = Tag.TagType.custom(displayName)
                        
                        // 检查映射冲突
                        let conflictResult = TagMappingManager.shared.checkMappingConflict(key: displayName, typeName: displayName)
                        switch conflictResult {
                        case .conflict(let existing, let requested):
                            print("🔄 映射更新请求：快捷键 '\(displayName)' 从 '\(existing.typeName)' 更新到 '\(requested)'")
                            // 继续创建标签，映射更新由 Node.updateTagDisplayName 处理
                            break
                        case .noConflict(_), .canCreate:
                            let success = TagMappingManager.shared.addMappingIfNeeded(key: displayName, typeName: displayName)
                            if !success {
                                print("❌ 添加映射失败: key='\(displayName)', typeName='\(displayName)'")
                                i += 1
                                continue
                            }
                        }
                        
                        print("🔧 独立普通格式: key='\(displayName)', value='\(tagValue)'")
                    }
                    
                    let tag = store.createTag(type: customTagType, value: tagValue, isShortcutType: isShortcut)
                    newTags.append(tag)
                    print("✅ 创建独立自定义标签: \(displayName) - \(tagValue)")
                    
                    i += 1
                } else {
                    print("❌ token '\(token)' 不是标签类型，跳过")
                    i += 1
                }
            }
        }
        
        print("🔧 解析完成，创建了 \(newTags.count) 个标签:")
        for (index, tag) in newTags.enumerated() {
            print("  [\(index)] \(tag.type.displayName): \(tag.value)")
        }
        
        // 只有当成功解析出标签时才替换节点的所有标签
        if !newTags.isEmpty {
            print("✅ 开始替换节点标签")
            
            // 不再自动添加 compound 标签，保持命令行简洁
            
            await MainActor.run {
                // 先删除所有现有标签
                let currentNode = store.nodes.first { $0.id == node.id }
                if let existingNode = currentNode {
                    print("🗑️ 删除现有的 \(existingNode.tags.count) 个标签")
                    for tag in existingNode.tags {
                        store.removeTag(from: node.id, tagId: tag.id)
                    }
                }
                
                // 添加新标签
                print("➕ 添加 \(newTags.count) 个新标签")
                for tag in newTags {
                    store.addTag(to: node.id, tag: tag)
                }
            }
            print("✅ 标签替换完成")
            
            // 处理重命名
            if needsRename {
                print("🔄 执行节点重命名: '\(node.text)' -> '\(newNodeName)'")
                store.updateNode(node.id, text: newNodeName, phonetic: nil, meaning: nil)
                DispatchQueue.main.async {
                    store.objectWillChange.send()
                }
                // 延迟强制刷新，确保所有UI组件都收到更新
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    store.forceRefreshUI()
                    print("🔄 强制UI刷新完成（重命名）")
                }
                print("✅ 节点重命名完成")
            }
            
            return true
        } else {
            print("❌ 没有解析出任何标签")
            // 即使没有标签变化，也要处理重命名
            await MainActor.run {
                if needsRename {
                    print("🔄 只有重命名操作: '\(node.text)' -> '\(newNodeName)'")
                    store.updateNode(node.id, text: newNodeName, phonetic: nil, meaning: nil)
                    DispatchQueue.main.async {
                        store.objectWillChange.send()
                    }
                    // 延迟强制刷新，确保所有UI组件都收到更新
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        store.forceRefreshUI()
                        // 发送通知强制刷新NodeListView
                        NotificationCenter.default.post(name: NSNotification.Name("forceRefreshNodeList"), object: nil)
                        print("🔄 强制UI刷新完成（重命名）")
                    }
                    print("✅ 节点重命名完成")
                }
            }
            return needsRename // 如果有重命名则返回true，否则返回false
        }
    }
    
    private func mapTokenToTagType(_ token: String) -> Tag.TagType? {
        // 检查是否是坐标格式或其他特殊值格式，如果是则不当作标签类型
        if token.hasPrefix("@") && (token.contains("[") || token.contains(",")) {
            print("🔍 mapTokenToTagType: '\(token)' -> 跳过（坐标格式）")
            return nil
        }
        
        // 检查是否是完整的坐标格式 @lat,lng[name]
        if token.hasPrefix("@") && token.contains(",") && token.contains("[") && token.contains("]") {
            print("🔍 mapTokenToTagType: '\(token)' -> 跳过（完整坐标格式）")
            return nil
        }
        
        // 检查是否是纯数字（可能是坐标的一部分）
        if Double(token) != nil && token.contains(".") {
            print("🔍 mapTokenToTagType: '\(token)' -> 跳过（疑似坐标数字）")
            return nil
        }
        
        // 检查是否是带引号的值，如果是则不当作标签类型
        if (token.hasPrefix("\"") && token.hasSuffix("\"")) {
            print("🔍 mapTokenToTagType: '\(token)' -> 跳过（引号值格式）")
            return nil
        }
        
        // 检查是否包含方括号
        if token.contains("[") || token.contains("]") {
            // 检查是否是 tagType[displayName] 格式（标签类型+显示名格式）
            if token.contains("[") && token.contains("]") {
                // 可能是两种情况：
                // 1. tagType[displayName] - beef[牛肉类型] 
                // 2. value[displayName] - sdlf[牛肉品种]
                
                if let bracketStart = token.firstIndex(of: "["),
                   let bracketEnd = token.firstIndex(of: "]"),
                   bracketStart < bracketEnd && token.index(after: bracketStart) <= bracketEnd {
                    
                    let beforeBracket = String(token[..<bracketStart])
                    let insideBracket = String(token[token.index(after: bracketStart)..<bracketEnd])
                    
                    // 检查是否是已知的标签类型映射
                    let tagManager = TagMappingManager.shared
                    
                    // 先检查映射字典，避免创建错误的映射
                    if let (existingTypeName, tagType) = tagManager.mappingDictionary[beforeBracket.lowercased()] {
                        print("🔍 mapTokenToTagType: '\(token)' -> 找到现有映射: \(beforeBracket) -> \(existingTypeName)")
                        
                        // 检查是否需要更新显示名（如果括号内提供了新的显示名）
                        if !insideBracket.isEmpty && insideBracket != existingTypeName {
                            print("🔄 mapTokenToTagType: 检测到显示名更新需求: '\(existingTypeName)' -> '\(insideBracket)'")
                            // 找到现有映射并更新其显示名
                            if let existingMapping = tagManager.tagMappings.first(where: { $0.key.lowercased() == beforeBracket.lowercased() }) {
                                let updatedMapping = TagMapping(id: existingMapping.id, key: existingMapping.key, typeName: insideBracket)
                                tagManager.updateMapping(updatedMapping)
                                print("✅ mapTokenToTagType: 映射显示名更新成功: \(beforeBracket) -> \(insideBracket)")
                            } else {
                                print("⚠️ mapTokenToTagType: 找不到现有映射，无法更新")
                            }
                        }
                        
                        return tagType
                    }
                    
                    // 如果没有现有映射，这是新的快捷键定义：beef[牛肉种类]
                    // 检查映射冲突
                    let conflictResult = tagManager.checkMappingConflict(key: beforeBracket, typeName: insideBracket)
                    switch conflictResult {
                    case .conflict(let existing, let requested):
                        print("🔄 mapTokenToTagType: 映射更新请求：快捷键 '\(beforeBracket)' 从 '\(existing.typeName)' 更新到 '\(requested)'")
                        // 不要阻止创建，让标签创建继续进行，映射更新由 Node.updateTagDisplayName 处理
                        return Tag.TagType.custom(beforeBracket)
                    case .noConflict(_), .canCreate:
                        print("🔍 mapTokenToTagType: '\(token)' -> 创建新的快捷键映射: \(beforeBracket) -> \(insideBracket)")
                        let success = tagManager.addMappingIfNeeded(key: beforeBracket, typeName: insideBracket)
                        if success {
                            return Tag.TagType.custom(beforeBracket)
                        } else {
                            return nil
                        }
                    }
                } else {
                    print("🔍 mapTokenToTagType: '\(token)' -> 跳过（无效的方括号格式）")
                    return nil
                }
            }
            print("🔍 mapTokenToTagType: '\(token)' -> 跳过（包含方括号）")
            return nil
        }
        
        let tagManager = TagMappingManager.shared
        print("🔍 mapTokenToTagType: 检查单独token '\(token)'")
        
        // 🔧 已移除beef特殊处理，允许用户永久删除beef映射
        
        print("🔍 当前映射字典keys: \(Array(tagManager.mappingDictionary.keys))")
        let result = tagManager.parseTokenToTagTypeWithStore(token, store: store)
        print("🔍 mapTokenToTagType: '\(token)' -> \(result?.displayName ?? "nil")")
        return result
    }
    
    // 检查是否是地图/位置标签的key
    private func isLocationTagKey(_ key: String) -> Bool {
        let locationKeys = ["loc", "location", "地点", "位置"]
        return locationKeys.contains(key.lowercased())
    }
    
    
    private func openMapForLocationSelection() {
        // 发送通知打开地图窗口并进入位置选择模式
        NotificationCenter.default.post(name: NSNotification.Name("openMapWindow"), object: nil)
        // 延迟发送位置选择模式通知，给地图窗口时间打开
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(
                name: NSNotification.Name("openMapForLocationSelection"),
                object: nil
            )
        }
    }
    
    private func executeSelectedCommand() {
        if !commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if availableCommands.indices.contains(selectedIndex) {
                let command = availableCommands[selectedIndex]
                let context = CommandContext(store: store, currentNode: node)
                Task {
                    do {
                        _ = try await command.execute(with: context)
                        await MainActor.run {
                            DispatchQueue.main.async {
                                store.objectWillChange.send()
                            }
                            dismiss()
                        }
                    } catch {
                        print("Command execution failed: \(error)")
                    }
                }
            }
        }
    }
    
    private func handleCompoundNodeRefreshed(_ notification: Notification) {
        // 检查是否需要刷新当前节点的UI
        let shouldRefresh: Bool
        
        if let compoundNodeId = notification.userInfo?["compoundNodeId"] as? UUID {
            // 情况1：当前查看的就是被更新的复合节点
            if compoundNodeId == node.id {
                shouldRefresh = true
                print("🔄 [图谱刷新] 当前节点就是被更新的复合节点")
            }
            // 情况2：当前查看的是子节点，有复合节点引用了它
            else if let childNodeName = notification.userInfo?["childNodeName"] as? String,
                    childNodeName == node.text {
                shouldRefresh = true
                print("🔄 [图谱刷新] 当前节点是被引用的子节点: \(childNodeName)")
            }
            // 情况3：当前节点是复合节点，需要检查是否引用了变化的子节点
            else if node.isCompound,
                    let childNodeName = notification.userInfo?["childNodeName"] as? String {
                // 从 child 标签中提取引用的节点名称
                let referencedNodes = node.tags.compactMap { tag -> String? in
                    if case .custom(let key) = tag.type, key == "child" {
                        return tag.value
                    }
                    return nil
                }
                shouldRefresh = referencedNodes.contains(childNodeName)
                if shouldRefresh {
                    print("🔄 [图谱刷新] 当前复合节点引用了变化的子节点: \(childNodeName)")
                }
            } else {
                shouldRefresh = false
            }
        } else {
            shouldRefresh = false
        }
        
        if shouldRefresh {
            print("🔄 收到复合节点刷新通知，正在更新UI...")
            
            // 触发UI刷新
            refreshTrigger.toggle()
            
            // 重新生成命令文本
            commandText = initialCommand
            
            print("✅ 复合节点UI已刷新")
        }
    }
}



// Preview temporarily disabled due to @FocusState initialization complexity
// #Preview {
//     NodeManagerView()
//         .environmentObject(NodeStore.shared)
// }