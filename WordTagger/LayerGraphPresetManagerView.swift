import SwiftUI
import AppKit

// MARK: - 图谱预设管理视图

struct LayerGraphPresetManagerView: View {
    @Binding var filteredLayerIds: Set<UUID>
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var presetManager = LayerGraphPresetManager.shared
    
    @State private var searchText = ""
    @State private var showingDeleteAlert = false
    @State private var presetToDelete: LayerGraphPreset?
    @State private var selectedPresetIds: Set<UUID> = []
    @State private var showingBatchDeleteAlert = false
    
    private var filteredPresets: [LayerGraphPreset] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return presetManager.presets.sorted { $0.lastUsedAt > $1.lastUsedAt }
        }
        
        return presetManager.presets.filter { preset in
            preset.name.localizedCaseInsensitiveContains(searchText)
        }.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // 删除了标题行，直接从搜索框开始
            
            // 搜索框和控制按钮
            HStack {
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
                
                // 全选/取消全选按钮
                if !filteredPresets.isEmpty {
                    Button {
                        if selectedPresetIds.count == filteredPresets.count {
                            selectedPresetIds.removeAll()
                        } else {
                            selectedPresetIds = Set(filteredPresets.map { $0.id })
                        }
                    } label: {
                        Label(selectedPresetIds.count == filteredPresets.count ? "取消全选" : "全选",
                              systemImage: selectedPresetIds.count == filteredPresets.count ? "square" : "checkmark.square")
                    }
                    .buttonStyle(.bordered)
                }
                
                // 批量删除按钮
                if !selectedPresetIds.isEmpty {
                    Button {
                        showingBatchDeleteAlert = true
                    } label: {
                        Label("删除选中 (\(selectedPresetIds.count))", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            // 预设列表
            if filteredPresets.isEmpty && presetManager.presets.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: searchText.isEmpty ? "bookmark.slash" : "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text(searchText.isEmpty ? "暂无保存的图谱预设" : "没有找到匹配的预设")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if searchText.isEmpty {
                        Text("在图谱中选择层级后，点击\"保存为预设\"来创建您的第一个预设。")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // 只显示用户预设，不再显示默认预设
                        ForEach(filteredPresets) { preset in
                            LayerPresetRowView(
                                preset: preset,
                                isCurrentPreset: presetManager.currentPreset?.id == preset.id,
                                isDefault: false,
                                isSelected: selectedPresetIds.contains(preset.id),
                                store: store,
                                onLoad: {
                                    presetManager.loadPreset(preset)
                                    filteredLayerIds = preset.filteredLayerIds
                                    // 不再自动关闭窗口
                                },
                                onDelete: {
                                    presetToDelete = preset
                                    showingDeleteAlert = true
                                },
                                onToggleSelection: {
                                    if selectedPresetIds.contains(preset.id) {
                                        selectedPresetIds.remove(preset.id)
                                    } else {
                                        selectedPresetIds.insert(preset.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .padding()
        .frame(minWidth: 270, minHeight: 450)
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
        .alert("批量删除预设", isPresented: $showingBatchDeleteAlert) {
            Button("删除", role: .destructive) {
                // 批量删除选中的预设
                let presetsToDelete = presetManager.presets.filter { selectedPresetIds.contains($0.id) }
                for preset in presetsToDelete {
                    presetManager.deletePreset(preset)
                }
                selectedPresetIds.removeAll()
            }
            Button("取消", role: .cancel) {
                // 不做任何操作
            }
        } message: {
            Text("确定要删除选中的 \(selectedPresetIds.count) 个预设吗？此操作无法撤销。")
        }
    }
}

// MARK: - 图谱预设行视图

struct LayerPresetRowView: View {
    let preset: LayerGraphPreset
    let isCurrentPreset: Bool
    let isDefault: Bool
    let isSelected: Bool
    let store: NodeStore
    let onLoad: () -> Void
    let onDelete: (() -> Void)?
    let onToggleSelection: (() -> Void)?
    
    @State private var isHovered = false
    
    private func getLayerNames(for layerIds: Set<UUID>) -> [String] {
        return store.layers
            .filter { layerIds.contains($0.id) }
            .map { $0.displayName }
            .sorted()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 预设标题行
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(preset.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if isCurrentPreset {
                            Text("当前")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                        
                        if isDefault {
                            Text("默认")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                    }
                    
                    // 移除了"包含x个层"的显示
                }
                
                Spacer()
                
                // 移除了单个删除按钮，仅保留批量删除功能
            }
            
            // 预设内容概览
            HStack(spacing: 20) {
                // 层信息 - 左侧显示数量
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "square.stack")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                        Text("包含 \(preset.filteredLayerIds.count) 个层")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // 层名称 - 右侧显示
                if !preset.filteredLayerIds.isEmpty {
                    let layerNames = getLayerNames(for: preset.filteredLayerIds)
                    Text(layerNames.joined(separator: ", "))
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(fillColor)
                .stroke(strokeColor, lineWidth: strokeWidth)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture(count: 2) {
            // 双击加载预设
            onLoad()
        }
        .simultaneousGesture(
            TapGesture(count: 1)
                .modifiers(.command)
                .onEnded { _ in
                    // Command+点击进行多选
                    onToggleSelection?()
                }
        )
        .help("双击加载预设，Command+点击多选")
    }
    
    private var fillColor: Color {
        if isCurrentPreset {
            return Color.blue.opacity(0.05)
        } else if isSelected {
            return Color.blue.opacity(0.1)
        } else {
            return Color(NSColor.controlBackgroundColor)
        }
    }
    
    private var strokeColor: Color {
        if isCurrentPreset {
            return Color.blue.opacity(0.3)
        } else if isSelected {
            return Color.blue.opacity(0.5)
        } else if isHovered {
            return Color.blue.opacity(0.3)
        } else {
            return Color.gray.opacity(0.2)
        }
    }
    
    private var strokeWidth: CGFloat {
        if isCurrentPreset || isSelected {
            return 2
        } else if isHovered {
            return 1.5
        } else {
            return 1
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}