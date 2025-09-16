import SwiftUI
import AppKit

// MARK: - 节点图谱预设管理视图

struct NodeGraphPresetManagerView: View {
    @Binding var selectedNodeIds: Set<UUID>
    @Binding var selectedLayerIds: Set<UUID>
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var presetManager = NodeGraphPresetManager.shared
    
    @State private var searchText = ""
    @State private var showingDeleteAlert = false
    @State private var presetToDelete: NodeGraphPreset?
    
    private var filteredPresets: [NodeGraphPreset] {
        let presets = presetManager.presets
        print("🔍 [NodeGraphPresetManagerView] filteredPresets计算中，总预设数: \(presets.count)")
        
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let sorted = presetManager.presetsSortedByLastUsed
            print("🔍 [NodeGraphPresetManagerView] 返回排序后的预设: \(sorted.count)个")
            return sorted
        }
        
        let filtered = presetManager.presets.filter { preset in
            preset.name.localizedCaseInsensitiveContains(searchText) ||
            preset.description?.localizedCaseInsensitiveContains(searchText) == true
        }.sorted { $0.lastUsed > $1.lastUsed }
        
        print("🔍 [NodeGraphPresetManagerView] 返回筛选后的预设: \(filtered.count)个")
        return filtered
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("节点图谱预设管理")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("(\(presetManager.presets.count) 个预设)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
            
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索预设...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // 预设列表
            if filteredPresets.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: searchText.isEmpty ? "bookmark.slash" : "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text(searchText.isEmpty ? "暂无保存的节点图谱预设" : "没有找到匹配的预设")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if searchText.isEmpty {
                        Text("在全局节点图谱中选择节点和层级后，点击\"保存为预设\"来创建您的第一个预设。")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredPresets) { preset in
                            PresetRowView(
                                preset: preset,
                                isCurrentPreset: presetManager.currentPreset?.id == preset.id,
                                store: store,
                                onLoad: {
                                    let result = presetManager.loadPreset(preset)
                                    selectedNodeIds = result.selectedNodeIds
                                    selectedLayerIds = result.selectedLayerIds
                                    // 不再自动关闭窗口，让用户可以继续选择其他预设
                                    // dismiss()
                                },
                                onDelete: {
                                    presetToDelete = preset
                                    showingDeleteAlert = true
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
        .alert("删除预设", isPresented: $showingDeleteAlert, presenting: presetToDelete) { preset in
            Button("删除", role: .destructive) {
                presetManager.deletePreset(preset)
                presetToDelete = nil
            }
            Button("取消", role: .cancel) {
                presetToDelete = nil
            }
        } message: { preset in
            Text("确定要删除预设 \"\(preset.name)\" 吗？此操作无法撤销。")
        }
        .onAppear {
            print("🔍 [NodeGraphPresetManagerView] onAppear: 强制刷新预设列表")
            print("🔍 [NodeGraphPresetManagerView] onAppear: 当前预设数量: \(presetManager.presets.count)")
            presetManager.reloadPresets()
            print("🔍 [NodeGraphPresetManagerView] onAppear: 重新加载后预设数量: \(presetManager.presets.count)")
        }
        .onReceive(presetManager.objectWillChange) {
            print("🔄 [NodeGraphPresetManagerView] 收到presetManager变更通知")
        }
    }
}

// MARK: - 预设行视图

struct PresetRowView: View {
    let preset: NodeGraphPreset
    let isCurrentPreset: Bool
    let store: NodeStore
    let onLoad: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    private func getNodeNames(for nodeIds: Set<UUID>) -> [String] {
        return store.nodes
            .filter { nodeIds.contains($0.id) }
            .map { $0.text }
            .sorted()
    }
    
    private func getLayerNames(for layerIds: Set<UUID>) -> [String] {
        return store.layers
            .filter { layerIds.contains($0.id) }
            .map { $0.displayName }
            .sorted()
    }
    
    // 预设标题行视图
    private var headerView: some View {
        HStack {
            presetTitleView
            Spacer()
            actionButtonsView
        }
    }
    
    // 预设标题部分
    private var presetTitleView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(preset.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                if isCurrentPreset {
                    currentPresetBadge
                }
                
                Spacer()
            }
            
            if let description = preset.description {
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }
    
    // 当前预设标识
    private var currentPresetBadge: some View {
        Text("当前")
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.2))
            .foregroundColor(.green)
            .cornerRadius(4)
    }
    
    // 操作按钮组
    private var actionButtonsView: some View {
        HStack(spacing: 8) {
            Button("加载") {
                onLoad()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            
            if isHovered {
                deleteButton
            }
        }
    }
    
    // 删除按钮
    private var deleteButton: some View {
        Button {
            onDelete()
        } label: {
            Image(systemName: "trash")
                .foregroundColor(.red)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("删除预设")
    }
    
    // 预设内容概览
    private var contentOverviewView: some View {
        HStack(spacing: 20) {
            if !preset.selectedNodeIds.isEmpty {
                nodeInfoView
            }
            
            if !preset.selectedLayerIds.isEmpty {
                layerInfoView
            }
            
            Spacer()
            timeInfoView
        }
    }
    
    // 节点信息视图
    private var nodeInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "circle")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                Text("节点 (\(preset.selectedNodeIds.count))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.blue)
            }
            
            nodeNamesText
        }
    }
    
    // 节点名称文本
    private var nodeNamesText: some View {
        let nodeUUIDs = Set(preset.selectedNodeIds.compactMap { UUID(uuidString: $0) })
        let nodeNames = getNodeNames(for: nodeUUIDs)
        let displayedNodeNames = nodeNames.prefix(3).joined(separator: ", ")
        let nodeNamesText = nodeNames.count > 3 ? displayedNodeNames + "..." : displayedNodeNames
        
        return Text(nodeNamesText)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .lineLimit(1)
    }
    
    // 层级信息视图
    private var layerInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "square.stack")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
                Text("层级 (\(preset.selectedLayerIds.count))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.green)
            }
            
            layerNamesText
        }
    }
    
    // 层级名称文本
    private var layerNamesText: some View {
        let layerUUIDs = Set(preset.selectedLayerIds.compactMap { UUID(uuidString: $0) })
        let layerNames = getLayerNames(for: layerUUIDs)
        let displayedLayerNames = layerNames.prefix(3).joined(separator: ", ")
        let layerNamesText = layerNames.count > 3 ? displayedLayerNames + "..." : displayedLayerNames
        
        return Text(layerNamesText)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .lineLimit(1)
    }
    
    // 时间信息视图
    private var timeInfoView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("创建: \(preset.createdAt, formatter: dateFormatter)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            Text("使用: \(preset.lastUsed, formatter: dateFormatter)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
    
    // 背景样式
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(fillColor)
            .stroke(strokeColor, lineWidth: strokeWidth)
    }
    
    private var fillColor: Color {
        isCurrentPreset ? Color.green.opacity(0.05) : Color(NSColor.controlBackgroundColor)
    }
    
    private var strokeColor: Color {
        if isCurrentPreset {
            return Color.green.opacity(0.3)
        } else if isHovered {
            return Color.blue.opacity(0.3)
        } else {
            return Color.gray.opacity(0.2)
        }
    }
    
    private var strokeWidth: CGFloat {
        if isCurrentPreset {
            return 2
        } else if isHovered {
            return 1.5
        } else {
            return 1
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            contentOverviewView
        }
        .padding(16)
        .background(backgroundView)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onLoad()
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}