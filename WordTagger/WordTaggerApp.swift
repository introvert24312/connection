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
        // 启动时延迟加载，等待外部数据服务准备好
        tagMappings = getDefaultMappings()
        
        // 异步尝试从外部存储加载
        Task {
            await loadFromExternalStorageOrFallback()
        }
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
        print("🔄 TagMappingManager.saveMapping() 开始")
        print("   - 输入映射: id=\(mapping.id), key=\(mapping.key), typeName=\(mapping.typeName)")
        print("   - 当前映射数量: \(tagMappings.count)")
        
        var oldTypeName: String?
        
        if let index = tagMappings.firstIndex(where: { $0.id == mapping.id }) {
            print("   - 找到现有映射在索引 \(index), 更新中...")
            print("   - 旧值: key=\(tagMappings[index].key), typeName=\(tagMappings[index].typeName)")
            
            oldTypeName = tagMappings[index].typeName
            
            // 强制重新创建数组以触发SwiftUI更新
            var newMappings = tagMappings
            newMappings[index] = mapping
            tagMappings = newMappings
            
            print("   - 新值: key=\(tagMappings[index].key), typeName=\(tagMappings[index].typeName)")
            print("   - 数组已重新创建以触发UI更新")
        } else {
            print("   - 未找到现有映射，添加新映射...")
            tagMappings.append(mapping)
        }
        
        print("   - 更新后映射数量: \(tagMappings.count)")
        print("   - 所有映射:")
        for (i, m) in tagMappings.enumerated() {
            print("     [\(i)] id=\(m.id), key=\(m.key), typeName=\(m.typeName)")
        }
        
        saveToUserDefaults()
        
        // 同步到外部存储
        Task {
            do {
                try await ExternalDataService.shared.saveTagMappingsOnly()
                print("✅ TagMappings已同步到外部存储")
            } catch {
                print("⚠️ TagMappings同步到外部存储失败: \(error)")
            }
        }
        
        // 如果是更新操作且typeName发生了变化，通知Store更新相关Tag
        if let oldName = oldTypeName, oldName != mapping.typeName {
            print("🔄 标签类型名称发生变化: \(oldName) -> \(mapping.typeName)")
            notifyTagTypeNameChanged(from: oldName, to: mapping.typeName, key: mapping.key)
        }
        
        print("✅ TagMappingManager.saveMapping() 完成")
    }
    
    // 通知标签类型名称变化
    private func notifyTagTypeNameChanged(from oldName: String, to newName: String, key: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("tagTypeNameChanged"),
            object: nil,
            userInfo: [
                "oldName": oldName,
                "newName": newName,
                "key": key
            ]
        )
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
    func parseTokenToTagType(_ token: String, store: NodeStore? = nil) -> Tag.TagType? {
        let lowerToken = token.lowercased()
        
        // 1. 首先检查TagMappingManager中的映射
        if let (typeName, tagType) = mappingDictionary[lowerToken] {
            print("✅ 找到标签映射: \(lowerToken) -> \(typeName) (\(tagType))")
            return tagType
        }
        
        // 2. 不再使用硬编码的预定义标签类型匹配
        // 让用户完全控制标签系统
        
        // 3. 检查已存在的自定义标签类型（如果提供了store）
        // 注意：由于MainActor隔离，这部分检查需要在调用时处理
        // 这里先跳过，直接创建新的自定义标签类型
        
        // 5. 创建新的自定义标签类型并自动添加到映射管理器
        print("🆕 创建新的自定义标签类型: \(token)")
        let customTagType = Tag.TagType.custom(token)
        
        // 自动添加到标签映射管理器
        addMappingIfNeeded(key: lowerToken, typeName: token)
        
        return customTagType
    }
    
    // MainActor隔离的版本，用于需要访问store的情况
    @MainActor
    func parseTokenToTagTypeWithStore(_ token: String, store: NodeStore) -> Tag.TagType? {
        let lowerToken = token.lowercased()
        
        // 1. 首先检查TagMappingManager中的映射
        if let (typeName, tagType) = mappingDictionary[lowerToken] {
            print("✅ 找到标签映射: \(lowerToken) -> \(typeName) (\(tagType))")
            return tagType
        }
        
        // 2. 不再使用硬编码的预定义标签类型匹配
        // 让用户完全控制标签系统
        
        // 3. 检查已存在的自定义标签类型
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
        
        // 5. 创建新的自定义标签类型并自动添加到映射管理器
        print("🆕 创建新的自定义标签类型: \(token)")
        let customTagType = Tag.TagType.custom(token)
        
        // 自动添加到标签映射管理器
        addMappingIfNeeded(key: lowerToken, typeName: token)
        
        return customTagType
    }
    
    // 检查是否是地图/位置标签的key
    func isLocationTagKey(_ key: String) -> Bool {
        let locationKeys = ["loc", "location", "地点", "位置"]
        return locationKeys.contains(key.lowercased())
    }
    
    // 删除标签映射
    func deleteMapping(withId id: UUID) {
        print("🗑️ TagMappingManager.deleteMapping() 开始")
        print("   - 删除映射ID: \(id)")
        print("   - 删除前映射数量: \(tagMappings.count)")
        
        // 检查是否是内置核心标签，如果是则拒绝删除
        if let mappingToDelete = tagMappings.first(where: { $0.id == id }),
           isBuiltInCoreTag(mappingToDelete.key) {
            print("❌ 拒绝删除内置核心标签: \(mappingToDelete.key)")
            return
        }
        
        tagMappings.removeAll { $0.id == id }
        
        print("   - 删除后映射数量: \(tagMappings.count)")
        
        saveToUserDefaults()
        
        // 同步到外部存储
        Task {
            do {
                try await ExternalDataService.shared.saveTagMappingsOnly()
                print("✅ 标签删除已同步到外部存储")
            } catch {
                print("⚠️ 标签删除同步到外部存储失败: \(error)")
            }
        }
        
        print("✅ TagMappingManager.deleteMapping() 完成")
    }
    
    // 系统内置核心标签 - 永远不能被删除
    static let builtInCoreTags = [
        TagMapping(key: "loc", typeName: "地点"),
        TagMapping(key: "root", typeName: "词根"),
        TagMapping(key: "compound", typeName: "复合节点"),
        TagMapping(key: "child", typeName: "子节点")
    ]
    
    // 检查是否是内置核心标签
    func isBuiltInCoreTag(_ key: String) -> Bool {
        return Self.builtInCoreTags.contains { $0.key == key.lowercased() }
    }
    
    // 确保内置核心标签存在
    func ensureBuiltInCoreTags() {
        print("🔧 确保内置核心标签存在...")
        
        for coreTag in Self.builtInCoreTags {
            if !tagMappings.contains(where: { $0.key == coreTag.key }) {
                print("   + 添加内置核心标签: \(coreTag.key) -> \(coreTag.typeName)")
                tagMappings.append(coreTag)
            }
        }
        
        saveToUserDefaults()
    }
    
    // 重置为默认映射
    func resetToDefaults() {
        print("🔄 TagMappingManager.resetToDefaults() 开始")
        
        tagMappings = Self.builtInCoreTags + [
            TagMapping(key: "time", typeName: "时间"),
            TagMapping(key: "sub", typeName: "子类")
        ]
        
        print("   - 重置后映射数量: \(tagMappings.count)")
        
        saveToUserDefaults()
        
        // 同步到外部存储
        Task {
            do {
                try await ExternalDataService.shared.saveTagMappingsOnly()
                print("✅ 标签重置已同步到外部存储")
            } catch {
                print("⚠️ 标签重置同步到外部存储失败: \(error)")
            }
        }
        
        print("✅ TagMappingManager.resetToDefaults() 完成")
    }
    
    // 完全清空所有标签映射（用于彻底清除数据）
    func clearAll() {
        print("🗑️ TagMappingManager.clearAll() 开始")
        print("   - 清空前映射数量: \(tagMappings.count)")
        
        tagMappings.removeAll()
        
        print("   - 清空后映射数量: \(tagMappings.count)")
        
        saveToUserDefaults()
        
        // 同步到外部存储
        Task {
            do {
                try await ExternalDataService.shared.saveTagMappingsOnly()
                print("✅ 标签映射清空已同步到外部存储")
            } catch {
                print("⚠️ 标签映射清空同步到外部存储失败: \(error)")
            }
        }
        
        print("✅ TagMappingManager.clearAll() 完成")
    }
    
    // 公共方法：重新从外部存储加载标签映射（用于切换位置时）
    @MainActor
    public func reloadFromExternalStorage() async {
        print("🔄 TagMappingManager: 重新从外部存储加载标签映射...")
        await loadFromExternalStorageOrFallback()
    }
    
    // 获取默认映射
    private func getDefaultMappings() -> [TagMapping] {
        // 总是包含内置核心标签
        return Self.builtInCoreTags
    }
    
    // 优先从外部存储加载，失败时从UserDefaults加载
    @MainActor
    private func loadFromExternalStorageOrFallback() async {
        print("🏷️ TagMappingManager: 尝试从外部存储加载标签映射...")
        
        do {
            // 尝试从外部存储加载
            if let url = ExternalDataManager.shared.getTagMappingsURL(),
               FileManager.default.fileExists(atPath: url.path) {
                
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let loadedMappings = try decoder.decode([TagMapping].self, from: data)
                
                await MainActor.run {
                    tagMappings = loadedMappings
                    print("✅ 从外部存储成功加载 \(loadedMappings.count) 个标签映射")
                    
                    // 确保包含内置核心标签
                    ensureBuiltInCoreTags()
                    
                    // 同步到UserDefaults作为备份
                    saveToUserDefaults()
                }
                return
            }
        } catch {
            print("⚠️ 从外部存储加载标签映射失败: \(error)")
        }
        
        // 外部存储失败，尝试从UserDefaults加载
        print("🏷️ TagMappingManager: 从UserDefaults加载标签映射...")
        await MainActor.run {
            loadTagMappingsFromUserDefaults()
        }
    }
    
    // 从UserDefaults加载（作为fallback）
    private func loadTagMappingsFromUserDefaults() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let savedMappings = try? decoder.decode([TagMapping].self, from: data) {
            tagMappings = savedMappings
            print("✅ 从UserDefaults成功加载 \(savedMappings.count) 个标签映射")
            
            // 确保包含内置核心标签
            ensureBuiltInCoreTags()
            
            // 迁移：确保包含新的默认映射
            migrateToLatestMappings()
            
            // 同步到外部存储
            Task {
                do {
                    try await ExternalDataService.shared.saveTagMappingsOnly()
                    print("✅ 已将UserDefaults中的标签映射同步到外部存储")
                } catch {
                    print("⚠️ 同步标签映射到外部存储失败: \(error)")
                }
            }
        } else {
            print("⚠️ UserDefaults中也没有标签映射，使用默认值")
            tagMappings = getDefaultMappings()
        }
    }
    
    // 保存到UserDefaults
    private func saveToUserDefaults() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(tagMappings) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    
    // 迁移到最新的映射（不再自动添加预定义映射）
    private func migrateToLatestMappings() {
        // 不再自动添加预定义映射，让用户完全控制标签系统
        print("🔄 迁移检查完成，不再自动添加预定义标签映射")
    }
}

public struct TagMapping: Identifiable, Codable {
    public let id: UUID
    public let key: String
    public let typeName: String
    
    public init(id: UUID = UUID(), key: String, typeName: String) {
        self.id = id
        self.key = key
        self.typeName = typeName
    }
    
    // 转换为 Tag.TagType
    public var tagType: Tag.TagType {
        // 所有标签都使用自定义类型，让用户完全控制
        return .custom(key)
    }
}

// MARK: - Quick Add Sheet View

struct QuickAddSheetView: View {
    @EnvironmentObject private var store: NodeStore
    @ObservedObject private var tagManager = TagMappingManager.shared
    @Environment(\.dismiss) var dismiss
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
                
                TextField("输入: 节点 root 词根内容 memory 记忆内容...", text: $inputText)
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
                        // 清理状态后再关闭
                        isInputFocused = false
                        inputText = ""
                        selectedSuggestionIndex = -1
                        suggestions = []
                        
                        // 延迟关闭，确保状态清理完成
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            dismiss()
                        }
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
                Text("输入格式: 节点 快捷键 内容")
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
        .navigationTitle("快速添加节点")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    // 清理状态后再关闭
                    isInputFocused = false
                    inputText = ""
                    selectedSuggestionIndex = -1
                    suggestions = []
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        dismiss()
                    }
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
            if let alert = store.duplicateNodeAlert {
                Text(alert.message)
            }
        }
        .onReceive(store.$duplicateNodeAlert) { alert in
            if alert != nil {
                showingDuplicateAlert = true
                // 稍微延长延迟，避免状态竞态
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    store.duplicateNodeAlert = nil
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
        
        let nodeText = components[0]
        var tags: [Tag] = []
        var i = 1
        
        while i < components.count {
            let tagKey = components[i]
            
            // 检查是否是标签重命名语法: tagtype[newName]
            if tagKey.contains("[") && tagKey.contains("]") {
                if let startBracket = tagKey.firstIndex(of: "["),
                   let endBracket = tagKey.firstIndex(of: "]"),
                   startBracket < endBracket {
                    
                    let actualTagKey = String(tagKey[..<startBracket])
                    let newTypeName = String(tagKey[tagKey.index(after: startBracket)..<endBracket])
                    
                    print("🏷️ QuickAdd: 检测到标签重命名 - key: '\(actualTagKey)', newName: '\(newTypeName)'")
                    
                    // 处理标签重命名
                    if let existingMapping = tagManager.tagMappings.first(where: { $0.key == actualTagKey }) {
                        let oldTypeName = existingMapping.typeName
                        print("🔄 QuickAdd: 更新标签映射 - \(oldTypeName) -> \(newTypeName)")
                        
                        // 创建更新后的映射
                        let updatedMapping = TagMapping(
                            id: existingMapping.id,
                            key: actualTagKey,
                            typeName: newTypeName
                        )
                        
                        // 保存到TagManager，会自动触发UI更新
                        tagManager.saveMapping(updatedMapping)
                        
                        print("✅ QuickAdd: 标签重命名完成")
                    } else {
                        print("⚠️ QuickAdd: 未找到key '\(actualTagKey)' 对应的映射")
                    }
                    
                    i += 1
                    continue
                }
            }
            
            if let tagType = tagManager.parseTokenToTagTypeWithStore(tagKey, store: store) {
                if i + 1 < components.count { 
                    let content = components[i + 1]
                    
                    // 检查是否是地图标签（通过key识别）
                    if tagManager.isLocationTagKey(tagKey) {
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
        
        // 检查层级可用性，不再使用UUID()作为fallback
        guard let layerId = store.currentLayer?.id ?? store.layers.first?.id else {
            print("❌ QuickAdd: 无可用层，无法创建节点")
            // 触发警告
            store.duplicateNodeAlert = NodeStore.DuplicateNodeAlert(
                message: "无法添加节点：请先创建至少一个层",
                isDuplicate: false,
                existingNode: nil,
                newNode: Node(text: nodeText, layerId: UUID(), tags: [])
            )
            return
        }
        
        let newNode = Node(text: nodeText, layerId: layerId, tags: tags)
        let success = store.addNode(newNode)
        inputText = ""
        if success {
            dismiss()
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
    @EnvironmentObject private var store: NodeStore
    @ObservedObject private var tagManager = TagMappingManager.shared
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
                        TextField("输入: 节点 root 词根内容 memory 记忆内容...", text: $inputText)
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
                    Text("💡 格式: 节点 标签1 内容1 标签2 内容2...").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("⌘+I").font(.caption).foregroundColor(.secondary)
                }.padding(.top, 12)
            }.padding(20).frame(maxWidth: 600)
        }
        .onKeyPress(.escape) { onDismiss(); return .handled }
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
        let nodeText = components[0]
        var tags: [Tag] = []
        var i = 1
        
        while i < components.count {
            let tagKey = components[i]
            if let tagType = tagManager.parseTokenToTagTypeWithStore(tagKey, store: store) {
                if i + 1 < components.count {
                    let content = components[i + 1]
                    
                    // 检查是否是地图标签且包含坐标信息
                    if tagManager.isLocationTagKey(tagKey) && content.contains("@") {
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
        
        // 检查层级可用性，不再使用UUID()作为fallback
        guard let layerId = store.currentLayer?.id ?? store.layers.first?.id else {
            print("❌ QuickAddView: 无可用层，无法创建节点")
            // 触发警告
            store.duplicateNodeAlert = NodeStore.DuplicateNodeAlert(
                message: "无法添加节点：请先创建至少一个层",
                isDuplicate: false,
                existingNode: nil,
                newNode: Node(text: nodeText, layerId: UUID(), tags: [])
            )
            return
        }
        
        let newNode = Node(text: nodeText, layerId: layerId, tags: tags)
        let success = store.addNode(newNode)
        inputText = ""
        if success {
            onDismiss()
        }
        // 如果不成功，保持窗口打开让用户看到警告
    }
}

// MARK: - Quick Search View

struct QuickSearchView: View {
    @EnvironmentObject private var store: NodeStore
    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0
    let onDismiss: () -> Void
    let onNodeSelected: (Node) -> Void
    
    private var filteredNodes: [Node] {
        if searchText.isEmpty { return Array(store.nodes.prefix(10)) }
        else { return store.nodes.filter { node in
            node.text.localizedCaseInsensitiveContains(searchText) ||
            node.meaning?.localizedCaseInsensitiveContains(searchText) == true ||
            node.tags.contains { tag in tag.value.localizedCaseInsensitiveContains(searchText) }
        }}
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { onDismiss() }
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.blue).font(.title2)
                    TextField("搜索节点、含义或标签...", text: $searchText)
                        .textFieldStyle(.plain).font(.system(size: 16, weight: .medium))
                        .onSubmit { selectCurrentNode() }
                }.padding(.horizontal, 16).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial).shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8))
                
                if !filteredNodes.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredNodes.enumerated()), id: \.element.id) { index, node in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(node.text).font(.system(size: 16, weight: .semibold)).foregroundColor(.primary)
                                        Spacer()
                                        HStack(spacing: 4) {
                                            ForEach(node.tags.prefix(3), id: \.id) { tag in
                                                Text(tag.displayName).font(.caption)
                                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.from(tagType: tag.type).opacity(0.2)))
                                                    .foregroundColor(Color.from(tagType: tag.type))
                                            }
                                            if node.tags.count > 3 { Text("+\(node.tags.count - 3)").font(.caption).foregroundColor(.secondary) }
                                        }
                                    }
                                    if let meaning = node.meaning, !meaning.isEmpty {
                                        Text(meaning).font(.caption).foregroundColor(.secondary).lineLimit(2)
                                    }
                                }.padding(.horizontal, 16).padding(.vertical, 10)
                                .onTapGesture { onNodeSelected(node); onDismiss() }
                                .background(index == selectedIndex ? Color.blue.opacity(0.1) : Color.clear)
                            }
                        }
                    }.background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                    .frame(maxHeight: 400).padding(.top, 8)
                }
                
                HStack {
                    Text("💡 输入关键词搜索节点").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("⌘+F").font(.caption).foregroundColor(.secondary)
                }.padding(.top, 12)
            }.padding(20).frame(maxWidth: 600)
        }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .onChange(of: filteredNodes) { _, _ in selectedIndex = 0 }
    }
    
    private func selectCurrentNode() {
        guard selectedIndex < filteredNodes.count else { return }
        let selectedNode = filteredNodes[selectedIndex]; onNodeSelected(selectedNode); onDismiss()
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
    @StateObject private var store = NodeStore.shared
    @State private var showPalette = false
    @State private var showQuickAdd = false
    @State private var showQuickSearch = false
    @State private var showTagManager = false
    @State private var showCompoundNodeAdd = false
    
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
        WindowGroup("节点标签管理器") {
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
                        onNodeSelected: { node in
                            store.selectNode(node)
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
            .sheet(isPresented: $showCompoundNodeAdd) {
                CompoundNodeAddSheetView()
                    .environmentObject(store)
            }
            .onReceive(NotificationCenter.default.publisher(for: .addNewNode)) { _ in
                showQuickAdd = true
            }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {}
            CommandMenu("节点标签") {
                Button("命令面板") { 
                    showPalette = true 
                }
                .keyboardShortcut("k", modifiers: [.command])
                
                Divider()
                
                Button("快速添加节点") {
                    showQuickAdd = true
                }
                .keyboardShortcut("i", modifiers: [.command])
                
                Button("添加复合节点") {
                    showCompoundNodeAdd = true
                }
                .keyboardShortcut("u", modifiers: [.command])
                
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
                
                Button("节点管理") {
                    NotificationCenter.default.post(name: Notification.Name("openNodeManager"), object: nil)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                
                Divider()
                
                Button("添加节点") {
                    // 触发添加节点对话框
                    NotificationCenter.default.post(name: Notification.Name("addNewNode"), object: nil)
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
        
        // 节点管理窗口
        WindowGroup("节点管理", id: "nodeManager") {
            NodeManagerView()
                .environmentObject(store)
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 700)
        
        // 全屏图谱窗口 - SwiftUI原生方式
        WindowGroup("全屏图谱", id: "fullscreenGraph") {
            FullscreenGraphView()
                .environmentObject(store)
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified)
        
        // 设置窗口
        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

// MARK: - Tag Manager View (New Implementation)

struct TagManagerView: View {
    @ObservedObject private var tagManager = TagMappingManager.shared
    
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
                        ForEach(tagManager.tagMappings, id: \.id) { mapping in
                            TagMappingRow(
                                mapping: mapping,
                                onEdit: {
                                    print("🎯 TagManagerView: 开始编辑映射")
                                    print("   - 选中映射: id=\(mapping.id), key=\(mapping.key), typeName=\(mapping.typeName)")
                                    editingMapping = mapping
                                    newKey = mapping.key
                                    newTypeName = mapping.typeName
                                    print("   - 表单已填充: newKey=\(newKey), newTypeName=\(newTypeName)")
                                },
                                onDelete: {
                                    print("🗑️ TagManagerView: 删除映射 id=\(mapping.id)")
                                    tagManager.deleteMapping(withId: mapping.id)
                                }
                            )
                            .id("\(mapping.id)-\(mapping.typeName)")
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
                    Text("输入格式: 节点 快捷键 内容")
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
        print("💾 TagManagerView: saveMapping() 开始")
        print("   - editingMapping存在: \(editingMapping != nil)")
        print("   - newKey: '\(newKey)'")
        print("   - newTypeName: '\(newTypeName)'")
        
        let mapping = TagMapping(
            id: editingMapping?.id ?? UUID(),
            key: newKey.lowercased(),
            typeName: newTypeName
        )
        
        print("   - 创建的映射: id=\(mapping.id), key=\(mapping.key), typeName=\(mapping.typeName)")
        print("   - 是否编辑模式: \(editingMapping != nil)")
        if let editing = editingMapping {
            print("   - 编辑中的原始映射: id=\(editing.id), key=\(editing.key), typeName=\(editing.typeName)")
        }
        
        tagManager.saveMapping(mapping)
        resetForm()
        print("✅ TagManagerView: saveMapping() 完成")
    }
    
    private func resetForm() {
        print("🔄 TagManagerView: resetForm() 重置表单")
        newKey = ""
        newTypeName = ""
        editingMapping = nil
        print("   - 表单已重置")
    }
    
}

struct TagMappingRow: View {
    let mapping: TagMapping
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    private var isBuiltInCore: Bool {
        TagMappingManager.shared.isBuiltInCoreTag(mapping.key)
    }
    
    var body: some View {
        let _ = print("🎨 TagMappingRow: 渲染 id=\(mapping.id), key=\(mapping.key), typeName=\(mapping.typeName)")
        return HStack {
            // 标签颜色指示器
            Circle()
                .fill(Color.from(tagType: mapping.tagType))
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(mapping.key)
                        .font(.system(size: 14, weight: .medium))
                    
                    if isBuiltInCore {
                        Text("系统")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.orange)
                            )
                    }
                }
                
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
                    .foregroundColor(isBuiltInCore ? .gray : .blue)
            }
            .buttonStyle(.plain)
            .disabled(isBuiltInCore)
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(isBuiltInCore ? .gray : .red)
            }
            .buttonStyle(.plain)
            .disabled(isBuiltInCore)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.clear)
    }
}

// MARK: - 复合节点添加界面

struct CompoundNodeAddSheetView: View {
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) var dismiss
    @State private var inputText: String = ""
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("添加复合节点")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("输入格式：复合节点名 节点1 节点2 节点3...")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Text("创建1级复合节点：动物 狗 猫 鸟")
                        .font(.caption)
                        .foregroundColor(.purple.opacity(0.8))
                    
                    Text("创建2级复合节点：生物 动物 植物")
                        .font(.caption)
                        .foregroundColor(.orange.opacity(0.8))
                    
                    Text("删除子节点：动物 -狗 -猫")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.8))
                        
                    Text("💡 复合节点可以无限嵌套，颜色会自动区分层级")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                TextField("例如：颜色 红色 蓝色 绿色", text: $inputText, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...6)
                    .onKeyPress(.return) {
                        processInput()
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        dismiss()
                        return .handled
                    }
                
                Spacer()
            }
            .padding(20)
            .frame(width: 500, height: 300)
            .navigationTitle("添加复合节点")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        processInput()
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return)
                }
            }
        }
        .alert("错误", isPresented: $showingErrorAlert) {
            Button("确定") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func processInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let components = trimmed.split(separator: " ").map { String($0) }
        guard components.count >= 2 else {
            errorMessage = "请至少输入复合节点名和一个子节点"
            showingErrorAlert = true
            return
        }
        
        let compoundNodeName = components[0]
        let childNodeNames = Array(components[1...])
        
        guard let currentLayer = store.currentLayer else {
            errorMessage = "请先选择一个活跃层"
            showingErrorAlert = true
            return
        }
        
        // 检查是否有删除操作（子节点名以"-"开头）
        let (childNamesToAdd, childNamesToRemove) = separateAddAndRemoveOperations(childNodeNames)
        
        // 检查复合节点是否已存在
        if let existingCompoundNode = store.nodes.first(where: { 
            $0.text.lowercased() == compoundNodeName.lowercased() && $0.isCompound 
        }) {
            // 模式2/3: 修改已存在的复合节点
            if !childNamesToRemove.isEmpty {
                print("🗑️ 从复合节点删除子节点: \(compoundNodeName)")
                removeChildrenFromCompoundNode(existingCompoundNode, childNames: childNamesToRemove)
            }
            if !childNamesToAdd.isEmpty {
                print("🔄 向已存在的复合节点添加子节点: \(compoundNodeName)")
                addChildrenToExistingCompoundNode(existingCompoundNode, childNames: childNamesToAdd)
            }
        } else {
            // 模式1: 创建新的复合节点
            if !childNamesToRemove.isEmpty {
                errorMessage = "无法从不存在的复合节点中删除子节点"
                showingErrorAlert = true
                return
            }
            print("🏗️ 创建新复合节点: \(compoundNodeName)")
            createNewCompoundNode(name: compoundNodeName, childNames: childNamesToAdd, layerId: currentLayer.id)
        }
        
        // 清空输入并关闭
        inputText = ""
        dismiss()
    }
    
    private func separateAddAndRemoveOperations(_ childNames: [String]) -> ([String], [String]) {
        var toAdd: [String] = []
        var toRemove: [String] = []
        
        for name in childNames {
            if name.hasPrefix("-") {
                // 删除操作：去掉"-"前缀
                let nameToRemove = String(name.dropFirst())
                if !nameToRemove.isEmpty {
                    toRemove.append(nameToRemove)
                }
            } else {
                // 添加操作
                toAdd.append(name)
            }
        }
        
        return (toAdd, toRemove)
    }
    
    private func removeChildrenFromCompoundNode(_ compoundNode: Node, childNames: [String]) {
        print("🗑️ 从复合节点 '\(compoundNode.text)' 删除 \(childNames.count) 个子节点")
        
        // 获取现有的子节点引用
        let existingChildReferences = compoundNode.tags.compactMap { tag in
            if case .custom(let key) = tag.type, key == "child" {
                return tag.value
            }
            return nil
        }
        print("🔍 现有子节点: [\(existingChildReferences.joined(separator: ", "))]")
        
        // 找到要删除的子节点
        let childNamesToRemove = childNames.filter { childName in
            existingChildReferences.contains { existingChild in
                existingChild.lowercased() == childName.lowercased()
            }
        }
        
        guard !childNamesToRemove.isEmpty else {
            errorMessage = "这些子节点不存在于复合节点中"
            showingErrorAlert = true
            return
        }
        
        print("🗑️ 需要删除的子节点: [\(childNamesToRemove.joined(separator: ", "))]")
        
        // 过滤掉要删除的子节点标签
        let updatedTags = compoundNode.tags.filter { tag in
            if case .custom(let key) = tag.type, key == "child" {
                return !childNamesToRemove.contains { childName in
                    tag.value.lowercased() == childName.lowercased()
                }
            }
            return true // 保留非子节点引用标签
        }
        
        let remainingChildCount = existingChildReferences.count - childNamesToRemove.count
        let updatedMeaning = "复合节点：包含 \(remainingChildCount) 个子节点"
        
        // 更新复合节点
        store.updateNodeTags(compoundNode.id, tags: updatedTags)
        store.updateNode(compoundNode.id, text: nil, phonetic: nil, meaning: updatedMeaning)
        
        // 清除图谱缓存以刷新显示
        NodeGraphDataCache.shared.invalidateCache(for: compoundNode.id)
        
        // 强制触发UI更新 - 确保WordListView刷新
        DispatchQueue.main.async {
            print("🔄 强制触发UI更新（删除操作）")
            store.objectWillChange.send()
            
            NotificationCenter.default.post(
                name: Notification.Name("nodesUpdated"),
                object: nil,
                userInfo: ["deletedChildNodes": childNamesToRemove.count]
            )
        }
        
        print("✅ 复合节点删除操作完成:")
        print("  复合节点: \(compoundNode.text)")
        print("  删除的子节点: [\(childNamesToRemove.joined(separator: ", "))]")
        print("  剩余子节点数: \(remainingChildCount)")
    }
    
    private func addChildrenToExistingCompoundNode(_ compoundNode: Node, childNames: [String]) {
        print("🔗 向复合节点 '\(compoundNode.text)' 添加 \(childNames.count) 个子节点")
        
        // 获取现有的子节点引用
        let existingChildReferences = compoundNode.tags.compactMap { tag in
            if case .custom(let key) = tag.type, key == "child" {
                return tag.value
            }
            return nil
        }
        print("🔍 现有子节点: [\(existingChildReferences.joined(separator: ", "))]")
        
        // 过滤掉已经存在的子节点
        let newChildNames = childNames.filter { childName in
            !existingChildReferences.contains { existingChild in
                existingChild.lowercased() == childName.lowercased()
            }
        }
        
        guard !newChildNames.isEmpty else {
            errorMessage = "这些子节点已经存在于复合节点中"
            showingErrorAlert = true
            return
        }
        
        print("🆕 需要添加的新子节点: [\(newChildNames.joined(separator: ", "))]")
        
        // 为新子节点创建标签
        var newChildTags: [Tag] = []
        for childName in newChildNames {
            let childReferenceTag = Tag(
                type: .custom("child"),
                value: childName
            )
            newChildTags.append(childReferenceTag)
        }
        
        // 更新复合节点的标签（添加新的子节点引用）
        let updatedTags = compoundNode.tags + newChildTags
        let updatedMeaning = "复合节点：包含 \(existingChildReferences.count + newChildNames.count) 个子节点"
        
        store.updateNodeTags(compoundNode.id, tags: updatedTags)
        store.updateNode(compoundNode.id, text: nil, phonetic: nil, meaning: updatedMeaning)
        
        // 创建或确保新子节点存在
        var childNodesToCreate: [Node] = []
        for childName in newChildNames {
            if let existingNode = store.nodes.first(where: { $0.text.lowercased() == childName.lowercased() }) {
                print("🔍 找到已存在的子节点: \(existingNode.text), 保持其标签不变")
            } else {
                let childNode = Node(
                    text: childName,
                    phonetic: nil,
                    meaning: nil,
                    layerId: compoundNode.layerId,
                    tags: []
                )
                childNodesToCreate.append(childNode)
                print("🆕 创建新子节点: \(childName)")
            }
        }
        
        // 添加新创建的子节点到store
        for childNode in childNodesToCreate {
            let success = store.addNode(childNode)
            print("📝 子节点添加结果: \(childNode.text) - \(success ? "成功" : "失败")")
        }
        
        // 清除图谱缓存以刷新显示
        NodeGraphDataCache.shared.invalidateCache(for: compoundNode.id)
        
        // 强制触发UI更新 - 确保WordListView刷新
        DispatchQueue.main.async {
            print("🔄 强制触发UI更新")
            // 触发@Published属性更新
            store.objectWillChange.send()
            
            // 额外触发节点数组的更新通知
            NotificationCenter.default.post(
                name: Notification.Name("nodesUpdated"),
                object: nil,
                userInfo: ["newNodeCount": store.nodes.count]
            )
            
            print("📢 发送节点更新通知，当前节点总数: \(store.nodes.count)")
        }
        
        print("✅ 复合节点更新完成:")
        print("  复合节点: \(compoundNode.text)")
        print("  原有子节点: [\(existingChildReferences.joined(separator: ", "))]")
        print("  新增子节点: [\(newChildNames.joined(separator: ", "))]")
    }
    
    // 计算子节点中的最大复合节点深度
    private func calculateMaxChildDepth(childNames: [String]) -> Int {
        var maxDepth = 0
        
        for childName in childNames {
            if let childNode = store.nodes.first(where: { $0.text.lowercased() == childName.lowercased() }) {
                if childNode.isCompound {
                    let childDepth = childNode.getCompoundDepth(allNodes: store.nodes)
                    maxDepth = max(maxDepth, childDepth)
                }
                // 普通节点深度为0，不影响maxDepth
            }
        }
        
        return maxDepth
    }
    
    private func createNewCompoundNode(name: String, childNames: [String], layerId: UUID) {
        // 为复合节点创建特殊标签，包含所有子节点名称作为标签值
        var compoundTags: [Tag] = []
        
        // 计算复合节点层级
        let childDepth = calculateMaxChildDepth(childNames: childNames)
        let currentDepth = childDepth + 1
        
        // 主复合节点标签，包含层级信息
        let compoundTag = Tag(
            type: .custom("compound"),
            value: "\(currentDepth)级复合节点"
        )
        compoundTags.append(compoundTag)
        
        // 为每个子节点创建标签，记录子节点的名称
        for childName in childNames {
            let childReferenceTag = Tag(
                type: .custom("child"),
                value: childName
            )
            compoundTags.append(childReferenceTag)
            print("🔗 为复合节点添加子节点引用标签: \(childName)")
        }
        
        print("🏗️ 创建复合节点: \(name), 标签数: \(compoundTags.count)")
        print("  - 复合标签: \(compoundTag.value)")
        for tag in compoundTags.dropFirst() {
            print("  - 子节点引用: \(tag.value)")
        }
        
        // 创建复合节点，只包含复合标签和子节点引用标签
        let compoundNode = Node(
            text: name,
            phonetic: nil,
            meaning: "复合节点：包含 \(childNames.joined(separator: ", "))",
            layerId: layerId,
            tags: compoundTags,
            isCompound: true
        )
        
        // 创建或确保子节点存在
        var childNodes: [Node] = []
        for childName in childNames {
            // 检查是否已存在
            if let existingNode = store.nodes.first(where: { $0.text.lowercased() == childName.lowercased() }) {
                print("🔍 找到已存在的子节点: \(existingNode.text), 保持其标签不变")
                // 子节点已存在，保持其原有标签
            } else {
                // 创建新的子节点
                let childNode = Node(
                    text: childName,
                    phonetic: nil,
                    meaning: nil,
                    layerId: layerId,
                    tags: []
                )
                childNodes.append(childNode)
                print("🆕 创建新子节点: \(childName)")
            }
        }
        
        // 添加到store
        store.addNode(compoundNode)
        for childNode in childNodes {
            store.addNode(childNode)
        }
        
        print("✅ 复合节点结构创建完成:")
        print("  复合节点: \(name) (包含 \(compoundTags.count) 个标签)")
        print("  子节点: \(childNames.joined(separator: ", "))")
    }
}

