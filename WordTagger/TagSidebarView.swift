import SwiftUI
import CoreLocation
import MapKit

struct TagSidebarView: View {
    @EnvironmentObject private var store: NodeStore
    @State private var filter: String = ""
    @State private var selectedTagType: Tag.TagType?
    @Binding var selectedNode: Node?
    @State private var selectedIndex: Int = -1
    @FocusState private var isListFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 当前层级指示器
            if let currentLayer = store.currentLayer {
                HStack {
                    Circle()
                        .fill(Color.from(currentLayer.color))
                        .frame(width: 12, height: 12)
                    
                    Text(currentLayer.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(store.getNodesInCurrentLayer().count) 个节点")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.from(currentLayer.color).opacity(0.1))
                
                Divider()
            }
            
            // 搜索栏
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("搜索标签...", text: $filter)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                
                // 标签类型过滤器
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        TagTypeFilterButton(
                            type: nil,
                            isSelected: selectedTagType == nil,
                            action: { selectedTagType = nil }
                        )
                        
                        ForEach(Tag.TagType.allCases, id: \.self) { type in
                            TagTypeFilterButton(
                                type: type,
                                isSelected: selectedTagType == type,
                                action: { 
                                    selectedTagType = selectedTagType == type ? nil : type
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 标签列表
            ScrollViewReader { proxy in
                List(Array(filteredTags.enumerated()), id: \.offset) { index, tag in
                    TagRowView(
                        tag: tag,
                        isHighlighted: index == selectedIndex
                    ) {
                        selectTagAtIndex(index)
                    }
                    .id(index)
                    .onAppear {
                        print("🎨 TagRow出现: index=\(index), tag='\(tag.value)', highlighted=\(index == selectedIndex)")
                    }
                }
                .listStyle(.sidebar)
                .focused($isListFocused)
                .onKeyPress(.upArrow) {
                    if selectedIndex > 0 {
                        selectedIndex -= 1
                        selectTagAtIndex(selectedIndex)
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(selectedIndex, anchor: .center)
                        }
                    }
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    if selectedIndex < filteredTags.count - 1 {
                        selectedIndex += 1
                        selectTagAtIndex(selectedIndex)
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(selectedIndex, anchor: .center)
                        }
                    }
                    return .handled
                }
                .onKeyPress(.return) {
                    selectTagAtIndex(selectedIndex)
                    return .handled
                }
                .onChange(of: filteredTags) { _, newTags in
                    print("🔄 filteredTags changed: 旧selectedIndex=\(selectedIndex), 新标签数=\(newTags.count)")
                    DispatchQueue.main.async {
                        let oldIndex = self.selectedIndex
                        self.selectedIndex = min(self.selectedIndex, max(0, newTags.count - 1))
                        print("🔄 selectedIndex 更新: \(oldIndex) -> \(self.selectedIndex)")
                        
                        // 如果没有标签了，确保清除选中状态
                        if newTags.isEmpty {
                            self.selectedIndex = -1
                            print("🧹 清空选中索引，因为没有标签")
                        }
                    }
                }
                .onAppear {
                    DispatchQueue.main.async {
                        isListFocused = true
                        // 重置选中索引，避免显示异常高亮
                        selectedIndex = -1
                        print("🧹 onAppear: 重置selectedIndex=-1，避免意外高亮")
                    }
                }
            }
            .navigationTitle("标签")
            .focusable()
            .onKeyPress(.escape) {
                // 按ESC键隐藏标签管理侧边栏
                print("🔑 TagSidebarView: ESC键按下，隐藏标签管理")
                NotificationCenter.default.post(name: Notification.Name("toggleSidebar"), object: nil)
                return .handled
            }
            .onAppear {
                // 确保获得键盘焦点，这对ESC键处理很重要
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    print("🔑 TagSidebarView 获得键盘焦点")
                    // 强制设置焦点到整个视图
                    if let window = NSApp.keyWindow {
                        window.makeFirstResponder(window.contentView)
                        print("🔑 设置键盘焦点到窗口内容视图")
                    }
                }
            }
            // 添加额外的ESC键处理层
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                print("🔑 窗口获得键盘焦点")
            }
        }
    }
    
    private var filteredTags: [Tag] {
        print("🔍 TagSidebarView.filteredTags 开始计算")
        print("   - searchQuery: '\(store.searchQuery)'")
        print("   - currentLayer: \(store.currentLayer?.displayName ?? "nil")")
        
        // 如果有全局搜索查询，优先显示相关标签
        var tags: [Tag]
        if !store.searchQuery.isEmpty {
            tags = store.getRelevantTags(for: store.searchQuery)
            print("   - 使用搜索标签: \(tags.count)个")
        } else {
            // 如果有当前层，显示当前层标签；否则显示所有标签
            if store.currentLayer != nil {
                tags = store.currentLayerTags
                print("   - 使用当前层标签: \(tags.count)个")
            } else {
                tags = store.allTags
                print("   - 使用全局标签: \(tags.count)个")
            }
        }
        
        // 按类型过滤
        if let selectedType = selectedTagType {
            tags = tags.filter { $0.type == selectedType }
        }
        
        // 过滤掉内部管理标签
        tags = tags.filter { tag in
            if case .custom(let key) = tag.type {
                return !(key == "compound" || key == "child")
            }
            return true
        }
        
        // 按本地搜索文本过滤
        if !filter.isEmpty {
            tags = tags.filter { $0.value.localizedCaseInsensitiveContains(filter) }
        }
        
        // 按类型和值排序
        return tags.sorted { tag1, tag2 in
            if tag1.type != tag2.type {
                return tag1.type.rawValue < tag2.type.rawValue
            }
            return tag1.value < tag2.value
        }
    }
    
    private func selectTagAtIndex(_ index: Int) {
        guard index < filteredTags.count else { return }
        let tag = filteredTags[index]
        selectedIndex = index
        
        // 使用异步调度避免在视图更新期间修改状态
        DispatchQueue.main.async {
            store.selectTag(tag)
            let relatedNodes = store.nodes(withTag: tag)
            if let firstNode = relatedNodes.first {
                self.selectedNode = firstNode
                store.selectNode(firstNode)
            }
        }
    }
    
}

// MARK: - 标签类型过滤按钮

struct TagTypeFilterButton: View {
    let type: Tag.TagType?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let type = type {
                    Circle()
                        .fill(Color.from(tagType: type))
                        .frame(width: 8, height: 8)
                    Text(type.displayName)
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Text("全部")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 标签行视图

struct TagRowView: View {
    let tag: Tag
    let isHighlighted: Bool
    let onTap: () -> Void
    @EnvironmentObject private var store: NodeStore
    
    init(tag: Tag, isHighlighted: Bool = false, onTap: @escaping () -> Void) {
        self.tag = tag
        self.isHighlighted = isHighlighted
        self.onTap = onTap
    }
    
    private var wordsCount: Int {
        store.nodes(withTag: tag).count
    }
    
    var body: some View {
        let isCurrentlySelected = store.selectedTag?.id == tag.id
        let _ = print("🏷️ TagRowView: 渲染标签 value='\(tag.value)', type=\(tag.type), displayName='\(tag.type.displayName)', selected=\(isCurrentlySelected), highlighted=\(isHighlighted)")
        return Button(action: onTap) {
            HStack(spacing: 16) {
                // 标签类型指示器
                Circle()
                    .fill(Color.from(tagType: tag.type))
                    .frame(width: 12, height: 12)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(tag.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack {
                        Text(tag.type.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        if tag.hasCoordinates {
                            Image(systemName: "location.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Spacer()
                
                // 单词数量
                VStack {
                    Text("\(wordsCount)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                    
                    Text("单词")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    // 只有在有标签且实际选中时才高亮
                    (isHighlighted && !store.allTags.isEmpty) ? Color.blue.opacity(0.2) : 
                    (isCurrentlySelected ? Color.blue.opacity(0.1) : Color.clear)
                )
        )
    }
}

#Preview {
    NavigationSplitView {
        TagSidebarView(selectedNode: .constant(nil))
            .environmentObject(NodeStore.shared)
    } content: {
        Text("Content")
    } detail: {
        Text("Detail")
    }
}
