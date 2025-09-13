import SwiftUI
import AppKit

// MARK: - 层级选择器视图

struct LayerSelectorView: View {
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLayerIds: Set<UUID>
    @State private var tempSelectedIds: Set<UUID> = []
    @State private var searchQuery: String = ""
    
    private var filteredLayers: [Layer] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return store.layers.sorted { $0.displayName < $1.displayName }
        }
        
        return store.layers.filter { layer in
            layer.displayName.localizedCaseInsensitiveContains(searchQuery) ||
            layer.name.localizedCaseInsensitiveContains(searchQuery)
        }.sorted { $0.displayName < $1.displayName }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("选择要显示的层")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("完成") {
                    selectedLayerIds = tempSelectedIds
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 搜索栏
            HStack {
                TextField("搜索层...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                
                if !searchQuery.isEmpty {
                    Button("清除") {
                        searchQuery = ""
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 快速选择按钮
            HStack {
                Button("全选") {
                    tempSelectedIds = Set(store.layers.map { $0.id })
                }
                .buttonStyle(.bordered)
                
                Button("全不选") {
                    tempSelectedIds.removeAll()
                }
                .buttonStyle(.bordered)
                
                Button("显示所有层") {
                    tempSelectedIds.removeAll() // 空集表示显示所有层
                }
                .buttonStyle(.bordered)
                
                if let currentLayer = store.currentLayer {
                    Button("仅当前层") {
                        tempSelectedIds = Set([currentLayer.id])
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // 层列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredLayers, id: \.id) { layer in
                        LayerSelectorRow(
                            layer: layer,
                            isSelected: tempSelectedIds.contains(layer.id),
                            isCurrentLayer: store.currentLayer?.id == layer.id
                        ) {
                            toggleLayer(layer)
                        }
                    }
                    
                    // 空状态
                    if filteredLayers.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            
                            Text("没有找到匹配的层")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            tempSelectedIds = selectedLayerIds
        }
    }
    
    private func toggleLayer(_ layer: Layer) {
        if tempSelectedIds.contains(layer.id) {
            tempSelectedIds.remove(layer.id)
        } else {
            tempSelectedIds.insert(layer.id)
        }
    }
}

// MARK: - 层级选择器行视图

struct LayerSelectorRow: View {
    @EnvironmentObject private var store: NodeStore
    let layer: Layer
    let isSelected: Bool
    let isCurrentLayer: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 复选框
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            
            // 层级颜色指示器
            Circle()
                .fill(Color.from(layer.color))
                .frame(width: 12, height: 12)
            
            // 层级信息
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(layer.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    if isCurrentLayer {
                        Text("当前层")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                    
                    if layer.isCompound {
                        Text("复合")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    // 节点数量
                    let nodeCount = store.nodes.filter { $0.layerId == layer.id }.count
                    Text("\(nodeCount)个节点")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("(\(layer.name))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        )
        .onTapGesture {
            onToggle()
        }
    }
}

// MARK: - Layer Window Accessor for fixing layer selector sheet window size

struct LayerWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.findAndConfigureWindow()
        }
        
        // 多次延迟尝试，确保能找到并配置窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.findAndConfigureWindow()
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.findAndConfigureWindow()
        }
    }
    
    private func findAndConfigureWindow() {
        // 查找所有Sheet类型的窗口
        for window in NSApp.windows {
            // 检查是否是Sheet窗口并且包含层级选择相关内容
            if window.isSheet || window.title.contains("选择要显示的层") || window.level == NSWindow.Level.modalPanel {
                self.configureWindow(window)
            }
        }
        
        // 如果找不到特定窗口，尝试最新的非主窗口
        if let latestWindow = NSApp.windows.filter({ !$0.isMainWindow && $0.isVisible }).first {
            self.configureWindow(latestWindow)
        }
    }
    
    private func configureWindow(_ window: NSWindow) {
        // 完全禁用窗口大小调整
        window.styleMask.remove(.resizable)
        
        // 设置层级选择器的固定尺寸约束
        let targetSize = NSSize(width: 600, height: 500)
        window.minSize = targetSize
        window.maxSize = targetSize
        
        // 强制设置窗口尺寸
        if window.frame.size != targetSize {
            let currentFrame = window.frame
            let newFrame = NSRect(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y,
                width: targetSize.width,
                height: targetSize.height
            )
            window.setFrame(newFrame, display: true, animate: false)
        }
        
        // 设置窗口不可移动（如果需要的话）
        window.isMovable = true // 保持可移动，但不可调整大小
        
        // 确保内容视图也不能调整大小
        if let contentView = window.contentView {
            contentView.autoresizingMask = []
        }
    }
}