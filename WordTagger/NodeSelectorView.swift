import SwiftUI
import AppKit

// MARK: - 节点选择器视图

struct NodeSelectorView: View {
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedNodeIds: Set<UUID>
    @State private var tempSelectedIds: Set<UUID> = []
    @State private var searchQuery: String = ""
    
    private var filteredNodes: [Node] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return store.nodes.sorted { $0.text < $1.text }
        }
        
        return store.nodes.filter { node in
            node.text.localizedCaseInsensitiveContains(searchQuery) ||
            node.meaning?.localizedCaseInsensitiveContains(searchQuery) == true
        }.sorted { $0.text < $1.text }
    }
    
    private var regularNodes: [Node] {
        filteredNodes.filter { !$0.isCompound }
    }
    
    private var compoundNodes: [Node] {
        filteredNodes.filter { $0.isCompound }
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
                
                Text("选择要显示的节点")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("完成") {
                    selectedNodeIds = tempSelectedIds
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 搜索栏
            HStack {
                TextField("搜索节点...", text: $searchQuery)
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
                    tempSelectedIds = Set(store.nodes.map { $0.id })
                }
                .buttonStyle(.bordered)
                
                Button("全不选") {
                    tempSelectedIds.removeAll()
                }
                .buttonStyle(.bordered)
                
                Button("仅复合节点") {
                    tempSelectedIds = Set(store.nodes.filter { $0.isCompound }.map { $0.id })
                }
                .buttonStyle(.bordered)
                
                Button("仅普通节点") {
                    tempSelectedIds = Set(store.nodes.filter { !$0.isCompound }.map { $0.id })
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // 节点列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // 复合节点部分
                    if !compoundNodes.isEmpty {
                        SectionHeaderView(title: "复合节点", count: compoundNodes.count)
                        
                        ForEach(compoundNodes, id: \.id) { node in
                            NodeSelectorRow(
                                node: node,
                                isSelected: tempSelectedIds.contains(node.id),
                                isCompound: true
                            ) {
                                toggleNode(node)
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 8)
                    }
                    
                    // 普通节点部分
                    if !regularNodes.isEmpty {
                        SectionHeaderView(title: "普通节点", count: regularNodes.count)
                        
                        ForEach(regularNodes, id: \.id) { node in
                            NodeSelectorRow(
                                node: node,
                                isSelected: tempSelectedIds.contains(node.id),
                                isCompound: false
                            ) {
                                toggleNode(node)
                            }
                        }
                    }
                    
                    // 空状态
                    if filteredNodes.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            
                            Text("没有找到匹配的节点")
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
            tempSelectedIds = selectedNodeIds
        }
    }
    
    private func toggleNode(_ node: Node) {
        if tempSelectedIds.contains(node.id) {
            tempSelectedIds.remove(node.id)
        } else {
            tempSelectedIds.insert(node.id)
        }
    }
}

// MARK: - 节点选择器行视图

struct NodeSelectorRow: View {
    let node: Node
    let isSelected: Bool
    let isCompound: Bool
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
            
            // 节点类型指示器
            Circle()
                .fill(isCompound ? Color.purple : Color.blue)
                .frame(width: 8, height: 8)
            
            // 节点信息
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(node.text)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    if isCompound {
                        Text("复合")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    // 标签数量
                    Text("\(node.tags.count)个标签")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let meaning = node.meaning {
                    Text(meaning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
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

// MARK: - 分组标题视图

struct SectionHeaderView: View {
    let title: String
    let count: Int
    
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("(\(count))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

// MARK: - Window Accessor for fixing sheet window size

struct WindowAccessor: NSViewRepresentable {
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
            // 检查是否是Sheet窗口并且包含我们的内容
            if window.isSheet || window.title.contains("选择要显示的节点") || window.level == NSWindow.Level.modalPanel {
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
        
        // 设置固定尺寸约束
        let targetSize = NSSize(width: 700, height: 600)
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