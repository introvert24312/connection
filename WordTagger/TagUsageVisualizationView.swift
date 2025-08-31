import SwiftUI

/// 增强的标签使用分析界面（融合批量管理功能）
struct EnhancedTagUsageView: View {
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var selectedTagType: Tag.TagType?
    @State private var expandedGroups: Set<Tag.TagType> = []
    @State private var sortMode: SortMode = .byUsageCount
    @State private var showingNodeList = false
    @State private var selectedUsageInfo: TagUsageInfo?
    
    // 层级筛选功能状态
    @State private var selectedLayerId: UUID? = nil  // 选中的层ID，nil表示显示所有层
    @State private var showingLayerSelector = false
    
    // 批量管理功能状态
    @State private var analysisMode: AnalysisMode = .usedTags
    @State private var selectedForDeletion: Set<String> = []  // 选中要删除的项目
    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteResult = false
    @State private var lastDeleteResult: String?
    
    enum SortMode: String, CaseIterable {
        case byUsageCount = "按使用次数"
        case byTagType = "按标签类型"
        case alphabetical = "按字母排序"
    }
    
    enum AnalysisMode: String, CaseIterable {
        case usedTags = "已使用标签"
        case unusedMappings = "未使用映射"
    }
    
    // 计算属性
    private var tagUsageAnalysis: [TagUsageInfo] {
        let analysis: [TagUsageInfo]
        
        if let selectedLayerId = selectedLayerId {
            // 如果选择了特定层，只分析该层的标签使用情况
            analysis = store.getTagUsageAnalysisForLayer(selectedLayerId)
        } else {
            // 显示所有层的标签使用情况
            analysis = store.getTagUsageAnalysis()
        }
        
        let filtered = searchText.isEmpty ? analysis : analysis.filter { usage in
            usage.tagType.displayName.localizedCaseInsensitiveContains(searchText) ||
            usage.tagValue.localizedCaseInsensitiveContains(searchText)
        }
        
        switch sortMode {
        case .byUsageCount:
            return filtered.sorted { $0.nodeCount > $1.nodeCount }
        case .byTagType:
            return filtered.sorted { 
                if $0.tagType.displayName == $1.tagType.displayName {
                    return $0.tagValue < $1.tagValue
                }
                return $0.tagType.displayName < $1.tagType.displayName
            }
        case .alphabetical:
            return filtered.sorted { $0.tagValue < $1.tagValue }
        }
    }
    
    // 未使用的标签映射
    private var unusedMappings: [TagMapping] {
        let mappings: [TagMapping]
        
        if let selectedLayerId = selectedLayerId {
            // 如果选择了特定层，只显示在该层未使用的标签映射
            mappings = store.findUnusedTagMappingsForLayer(selectedLayerId)
        } else {
            // 显示在所有层都未使用的标签映射
            mappings = store.findUnusedTagMappings()
        }
        
        let filtered = searchText.isEmpty ? mappings : mappings.filter { mapping in
            mapping.key.localizedCaseInsensitiveContains(searchText) ||
            mapping.typeName.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted { $0.typeName < $1.typeName }
    }
    
    private var groupedUsage: [Tag.TagType: [TagUsageInfo]] {
        return Dictionary(grouping: tagUsageAnalysis) { $0.tagType }
    }
    
    private var sortedTagTypes: [Tag.TagType] {
        return groupedUsage.keys.sorted { type1, type2 in
            let count1 = groupedUsage[type1]?.reduce(0) { $0 + $1.nodeCount } ?? 0
            let count2 = groupedUsage[type2]?.reduce(0) { $0 + $1.nodeCount } ?? 0
            return count1 > count2
        }
    }
    
    // 获取当前选中层的显示名称
    private var selectedLayerName: String {
        guard let selectedLayerId = selectedLayerId,
              let layer = store.layers.first(where: { $0.id == selectedLayerId }) else {
            return "所有层"
        }
        return layer.displayName
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            headerView
            
            Divider()
            
            // 工具栏
            toolbarView
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            
            Divider()
            
            // 主内容
            if analysisMode == .usedTags {
                // 已使用标签的分析视图
                if tagUsageAnalysis.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(sortedTagTypes, id: \.self) { tagType in
                                TagTypeGroupView(
                                    tagType: tagType,
                                    usageList: groupedUsage[tagType] ?? [],
                                    isExpanded: expandedGroups.contains(tagType),
                                    onToggleExpansion: {
                                        toggleExpansion(for: tagType)
                                    },
                                    onSelectUsage: { usage in
                                        selectedUsageInfo = usage
                                        showingNodeList = true
                                    },
                                    onDeleteUsage: selectedLayerId != nil ? { usage in
                                        deleteSpecificTagFromLayer(usage)
                                    } : nil,
                                    selectedLayerId: selectedLayerId
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            } else {
                // 未使用映射的管理视图
                if unusedMappings.isEmpty {
                    emptyUnusedStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(unusedMappings, id: \.id) { mapping in
                                UnusedMappingRow(
                                    mapping: mapping,
                                    isSelected: selectedForDeletion.contains("[\(mapping.key)] \(mapping.typeName)"),
                                    onSelectionChanged: { isSelected in
                                        let identifier = "[\(mapping.key)] \(mapping.typeName)"
                                        if isSelected {
                                            selectedForDeletion.insert(identifier)
                                        } else {
                                            selectedForDeletion.remove(identifier)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .frame(width: 700, height: 450)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingNodeList) {
            if let usage = selectedUsageInfo {
                TagNodeListView(usage: usage)
            }
        }
        .alert("确认删除", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                performDelete()
            }
        } message: {
            Text("即将删除 \(selectedForDeletion.count) 个未使用的标签映射。\n\n这些标签没有被任何节点使用，删除后可以清理你的标签系统。此操作无法撤销。")
        }
        .alert("删除完成", isPresented: $showingDeleteResult) {
            Button("确定") { }
        } message: {
            if let result = lastDeleteResult {
                Text(result)
            }
        }
        .alert("确认删除标签", isPresented: $showingSpecificTagDeleteConfirmation) {
            Button("取消", role: .cancel) { 
                tagToDelete = nil
            }
            Button("删除", role: .destructive) {
                confirmDeleteSpecificTag()
            }
        } message: {
            if let usage = tagToDelete {
                Text("确定要从层 '\(selectedLayerName)' 删除标签 '\(usage.tagType.displayName): \(usage.tagValue)' 吗？\n\n这将从该层的 \(usage.nodeCount) 个节点中移除此标签。")
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("标签使用分析")
                    .font(.system(size: 16, weight: .semibold))
                
                Text("当前层: \(selectedLayerName)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(tagUsageAnalysis.count) 个标签")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Button("关闭") {
                dismiss()
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Toolbar
    
    private var toolbarView: some View {
        VStack(spacing: 8) {
            // 第一行：层级选择和模式切换
            HStack {
                // 层级选择器
                Text("层级:")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Menu {
                    Button("所有层") {
                        selectedLayerId = nil
                        selectedForDeletion.removeAll()
                    }
                    
                    Divider()
                    
                    ForEach(store.layers, id: \.id) { layer in
                        Button(layer.displayName) {
                            selectedLayerId = layer.id
                            selectedForDeletion.removeAll()
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedLayerName)
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // 模式切换
                Text("模式:")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    ForEach(AnalysisMode.allCases, id: \.self) { mode in
                        Button {
                            analysisMode = mode
                            selectedForDeletion.removeAll()
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(analysisMode == mode ? .white : .primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(analysisMode == mode ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
                
                // 批量删除操作（仅在未使用映射模式下显示）
                if analysisMode == .unusedMappings {
                    Button("全选") {
                        if selectedForDeletion.count == unusedMappings.count {
                            selectedForDeletion.removeAll()
                        } else {
                            selectedForDeletion = Set(unusedMappings.map { "[\($0.key)] \($0.typeName)" })
                        }
                    }
                    .font(.system(size: 11))
                    .disabled(unusedMappings.isEmpty)
                    
                    Button("删除") {
                        if !selectedForDeletion.isEmpty {
                            showingDeleteConfirmation = true
                        }
                    }
                    .font(.system(size: 11))
                    .disabled(selectedForDeletion.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }
            
            // 第二行：搜索和排序
            HStack(spacing: 12) {
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    
                    TextField(analysisMode == .usedTags ? "搜索标签类型或值..." : "搜索映射关键词...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                
                Spacer()
                
            }
        }
    }
    
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tag.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("没有标签数据")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            
            Text("当前层没有使用任何标签，或者搜索条件没有匹配结果")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func toggleExpansion(for tagType: Tag.TagType) {
        if expandedGroups.contains(tagType) {
            expandedGroups.remove(tagType)
        } else {
            expandedGroups.insert(tagType)
        }
    }
    
    
    private func performDelete() {
        let mappingsToDelete = unusedMappings.filter { mapping in
            selectedForDeletion.contains("[\(mapping.key)] \(mapping.typeName)")
        }
        
        if let selectedLayerId = selectedLayerId {
            // 如果选择了特定层，只从该层删除对应的标签
            let result = store.batchDeleteUnusedMappingsFromLayer(mappingsToDelete, layerId: selectedLayerId)
            lastDeleteResult = "已从层 '\(selectedLayerName)' 删除 \(result.deletedTagCount) 个标签，影响 \(result.affectedNodeCount) 个节点"
        } else {
            // 如果是所有层模式，删除标签映射（全局删除）
            for mapping in mappingsToDelete {
                TagMappingManager.shared.removeMapping(mapping)
            }
            lastDeleteResult = "已删除 \(mappingsToDelete.count) 个未使用的标签映射"
        }
        
        selectedForDeletion.removeAll()
        showingDeleteResult = true
    }
    
    // 删除特定层中的特定标签
    @State private var showingSpecificTagDeleteConfirmation = false
    @State private var tagToDelete: TagUsageInfo?
    
    private func deleteSpecificTagFromLayer(_ usage: TagUsageInfo) {
        tagToDelete = usage
        showingSpecificTagDeleteConfirmation = true
    }
    
    private func confirmDeleteSpecificTag() {
        guard let usage = tagToDelete,
              let selectedLayerId = selectedLayerId else { return }
        
        // 创建要删除的标签
        let tagToDelete = Tag(type: usage.tagType, value: usage.tagValue)
        
        // 从指定层的节点中删除此特定标签
        let result = store.batchDeleteSpecificTagFromLayer([tagToDelete], layerId: selectedLayerId)
        
        // 显示删除结果
        lastDeleteResult = "已从层 '\(selectedLayerName)' 删除标签 '\(usage.tagType.displayName): \(usage.tagValue)'，影响 \(result.affectedNodeCount) 个节点"
        showingDeleteResult = true
        
        // 清理状态
        self.tagToDelete = nil
    }
    
    // MARK: - Empty States
    
    private var emptyUnusedStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("没有未使用的标签映射")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            
            Text("所有标签映射都有对应的节点在使用，系统很整洁！")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Unused Mapping Row

struct UnusedMappingRow: View {
    let mapping: TagMapping
    let isSelected: Bool
    let onSelectionChanged: (Bool) -> Void
    
    var body: some View {
        Button {
            onSelectionChanged(!isSelected)
        } label: {
            HStack(spacing: 12) {
                // 选择框
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.system(size: 14))
                
                // 标签颜色指示器
                Circle()
                    .fill(Color.from(tagType: mapping.tagType))
                    .frame(width: 10, height: 10)
                
                // 映射信息
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(mapping.key)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text("→")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        Text(mapping.typeName)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Text("未使用")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange.opacity(0.2))
                        )
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Backward Compatibility

typealias TagUsageVisualizationView = EnhancedTagUsageView

// MARK: - Tag Type Group View

struct TagTypeGroupView: View {
    let tagType: Tag.TagType
    let usageList: [TagUsageInfo]
    let isExpanded: Bool
    let onToggleExpansion: () -> Void
    let onSelectUsage: (TagUsageInfo) -> Void
    let onDeleteUsage: ((TagUsageInfo) -> Void)? // 可选的删除回调
    let selectedLayerId: UUID? // 当前选择的层ID
    
    private var totalNodeCount: Int {
        usageList.reduce(0) { $0 + $1.nodeCount }
    }
    
    private var uniqueNodeCount: Int {
        let allNodes = usageList.flatMap { $0.nodes }
        let uniqueNodeIds = Set(allNodes.map { $0.id })
        return uniqueNodeIds.count
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // 标签类型头部
            Button(action: onToggleExpansion) {
                HStack(spacing: 12) {
                    // 展开/收起图标
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    
                    // 标签类型名称
                    Text(tagType.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // 统计信息
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(usageList.count) 个标签值")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        Text("\(uniqueNodeCount) 个节点")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            // 展开的内容
            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(usageList.sorted { $0.nodeCount > $1.nodeCount }, id: \.tagValue) { usage in
                        TagUsageRow(
                            usage: usage,
                            onTap: { onSelectUsage(usage) },
                            onDelete: selectedLayerId != nil ? {
                                // 只在选择了特定层时允许删除
                                onDeleteUsage?(usage)
                            } : nil
                        )
                    }
                }
                .padding(.leading, 24)
            }
        }
    }
}

// MARK: - Tag Usage Row

struct TagUsageRow: View {
    let usage: TagUsageInfo
    let onTap: () -> Void
    let onDelete: (() -> Void)? // 可选的删除回调
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            // 主内容按钮
            Button(action: onTap) {
                HStack(spacing: 8) {
                    // 标签值
                    Text(usage.tagValue)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // 使用次数
                    HStack(spacing: 4) {
                        Image(systemName: "number")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        
                        Text("\(usage.nodeCount)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue.opacity(0.1))
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            
            // 删除按钮（仅在有删除回调且悬停时显示）
            if let onDelete = onDelete, isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .help("删除此标签")
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
        .onHover { hover in
            isHovered = hover
        }
    }
}

// MARK: - Tag Node List View

struct TagNodeListView: View {
    let usage: TagUsageInfo
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: NodeStore
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("标签详情")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("\(usage.tagType.displayName): \(usage.tagValue)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(usage.nodeCount) 个节点")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
                
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            // 节点列表
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(usage.nodes, id: \.id) { node in
                        NodeRow(node: node) {
                            // 点击节点时选中并关闭弹窗
                            store.setSelectedNode(node)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 400, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Node Row

struct NodeRow: View {
    let node: Node
    let onTap: () -> Void
    @EnvironmentObject private var store: NodeStore
    
    // 根据layerId获取层名称
    private var layerName: String {
        if let layer = store.layers.first(where: { $0.id == node.layerId }) {
            return layer.displayName
        }
        return "未知层"
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(node.text)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        // 显示层信息
                        Text("[\(layerName)]")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.orange.opacity(0.1))
                            )
                    }
                    
                    if let meaning = node.meaning {
                        Text(meaning)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    if !node.tags.isEmpty {
                        Text("\(node.tags.count) 个标签")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}