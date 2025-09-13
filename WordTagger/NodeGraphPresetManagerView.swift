import SwiftUI
import AppKit

// MARK: - 节点图谱预设管理视图

struct NodeGraphPresetManagerView: View {
    @Binding var selectedNodeIds: Set<UUID>
    @Binding var selectedLayerIds: Set<UUID>
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var presetManager = NodeGraphPresetManager.shared
    
    @State private var searchText = ""
    @State private var showingDeleteAlert = false
    @State private var presetToDelete: NodeGraphPreset?
    
    private var filteredPresets: [NodeGraphPreset] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return presetManager.presetsSortedByLastUsed
        }
        
        return presetManager.presets.filter { preset in
            preset.name.localizedCaseInsensitiveContains(searchText) ||
            preset.description?.localizedCaseInsensitiveContains(searchText) == true
        }.sorted { $0.lastUsed > $1.lastUsed }
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
                        
                        Spacer()
                    }
                    
                    if let description = preset.description {
                        Text(description)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                // 操作按钮
                HStack(spacing: 8) {
                    Button("加载") {
                        onLoad()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    if isHovered {
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
                }
            }
            
            // 预设内容概览
            HStack(spacing: 20) {
                // 节点信息
                if !preset.selectedNodeIds.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "circle")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            Text("节点 (\(preset.selectedNodeIds.count))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        
                        let nodeNames = getNodeNames(for: preset.selectedNodeIds)
                        Text(nodeNames.prefix(3).joined(separator: ", ") + (nodeNames.count > 3 ? "..." : ""))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                // 层级信息
                if !preset.selectedLayerIds.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "square.stack")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                            Text("层级 (\(preset.selectedLayerIds.count))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                        }
                        
                        let layerNames = getLayerNames(for: preset.selectedLayerIds)
                        Text(layerNames.prefix(3).joined(separator: ", ") + (layerNames.count > 3 ? "..." : ""))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // 时间信息
                VStack(alignment: .trailing, spacing: 2) {
                    Text("创建: \(preset.createdAt, formatter: dateFormatter)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Text("使用: \(preset.lastUsed, formatter: dateFormatter)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
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