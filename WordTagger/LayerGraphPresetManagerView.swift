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
            HStack {
                Text("图谱预设管理")
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
                        // 默认预设
                        let defaultPreset = presetManager.getDefaultPreset(allLayers: store.layers)
                        if searchText.isEmpty || defaultPreset.name.localizedCaseInsensitiveContains(searchText) {
                            LayerPresetRowView(
                                preset: defaultPreset,
                                isCurrentPreset: presetManager.currentPreset?.id == defaultPreset.id,
                                isDefault: true,
                                store: store,
                                onLoad: {
                                    presetManager.loadPreset(defaultPreset)
                                    filteredLayerIds = defaultPreset.filteredLayerIds
                                    dismiss()
                                },
                                onDelete: nil // 默认预设不能删除
                            )
                        }
                        
                        // 用户预设
                        ForEach(filteredPresets) { preset in
                            LayerPresetRowView(
                                preset: preset,
                                isCurrentPreset: presetManager.currentPreset?.id == preset.id,
                                isDefault: false,
                                store: store,
                                onLoad: {
                                    presetManager.loadPreset(preset)
                                    filteredLayerIds = preset.filteredLayerIds
                                    dismiss()
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
        .frame(width: 800, height: 600)
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
    }
}

// MARK: - 图谱预设行视图

struct LayerPresetRowView: View {
    let preset: LayerGraphPreset
    let isCurrentPreset: Bool
    let isDefault: Bool
    let store: NodeStore
    let onLoad: () -> Void
    let onDelete: (() -> Void)?
    
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
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
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
                    
                    Text("包含 \(preset.filteredLayerIds.count) 个层")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // 操作按钮
                HStack(spacing: 8) {
                    Button("加载") {
                        onLoad()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    if isHovered && onDelete != nil {
                        Button {
                            onDelete?()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("删除预设")
                    }
                }
            }
            
            // 预设内容概览
            HStack(spacing: 20) {
                // 层级信息
                if !preset.filteredLayerIds.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "square.stack")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            Text("层级 (\(preset.filteredLayerIds.count))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        
                        let layerNames = getLayerNames(for: preset.filteredLayerIds)
                        Text(layerNames.prefix(3).joined(separator: ", ") + (layerNames.count > 3 ? "..." : ""))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // 时间信息
                if !isDefault {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("创建: \(preset.createdAt, formatter: dateFormatter)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        
                        Text("使用: \(preset.lastUsedAt, formatter: dateFormatter)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrentPreset ? Color.green.opacity(0.05) : Color(NSColor.controlBackgroundColor))
                .stroke(
                    isCurrentPreset ? Color.green.opacity(0.3) : (isHovered ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2)),
                    lineWidth: isCurrentPreset ? 2 : (isHovered ? 1.5 : 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            // 单击加载预设
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