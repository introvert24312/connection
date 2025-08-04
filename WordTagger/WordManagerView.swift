import SwiftUI
import MapKit
import CoreLocation

struct WordManagerView: View {
    @EnvironmentObject private var store: WordStore
    @State private var selectedWords: Set<UUID> = []
    @State private var localSearchQuery: String = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var showingDeleteAlert = false
    @State private var sortOption: SortOption = .alphabetical
    @State private var filterOption: FilterOption = .all
    @State private var showingCommandPalette = false
    @State private var commandPaletteWord: Word?
    @State private var isSelectionMode = false
    @FocusState private var isSearchFieldFocused: Bool
    
    enum SortOption: String, CaseIterable {
        case alphabetical = "按字母排序"
        case createdDate = "按创建时间"
        case updatedDate = "按修改时间"
        case tagCount = "按标签数量"
    }
    
    enum FilterOption: String, CaseIterable {
        case all = "全部单词"
        case withTags = "有标签的"
        case withoutTags = "无标签的"
        case withMeaning = "有释义的"
        case withoutMeaning = "无释义的"
    }
    
    var filteredAndSortedWords: [Word] {
        var words = store.words
        
        // 如果有搜索查询，优先显示搜索结果，忽略selectedTag过滤
        if !localSearchQuery.isEmpty {
            words = words.filter { word in
                word.text.localizedCaseInsensitiveContains(localSearchQuery) ||
                (word.meaning?.localizedCaseInsensitiveContains(localSearchQuery) ?? false) ||
                (word.phonetic?.localizedCaseInsensitiveContains(localSearchQuery) ?? false) ||
                word.tags.contains { $0.value.localizedCaseInsensitiveContains(localSearchQuery) }
            }
        } else if let selectedTag = store.selectedTag {
            // 只在没有搜索查询时应用selectedTag过滤
            words = words.filter { $0.hasTag(selectedTag) }
        }
        
        // 应用过滤器
        switch filterOption {
        case .all:
            break
        case .withTags:
            words = words.filter { !$0.tags.isEmpty }
        case .withoutTags:
            words = words.filter { $0.tags.isEmpty }
        case .withMeaning:
            words = words.filter { $0.meaning != nil && !$0.meaning!.isEmpty }
        case .withoutMeaning:
            words = words.filter { $0.meaning == nil || $0.meaning!.isEmpty }
        }
        
        // 应用排序
        switch sortOption {
        case .alphabetical:
            words.sort { $0.text.localizedCompare($1.text) == .orderedAscending }
        case .createdDate:
            words.sort { $0.createdAt > $1.createdAt }
        case .updatedDate:
            words.sort { $0.updatedAt > $1.updatedAt }
        case .tagCount:
            words.sort { $0.tags.count > $1.tags.count }
        }
        
        return words
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("单词管理")
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
                    
                    TextField("搜索单词、释义、音标或标签...", text: $localSearchQuery)
                        .textFieldStyle(.plain)
                        .frame(width: 200)
                        .focused($isSearchFieldFocused)
                        .onChange(of: localSearchQuery) { oldValue, newValue in
                            print("🔤 WordManagerView: localSearchQuery changed from '\(oldValue)' to '\(newValue)'")
                            
                            // 取消之前的搜索任务
                            searchTask?.cancel()
                            
                            // 立即更新store的搜索查询，让Store的防抖机制处理重复请求
                            print("🔄 WordManagerView: Immediately updating store.searchQuery to '\(newValue)'")
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
                        selectedWords.removeAll()
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
                Text("选中 \(selectedWords.count) / \(filteredAndSortedWords.count) 个单词")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 全选/取消全选
                Button(action: {
                    if selectedWords.count == filteredAndSortedWords.count {
                        selectedWords.removeAll()
                    } else {
                        selectedWords = Set(filteredAndSortedWords.map { $0.id })
                    }
                }) {
                    Text(selectedWords.count == filteredAndSortedWords.count ? "取消全选" : "全选")
                        .font(.caption)
                }
                .disabled(filteredAndSortedWords.isEmpty)
                
                // 批量删除按钮
                Button(action: {
                    showingDeleteAlert = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("删除选中")
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                .disabled(selectedWords.isEmpty)
                .alert("确认删除", isPresented: $showingDeleteAlert) {
                    Button("取消", role: .cancel) { }
                    Button("删除", role: .destructive) {
                        batchDeleteWords()
                    }
                } message: {
                    Text("确定要删除选中的 \(selectedWords.count) 个单词吗？此操作不可撤销。")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            }
            
            // 单词列表
            if filteredAndSortedWords.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
                    Group {
                        if localSearchQuery.isEmpty {
                            if store.selectedTag != nil {
                                Text("当前标签下暂无单词")
                            } else {
                                Text("暂无单词")
                            }
                        } else {
                            Text("未找到匹配 \"\(localSearchQuery)\" 的单词")
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
                        ForEach(filteredAndSortedWords, id: \.id) { word in
                            WordManagerRowView(
                                word: word,
                                isSelected: selectedWords.contains(word.id),
                                isSelectionMode: isSelectionMode,
                                onToggleSelection: {
                                    if selectedWords.contains(word.id) {
                                        selectedWords.remove(word.id)
                                    } else {
                                        selectedWords.insert(word.id)
                                    }
                                },
                                onWordEdit: { word in
                                    commandPaletteWord = word
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
        .navigationTitle("单词管理")
        .sheet(item: Binding<Word?>(
            get: { showingCommandPalette ? commandPaletteWord : nil },
            set: { newValue in
                if newValue == nil {
                    showingCommandPalette = false
                    commandPaletteWord = nil
                }
            }
        )) { word in
            TagEditCommandView(word: word)
                .environmentObject(store)
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }
    
    private func batchDeleteWords() {
        for wordId in selectedWords {
            store.deleteWord(wordId)
        }
        selectedWords.removeAll()
    }
}

// MARK: - Word Manager Row View

struct WordManagerRowView: View {
    let word: Word
    let isSelected: Bool
    let isSelectionMode: Bool
    let onToggleSelection: () -> Void
    let onWordEdit: (Word) -> Void
    
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
            
            // 单词信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    // 单词文本
                    Text(word.text)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    // 音标
                    if let phonetic = word.phonetic {
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
                    if !word.tags.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "tag.fill")
                                .font(.caption2)
                            Text("\(word.tags.count)")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                // 释义
                if let meaning = word.meaning, !meaning.isEmpty {
                    Text(meaning)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // 标签
                if !word.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(word.tags.prefix(5), id: \.id) { tag in
                                Group {
                                    if tag.type == .location && tag.hasCoordinates {
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
                            
                            if word.tags.count > 5 {
                                Text("+\(word.tags.count - 5)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // 时间信息
                HStack(spacing: 12) {
                    Text("创建: \(word.createdAt.timeAgoDisplay())")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if word.updatedAt > word.createdAt {
                        Text("修改: \(word.updatedAt.timeAgoDisplay())")
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
                onWordEdit(word)
            }
        }
        .allowsHitTesting(true)
    }
    
    private func previewLocation(tag: Tag) {
        guard let latitude = tag.latitude,
              let longitude = tag.longitude else { return }
        
        print("🎯 Previewing location: \(tag.displayName) at (\(latitude), \(longitude))")
        
        // 打开地图窗口
        NotificationCenter.default.post(name: .openMapWindow, object: nil)
        
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
    let word: Word
    @EnvironmentObject private var store: WordStore
    @Environment(\.dismiss) private var dismiss
    @State private var commandText: String = ""
    @State private var selectedIndex: Int = 0
    @State private var showingLocationPicker = false
    @StateObject private var commandParser = CommandParser.shared
    @State private var showingDuplicateAlert = false
    
    private var initialCommand: String {
        // 生成当前单词的完整命令
        let tagCommands = word.tags.map { tag in
            // 对于location标签且有坐标信息，生成完整的loc命令
            if tag.type == .location && tag.hasCoordinates,
               let lat = tag.latitude, let lng = tag.longitude {
                return "loc @\(lat),\(lng)[\(tag.value)]"
            } else if tag.type == .location {
                // 对于没有坐标的location标签，提供提示格式让用户补充坐标
                return "loc @需要添加坐标[\(tag.value)]"
            } else {
                return "\(tag.type.rawValue) \(tag.value)"
            }
        }.joined(separator: " ")
        
        if tagCommands.isEmpty {
            return "\(word.text) "
        } else {
            return "\(word.text) \(tagCommands)"
        }
    }
    
    @State private var availableCommands: [Command] = []
    
    @MainActor
    private func updateAvailableCommands() {
        let context = CommandContext(store: store, currentWord: word)
        Task {
            availableCommands = await commandParser.parse(commandText, context: context)
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // 标题栏
            HStack {
                Text("编辑单词: \(word.text)")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("完成") {
                    executeCommand()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
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
                Text("当前标签 (\(word.tags.count)个):")
                    .font(.headline)
                
                if word.tags.isEmpty {
                    Text("暂无标签")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(word.tags, id: \.id) { tag in
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
            commandText = initialCommand
            updateAvailableCommands()
        }
        .onKeyPress(.return) {
            executeCommand()
            return .handled
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
                    print("🎯 WordManager: Using location with name: \(locationName)")
                } else {
                    locationCommand = "loc @\(latitude),\(longitude)[]"
                    print("🎯 WordManager: Using coordinates only, user needs to fill name")
                }
                
                if commandText.isEmpty || commandText == initialCommand {
                    commandText = "\(word.text) \(locationCommand)"
                } else {
                    commandText += " \(locationCommand)"
                }
            }
        }
        .alert("重复检测", isPresented: $showingDuplicateAlert) {
            Button("确定") { }
        } message: {
            if let alert = store.duplicateWordAlert {
                Text(alert.message)
            }
        }
        .onReceive(store.$duplicateWordAlert) { alert in
            if alert != nil {
                showingDuplicateAlert = true
                // 延迟清除alert以避免立即触发下一次
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    store.duplicateWordAlert = nil
                }
            }
        }
    }
    
    private func executeCommand() {
        let trimmedText = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { 
            dismiss()
            return 
        }
        
        Task {
            // 使用新的批量标签解析器
            let success = await parseBatchTagCommand(trimmedText)
            
            await MainActor.run {
                if success {
                    store.objectWillChange.send()
                    print("✅ 标签批量更新成功")
                } else {
                    print("❌ 标签批量更新失败")
                }
                dismiss()
            }
        }
    }
    
    private func parseBatchTagCommand(_ input: String) async -> Bool {
        // 分词：按空格分割
        let tokens = input.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        guard tokens.count >= 2 else { return false }
        
        // 第一个token应该是单词名，跳过
        let wordText = tokens[0]
        guard wordText == word.text else { 
            print("❌ 单词名不匹配: \(wordText) vs \(word.text)")
            return false 
        }
        
        // 解析剩余的标签token
        var newTags: [Tag] = []
        var i = 1
        
        while i < tokens.count {
            let token = tokens[i]
            
            // 检查是否是标签类型关键词
            if let tagType = mapTokenToTagType(token) {
                i += 1
                
                // 收集这个标签类型的值
                var values: [String] = []
                while i < tokens.count {
                    let nextToken = tokens[i]
                    
                    // 如果遇到下一个标签类型，停止
                    if mapTokenToTagType(nextToken) != nil {
                        break
                    }
                    
                    values.append(nextToken)
                    i += 1
                }
                
                // 创建标签
                if !values.isEmpty {
                    let value = values.joined(separator: " ")
                    
                    // 检查是否是location标签
                    if tagType == .location {
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
                            // 提取坐标部分 @纬度,经度
                            if let atIndex = value.firstIndex(of: "@"),
                               let bracketIndex = value.firstIndex(of: "[") {
                                let coordString = String(value[value.index(after: atIndex)..<bracketIndex])
                                let coords = coordString.split(separator: ",")
                                
                                if coords.count == 2,
                                   let latitude = Double(coords[0]),
                                   let longitude = Double(coords[1]) {
                                    lat = latitude
                                    lng = longitude
                                    
                                    // 提取名称部分 [名称]
                                    if let startBracket = value.firstIndex(of: "["),
                                       let endBracket = value.firstIndex(of: "]"),
                                       startBracket < endBracket {
                                        locationName = String(value[value.index(after: startBracket)..<endBracket])
                                        parsed = true
                                    }
                                }
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
                            let tag = store.createTag(type: tagType, value: locationName, latitude: lat, longitude: lng)
                            newTags.append(tag)
                            print("✅ 创建位置标签: \(locationName) (\(lat), \(lng))")
                            print("✅ 标签详情: type=\(tag.type.rawValue), value=\(tag.value), hasCoords=\(tag.hasCoordinates)")
                        } else if tagType == .location && !value.contains("@") {
                            // 如果是location标签但没有找到匹配的位置，提示用户
                            print("⚠️ 未找到位置标签: \(value)，请使用完整格式或确保该位置已存在")
                            // 创建无坐标的位置标签作为fallback
                            let tag = store.createTag(type: tagType, value: value)
                            newTags.append(tag)
                        } else {
                            // 其他location标签处理失败的情况
                            let tag = store.createTag(type: tagType, value: value)
                            newTags.append(tag)
                        }
                    } else {
                        // 普通标签
                        let tag = store.createTag(type: tagType, value: value)
                        newTags.append(tag)
                        print("✅ 创建标签: \(tagType.displayName) - \(value)")
                    }
                }
            } else {
                i += 1
            }
        }
        
        // 替换单词的所有标签
        await MainActor.run {
            // 先删除所有现有标签
            let currentWord = store.words.first { $0.id == word.id }
            if let existingWord = currentWord {
                for tag in existingWord.tags {
                    store.removeTag(from: word.id, tagId: tag.id)
                }
            }
            
            // 添加新标签
            for tag in newTags {
                store.addTag(to: word.id, tag: tag)
            }
        }
        
        return !newTags.isEmpty
    }
    
    private func mapTokenToTagType(_ token: String) -> Tag.TagType? {
        let tagManager = TagMappingManager.shared
        return tagManager.parseTokenToTagTypeWithStore(token, store: store)
    }
    
    private func openMapForLocationSelection() {
        // 发送通知打开地图窗口并进入位置选择模式
        NotificationCenter.default.post(name: .openMapWindow, object: nil)
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
                let context = CommandContext(store: store, currentWord: word)
                Task {
                    do {
                        _ = try await command.execute(with: context)
                        await MainActor.run {
                            store.objectWillChange.send()
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



#Preview {
    WordManagerView()
        .environmentObject(WordStore.shared)
}