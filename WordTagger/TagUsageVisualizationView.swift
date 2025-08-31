import SwiftUI

/// 标签使用情况可视化界面
struct TagUsageVisualizationView: View {
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var selectedTagType: Tag.TagType?
    @State private var expandedGroups: Set<Tag.TagType> = []
    @State private var sortMode: SortMode = .byUsageCount
    @State private var showingNodeList = false
    @State private var selectedUsageInfo: TagUsageInfo?
    
    enum SortMode: String, CaseIterable {
        case byUsageCount = "按使用次数"
        case byTagType = "按标签类型"
        case alphabetical = "按字母排序"
    }
    
    // 计算属性
    private var tagUsageAnalysis: [TagUsageInfo] {
        let analysis = store.getTagUsageAnalysis()
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
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
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
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Text("标签使用分析")
                .font(.system(size: 16, weight: .semibold))
            
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
        HStack(spacing: 12) {
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                
                TextField("搜索标签类型或值...", text: $searchText)
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
            
            // 排序方式
            Text("排序:")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Picker("排序方式", selection: $sortMode) {
                ForEach(SortMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            
            // 展开/收起所有
            Button(allExpanded ? "收起全部" : "展开全部") {
                toggleAllExpansion()
            }
            .font(.system(size: 12))
            .controlSize(.small)
        }
    }
    
    private var allExpanded: Bool {
        expandedGroups.count == sortedTagTypes.count
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
    
    private func toggleAllExpansion() {
        if allExpanded {
            expandedGroups.removeAll()
        } else {
            expandedGroups = Set(sortedTagTypes)
        }
    }
}

// MARK: - Tag Type Group View

struct TagTypeGroupView: View {
    let tagType: Tag.TagType
    let usageList: [TagUsageInfo]
    let isExpanded: Bool
    let onToggleExpansion: () -> Void
    let onSelectUsage: (TagUsageInfo) -> Void
    
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
                        TagUsageRow(usage: usage) {
                            onSelectUsage(usage)
                        }
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
    
    var body: some View {
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
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
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
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
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