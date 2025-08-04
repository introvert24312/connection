import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - Tag Mapping Manager

class TagMappingManager: ObservableObject {
    @Published var tagMappings: [TagMapping] = []
    
    static let shared = TagMappingManager()
    
    private let userDefaultsKey = "tagMappings"
    
    private init() {
        loadTagMappings()
    }
    
    // 获取字典格式的映射（用于快速查找）
    var mappingDictionary: [String: (String, Tag.TagType)] {
        var dict: [String: (String, Tag.TagType)] = [:]
        for mapping in tagMappings {
            dict[mapping.key] = (mapping.typeName, mapping.tagType)
        }
        return dict
    }
    
    // 添加或更新标签映射
    func saveMapping(_ mapping: TagMapping) {
        if let index = tagMappings.firstIndex(where: { $0.id == mapping.id }) {
            tagMappings[index] = mapping
        } else {
            tagMappings.append(mapping)
        }
        saveToUserDefaults()
    }
    
    // 动态添加缺失的标签映射
    func addMappingIfNeeded(key: String, typeName: String) {
        // 检查是否已存在该映射
        if !tagMappings.contains(where: { $0.key == key.lowercased() }) {
            let newMapping = TagMapping(key: key.lowercased(), typeName: typeName)
            tagMappings.append(newMapping)
            saveToUserDefaults()
            print("🔄 自动添加标签映射: \(key) -> \(typeName)")
        }
    }
    
    // 智能解析token为TagType，支持动态创建
    func parseTokenToTagType(_ token: String, store: WordStore? = nil) -> Tag.TagType? {
        let lowerToken = token.lowercased()
        
        // 1. 首先检查TagMappingManager中的映射
        if let (typeName, tagType) = mappingDictionary[lowerToken] {
            print("✅ 找到标签映射: \(lowerToken) -> \(typeName) (\(tagType))")
            return tagType
        }
        
        // 2. 根据原始值匹配预定义类型
        switch lowerToken {
        case "memory": return .memory
        case "location", "loc": return .location  // 支持 location 和 loc 两种写法
        case "root": return .root
        case "shape": return .shape
        case "sound": return .sound
        default: break
        }
        
        // 3. 根据显示名称匹配预定义类型
        for tagType in Tag.TagType.allCases {
            if tagType.displayName == token || tagType.rawValue == lowerToken {
                return tagType
            }
        }
        
        // 4. 检查已存在的自定义标签类型（如果提供了store）
        if let store = store {
            let allExistingTags = store.allTags
            for existingTag in allExistingTags {
                if case .custom(let customName) = existingTag.type {
                    // 检查是否匹配自定义标签的名称或token
                    if customName.lowercased() == lowerToken || 
                       existingTag.type.displayName.lowercased() == lowerToken {
                        print("✅ 找到已有自定义标签类型: \(lowerToken) -> \(customName)")
                        return existingTag.type
                    }
                }
            }
        }
        
        // 5. 创建新的自定义标签类型并自动添加到映射管理器
        print("🆕 创建新的自定义标签类型: \(token)")
        let customTagType = Tag.TagType.custom(token)
        
        // 自动添加到标签映射管理器
        addMappingIfNeeded(key: lowerToken, typeName: token)
        
        return customTagType
    }
    
    // 删除标签映射
    func deleteMapping(withId id: UUID) {
        tagMappings.removeAll { $0.id == id }
        saveToUserDefaults()
    }
    
    // 重置为默认映射
    func resetToDefaults() {
        tagMappings = [
            TagMapping(key: "root", typeName: "词根"),
            TagMapping(key: "memory", typeName: "记忆"),
            TagMapping(key: "loc", typeName: "地点"),
            TagMapping(key: "time", typeName: "时间"),
            TagMapping(key: "shape", typeName: "形近"),
            TagMapping(key: "sound", typeName: "音近"),
            TagMapping(key: "sub", typeName: "子类")
        ]
        saveToUserDefaults()
    }
    
    // 保存到UserDefaults
    private func saveToUserDefaults() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(tagMappings) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    // 从UserDefaults加载
    private func loadTagMappings() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let savedMappings = try? decoder.decode([TagMapping].self, from: data) {
            tagMappings = savedMappings
            
            // 迁移：确保包含新的默认映射
            migrateToLatestMappings()
        } else {
            // 如果没有保存的数据，使用默认值
            resetToDefaults()
        }
    }
    
    // 迁移到最新的映射（确保新添加的默认映射被包含）
    private func migrateToLatestMappings() {
        let defaultMappings = [
            ("root", "词根"),
            ("memory", "记忆"),
            ("loc", "地点"),
            ("time", "时间"),
            ("shape", "形近"),
            ("sound", "音近"),
            ("sub", "子类")
        ]
        
        var hasChanges = false
        
        for (key, typeName) in defaultMappings {
            if !tagMappings.contains(where: { $0.key == key }) {
                let newMapping = TagMapping(key: key, typeName: typeName)
                tagMappings.append(newMapping)
                hasChanges = true
                print("🔄 迁移添加标签映射: \(key) -> \(typeName)")
            }
        }
        
        if hasChanges {
            saveToUserDefaults()
        }
    }
}

struct TagMapping: Identifiable, Codable {
    let id: UUID
    let key: String
    let typeName: String
    
    init(id: UUID = UUID(), key: String, typeName: String) {
        self.id = id
        self.key = key
        self.typeName = typeName
    }
    
    // 转换为 Tag.TagType
    var tagType: Tag.TagType {
        switch typeName {
        case "记忆": return .memory
        case "地点": return .location
        case "词根": return .root
        case "形近": return .shape
        case "音近": return .sound
        default: return .custom(typeName)
        }
    }
}

// MARK: - Quick Add Sheet View

struct QuickAddSheetView: View {
    @EnvironmentObject private var store: WordStore
    @StateObject private var tagManager = TagMappingManager.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var inputText: String = ""
    @State private var suggestions: [String] = []
    @State private var selectedSuggestionIndex: Int = -1
    @FocusState private var isInputFocused: Bool
    @State private var isWaitingForLocationSelection = false
    @State private var showingDuplicateAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索输入框 - 采用CommandPalette样式
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue)
                
                TextField("输入: 单词 root 词根内容 memory 记忆内容...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isInputFocused)
                    .onChange(of: inputText) { _, newValue in updateSuggestions(for: newValue) }
                    .onKeyPress(.upArrow) {
                        if !suggestions.isEmpty {
                            selectedSuggestionIndex = max(0, selectedSuggestionIndex - 1)
                        }
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        if !suggestions.isEmpty {
                            selectedSuggestionIndex = min(suggestions.count - 1, selectedSuggestionIndex + 1)
                        }
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        if selectedSuggestionIndex >= 0 && selectedSuggestionIndex < suggestions.count {
                            selectSuggestion(suggestions[selectedSuggestionIndex])
                        }
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        presentationMode.wrappedValue.dismiss()
                        return .handled
                    }
                
                Button(action: openMapForLocationSelection) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("选择地点位置 (⌘P)")
                .keyboardShortcut("p", modifiers: .command)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 建议列表 - 采用CommandPalette的NewCommandRowView样式
            if !suggestions.isEmpty {
                ScrollViewReader { proxy in
                    List(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                        QuickAddSuggestionRow(
                            suggestion: suggestion,
                            tagTypeName: tagManager.mappingDictionary[suggestion]?.0 ?? "自定义",
                            isSelected: index == selectedSuggestionIndex
                        ) {
                            selectSuggestion(suggestion)
                        }
                        .id(index)
                    }
                    .listStyle(.plain)
                    .frame(height: min(CGFloat(suggestions.count) * 44, 300))
                    .onChange(of: selectedSuggestionIndex) { _, newIndex in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
            
            if suggestions.isEmpty && !inputText.isEmpty {
                VStack {
                    Text("输入标签快捷键获得建议")
                        .foregroundColor(.secondary)
                        .padding()
                }
                .frame(height: 100)
            }
            
            // 底部帮助信息
            VStack(alignment: .leading, spacing: 8) {
                Text("💡 使用方法:")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("输入格式: 单词 快捷键 内容")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("例如: apple root 苹果 memory 红苹果")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Text("快捷键: ↑↓选择建议 • Tab选择 • ⌘+R提交 • Esc关闭")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 600)
        .navigationTitle("快速添加单词")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("添加") {
                    processInput()
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut("r", modifiers: .command)
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
        .onAppear {
            // 自动聚焦到输入框
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
            
            // 监听位置选择通知
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("locationSelected"),
                object: nil,
                queue: .main
            ) { notification in
                if let locationData = notification.object as? [String: Any],
                   let latitude = locationData["latitude"] as? Double,
                   let longitude = locationData["longitude"] as? Double {
                    
                    // 如果有地名信息，使用地名；否则让用户自己输入
                    if let locationName = locationData["name"] as? String {
                        let locationCommand = "@\(latitude),\(longitude)[\(locationName)]"
                        insertLocationIntoInput(locationCommand)
                        print("🎯 QuickAdd: Using location with name: \(locationName)")
                    } else {
                        // 只使用坐标，让用户自己输入地名
                        let locationCommand = "@\(latitude),\(longitude)[]"
                        insertLocationIntoInput(locationCommand)
                        print("🎯 QuickAdd: Using coordinates only, user needs to fill name")
                    }
                } else if let locationName = notification.object as? String {
                    // 向后兼容旧格式
                    insertLocationIntoInput("location \(locationName)")
                }
            }
        }
        // TODO: 修复onKeyPress API调用
        // .onKeyPress(KeyEquivalent("p"), modifiers: .command) { _ in
        //     if isInputFocused {
        //         openMapForLocationSelection()
        //         return .handled
        //     }
        //     return .ignored
        // }
    }
    
    private func updateSuggestions(for input: String) {
        let words = input.split(separator: " ")
        guard let lastWord = words.last?.lowercased() else { 
            suggestions = []
            selectedSuggestionIndex = -1
            return 
        }
        
        let matchingSuggestions = tagManager.mappingDictionary.keys.filter { key in 
            key.lowercased().hasPrefix(String(lastWord)) && key.lowercased() != String(lastWord) 
        }.sorted()
        
        suggestions = matchingSuggestions
        selectedSuggestionIndex = matchingSuggestions.isEmpty ? -1 : 0
    }
    
    private func selectSuggestion(_ suggestion: String) {
        let words = inputText.split(separator: " ").map(String.init)
        if !words.isEmpty { 
            let newWords = words.dropLast() + [suggestion]
            inputText = newWords.joined(separator: " ") + " " 
        } else { 
            inputText = suggestion + " " 
        }
        suggestions = []
        selectedSuggestionIndex = -1
    }
    
    private func processInput() {
        let components = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        
        guard !components.isEmpty else { return }
        
        let wordText = components[0]
        var tags: [Tag] = []
        var i = 1
        
        while i < components.count {
            let tagKey = components[i]
            if let tagType = tagManager.parseTokenToTagType(tagKey, store: store) {
                if i + 1 < components.count { 
                    let content = components[i + 1]
                    
                    // 检查是否是location标签
                    if tagType == .location {
                        var locationName: String = ""
                        var lat: Double = 0
                        var lng: Double = 0
                        var parsed = false
                        
                        // 格式1: 名称@纬度,经度 (如: 天马广场@37.45,121.61)
                        if content.contains("@") && !content.hasPrefix("@") {
                            let components = content.split(separator: "@", maxSplits: 1)
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
                        else if content.hasPrefix("@") && content.contains("[") && content.contains("]") {
                            // 提取坐标部分 @纬度,经度
                            if let atIndex = content.firstIndex(of: "@"),
                               let bracketIndex = content.firstIndex(of: "[") {
                                let coordString = String(content[content.index(after: atIndex)..<bracketIndex])
                                let coords = coordString.split(separator: ",")
                                
                                if coords.count == 2,
                                   let latitude = Double(coords[0]),
                                   let longitude = Double(coords[1]) {
                                    lat = latitude
                                    lng = longitude
                                    
                                    // 提取名称部分 [名称]
                                    if let startBracket = content.firstIndex(of: "["),
                                       let endBracket = content.firstIndex(of: "]"),
                                       startBracket < endBracket {
                                        locationName = String(content[content.index(after: startBracket)..<endBracket])
                                        parsed = true
                                    }
                                }
                            }
                        }
                        // 格式3: 简单地名引用 (如: 武功山) - 新增功能
                        else if !content.contains("@") && !content.contains("[") && !content.contains("]") {
                            // 尝试在已有的位置标签中查找匹配的地名
                            if let existingTag = store.findLocationTagByName(content) {
                                locationName = existingTag.value
                                if let existingLat = existingTag.latitude, let existingLng = existingTag.longitude {
                                    lat = existingLat
                                    lng = existingLng
                                    parsed = true
                                    print("🎯 QuickAdd: 找到已有位置标签: \(locationName) (\(lat), \(lng))")
                                }
                            }
                        }
                        
                        if parsed && !locationName.isEmpty {
                            let tag = store.createTag(type: tagType, value: locationName, latitude: lat, longitude: lng)
                            tags.append(tag)
                        } else if !content.contains("@") {
                            // 如果是location标签但没有找到匹配的位置，提示用户
                            print("⚠️ QuickAdd: 未找到位置标签: \(content)，请使用完整格式或确保该位置已存在")
                            // 创建无坐标的位置标签作为fallback
                            let tag = Tag(type: tagType, value: content)
                            tags.append(tag)
                        } else {
                            // 如果解析失败，创建普通标签
                            let tag = Tag(type: tagType, value: content)
                            tags.append(tag)
                        }
                    } else {
                        // 普通标签
                        let tag = Tag(type: tagType, value: content)
                        tags.append(tag)
                    }
                    i += 2 
                } else { 
                    i += 1 
                }
            } else { 
                i += 1 
            }
        }
        
        let newWord = Word(text: wordText, tags: tags)
        let success = store.addWord(newWord)
        inputText = ""
        if success {
            presentationMode.wrappedValue.dismiss()
        }
        // 如果不成功，保持窗口打开让用户看到警告
    }
    
    private func openMapForLocationSelection() {
        print("📍 QuickAddSheetView: Opening map for location selection...")
        isWaitingForLocationSelection = true
        
        // 打开地图窗口
        print("📍 QuickAddSheetView: Posting openMapWindow notification")
        NotificationCenter.default.post(name: .openMapWindow, object: nil)
        
        // 设置为位置选择模式
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("📍 QuickAddSheetView: About to post openMapForLocationSelection notification")
            NotificationCenter.default.post(name: NSNotification.Name("openMapForLocationSelection"), object: nil)
            print("📍 QuickAddSheetView: Posted openMapForLocationSelection notification")
        }
    }
    
    private func insertLocationIntoInput(_ locationCommand: String) {
        print("Inserting location into input: \(locationCommand)")
        
        // 在当前光标位置插入 "loc 坐标格式 "，用户需要在[]中填入地名
        let locationText = "loc \(locationCommand) "
        inputText += locationText
        isWaitingForLocationSelection = false
        
        print("Input text updated to: \(inputText)")
        
        // 重新聚焦到输入框
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isInputFocused = true
        }
    }
}

// MARK: - Quick Add Suggestion Row

private struct QuickAddSuggestionRow: View {
    let suggestion: String
    let tagTypeName: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "tag.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("标签快捷键")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Type badge
                Text(tagTypeName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.2))
                    )
                    .foregroundColor(.blue)
                
                if isSelected {
                    Image(systemName: "return")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.15) : Color.clear)
        )
    }
}

// MARK: - Quick Add View

struct QuickAddView: View {
    @EnvironmentObject private var store: WordStore
    @StateObject private var tagManager = TagMappingManager.shared
    @State private var inputText: String = ""
    @State private var suggestions: [String] = []
    @State private var selectedSuggestionIndex: Int = -1
    @State private var showingDuplicateAlert = false
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { onDismiss() }
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "plus.circle.fill").foregroundColor(.blue).font(.title2)
                        TextField("输入: 单词 root 词根内容 memory 记忆内容...", text: $inputText)
                            .textFieldStyle(.plain).font(.system(size: 16, weight: .medium))
                            .onSubmit { processInput() }
                            .onChange(of: inputText) { _, newValue in updateSuggestions(for: newValue) }
                        
                        Button(action: openMapForLocationSelection) {
                            Image(systemName: "location.fill")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("选择地点位置 (⌘P)")
                    }.padding(.horizontal, 16).padding(.vertical, 12)
                }.background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial).shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8))
                
                if !suggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                            HStack {
                                Image(systemName: "tag.fill").foregroundColor(.blue).font(.caption)
                                Text(suggestion).font(.system(size: 14, weight: .medium))
                                Spacer()
                                Text(tagManager.mappingDictionary[suggestion]?.0 ?? "自定义").font(.caption).foregroundColor(.secondary)
                            }.padding(.horizontal, 16).padding(.vertical, 8)
                            .background(selectedSuggestionIndex == index ? Color.blue.opacity(0.1) : Color.clear)
                            .onTapGesture { selectSuggestion(suggestion) }
                        }
                    }.background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)).padding(.top, 8)
                }
                
                HStack {
                    Text("💡 格式: 单词 标签1 内容1 标签2 内容2...").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("⌘+I").font(.caption).foregroundColor(.secondary)
                }.padding(.top, 12)
            }.padding(20).frame(maxWidth: 600)
        }
        .onKeyPress(.escape) { onDismiss(); return .handled }
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
        .onAppear {
            // 监听位置选择通知
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("locationSelected"),
                object: nil,
                queue: .main
            ) { notification in
                if let locationData = notification.object as? [String: Any],
                   let latitude = locationData["latitude"] as? Double,
                   let longitude = locationData["longitude"] as? Double {
                    // 只使用坐标，让用户自己输入地名
                    let locationCommand = "loc @\(latitude),\(longitude)[] "
                    inputText += locationCommand
                }
            }
        }
    }
    
    private func openMapForLocationSelection() {
        print("📍 QuickAddView: Opening map for location selection...")
        
        // 打开地图窗口
        NotificationCenter.default.post(name: .openMapWindow, object: nil)
        
        // 设置为位置选择模式
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(name: NSNotification.Name("openMapForLocationSelection"), object: nil)
        }
    }
    
    private func updateSuggestions(for input: String) {
        let words = input.split(separator: " ")
        guard let lastWord = words.last?.lowercased() else { suggestions = []; selectedSuggestionIndex = -1; return }
        let matchingSuggestions = tagManager.mappingDictionary.keys.filter { key in key.lowercased().hasPrefix(String(lastWord)) && key.lowercased() != String(lastWord) }.sorted()
        suggestions = matchingSuggestions; selectedSuggestionIndex = matchingSuggestions.isEmpty ? -1 : 0
    }
    
    private func selectSuggestion(_ suggestion: String) {
        let words = inputText.split(separator: " ").map(String.init)
        if !words.isEmpty { 
            let newWords = words.dropLast() + [suggestion]
            inputText = newWords.joined(separator: " ") + " " 
        } else { 
            inputText = suggestion + " " 
        }
        suggestions = []
        selectedSuggestionIndex = -1
    }
    
    private func processInput() {
        let components = inputText.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return }
        let wordText = components[0]
        var tags: [Tag] = []
        var i = 1
        
        while i < components.count {
            let tagKey = components[i]
            if let tagType = tagManager.parseTokenToTagType(tagKey, store: store) {
                if i + 1 < components.count {
                    let content = components[i + 1]
                    
                    // 检查是否是location标签且包含坐标信息
                    if tagType == .location && content.contains("@") {
                        var locationName: String = ""
                        var lat: Double = 0
                        var lng: Double = 0
                        var parsed = false
                        
                        // 格式1: 名称@纬度,经度 (如: 天马广场@37.45,121.61)
                        if content.contains("@") && !content.hasPrefix("@") {
                            let components = content.split(separator: "@", maxSplits: 1)
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
                        else if content.hasPrefix("@") && content.contains("[") && content.contains("]") {
                            // 提取坐标部分 @纬度,经度
                            if let atIndex = content.firstIndex(of: "@"),
                               let bracketIndex = content.firstIndex(of: "[") {
                                let coordString = String(content[content.index(after: atIndex)..<bracketIndex])
                                let coords = coordString.split(separator: ",")
                                
                                if coords.count == 2,
                                   let latitude = Double(coords[0]),
                                   let longitude = Double(coords[1]) {
                                    lat = latitude
                                    lng = longitude
                                    
                                    // 提取名称部分 [名称]
                                    if let startBracket = content.firstIndex(of: "["),
                                       let endBracket = content.firstIndex(of: "]"),
                                       startBracket < endBracket {
                                        locationName = String(content[content.index(after: startBracket)..<endBracket])
                                        parsed = true
                                    }
                                }
                            }
                        }
                        
                        if parsed && !locationName.isEmpty {
                            let tag = store.createTag(type: tagType, value: locationName, latitude: lat, longitude: lng)
                            tags.append(tag)
                        } else {
                            // 如果解析失败，创建普通标签
                            let tag = Tag(type: tagType, value: content)
                            tags.append(tag)
                        }
                    } else {
                        // 普通标签
                        let tag = Tag(type: tagType, value: content)
                        tags.append(tag)
                    }
                    i += 2
                } else {
                    i += 1
                }
            } else {
                i += 1
            }
        }
        
        let newWord = Word(text: wordText, tags: tags)
        let success = store.addWord(newWord)
        inputText = ""
        if success {
            onDismiss()
        }
        // 如果不成功，保持窗口打开让用户看到警告
    }
}

// MARK: - Quick Search View

struct QuickSearchView: View {
    @EnvironmentObject private var store: WordStore
    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0
    let onDismiss: () -> Void
    let onWordSelected: (Word) -> Void
    
    private var filteredWords: [Word] {
        if searchText.isEmpty { return Array(store.words.prefix(10)) }
        else { return store.words.filter { word in
            word.text.localizedCaseInsensitiveContains(searchText) ||
            word.meaning?.localizedCaseInsensitiveContains(searchText) == true ||
            word.tags.contains { tag in tag.value.localizedCaseInsensitiveContains(searchText) }
        }}
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { onDismiss() }
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.blue).font(.title2)
                    TextField("搜索单词、含义或标签...", text: $searchText)
                        .textFieldStyle(.plain).font(.system(size: 16, weight: .medium))
                        .onSubmit { selectCurrentWord() }
                }.padding(.horizontal, 16).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial).shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8))
                
                if !filteredWords.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredWords.enumerated()), id: \.element.id) { index, word in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(word.text).font(.system(size: 16, weight: .semibold)).foregroundColor(.primary)
                                        Spacer()
                                        HStack(spacing: 4) {
                                            ForEach(word.tags.prefix(3), id: \.id) { tag in
                                                Text(tag.displayName).font(.caption)
                                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.from(tagType: tag.type).opacity(0.2)))
                                                    .foregroundColor(Color.from(tagType: tag.type))
                                            }
                                            if word.tags.count > 3 { Text("+\(word.tags.count - 3)").font(.caption).foregroundColor(.secondary) }
                                        }
                                    }
                                    if let meaning = word.meaning, !meaning.isEmpty {
                                        Text(meaning).font(.caption).foregroundColor(.secondary).lineLimit(2)
                                    }
                                }.padding(.horizontal, 16).padding(.vertical, 10)
                                .onTapGesture { onWordSelected(word); onDismiss() }
                                .background(index == selectedIndex ? Color.blue.opacity(0.1) : Color.clear)
                            }
                        }
                    }.background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                    .frame(maxHeight: 400).padding(.top, 8)
                }
                
                HStack {
                    Text("💡 输入关键词搜索单词").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("⌘+F").font(.caption).foregroundColor(.secondary)
                }.padding(.top, 12)
            }.padding(20).frame(maxWidth: 600)
        }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .onChange(of: filteredWords) { _, _ in selectedIndex = 0 }
    }
    
    private func selectCurrentWord() {
        guard selectedIndex < filteredWords.count else { return }
        let selectedWord = filteredWords[selectedIndex]; onWordSelected(selectedWord); onDismiss()
    }
}


// MARK: - Geographic Data

struct GeographicData {
    static let commonLocations: [CommonLocation] = [
        CommonLocation(name: "北京", coordinate: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)),
        CommonLocation(name: "上海", coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)),
        CommonLocation(name: "纽约", coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)),
        CommonLocation(name: "伦敦", coordinate: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)),
        CommonLocation(name: "东京", coordinate: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)),
        CommonLocation(name: "故宫", coordinate: CLLocationCoordinate2D(latitude: 39.9163, longitude: 116.3972)),
        CommonLocation(name: "西湖", coordinate: CLLocationCoordinate2D(latitude: 30.2489, longitude: 120.1292)),
        CommonLocation(name: "埃菲尔铁塔", coordinate: CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945)),
        CommonLocation(name: "清华大学", coordinate: CLLocationCoordinate2D(latitude: 40.0031, longitude: 116.3262)),
        CommonLocation(name: "哈佛大学", coordinate: CLLocationCoordinate2D(latitude: 42.3770, longitude: -71.1167))
    ]
    
    static func searchLocations(query: String) -> [CommonLocation] {
        guard !query.isEmpty else { return [] }
        return commonLocations.filter { location in location.name.localizedCaseInsensitiveContains(query) }
    }
    
    static func createMKMapItem(from location: CommonLocation) -> MKMapItem {
        let placemark = MKPlacemark(coordinate: location.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = location.name
        return mapItem
    }
}

struct CommonLocation: Identifiable, Hashable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    
    init(id: UUID = UUID(), name: String, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
    }
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: CommonLocation, rhs: CommonLocation) -> Bool { lhs.id == rhs.id }
}

@main
struct WordTaggerApp: App {
    @StateObject private var store = WordStore.shared
    @State private var showPalette = false
    @State private var showQuickAdd = false
    @State private var showQuickSearch = false
    @State private var showTagManager = false
    
    init() {
        // 设置环境变量以抑制SQLite系统数据库访问警告
        setenv("SQLITE_ENABLE_FTS4", "0", 1)
        setenv("SQLITE_ENABLE_FTS5", "0", 1)
        setenv("SQLITE_SECURE_DELETE", "fast", 1)
        
        // 减少macOS系统服务的数据库查询
        UserDefaults.standard.set(false, forKey: "NSApplicationCrashOnExceptions")
        
        print("🚀 WordTagger 启动，已优化SQLite设置")
    }

    var body: some Scene {
        WindowGroup("单词标签管理器") {
            ZStack {
                ContentView()
                    .environmentObject(store)
                    .frame(minWidth: 800, minHeight: 600)
                
                if showPalette {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showPalette = false
                        }
                    
                    CommandPaletteView(isPresented: $showPalette)
                        .environmentObject(store)
                        .transition(.asymmetric(insertion: AnyTransition.scale.combined(with: .opacity), removal: .opacity))
                }
                
                
                if showQuickSearch {
                    QuickSearchView(
                        onDismiss: { showQuickSearch = false },
                        onWordSelected: { word in
                            store.selectWord(word)
                        }
                    )
                    .environmentObject(store)
                    .transition(.asymmetric(insertion: AnyTransition.scale.combined(with: .opacity), removal: .opacity))
                }
                
                if showTagManager {
                    TagManagerView {
                        showTagManager = false
                    }
                    .transition(.asymmetric(insertion: AnyTransition.scale.combined(with: .opacity), removal: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showPalette)
            .animation(.easeInOut(duration: 0.2), value: showQuickSearch)
            .animation(.easeInOut(duration: 0.2), value: showTagManager)
            .sheet(isPresented: $showQuickAdd) {
                QuickAddSheetView()
                    .environmentObject(store)
            }
            .onReceive(NotificationCenter.default.publisher(for: .addNewWord)) { _ in
                showQuickAdd = true
            }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {}
            CommandMenu("单词标签") {
                Button("命令面板") { 
                    showPalette = true 
                }
                .keyboardShortcut("k", modifiers: [.command])
                
                Divider()
                
                Button("快速添加单词") {
                    showQuickAdd = true
                }
                .keyboardShortcut("i", modifiers: [.command])
                
                Button("快速搜索") {
                    showQuickSearch = true
                }
                .keyboardShortcut("f", modifiers: [.command])
                
                Button("切换侧边栏") {
                    NotificationCenter.default.post(name: Notification.Name("toggleSidebar"), object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command])
                
                Button("标签管理") {
                    showTagManager = true
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                
                Button("单词管理") {
                    NotificationCenter.default.post(name: Notification.Name("openWordManager"), object: nil)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                
                Divider()
                
                Button("添加单词") {
                    // 触发添加单词对话框
                    NotificationCenter.default.post(name: Notification.Name("addNewWord"), object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
                
                Divider()
                
                Button("打开地图") {
                    NotificationCenter.default.post(name: Notification.Name("openMapWindow"), object: nil)
                }
                .keyboardShortcut("m", modifiers: [.command])
                
                Button("打开图谱") {
                    NotificationCenter.default.post(name: Notification.Name("openGraphWindow"), object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command])
            }
        }
        
        // 地图窗口
        WindowGroup("地图视图", id: "map") {
            MapWindow()
                .environmentObject(store)
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 700)
        
        // 图谱窗口
        WindowGroup("全局图谱", id: "graph") {
            GraphView()
                .environmentObject(store)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .defaultSize(width: 1200, height: 800)
        
        // 单词管理窗口
        WindowGroup("单词管理", id: "wordManager") {
            WordManagerView()
                .environmentObject(store)
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 700)
        
        // 设置窗口
        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

// MARK: - Tag Manager View (New Implementation)

struct TagManagerView: View {
    @StateObject private var tagManager = TagMappingManager.shared
    
    @State private var newKey: String = ""
    @State private var newTypeName: String = ""
    @State private var editingMapping: TagMapping?
    
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    Text("标签管理")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
                
                Divider()
                
                // 现有标签列表
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tagManager.tagMappings) { mapping in
                            TagMappingRow(
                                mapping: mapping,
                                onEdit: {
                                    editingMapping = mapping
                                    newKey = mapping.key
                                    newTypeName = mapping.typeName
                                },
                                onDelete: {
                                    tagManager.deleteMapping(withId: mapping.id)
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 300)
                
                Divider()
                
                // 添加新标签
                VStack(spacing: 12) {
                    Text(editingMapping != nil ? "编辑标签" : "添加新标签")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("快捷键")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("例如: root", text: $newKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("类型名称")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("例如: 词根", text: $newTypeName)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    
                    HStack {
                        if editingMapping != nil {
                            Button("取消") {
                                resetForm()
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Button(editingMapping != nil ? "保存" : "添加") {
                            saveMapping()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newKey.isEmpty || newTypeName.isEmpty)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
                
                // 帮助文本
                VStack(alignment: .leading, spacing: 4) {
                    Text("💡 使用方法:")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("输入格式: 单词 快捷键 内容")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("例如: apple root 苹果 memory 红苹果")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .background(.ultraThinMaterial)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.2), radius: 30, x: 0, y: 10)
            .frame(maxWidth: 700, maxHeight: 600)
            .padding(20)
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }
    
    private func saveMapping() {
        let mapping = TagMapping(
            id: editingMapping?.id ?? UUID(),
            key: newKey.lowercased(),
            typeName: newTypeName
        )
        
        tagManager.saveMapping(mapping)
        resetForm()
    }
    
    private func resetForm() {
        newKey = ""
        newTypeName = ""
        editingMapping = nil
    }
    
}

struct TagMappingRow: View {
    let mapping: TagMapping
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            // 标签颜色指示器
            Circle()
                .fill(Color.from(tagType: mapping.tagType))
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.key)
                    .font(.system(size: 14, weight: .medium))
                Text("→ \(mapping.typeName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(mapping.typeName)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.from(tagType: mapping.tagType).opacity(0.2))
                )
                .foregroundColor(Color.from(tagType: mapping.tagType))
            
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.clear)
    }
}

