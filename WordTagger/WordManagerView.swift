import SwiftUI
import MapKit
import CoreLocation

struct NodeManagerView: View {
    @EnvironmentObject private var store: NodeStore
    @Binding var nodeToEdit: Node?
    @State private var selectedNodes: Set<UUID> = []
    @State private var localSearchQuery: String = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var showingDeleteAlert = false
    @State private var sortOption: SortOption = .alphabetical
    @State private var filterOption: FilterOption = .all
    @State private var showingCommandPalette = false
    @State private var commandPaletteNode: Node?
    @State private var isSelectionMode = false
    @FocusState private var isSearchFieldFocused: Bool
    
    enum SortOption: String, CaseIterable {
        case alphabetical = "按字母排序"
        case createdDate = "按创建时间"
        case updatedDate = "按修改时间"
        case tagCount = "按标签数量"
    }
    
    enum FilterOption: String, CaseIterable {
        case all = "全部节点"
        case withTags = "有标签的"
        case withoutTags = "无标签的"
        case withMeaning = "有释义的"
        case withoutMeaning = "无释义的"
    }
    
    var filteredAndSortedNodes: [Node] {
        var nodes = store.nodes
        
        // 如果有搜索查询，优先显示搜索结果，忽略selectedTag过滤
        if !localSearchQuery.isEmpty {
            nodes = nodes.filter { node in
                node.text.localizedCaseInsensitiveContains(localSearchQuery) ||
                (node.meaning?.localizedCaseInsensitiveContains(localSearchQuery) ?? false) ||
                (node.phonetic?.localizedCaseInsensitiveContains(localSearchQuery) ?? false) ||
                node.tags.contains { $0.value.localizedCaseInsensitiveContains(localSearchQuery) }
            }
        } else if let selectedTag = store.selectedTag {
            // 只在没有搜索查询时应用selectedTag过滤
            nodes = nodes.filter { $0.hasTag(selectedTag) }
        }
        
        // 应用过滤器
        switch filterOption {
        case .all:
            break
        case .withTags:
            nodes = nodes.filter { !$0.tags.isEmpty }
        case .withoutTags:
            nodes = nodes.filter { $0.tags.isEmpty }
        case .withMeaning:
            nodes = nodes.filter { $0.meaning != nil && !$0.meaning!.isEmpty }
        case .withoutMeaning:
            nodes = nodes.filter { $0.meaning == nil || $0.meaning!.isEmpty }
        }
        
        // 应用排序
        switch sortOption {
        case .alphabetical:
            nodes.sort { $0.text.localizedCompare($1.text) == .orderedAscending }
        case .createdDate:
            nodes.sort { $0.createdAt > $1.createdAt }
        case .updatedDate:
            nodes.sort { $0.updatedAt > $1.updatedAt }
        case .tagCount:
            nodes.sort { $0.tags.count > $1.tags.count }
        }
        
        return nodes
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("节点管理")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    // 显示当前过滤状态
                    if !localSearchQuery.isEmpty {
                        HStack(spacing: 4) {
                            Text("搜索: \"\(localSearchQuery)\" - 忽略标签过滤")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            Button("✕") {
                                localSearchQuery = ""
                            }
                            .font(.caption)
                            .foregroundColor(.green)
                            .buttonStyle(.plain)
                            .help("清除搜索")
                        }
                    } else if let selectedTag = store.selectedTag {
                        HStack(spacing: 4) {
                            Text("过滤: \(selectedTag.type.displayName) - \(selectedTag.value)")
                                .font(.caption)
                                .foregroundColor(.blue)
                            
                            Button("✕") {
                                store.selectTag(nil)
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                            .buttonStyle(.plain)
                            .help("清除标签过滤")
                        }
                    }
                }
                
                Spacer()
                
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("搜索节点、释义、音标或标签...", text: $localSearchQuery)
                        .textFieldStyle(.plain)
                        .frame(width: 200)
                        .focused($isSearchFieldFocused)
                        .onChange(of: localSearchQuery) { oldValue, newValue in
                            print("🔤 NodeManagerView: localSearchQuery changed from '\(oldValue)' to '\(newValue)'")
                            
                            // 取消之前的搜索任务
                            searchTask?.cancel()
                            
                            // 立即更新store的搜索查询，让Store的防抖机制处理重复请求
                            print("🔄 NodeManagerView: Immediately updating store.searchQuery to '\(newValue)'")
                            store.searchQuery = newValue
                            
                            // 保持焦点在输入框
                            DispatchQueue.main.async {
                                isSearchFieldFocused = true
                            }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                
                // 过滤器
                Menu {
                    ForEach(FilterOption.allCases, id: \.self) { option in
                        Button(action: {
                            filterOption = option
                        }) {
                            HStack {
                                Text(option.rawValue)
                                if filterOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(filterOption.rawValue)
                    }
                    .foregroundColor(.blue)
                }
                .help("过滤选项")
                
                // 排序选项
                Menu {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button(action: {
                            sortOption = option
                        }) {
                            HStack {
                                Text(option.rawValue)
                                if sortOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(sortOption.rawValue)
                    }
                    .foregroundColor(.blue)
                }
                .help("排序选项")
                
                // 模式切换按钮
                Button(action: {
                    isSelectionMode.toggle()
                    if !isSelectionMode {
                        selectedNodes.removeAll()
                    }
                }) {
                    HStack {
                        Image(systemName: isSelectionMode ? "checkmark.circle.fill" : "cursor.rays")
                        Text(isSelectionMode ? "选择模式" : "编辑模式")
                    }
                    .foregroundColor(isSelectionMode ? .orange : .blue)
                }
                .help(isSelectionMode ? "点击切换到编辑模式" : "点击切换到选择模式")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 操作栏（只在选择模式下显示）
            if isSelectionMode {
                HStack {
                Text("选中 \(selectedNodes.count) / \(filteredAndSortedNodes.count) 个节点")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 全选/取消全选
                Button(action: {
                    if selectedNodes.count == filteredAndSortedNodes.count {
                        selectedNodes.removeAll()
                    } else {
                        selectedNodes = Set(filteredAndSortedNodes.map { $0.id })
                    }
                }) {
                    Text(selectedNodes.count == filteredAndSortedNodes.count ? "取消全选" : "全选")
                        .font(.caption)
                }
                .disabled(filteredAndSortedNodes.isEmpty)
                
                // 批量删除按钮
                Button(action: {
                    showingDeleteAlert = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("删除选中节点")
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                .disabled(selectedNodes.isEmpty)
                .alert("确认删除", isPresented: $showingDeleteAlert) {
                    Button("取消", role: .cancel) { }
                    Button("删除", role: .destructive) {
                        batchDeleteNodes()
                    }
                } message: {
                    Text("确定要删除选中的 \(selectedNodes.count) 个节点吗？此操作不可撤销。")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            }
            
            // 节点列表
            if filteredAndSortedNodes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
                    Group {
                        if localSearchQuery.isEmpty {
                            if store.selectedTag != nil {
                                Text("当前标签下暂无节点")
                            } else {
                                Text("暂无节点")
                            }
                        } else {
                            Text("未找到匹配 \"\(localSearchQuery)\" 的节点")
                        }
                    }
                    .font(.title3)
                    .foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        if !localSearchQuery.isEmpty {
                            Button("清除搜索") {
                                localSearchQuery = ""
                            }
                            .foregroundColor(.blue)
                        }
                        
                        if store.selectedTag != nil && localSearchQuery.isEmpty {
                            Button("清除标签过滤") {
                                store.selectTag(nil)
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredAndSortedNodes, id: \.id) { node in
                            NodeManagerRowView(
                                node: node,
                                isSelected: selectedNodes.contains(node.id),
                                isSelectionMode: isSelectionMode,
                                onToggleSelection: {
                                    if selectedNodes.contains(node.id) {
                                        selectedNodes.remove(node.id)
                                    } else {
                                        selectedNodes.insert(node.id)
                                    }
                                },
                                onNodeEdit: { node in
                                    commandPaletteNode = node
                                    showingCommandPalette = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
        }
        .navigationTitle("节点管理")
        .sheet(item: Binding<Node?>(
            get: { showingCommandPalette ? commandPaletteNode : nil },
            set: { newValue in
                if newValue == nil {
                    showingCommandPalette = false
                    commandPaletteNode = nil
                }
            }
        )) { node in
            TagEditCommandView(node: node)
                .environmentObject(store)
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .onAppear {
            // 检查是否有待编辑的节点
            if let nodeToEdit = nodeToEdit {
                print("📝 NodeManagerView: 检测到待编辑节点: \(nodeToEdit.text)")
                // 自动打开编辑界面
                commandPaletteNode = nodeToEdit
                showingCommandPalette = true
                // 清除待编辑节点
                DispatchQueue.main.async {
                    self.nodeToEdit = nil
                }
            }
        }
        .onChange(of: nodeToEdit) { _, newNode in
            // 处理运行时设置的待编辑节点
            if let node = newNode {
                print("📝 NodeManagerView: onChange检测到待编辑节点: \(node.text)")
                commandPaletteNode = node
                showingCommandPalette = true
                // 清除待编辑节点
                DispatchQueue.main.async {
                    self.nodeToEdit = nil
                }
            }
        }
    }
    
    private func batchDeleteNodes() {
        for nodeId in selectedNodes {
            store.deleteNode(nodeId)
        }
        selectedNodes.removeAll()
    }
}

// MARK: - Node Manager Row View

struct NodeManagerRowView: View {
    let node: Node
    let isSelected: Bool
    let isSelectionMode: Bool
    let onToggleSelection: () -> Void
    let onNodeEdit: (Node) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 选择框（只在选择模式下显示）
            if isSelectionMode {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .blue : .secondary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }
            
            // 节点信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    // 节点文本
                    Text(node.text)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    // 音标
                    if let phonetic = node.phonetic {
                        Text(phonetic)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.1))
                            )
                    }
                    
                    Spacer()
                    
                    // 标签数量
                    if !node.tags.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "tag.fill")
                                .font(.caption2)
                            Text("\(node.tags.count)")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                // 释义
                if let meaning = node.meaning, !meaning.isEmpty {
                    Text(meaning)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // 标签
                if !node.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(node.tags.prefix(5), id: \.id) { tag in
                                Group {
                                    if case .custom(let key) = tag.type, TagMappingManager.shared.isLocationTagKey(key), tag.hasCoordinates {
                                        // 位置标签添加点击预览功能
                                        Button(action: {
                                            previewLocation(tag: tag)
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "location.fill")
                                                    .font(.caption2)
                                                Text(tag.displayName)
                                                    .font(.caption)
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color.from(tagType: tag.type).opacity(0.2))
                                            )
                                            .foregroundColor(Color.from(tagType: tag.type))
                                        }
                                        .buttonStyle(.plain)
                                        .help("点击预览位置")
                                    } else {
                                        Text(tag.displayName)
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color.from(tagType: tag.type).opacity(0.2))
                                            )
                                            .foregroundColor(Color.from(tagType: tag.type))
                                    }
                                }
                            }
                            
                            if node.tags.count > 5 {
                                Text("+\(node.tags.count - 5)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // 时间信息
                HStack(spacing: 12) {
                    Text("创建: \(node.createdAt.timeAgoDisplay())")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if node.updatedAt > node.createdAt {
                        Text("修改: \(node.updatedAt.timeAgoDisplay())")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection()
            } else {
                onNodeEdit(node)
            }
        }
        .allowsHitTesting(true)
    }
    
    private func previewLocation(tag: Tag) {
        guard let latitude = tag.latitude,
              let longitude = tag.longitude else { return }
        
        print("🎯 Previewing location: \(tag.displayName) at (\(latitude), \(longitude))")
        
        // 打开地图窗口
        NotificationCenter.default.post(name: NSNotification.Name("openMapWindow"), object: nil)
        
        // 延迟发送位置预览通知，给地图窗口时间打开
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let previewData: [String: Any] = [
                "latitude": latitude,
                "longitude": longitude,
                "name": tag.displayName,
                "isPreview": true
            ]
            
            NotificationCenter.default.post(
                name: NSNotification.Name("previewLocation"),
                object: previewData
            )
        }
    }
}

// MARK: - Tag Edit Command View

struct TagEditCommandView: View {
    let node: Node
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    @State private var commandText: String = ""
    @State private var selectedIndex: Int = 0
    @State private var showingLocationPicker = false
    @StateObject private var commandParser = CommandParser.shared
    @State private var showingDuplicateAlert = false
    
    // 从store获取最新的节点数据
    private var currentNode: Node {
        return store.nodes.first { $0.id == node.id } ?? node
    }
    
    private var initialCommand: String {
        // 使用最新的节点数据和新的规范化命令表示
        let currentNodeData = currentNode
        
        // 🔧 使用新的 canonicalCommandRepresentation 方法
        // 这将自动处理复合节点的简洁格式 "c 复合节点名 子节点1 子节点2"
        return currentNodeData.canonicalCommandRepresentation
    }
    
    @State private var availableCommands: [Command] = []
    
    @MainActor
    private func updateAvailableCommands() {
        let context = CommandContext(store: store, currentNode: node)
        Task {
            availableCommands = await commandParser.parse(commandText, context: context)
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // 标题栏
            HStack {
                Text("编辑节点: \(node.text)")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("执行") {
                    executeCommand()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r", modifiers: [.command])
            }
            .padding()
            
            Divider()
            
            // 命令输入框
            VStack(alignment: .leading, spacing: 12) {
                Text("输入标签命令:")
                    .font(.headline)
                
                TextField("例如: memory 记忆法 root dict", text: $commandText)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onSubmit {
                        executeCommand()
                    }
                    .onChange(of: commandText) { _, _ in
                        updateAvailableCommands()
                    }
                
                Text("当前命令: \(commandText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // 当前标签显示
            VStack(alignment: .leading, spacing: 8) {
                Text("当前标签 (\(node.tags.count)个):")
                    .font(.headline)
                
                if node.tags.isEmpty {
                    Text("暂无标签")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(node.tags, id: \.id) { tag in
                                HStack(spacing: 4) {
                                    Text(tag.type.displayName)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text(tag.value)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.from(tagType: tag.type).opacity(0.2))
                                )
                                .foregroundColor(Color.from(tagType: tag.type))
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
            .padding()
            
            Divider()
            
            // 使用说明
            VStack(alignment: .leading, spacing: 8) {
                Text("💡 使用提示:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• 格式: 标签类型 标签值")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("• 多个标签用空格分隔")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                        
                    Text("• 示例: memory 记忆法 root dict shape 长方形")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Spacer()
        }
        .frame(minWidth: 500, maxWidth: 600, minHeight: 400, maxHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            print("📝 TagEditCommandView onAppear")
            print("📝 传入节点: \(node.text), 标签数: \(node.tags.count)")
            let currentNodeData = currentNode
            print("📝 最新节点: \(currentNodeData.text), 标签数: \(currentNodeData.tags.count)")
            for (index, tag) in currentNodeData.tags.enumerated() {
                print("📝   标签[\(index)]: \(tag.type.displayName) = '\(tag.value)' (rawValue: '\(tag.type.rawValue)')")
            }
            print("📝 生成的初始命令: '\(initialCommand)'")
            commandText = initialCommand
            updateAvailableCommands()
        }
        .onKeyPress(.init("r"), phases: .down) { _ in
            if NSEvent.modifierFlags.contains(.command) {
                executeCommand()
                return .handled
            }
            return .ignored
        }
        .background(
            Button("") {
                openMapForLocationSelection()
            }
            .keyboardShortcut("p", modifiers: [.command])
            .hidden()
        )
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("locationSelected"))) { notification in
            if let locationData = notification.object as? [String: Any],
               let latitude = locationData["latitude"] as? Double,
               let longitude = locationData["longitude"] as? Double {
                
                // 如果有地名信息，使用地名；否则让用户自己输入
                let locationCommand: String
                if let locationName = locationData["name"] as? String {
                    locationCommand = "loc @\(latitude),\(longitude)[\(locationName)]"
                    print("🎯 NodeManager: Using location with name: \(locationName)")
                } else {
                    locationCommand = "loc @\(latitude),\(longitude)[]"
                    print("🎯 NodeManager: Using coordinates only, user needs to fill name")
                }
                
                if commandText.isEmpty || commandText == initialCommand {
                    commandText = "\(node.text) \(locationCommand)"
                } else {
                    commandText += " \(locationCommand)"
                }
            }
        }
        .alert("重复检测", isPresented: $showingDuplicateAlert) {
            Button("确定") { }
        } message: {
            if let alert = store.duplicateNodeAlert {
                Text(alert.message)
            }
        }
        .onReceive(store.$duplicateNodeAlert) { alert in
            if alert != nil {
                showingDuplicateAlert = true
                // 延迟清除alert以避免立即触发下一次
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    store.duplicateNodeAlert = nil
                }
            }
        }
    }
    
    private func executeCommand() {
        print("🚀 executeCommand() 被调用")
        print("🚀 当前命令文本: '\(commandText)'")
        
        let trimmedText = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🚀 去除空格后的命令: '\(trimmedText)'")
        
        guard !trimmedText.isEmpty else { 
            print("⚠️ 命令为空，直接关闭窗口")
            dismiss()
            return 
        }
        
        print("🔧 执行节点编辑命令: \(trimmedText)")
        
        Task {
            // 使用新的批量标签解析器
            let success = await parseBatchTagCommand(trimmedText)
            
            await MainActor.run {
                if success {
                    DispatchQueue.main.async {
                        store.objectWillChange.send()
                    }
                    print("✅ 标签批量更新成功")
                } else {
                    print("❌ 标签批量更新失败")
                }
                print("🚪 关闭节点编辑窗口")
                dismiss()
            }
        }
    }
    
    private func parseBatchTagCommand(_ input: String) async -> Bool {
        print("🔧 parseBatchTagCommand 开始解析: '\(input)'")
        
        // 分词：按空格分割
        let tokens = input.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        print("🔧 分词结果: \(tokens)")
        print("🔧 分词详情:")
        for (index, token) in tokens.enumerated() {
            print("   [\(index)]: '\(token)'")
        }
        
        guard tokens.count >= 2 else { 
            print("❌ Token数量不足: \(tokens.count) < 2")
            return false 
        }
        
        // 第一个token应该是节点名，跳过
        let nodeText = tokens[0]
        guard nodeText == node.text else { 
            print("❌ 节点名不匹配: \(nodeText) vs \(node.text)")
            return false 
        }
        
        print("✅ 节点名匹配: \(nodeText)")
        
        // 解析剩余的标签token
        var newTags: [Tag] = []
        var i = 1
        
        print("🔧 开始解析标签tokens，从索引 \(i) 开始")
        
        while i < tokens.count {
            let token = tokens[i]
            print("🔧 [主循环] 处理token [\(i)]: '\(token)'，总token数: \(tokens.count)")
            
            // 检查是否是标签类型关键词
            if let tagType = mapTokenToTagType(token) {
                print("✅ 识别标签类型: '\(token)' -> \(tagType)")
                let tagKey = token  // 保存原始token作为key
                
                // 检查是否是 tagType[displayName] 格式，如果是则需要处理显示名
                var customDisplayName: String? = nil
                if token.contains("[") && token.contains("]") {
                    if let bracketStart = token.firstIndex(of: "["),
                       let bracketEnd = token.firstIndex(of: "]"),
                       bracketStart < bracketEnd {
                        
                        let displayName = String(token[token.index(after: bracketStart)..<bracketEnd])
                        customDisplayName = displayName
                        print("🏷️ 检测到标签类型自定义显示名: '\(displayName)'")
                        
                        // 为该标签类型设置自定义显示名
                        let baseTagKey = String(token[..<bracketStart])
                        print("🔧 准备添加映射: key='\(baseTagKey)', typeName='\(displayName)'")
                        TagMappingManager.shared.addMappingIfNeeded(key: baseTagKey, typeName: displayName)
                        print("🔧 映射添加完成，当前映射数量: \(TagMappingManager.shared.tagMappings.count)")
                    }
                }
                
                i += 1
                
                // 收集这个标签类型的值
                var values: [String] = []
                print("🔧 收集标签值，从索引 \(i) 开始")
                
                // 特殊处理位置标签：如果是位置标签，需要特别处理坐标格式
                if TagMappingManager.shared.isLocationTagKey(tagKey) {
                    // 对于位置标签，可能有多种格式，需要更智能的解析
                    // 1. 单个完整坐标token: @lat,lng[name]
                    // 2. 分离的tokens: name @lat,lng 或其他组合
                    while i < tokens.count {
                        let nextToken = tokens[i]
                        print("🔧 检查位置标签值 [\(i)]: '\(nextToken)'")
                        
                        // 如果遇到下一个标签类型（但排除坐标格式），停止
                        if mapTokenToTagType(nextToken) != nil {
                            print("🔧 遇到下一个标签类型: '\(nextToken)'，停止收集位置标签值")
                            break
                        }
                        
                        values.append(nextToken)
                        print("🔧 添加位置标签值: '\(nextToken)'，当前值列表: \(values)")
                        
                        // 如果当前token是完整的坐标格式（包含@和[]），这是完整的位置标签值
                        if nextToken.hasPrefix("@") && nextToken.contains("[") && nextToken.contains("]") {
                            print("🔧 检测到完整坐标格式，这是位置标签的完整值")
                            print("🔧 当前索引 i = \(i)，即将跳出位置标签值收集循环")
                            i += 1
                            break
                        }
                        
                        i += 1
                    }
                } else {
                    // 普通标签的值收集逻辑：标签类型 标签值 配对模式
                    if i < tokens.count {
                        let nextToken = tokens[i]
                        print("🔧 检查标签值 [\(i)]: '\(nextToken)'")
                        
                        // 检查是否是 value[displayName] 格式
                        if nextToken.contains("[") && nextToken.contains("]"),
                           let bracketStart = nextToken.firstIndex(of: "["),
                           let bracketEnd = nextToken.firstIndex(of: "]"),
                           bracketStart < bracketEnd {
                            
                            let tagValue = String(nextToken[..<bracketStart])
                            let displayName = String(nextToken[nextToken.index(after: bracketStart)..<bracketEnd])
                            
                            print("🔧 检测到value[displayName]格式: value='\(tagValue)', displayName='\(displayName)'")
                            
                            // 检查是否是快捷键格式：tagValue是快捷键，displayName是类型名
                            // 如果TagMappingManager中已存在该快捷键映射，则这是快捷键格式
                            let isShortcutFormat = TagMappingManager.shared.tagMappings.contains { mapping in
                                mapping.key.lowercased() == tagValue.lowercased() && mapping.typeName == displayName
                            }
                            
                            let customTagType: Tag.TagType
                            let isShortcut: Bool
                            
                            if isShortcutFormat {
                                // 快捷键格式：beef[牛肉种类] -> 使用tagValue作为type的key
                                customTagType = Tag.TagType.custom(tagValue)
                                isShortcut = true
                                print("🔧 识别为快捷键格式: key='\(tagValue)', typeName='\(displayName)'")
                            } else {
                                // 普通value[displayName]格式 -> 使用displayName作为type的key
                                customTagType = Tag.TagType.custom(displayName)
                                isShortcut = false
                                TagMappingManager.shared.addMappingIfNeeded(key: displayName, typeName: displayName)
                                print("🔧 识别为普通格式: key='\(displayName)', value='\(tagValue)'")
                            }
                            
                            // 创建标签
                            let tag = store.createTag(type: customTagType, value: tagValue, isShortcutType: isShortcut)
                            newTags.append(tag)
                            print("✅ 创建自定义标签: \(displayName) - \(tagValue)")
                            
                            i += 1
                            continue // 跳过后续的普通处理逻辑
                        } else {
                            // 普通标签值处理
                            values.append(nextToken)
                            print("🔧 添加标签值: '\(nextToken)'")
                            i += 1
                        }
                    }
                }
                
                print("🔧 收集的值: \(values)")
                print("🔧 标签值收集完成，当前索引 i = \(i)，下一个token: \(i < tokens.count ? tokens[i] : "超出范围")")
                
                // 创建标签
                let value: String
                if !values.isEmpty {
                    value = values.joined(separator: " ")
                    print("🔧 创建标签，类型: \(tagType)，值: '\(value)'")
                } else {
                    // 如果没有收集到值，使用标签类型的显示名称作为值
                    value = tagType.displayName
                    print("🔧 创建无值标签，类型: \(tagType)，使用显示名称作为值: '\(value)'")
                }
                
                // 如果有自定义显示名，创建自定义标签类型
                let finalTagType: Tag.TagType
                if let customDisplayName = customDisplayName {
                    finalTagType = Tag.TagType.custom(customDisplayName)
                    print("🏷️ 使用自定义标签类型: \(customDisplayName)")
                } else {
                    finalTagType = tagType
                }
                    
                    // 检查是否是地图标签（通过key识别）
                    if TagMappingManager.shared.isLocationTagKey(tagKey) {
                        var locationName: String = ""
                        var lat: Double = 0
                        var lng: Double = 0
                        var parsed = false
                        
                        // 格式1: 名称@纬度,经度 (如: 天马广场@37.45,121.61)
                        if value.contains("@") && !value.hasPrefix("@") {
                            let components = value.split(separator: "@", maxSplits: 1)
                            if components.count == 2 {
                                locationName = String(components[0])
                                let coordString = String(components[1])
                                let coords = coordString.split(separator: ",")
                                
                                if coords.count == 2,
                                   let latitude = Double(coords[0]),
                                   let longitude = Double(coords[1]) {
                                    lat = latitude
                                    lng = longitude
                                    parsed = true
                                }
                            }
                        }
                        // 格式2: @纬度,经度[名称] (如: @37.45,121.61[天马广场])
                        else if value.hasPrefix("@") && value.contains("[") && value.contains("]") {
                            print("🔍 解析格式2坐标: \(value)")
                            // 提取坐标部分 @纬度,经度
                            if let atIndex = value.firstIndex(of: "@"),
                               let bracketIndex = value.firstIndex(of: "[") {
                                let coordString = String(value[value.index(after: atIndex)..<bracketIndex])
                                print("🔍 提取的坐标字符串: '\(coordString)'")
                                let coords = coordString.split(separator: ",")
                                print("🔍 分割后的坐标: \(coords)")
                                
                                if coords.count == 2 {
                                    let latString = String(coords[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                                    let lngString = String(coords[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                                    print("🔍 纬度字符串: '\(latString)', 经度字符串: '\(lngString)'")
                                    
                                    if let latitude = Double(latString),
                                       let longitude = Double(lngString) {
                                        lat = latitude
                                        lng = longitude
                                        print("🔍 坐标解析成功: lat=\(lat), lng=\(lng)")
                                        
                                        // 提取名称部分 [名称]
                                        if let startBracket = value.firstIndex(of: "["),
                                           let endBracket = value.firstIndex(of: "]"),
                                           startBracket < endBracket {
                                            locationName = String(value[value.index(after: startBracket)..<endBracket])
                                            print("🔍 地名解析成功: '\(locationName)'")
                                            parsed = true
                                        } else {
                                            print("❌ 地名解析失败")
                                        }
                                    } else {
                                        print("❌ 坐标转换为Double失败")
                                    }
                                } else {
                                    print("❌ 坐标分割后不是2个部分")
                                }
                            } else {
                                print("❌ 找不到@或[符号")
                            }
                        }
                        // 格式3: 简单地名引用 (如: 武功山) - 新增功能
                        else if !value.contains("@") && !value.contains("[") && !value.contains("]") {
                            // 尝试在已有的位置标签中查找匹配的地名
                            if let existingTag = store.findLocationTagByName(value) {
                                locationName = existingTag.value
                                if let existingLat = existingTag.latitude, let existingLng = existingTag.longitude {
                                    lat = existingLat
                                    lng = existingLng
                                    parsed = true
                                    print("🎯 找到已有位置标签: \(locationName) (\(lat), \(lng))")
                                }
                            }
                        }
                        
                        if parsed && !locationName.isEmpty {
                            // 对于成功解析的位置标签，只保存地名作为value，坐标保存在专门字段中
                            let tag = store.createTag(type: finalTagType, value: locationName, latitude: lat, longitude: lng, isShortcutType: customDisplayName != nil)
                            newTags.append(tag)
                            print("✅ 创建位置标签: \(locationName) (\(lat), \(lng))")
                            print("✅ 标签详情: type=\(tag.type.rawValue), value=\(tag.value), hasCoords=\(tag.hasCoordinates)")
                            print("✅ 坐标验证: lat=\(tag.latitude?.description ?? "nil"), lng=\(tag.longitude?.description ?? "nil")")
                        } else if TagMappingManager.shared.isLocationTagKey(tagKey) && !value.contains("@") {
                            // 如果是location标签但没有找到匹配的位置，提示用户
                            print("⚠️ 未找到位置标签: \(value)，请使用完整格式或确保该位置已存在")
                            // 创建无坐标的位置标签作为fallback
                            let tag = store.createTag(type: finalTagType, value: value, isShortcutType: customDisplayName != nil)
                            newTags.append(tag)
                        } else if TagMappingManager.shared.isLocationTagKey(tagKey) {
                            // 如果是location标签但解析失败，打印详细错误信息
                            print("❌ 位置标签解析失败: \(value)")
                            print("❌   parsed: \(parsed), locationName: '\(locationName)', lat: \(lat), lng: \(lng)")
                            // 创建无坐标的位置标签作为fallback
                            let tag = store.createTag(type: finalTagType, value: value, isShortcutType: customDisplayName != nil)
                            newTags.append(tag)
                        } else {
                            // 普通标签
                            let tag = store.createTag(type: finalTagType, value: value, isShortcutType: customDisplayName != nil)
                            newTags.append(tag)
                        }
                    } else {
                        // 普通标签 - 检查是否是快捷键类型
                        // 如果tagType来自映射查找且不同于原始token，则这是快捷键
                        let isShortcut = customDisplayName != nil || TagMappingManager.shared.tagMappings.contains { mapping in
                            mapping.key.lowercased() == tagKey.lowercased() && finalTagType.displayName == mapping.key
                        }
                        let tag = store.createTag(type: finalTagType, value: value, isShortcutType: isShortcut)
                        newTags.append(tag)
                        print("✅ 创建标签: \(finalTagType.displayName) - \(value)")
                    }
                print("🔧 标签处理完成，当前索引 i = \(i)，准备继续主循环")
            } else {
                // 检查是否是独立的 value[displayName] 格式（不需要前置标签类型）
                if token.contains("[") && token.contains("]"),
                   let bracketStart = token.firstIndex(of: "["),
                   let bracketEnd = token.firstIndex(of: "]"),
                   bracketStart < bracketEnd {
                    
                    let tagValue = String(token[..<bracketStart])
                    let displayName = String(token[token.index(after: bracketStart)..<bracketEnd])
                    
                    print("🔧 检测到独立的value[displayName]格式: value='\(tagValue)', displayName='\(displayName)'")
                    
                    // 检查是否是快捷键格式：tagValue是快捷键，displayName是类型名
                    let isShortcut = TagMappingManager.shared.tagMappings.contains { mapping in
                        mapping.key.lowercased() == tagValue.lowercased() && mapping.typeName == displayName
                    }
                    
                    let customTagType: Tag.TagType
                    if isShortcut {
                        // 快捷键格式：beef[牛肉种类] -> 使用tagValue作为type的key
                        customTagType = Tag.TagType.custom(tagValue)
                        print("🔧 独立快捷键格式: key='\(tagValue)', typeName='\(displayName)'")
                    } else {
                        // 普通value[displayName]格式 -> 使用displayName作为type的key
                        customTagType = Tag.TagType.custom(displayName)
                        TagMappingManager.shared.addMappingIfNeeded(key: displayName, typeName: displayName)
                        print("🔧 独立普通格式: key='\(displayName)', value='\(tagValue)'")
                    }
                    
                    let tag = store.createTag(type: customTagType, value: tagValue, isShortcutType: isShortcut)
                    newTags.append(tag)
                    print("✅ 创建独立自定义标签: \(displayName) - \(tagValue)")
                    
                    i += 1
                } else {
                    print("❌ token '\(token)' 不是标签类型，跳过")
                    i += 1
                }
            }
        }
        
        print("🔧 解析完成，创建了 \(newTags.count) 个标签:")
        for (index, tag) in newTags.enumerated() {
            print("  [\(index)] \(tag.type.displayName): \(tag.value)")
        }
        
        // 只有当成功解析出标签时才替换节点的所有标签
        if !newTags.isEmpty {
            print("✅ 开始替换节点标签")
            await MainActor.run {
                // 先删除所有现有标签
                let currentNode = store.nodes.first { $0.id == node.id }
                if let existingNode = currentNode {
                    print("🗑️ 删除现有的 \(existingNode.tags.count) 个标签")
                    for tag in existingNode.tags {
                        store.removeTag(from: node.id, tagId: tag.id)
                    }
                }
                
                // 添加新标签
                print("➕ 添加 \(newTags.count) 个新标签")
                for tag in newTags {
                    store.addTag(to: node.id, tag: tag)
                }
            }
            print("✅ 标签替换完成")
            return true
        } else {
            print("❌ 没有解析出任何标签，保持原有标签不变")
            return false
        }
    }
    
    private func mapTokenToTagType(_ token: String) -> Tag.TagType? {
        // 检查是否是坐标格式或其他特殊值格式，如果是则不当作标签类型
        if token.hasPrefix("@") && (token.contains("[") || token.contains(",")) {
            print("🔍 mapTokenToTagType: '\(token)' -> 跳过（坐标格式）")
            return nil
        }
        
        // 检查是否是完整的坐标格式 @lat,lng[name]
        if token.hasPrefix("@") && token.contains(",") && token.contains("[") && token.contains("]") {
            print("🔍 mapTokenToTagType: '\(token)' -> 跳过（完整坐标格式）")
            return nil
        }
        
        // 检查是否是纯数字（可能是坐标的一部分）
        if Double(token) != nil && token.contains(".") {
            print("🔍 mapTokenToTagType: '\(token)' -> 跳过（疑似坐标数字）")
            return nil
        }
        
        // 检查是否是带引号的值，如果是则不当作标签类型
        if (token.hasPrefix("\"") && token.hasSuffix("\"")) {
            print("🔍 mapTokenToTagType: '\(token)' -> 跳过（引号值格式）")
            return nil
        }
        
        // 检查是否包含方括号
        if token.contains("[") || token.contains("]") {
            // 检查是否是 tagType[displayName] 格式（标签类型+显示名格式）
            if token.contains("[") && token.contains("]") {
                // 可能是两种情况：
                // 1. tagType[displayName] - beef[牛肉类型] 
                // 2. value[displayName] - sdlf[牛肉品种]
                
                if let bracketStart = token.firstIndex(of: "["),
                   let bracketEnd = token.firstIndex(of: "]"),
                   bracketStart < bracketEnd {
                    
                    let beforeBracket = String(token[..<bracketStart])
                    let insideBracket = String(token[token.index(after: bracketStart)..<bracketEnd])
                    
                    // 检查是否是已知的标签类型映射
                    let tagManager = TagMappingManager.shared
                    
                    // 先检查映射字典，避免创建错误的映射
                    if let (typeName, tagType) = tagManager.mappingDictionary[beforeBracket.lowercased()] {
                        print("🔍 mapTokenToTagType: '\(token)' -> 找到现有映射: \(beforeBracket) -> \(typeName)")
                        return tagType
                    }
                    
                    // 如果没有现有映射，这是新的快捷键定义：beef[牛肉种类]
                    // 创建映射并返回标签类型
                    print("🔍 mapTokenToTagType: '\(token)' -> 创建新的快捷键映射: \(beforeBracket) -> \(insideBracket)")
                    tagManager.addMappingIfNeeded(key: beforeBracket, typeName: insideBracket)
                    return Tag.TagType.custom(beforeBracket)
                } else {
                    print("🔍 mapTokenToTagType: '\(token)' -> 跳过（无效的方括号格式）")
                    return nil
                }
            }
            print("🔍 mapTokenToTagType: '\(token)' -> 跳过（包含方括号）")
            return nil
        }
        
        let tagManager = TagMappingManager.shared
        print("🔍 mapTokenToTagType: 检查单独token '\(token)'")
        
        // 特殊处理beef，强制确保映射正确
        if token.lowercased() == "beef" {
            print("🔧 检测到beef token，强制重建映射...")
            tagManager.forceRebuildBeefMapping()
            print("🔧 重建后映射字典keys: \(Array(tagManager.mappingDictionary.keys))")
            if let (typeName, tagType) = tagManager.mappingDictionary["beef"] {
                print("✅ beef映射确认: beef -> \(typeName)")
                return tagType
            } else {
                print("❌ beef映射仍然不存在！这是严重错误！")
            }
        }
        
        print("🔍 当前映射字典keys: \(Array(tagManager.mappingDictionary.keys))")
        let result = tagManager.parseTokenToTagTypeWithStore(token, store: store)
        print("🔍 mapTokenToTagType: '\(token)' -> \(result?.displayName ?? "nil")")
        return result
    }
    
    // 检查是否是地图/位置标签的key
    private func isLocationTagKey(_ key: String) -> Bool {
        let locationKeys = ["loc", "location", "地点", "位置"]
        return locationKeys.contains(key.lowercased())
    }
    
    
    private func openMapForLocationSelection() {
        // 发送通知打开地图窗口并进入位置选择模式
        NotificationCenter.default.post(name: NSNotification.Name("openMapWindow"), object: nil)
        // 延迟发送位置选择模式通知，给地图窗口时间打开
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(
                name: NSNotification.Name("openMapForLocationSelection"),
                object: nil
            )
        }
    }
    
    private func executeSelectedCommand() {
        if !commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if availableCommands.indices.contains(selectedIndex) {
                let command = availableCommands[selectedIndex]
                let context = CommandContext(store: store, currentNode: node)
                Task {
                    do {
                        _ = try await command.execute(with: context)
                        await MainActor.run {
                            DispatchQueue.main.async {
                                store.objectWillChange.send()
                            }
                            dismiss()
                        }
                    } catch {
                        print("Command execution failed: \(error)")
                    }
                }
            }
        }
    }
}



// Preview temporarily disabled due to @FocusState initialization complexity
// #Preview {
//     NodeManagerView()
//         .environmentObject(NodeStore.shared)
// }