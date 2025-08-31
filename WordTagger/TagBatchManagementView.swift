import SwiftUI

/// 标签批量管理界面
struct TagBatchManagementView: View {
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var mode: TagBatchMode = .deleteUnusedMappings
    @State private var tagSelections: [TagSelectionItem] = []
    @State private var searchText = ""
    @State private var showingPreview = false
    @State private var showingDeleteConfirmation = false
    @State private var previewResult: BatchDeletePreview?
    @State private var isProcessing = false
    @State private var showingResult = false
    @State private var lastResult: BatchDeleteResult?
    
    // 计算属性
    private var filteredSelections: [TagSelectionItem] {
        if searchText.isEmpty {
            return tagSelections
        }
        return tagSelections.filter { item in
            item.displayText.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var selectedItems: [TagSelectionItem] {
        return tagSelections.filter { $0.isSelected }
    }
    
    private var hasSelection: Bool {
        return !selectedItems.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            headerView
            
            Divider()
            
            // 模式选择
            modeSelectionView
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            
            Divider()
            
            // 搜索框
            searchView
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            
            // 主内容区
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredSelections.indices, id: \.self) { index in
                        TagSelectionRow(
                            item: filteredSelections[index],
                            isSelected: filteredSelections[index].isSelected
                        ) { isSelected in
                            updateSelection(for: filteredSelections[index], isSelected: isSelected)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            
            Divider()
            
            // 底部操作栏
            bottomActionView
        }
        .frame(width: 700, height: 450)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadTagSelections()
        }
        .onChange(of: mode) { _ in
            loadTagSelections()
        }
        .sheet(isPresented: $showingPreview) {
            if let preview = previewResult {
                DeletePreviewView(preview: preview) {
                    showingPreview = false
                    showingDeleteConfirmation = true
                }
            }
        }
        .alert("确认删除", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                performDelete()
            }
        } message: {
            if mode == .deleteUnusedMappings {
                Text("即将删除 \(selectedItems.count) 个从未使用过的标签映射。\n\n这些标签没有被任何节点使用，删除后可以清理你的标签系统。此操作无法撤销。")
            } else if let preview = previewResult {
                Text("即将删除 \(preview.affectedTagCount) 个标签，影响 \(preview.affectedNodeCount) 个节点。此操作无法撤销。")
            }
        }
        .alert("删除完成", isPresented: $showingResult) {
            Button("确定") {
                dismiss()
            }
        } message: {
            if let result = lastResult {
                Text("已删除 \(result.deletedTagCount) 个标签，影响了 \(result.affectedNodeCount) 个节点。")
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Text("标签批量管理")
                .font(.system(size: 16, weight: .semibold))
            
            Spacer()
            
            Button("关闭") {
                dismiss()
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Mode Selection
    
    private var modeSelectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("操作模式")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
            
            VStack(spacing: 4) {
                RadioButton(
                    title: "🗑️ 清理未使用的标签（推荐）",
                    subtitle: "找出从未使用过的标签映射，一键清理",
                    isSelected: mode == .deleteUnusedMappings
                ) {
                    mode = .deleteUnusedMappings
                }
                
                RadioButton(
                    title: "删除具体标签",
                    subtitle: "选择要删除的具体标签值",
                    isSelected: mode == .deleteSpecificTags
                ) {
                    mode = .deleteSpecificTags
                }
                
                RadioButton(
                    title: "删除整个标签类型",
                    subtitle: "删除选中类型的所有标签",
                    isSelected: mode == .deleteByType
                ) {
                    mode = .deleteByType
                }
            }
        }
    }
    
    // MARK: - Search View
    
    private var searchView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("搜索标签...", text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Bottom Actions
    
    private var bottomActionView: some View {
        HStack {
            if mode == .deleteUnusedMappings {
                // 未使用标签模式的快捷操作
                Button("🚀 一键清理未使用") {
                    selectAllUnusedAndDelete()
                }
                .buttonStyle(.borderedProminent)
                .disabled(tagSelections.isEmpty || isProcessing)
                
                Spacer()
                
                // 选择统计
                Text("找到 \(tagSelections.count) 个未使用标签")
                    .font(.system(size: 12))
                    .foregroundColor(tagSelections.isEmpty ? .secondary : .orange)
                    .fontWeight(tagSelections.isEmpty ? .regular : .medium)
                
                Spacer()
                
                // 全选按钮
                Button(allSelected ? "取消全选" : "全选未使用") {
                    toggleSelectAll()
                }
                .disabled(tagSelections.isEmpty)
            } else {
                // 其他模式的常规操作
                Button(allSelected ? "取消全选" : "全选") {
                    toggleSelectAll()
                }
                .disabled(tagSelections.isEmpty)
                
                Spacer()
                
                // 选择统计
                Text("\(selectedItems.count)/\(tagSelections.count) 已选择")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 预览按钮
                Button("预览删除") {
                    generatePreview()
                }
                .disabled(!hasSelection || isProcessing)
                
                // 执行删除按钮
                Button("直接删除") {
                    showingDeleteConfirmation = true
                }
                .disabled(!hasSelection || isProcessing)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var allSelected: Bool {
        !tagSelections.isEmpty && tagSelections.allSatisfy { $0.isSelected }
    }
    
    // MARK: - Helper Methods
    
    private func loadTagSelections() {
        switch mode {
        case .deleteSpecificTags:
            loadSpecificTagSelections()
        case .deleteByType:
            loadTagTypeSelections()
        case .deleteUnusedMappings:
            loadUnusedMappingSelections()
        }
    }
    
    private func loadSpecificTagSelections() {
        let usageAnalysis = store.getTagUsageAnalysis()
        tagSelections = usageAnalysis.map { usage in
            TagSelectionItem(
                tagType: usage.tagType,
                tagValue: usage.tagValue,
                nodeCount: usage.nodeCount
            )
        }
    }
    
    private func loadTagTypeSelections() {
        let allTags = store.currentLayerTags
        let tagTypeGroups = Dictionary(grouping: allTags) { $0.type }
        
        tagSelections = tagTypeGroups.map { (tagType, tags) in
            let nodeCount = store.nodesInCurrentLayer(withTagType: tagType).count
            return TagSelectionItem(
                tagType: tagType,
                tagValue: nil,
                nodeCount: nodeCount
            )
        }.sorted { $0.tagType.displayName < $1.tagType.displayName }
    }
    
    private func loadUnusedMappingSelections() {
        let unusedMappings = store.findUnusedTagMappings()
        tagSelections = unusedMappings.map { mapping in
            TagSelectionItem(
                tagType: mapping.tagType,
                tagValue: "[\(mapping.key)] \(mapping.typeName)",
                nodeCount: 0
            )
        }
    }
    
    private func updateSelection(for item: TagSelectionItem, isSelected: Bool) {
        if let index = tagSelections.firstIndex(where: { $0.id == item.id }) {
            tagSelections[index].isSelected = isSelected
        }
    }
    
    private func toggleSelectAll() {
        let newValue = !allSelected
        for index in tagSelections.indices {
            tagSelections[index].isSelected = newValue
        }
    }
    
    private func selectAllUnusedAndDelete() {
        // 全选所有未使用的标签
        for index in tagSelections.indices {
            tagSelections[index].isSelected = true
        }
        
        // 立即执行删除确认
        showingDeleteConfirmation = true
    }
    
    private func generatePreview() {
        guard hasSelection else { return }
        
        switch mode {
        case .deleteSpecificTags:
            let tagsToDelete = selectedItems.compactMap { item -> Tag? in
                guard let tagValue = item.tagValue else { return nil }
                return Tag(type: item.tagType, value: tagValue, latitude: nil, longitude: nil, isShortcutType: false)
            }
            previewResult = BatchDeletePreview(
                mode: mode,
                affectedTagCount: tagsToDelete.count,
                affectedNodeCount: calculateAffectedNodeCount(for: tagsToDelete),
                selectedItems: selectedItems
            )
            
        case .deleteByType:
            let tagTypes = Set(selectedItems.map { $0.tagType })
            let affectedNodeCount = tagTypes.reduce(0) { count, tagType in
                count + store.nodesInCurrentLayer(withTagType: tagType).count
            }
            previewResult = BatchDeletePreview(
                mode: mode,
                affectedTagCount: selectedItems.count,
                affectedNodeCount: affectedNodeCount,
                selectedItems: selectedItems
            )
            
        case .deleteUnusedMappings:
            previewResult = BatchDeletePreview(
                mode: mode,
                affectedTagCount: selectedItems.count,
                affectedNodeCount: 0,
                selectedItems: selectedItems
            )
        }
        
        showingPreview = true
    }
    
    private func calculateAffectedNodeCount(for tags: [Tag]) -> Int {
        var affectedNodes: Set<UUID> = []
        for tag in tags {
            let nodes = store.nodesInCurrentLayer(withTag: tag)
            for node in nodes {
                affectedNodes.insert(node.id)
            }
        }
        return affectedNodes.count
    }
    
    private func performDelete() {
        isProcessing = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let result: BatchDeleteResult
            
            switch mode {
            case .deleteSpecificTags:
                let tagsToDelete = selectedItems.compactMap { item -> Tag? in
                    guard let tagValue = item.tagValue else { return nil }
                    return Tag(type: item.tagType, value: tagValue, latitude: nil, longitude: nil, isShortcutType: false)
                }
                result = store.batchDeleteSpecificTags(tagsToDelete)
                
            case .deleteByType:
                let tagTypes = Set(selectedItems.map { $0.tagType })
                result = store.batchDeleteTagTypes(tagTypes)
                
            case .deleteUnusedMappings:
                // 删除未使用的标签映射
                let mappingsToDelete = store.findUnusedTagMappings()
                let selectedMappings = mappingsToDelete.filter { mapping in
                    selectedItems.contains { item in
                        item.tagType == mapping.tagType
                    }
                }
                
                for mapping in selectedMappings {
                    TagMappingManager.shared.removeMapping(mapping)
                }
                
                result = BatchDeleteResult(
                    affectedNodeCount: 0,
                    deletedTagCount: selectedMappings.count,
                    affectedNodes: []
                )
            }
            
            lastResult = result
            isProcessing = false
            showingResult = true
        }
    }
}

// MARK: - Supporting Views

struct TagSelectionRow: View {
    let item: TagSelectionItem
    let isSelected: Bool
    let onSelectionChanged: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 选择框
            Button {
                onSelectionChanged(!isSelected)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            
            // 标签信息
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayText)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                
                if item.nodeCount > 0 {
                    Text("用于 \(item.nodeCount) 个节点")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("未使用")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectionChanged(!isSelected)
        }
    }
}

struct RadioButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.system(size: 14))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview Models

struct BatchDeletePreview {
    let mode: TagBatchMode
    let affectedTagCount: Int
    let affectedNodeCount: Int
    let selectedItems: [TagSelectionItem]
}

struct DeletePreviewView: View {
    let preview: BatchDeletePreview
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            // 标题
            Text("删除预览")
                .font(.system(size: 16, weight: .semibold))
            
            // 统计信息
            VStack(spacing: 8) {
                HStack {
                    Text("删除模式:")
                    Spacer()
                    Text(modeDisplayName)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("将删除标签:")
                    Spacer()
                    Text("\(preview.affectedTagCount) 个")
                        .foregroundColor(.red)
                        .fontWeight(.medium)
                }
                
                if preview.affectedNodeCount > 0 {
                    HStack {
                        Text("影响节点:")
                        Spacer()
                        Text("\(preview.affectedNodeCount) 个")
                            .foregroundColor(.orange)
                            .fontWeight(.medium)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            
            // 详细列表
            Text("详细信息")
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(preview.selectedItems, id: \.id) { item in
                        HStack {
                            Text("• \(item.displayText)")
                                .font(.system(size: 12))
                            Spacer()
                            if item.nodeCount > 0 {
                                Text("(\(item.nodeCount) 节点)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: 200)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            
            // 警告信息
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("此操作无法撤销，请确认后继续")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            // 按钮
            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .controlSize(.regular)
                
                Button("确认删除") {
                    onConfirm()
                    dismiss()
                }
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
    
    private var modeDisplayName: String {
        switch preview.mode {
        case .deleteSpecificTags:
            return "删除具体标签"
        case .deleteByType:
            return "删除标签类型"
        case .deleteUnusedMappings:
            return "删除未使用映射"
        }
    }
}