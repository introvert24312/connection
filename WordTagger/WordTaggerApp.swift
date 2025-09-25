import SwiftUI
import MapKit
import CoreLocation
import Combine
import AppKit

// MARK: - Constants 哈哈哈哈哈哈哈
private let WINDOW_TITLE: String = {
    // 笑脸版本 - 使用向上的弧形
    let macron = "¯"           // U+00AF MACRON
    let happy = "︶"           // U+FE36 向上的弧形（笑脸）哈哈哈哈哈哈哈哈哈
    
    let result = "(* \(macron) \(happy) \(macron) *)ノ ❤ ヽ( ^ ^ )"
    
    return result
}()

// MARK: - Tag Mapping Manager

class TagMappingManager: ObservableObject {
    @Published var tagMappings: [TagMapping] = []
    
    static let shared = TagMappingManager()
    
    private let userDefaultsKey = "tagMappings"
    
    private init() {
        // 启动时只加载内置核心标签，不再自动添加commonTags
        tagMappings = Self.builtInCoreTags
        
        // 异步尝试从外部存储加载，并扫描现有标签
        Task { @MainActor in
            await loadFromExternalStorageOrFallback()
            // 启动后扫描现有标签并更新映射
            rescanAndUpdateMappings()
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
        
        var oldTypeName: String?
        
        if let index = tagMappings.firstIndex(where: { $0.id == mapping.id }) {
            
            oldTypeName = tagMappings[index].typeName
            
            // 强制重新创建数组以触发SwiftUI更新
            var newMappings = tagMappings
            newMappings[index] = mapping
            tagMappings = newMappings
            
        } else {
            tagMappings.append(mapping)
        }
        
        
        saveToUserDefaults()
        
        // 同步到外部存储
        Task {
            do {
                try await ExternalDataService.shared.saveTagMappingsOnly()
            } catch {
            }
        }
        
        // 如果是更新操作且typeName发生了变化，通知Store更新相关Tag
        if let oldName = oldTypeName, oldName != mapping.typeName {
            notifyTagTypeNameChanged(from: oldName, to: mapping.typeName, key: mapping.key)
        }
        
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
    
    // 动态添加缺失的标签映射（带冲突检测）
    func addMappingIfNeeded(key: String, typeName: String) -> Bool {
        let normalizedKey = key.lowercased()
        
        // 检查是否已存在**完全相同的key**的映射
        if let existingIndex = tagMappings.firstIndex(where: { $0.key == normalizedKey }) {
            let existingMapping = tagMappings[existingIndex]
            
            // 只有当key完全相同时才考虑更新typeName
            // 这里我们不更新，因为可能破坏现有的映射关系
            if existingMapping.typeName != typeName {
                return false // 返回false表示冲突
            } else {
                return true // 返回true表示成功（已存在相同映射）
            }
        } else {
            // 不存在相同key的映射，可以安全添加
            let newMapping = TagMapping(key: normalizedKey, typeName: typeName)
            tagMappings.append(newMapping)
            saveToUserDefaults()
            return true // 返回true表示添加成功
        }
    }
    
    // 检查映射冲突的专用方法
    func checkMappingConflict(key: String, typeName: String) -> MappingConflictResult {
        let normalizedKey = key.lowercased()
        
        if let existingMapping = tagMappings.first(where: { $0.key == normalizedKey }) {
            if existingMapping.typeName != typeName {
                return .conflict(existing: existingMapping, requested: typeName)
            } else {
                return .noConflict(existingMapping)
            }
        } else {
            return .canCreate
        }
    }
    
    /// 添加新的标签映射
    func addMapping(_ mapping: TagMapping) {
        let normalizedKey = mapping.key.lowercased()
        let newMapping = TagMapping(id: mapping.id, key: normalizedKey, typeName: mapping.typeName)
        
        // 检查是否已存在，如果存在则更新
        if let index = tagMappings.firstIndex(where: { $0.key == normalizedKey }) {
            tagMappings[index] = newMapping
        } else {
            tagMappings.append(newMapping)
        }
        
        saveToUserDefaults()
    }
    
    /// 更新现有的标签映射
    func updateMapping(_ mapping: TagMapping) {
        let normalizedKey = mapping.key.lowercased()
        let updatedMapping = TagMapping(id: mapping.id, key: normalizedKey, typeName: mapping.typeName)
        
        if let index = tagMappings.firstIndex(where: { $0.id == mapping.id || $0.key == normalizedKey }) {
            tagMappings[index] = updatedMapping
            saveToUserDefaults()
        } else {
            // 如果找不到现有映射，则添加新的
            addMapping(updatedMapping)
        }
    }
    
    /// 删除标签映射
    func removeMapping(_ mapping: TagMapping) {
        
        if let index = tagMappings.firstIndex(where: { $0.id == mapping.id }) {
            _ = tagMappings.remove(at: index)
            
            saveToUserDefaults()
            
            // 同步到外部存储
            Task {
                do {
                    try await ExternalDataService.shared.saveTagMappingsOnly()
                } catch {
                }
            }
            
        } else {
        }
    }
    
    /// 批量删除标签映射
    func removeMappings(_ mappings: [TagMapping]) {
        
        let idsToRemove = Set(mappings.map { $0.id })
        let removedCount = tagMappings.count
        
        tagMappings.removeAll { mapping in
            idsToRemove.contains(mapping.id)
        }
        
        let actualRemovedCount = removedCount - tagMappings.count
        
        if actualRemovedCount > 0 {
            saveToUserDefaults()
            
            // 同步到外部存储
            Task {
                do {
                    try await ExternalDataService.shared.saveTagMappingsOnly()
                } catch {
                }
            }
        }
        
    }
    
    // 智能解析token为TagType，支持动态创建
    func parseTokenToTagType(_ token: String, store: NodeStore? = nil) -> Tag.TagType? {
        let lowerToken = token.lowercased()
        
        // 1. 首先检查TagMappingManager中的映射
        if let (_, tagType) = mappingDictionary[lowerToken] {
            return tagType
        }
        
        // 2. 不再使用硬编码的预定义标签类型匹配
        // 让用户完全控制标签系统
        
        // 3. 检查已存在的自定义标签类型（如果提供了store）
        // 注意：由于MainActor隔离，这部分检查需要在调用时处理
        // 这里先跳过，直接创建新的自定义标签类型
        
        // 5. 创建新的自定义标签类型并自动添加到映射管理器
        let customTagType = Tag.TagType.custom(token)
        
        // 自动添加到标签映射管理器
        _ = addMappingIfNeeded(key: lowerToken, typeName: token)
        
        return customTagType
    }
    
    // MainActor隔离的版本，用于需要访问store的情况
    @MainActor
    func parseTokenToTagTypeWithStore(_ token: String, store: NodeStore) -> Tag.TagType? {
        let lowerToken = token.lowercased()
        
        // 确保映射已修复
        if lowerToken == "beef" {
            ensureBuiltInCoreTags()
        }
        
        // 1. 首先检查TagMappingManager中的映射
        if let (_, tagType) = mappingDictionary[lowerToken] {
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
                    return existingTag.type
                }
            }
        }
        
        // 5. 创建新的自定义标签类型并自动添加到映射管理器
        let customTagType = Tag.TagType.custom(token)
        
        // 自动添加到标签映射管理器
        _ = addMappingIfNeeded(key: lowerToken, typeName: token)
        
        return customTagType
    }
    
    // 检查是否是地图/位置标签的key
    func isLocationTagKey(_ key: String) -> Bool {
        let locationKeys = ["loc", "location", "地点", "位置"]
        return locationKeys.contains(key.lowercased())
    }
    
    // 删除标签映射
    func deleteMapping(withId id: UUID) {
        
        // 检查是否是内置核心标签，如果是则拒绝删除
        if let mappingToDelete = tagMappings.first(where: { $0.id == id }),
           isBuiltInCoreTag(mappingToDelete.key) {
            return
        }
        
        tagMappings.removeAll { $0.id == id }
        
        
        saveToUserDefaults()
        
        // 同步到外部存储
        Task {
            do {
                try await ExternalDataService.shared.saveTagMappingsOnly()
            } catch {
            }
        }
        
    }
    
    // 系统内置核心标签 - 永远不能被删除
    static let builtInCoreTags = [
        TagMapping(key: "loc", typeName: "地点"),
        TagMapping(key: "compound", typeName: "复合节点"),
        TagMapping(key: "child", typeName: "子节点")
    ]
    
    // 常用标签 - 可以删除的预设标签（已移除自动添加功能）
    static let commonTags: [TagMapping] = [
        // 不再自动添加任何预设标签，让用户完全控制标签系统
    ]
    
    // 检查是否是内置核心标签
    func isBuiltInCoreTag(_ key: String) -> Bool {
        return Self.builtInCoreTags.contains { $0.key == key.lowercased() }
    }
    
    // 确保内置核心标签存在
    func ensureBuiltInCoreTags() {
        
        for coreTag in Self.builtInCoreTags {
            if !tagMappings.contains(where: { $0.key == coreTag.key }) {
                tagMappings.append(coreTag)
            }
        }
        
        // 🔧 移除自动beef映射恢复逻辑，允许用户永久删除beef映射
    }
    
    // 🔧 已移除自动beef映射恢复功能，允许用户永久删除beef映射
    // private func restoreMostRecentBeefMapping() -> TagMapping? { ... }
    
    // 修复节点中错误的标签类型
    @MainActor
    func fixNodeTagTypes(store: NodeStore) {
        
        var fixedCount = 0
        var nodesToUpdate: [(Node, [Tag])] = []
        
        for node in store.nodes {
            var needsUpdate = false
            var newTags: [Tag] = []
            
            for tag in node.tags {
                if case .custom(let customName) = tag.type {
                    // 检查是否有对应的映射，其中typeName == customName但key != customName
                    if let correctMapping = tagMappings.first(where: { $0.typeName == customName && $0.key != customName }) {
                        // 发现错误：标签类型应该是.custom(key)而不是.custom(typeName)
                        let correctTagType = Tag.TagType.custom(correctMapping.key)
                        let correctedTag = Tag(
                            type: correctTagType,
                            value: tag.value,
                            latitude: tag.latitude,
                            longitude: tag.longitude
                        )
                        newTags.append(correctedTag)
                        needsUpdate = true
                        fixedCount += 1
                    } else {
                        newTags.append(tag)
                    }
                } else {
                    newTags.append(tag)
                }
            }
            
            if needsUpdate {
                nodesToUpdate.append((node, newTags))
            }
        }
        
        // 批量更新节点
        for (node, newTags) in nodesToUpdate {
            store.updateNodeTags(node.id, tags: newTags)
        }
        
        if fixedCount > 0 {
        } else {
        }
    }
    
    // 🔧 已移除强制重建beef映射功能，允许用户永久删除beef映射
    // func forceRebuildBeefMapping() { ... }
    
    // 重置为默认映射
    func resetToDefaults() {
        
        // 只包含内置核心标签，不再自动添加其他预设标签
        tagMappings = Self.builtInCoreTags
        
        
        saveToUserDefaults()
        
        // 同步到外部存储
        Task {
            do {
                try await ExternalDataService.shared.saveTagMappingsOnly()
            } catch {
            }
        }
        
    }
    
    // 完全清空所有标签映射（用于彻底清除数据）
    func clearAll() {
        
        tagMappings.removeAll()
        
        
        saveToUserDefaults()
        
        // 同步到外部存储
        Task {
            do {
                try await ExternalDataService.shared.saveTagMappingsOnly()
            } catch {
            }
        }
        
    }
    
    // 公共方法：重新从外部存储加载标签映射（用于切换位置时）
    @MainActor
    public func reloadFromExternalStorage() async {
        await loadFromExternalStorageOrFallback()
    }
    
    // 重新扫描现有标签并更新映射
    @MainActor
    func rescanAndUpdateMappings() {
        
        // 保留现有的映射，只添加缺失的自动扫描映射
        let currentMappings = tagMappings
        let scannedMappings = getDefaultMappings()
        
        // 合并映射：保留现有映射，只添加新发现的
        var finalMappings = currentMappings
        
        for scannedMapping in scannedMappings {
            if !finalMappings.contains(where: { $0.key == scannedMapping.key }) {
                finalMappings.append(scannedMapping)
            }
        }
        
        // 🔧 修复错误的映射：检查节点中的实际标签值来推断正确的显示名称
        fixIncorrectMappings(&finalMappings)
        
        tagMappings = finalMappings
        
        // 保存到外部存储
        Task {
            try? await ExternalDataService.shared.saveTagMappingsOnly()
        }
    }
    
    // 公开方法：立即修复标签映射
    public func fixTagMappings() async {
        await MainActor.run {
            var currentMappings = tagMappings
            fixIncorrectMappings(&currentMappings)
            tagMappings = currentMappings
        }
        
        // 保存到外部存储
        try? await ExternalDataService.shared.saveTagMappingsOnly()
    }
    
    // 修复错误的标签映射
    private func fixIncorrectMappings(_ mappings: inout [TagMapping]) {
        
        // 检查每个映射是否正确
        for (index, mapping) in mappings.enumerated() {
            // 特别检查 "oo" 映射的情况
            if mapping.key == "oo" && mapping.typeName == "oo" {
                let correctTypeName = "好看" // 基于用户反馈的正确映射
                
                let correctedMapping = TagMapping(
                    id: mapping.id,
                    key: mapping.key,
                    typeName: correctTypeName
                )
                mappings[index] = correctedMapping
            }
            
            // 通用修复逻辑：如果key和typeName相同，但实际使用中应该有更好的显示名称
            if mapping.key == mapping.typeName {
                // 这里可以添加更多的修复逻辑
                // 对于现在的问题，主要是修复 "oo" 的情况
            }
        }
        
    }
    
    // 获取默认映射
    @MainActor
    private func getDefaultMappings() -> [TagMapping] {
        // 只包含内置核心标签，不再自动添加commonTags
        var mappings = Self.builtInCoreTags
        
        // 扫描现有节点中的标签，自动创建缺失的映射
        let store = NodeStore.shared
        let allTags = store.allTags
        
        
        // 详细调试输出
        for tag in allTags {
            if case .custom(let key) = tag.type {
                // 检查是否已有映射
                if !mappings.contains(where: { $0.key == key.lowercased() }) {
                    let newMapping = TagMapping(key: key.lowercased(), typeName: key)
                    mappings.append(newMapping)
                } else {
                }
            } else {
            }
        }
        
        return mappings
    }
    
    // 优先从外部存储加载，失败时从UserDefaults加载
    @MainActor
    private func loadFromExternalStorageOrFallback() async {
        
        do {
            // 尝试从外部存储加载
            if let url = ExternalDataManager.shared.getTagMappingsURL(),
               FileManager.default.fileExists(atPath: url.path) {
                
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let loadedMappings = try decoder.decode([TagMapping].self, from: data)
                
                await MainActor.run {
                    tagMappings = loadedMappings
                    
                    // 确保包含内置核心标签
                    ensureBuiltInCoreTags()
                    
                    // 同步到UserDefaults作为备份
                    saveToUserDefaults()
                }
                return
            }
        } catch {
        }
        
        // 外部存储失败，尝试从UserDefaults加载
        loadTagMappingsFromUserDefaults()
    }
    
    // 从UserDefaults加载（作为fallback）
    @MainActor
    private func loadTagMappingsFromUserDefaults() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let savedMappings = try? decoder.decode([TagMapping].self, from: data) {
            tagMappings = savedMappings
            
            // 确保包含内置核心标签
            ensureBuiltInCoreTags()
            
            // 迁移：确保包含新的默认映射
            migrateToLatestMappings()
            
            // 同步到外部存储
            Task {
                do {
                    try await ExternalDataService.shared.saveTagMappingsOnly()
                } catch {
                }
            }
        } else {
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

// MARK: - Mapping Conflict Result

enum MappingConflictResult {
    case canCreate
    case noConflict(TagMapping) // 已存在相同的映射
    case conflict(existing: TagMapping, requested: String) // 冲突：key相同但typeName不同
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
    @State private var showingTagModificationAlert = false
    
    // 新增：支持预填充节点（用于编辑模式）
    let prefilledNode: Node?
    // 新增：窗口ID，用于正确路由通知
    let windowId: UUID?
    
    // 初始化器，支持可选的预填充节点和窗口ID
    init(prefilledNode: Node? = nil, windowId: UUID? = nil) {
        self.prefilledNode = prefilledNode
        self.windowId = windowId
    }
    
    var body: some View {
        mainView
            .frame(width: 600)
            .navigationTitle(prefilledNode != nil ? "编辑节点" : "快速添加节点")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        cleanupAndDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(prefilledNode != nil ? "保存" : "添加") {
                        processInput()
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
            .alert("重复检测", isPresented: $showingDuplicateAlert) {
                if let alert = store.duplicateNodeAlert {
                    if alert.isContextConflict {
                        // 上下文冲突：提供强制添加选项
                        Button("取消", role: .cancel) { 
                            showingDuplicateAlert = false
                            cleanupAndDismiss()
                        }
                        Button("忽略冲突，强制添加") {
                            // 强制添加节点
                            let success = store.forceAddNode(alert.newNode, ignoreConflicts: true)
                            if success {
                                inputText = ""
                                dismiss()
                            }
                            store.duplicateNodeAlert = nil
                        }
                        Button("查看详情") {
                            // 显示详细的冲突信息
                            if alert.conflictDetails != nil {
                            }
                            store.duplicateNodeAlert = nil
                        }
                    } else if alert.isDuplicate && alert.existingNode != nil {
                        // 节点重复，询问是否合并
                        Button("取消", role: .cancel) { 
                            showingDuplicateAlert = false
                            cleanupAndDismiss()
                        }
                        Button("合并标签") {
                            // 执行标签合并
                            if let existingNode = alert.existingNode {
                                let newTags = alert.newNode.tags.filter { newTag in
                                    !existingNode.tags.contains { existingTag in
                                        existingTag.type == newTag.type && existingTag.value.lowercased() == newTag.value.lowercased()
                                    }
                                }
                                
                                for tag in newTags {
                                    store.addTag(to: existingNode.id, tag: tag)
                                }
                                
                                inputText = ""
                                dismiss()
                            }
                            store.duplicateNodeAlert = nil
                        }
                        Button("创建新节点") {
                            // 强制添加新节点
                            let success = store.forceAddNode(alert.newNode, ignoreConflicts: true)
                            if success {
                                inputText = ""
                                dismiss()
                            }
                            store.duplicateNodeAlert = nil
                        }
                    } else {
                        // 其他错误或信息
                        Button("确定") { 
                            store.duplicateNodeAlert = nil
                            showingDuplicateAlert = false
                        }
                    }
                } else {
                    Button("确定") { }
                }
            } message: {
                if let alert = store.duplicateNodeAlert {
                    Text(alert.message)
                }
            }
            .onReceive(store.$duplicateNodeAlert) { alert in
                handleDuplicateAlert(alert)
            }
            .alert("标签类型修改确认", isPresented: $showingTagModificationAlert) {
                if let alert = store.tagTypeModificationAlert {
                    Button("取消", role: .cancel) {
                        alert.onCancel()
                    }
                    Button("确认修改") {
                        alert.onConfirm()
                    }
                } else {
                    Button("确定") { }
                }
            } message: {
                if let alert = store.tagTypeModificationAlert {
                    Text(alert.message)
                }
            }
            .onReceive(store.$tagTypeModificationAlert) { alert in
                if alert != nil {
                    showingTagModificationAlert = true
                } else {
                    showingTagModificationAlert = false
                }
            }
            .onAppear {
                setupView()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("emergencyWindowCleanup"))) { _ in
                cleanupAndDismiss()
            }
            .onKeyPress(.escape) {
                cleanupAndDismiss()
                return .handled
            }
            .onKeyPress(.init("p"), phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) && isInputFocused {
                    // 🔧 修复：只在当前窗口有焦点时响应Command+P
                    guard let windowId = windowId, WindowFocusManager.shared.isActiveWindow(windowId) else {
                        return .ignored
                    }
                    
                    openMapForLocationSelection()
                    return .handled
                }
                return .ignored
            }
            // Command+Shift+R 功能已废除，改用统一的 Command+R
    }
    
    @ViewBuilder
    private var mainView: some View {
        VStack(spacing: 0) {
            inputSection
            Divider()
            suggestionsList
            emptyStateView
        }
    }
    
    @ViewBuilder
    private var inputSection: some View {
        HStack {
            Image(systemName: "plus.circle.fill")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                TextField("输入：@引用节点1 @ 引用节点2 节点 shortcut[标签类型] 标签值", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isInputFocused)
                    .onChange(of: inputText) { _, newValue in 
                        updateSuggestions(for: newValue) 
                    }
                    .onKeyPress(.upArrow) { handleUpArrow() }
                    .onKeyPress(.downArrow) { handleDownArrow() }
                    .onKeyPress(.tab) { handleTab() }
                    .onKeyPress(.escape) { handleEscape() }
                
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
    }
    
    @ViewBuilder
    private var suggestionsList: some View {
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
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        if suggestions.isEmpty && !inputText.isEmpty {
            VStack {
                Text("输入标签快捷键获得建议")
                    .foregroundColor(.secondary)
                    .padding()
            }
            .frame(height: 100)
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleUpArrow() -> KeyPress.Result {
        if !suggestions.isEmpty {
            selectedSuggestionIndex = max(0, selectedSuggestionIndex - 1)
        }
        return .handled
    }
    
    private func handleDownArrow() -> KeyPress.Result {
        if !suggestions.isEmpty {
            selectedSuggestionIndex = min(suggestions.count - 1, selectedSuggestionIndex + 1)
        }
        return .handled
    }
    
    private func handleTab() -> KeyPress.Result {
        if selectedSuggestionIndex >= 0 && selectedSuggestionIndex < suggestions.count {
            selectSuggestion(suggestions[selectedSuggestionIndex])
        }
        return .handled
    }
    
    private func handleEscape() -> KeyPress.Result {
        cleanupAndDismiss()
        return .handled
    }
    
    private func cleanupAndDismiss() {
        
        // 立即清理状态
        isInputFocused = false
        inputText = ""
        selectedSuggestionIndex = -1
        suggestions = []
        showingDuplicateAlert = false
        showingTagModificationAlert = false
        isWaitingForLocationSelection = false
        
        // 使用异步方式清理Store状态，避免在view更新期间修改状态
        DispatchQueue.main.async {
            self.store.duplicateNodeAlert = nil
            self.store.tagTypeModificationAlert = nil
        }
        
        // 立即调用dismiss，不使用延迟
        dismiss()
        
    }
    
    private func processCompoundNodeInput() {
        
        let components = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        
        guard components.count >= 2 else {
            store.duplicateNodeAlert = NodeStore.DuplicateNodeAlert(
                message: "复合节点语法错误：至少需要 '复合节点名 子节点1'",
                isDuplicate: false,
                existingNode: nil,
                newNode: Node(text: "错误命令", layerId: UUID(), tags: [])
            )
            return
        }
        
        let compoundNodeName = components[0]
        let childNodeNames = Array(components[1...])
        
        
        guard let currentLayer = store.currentLayer else {
            store.duplicateNodeAlert = NodeStore.DuplicateNodeAlert(
                message: "无法创建复合节点：请先选择一个活跃层",
                isDuplicate: false,
                existingNode: nil,
                newNode: Node(text: compoundNodeName, layerId: UUID(), tags: [])
            )
            return
        }
        
        // 检查是否有删除操作（子节点名以"-"开头）
        let (childNamesToAdd, childNamesToRemove) = separateAddAndRemoveOperations(childNodeNames)
        
        // 检查复合节点是否已存在
        if let existingCompoundNode = store.nodes.first(where: { 
            $0.text.lowercased() == compoundNodeName.lowercased() && $0.isCompound 
        }) {
            // 修改已存在的复合节点
            if !childNamesToRemove.isEmpty {
                removeChildrenFromCompoundNode(existingCompoundNode, childNames: childNamesToRemove)
            }
            if !childNamesToAdd.isEmpty {
                addChildrenToExistingCompoundNode(existingCompoundNode, childNames: childNamesToAdd)
            }
        } else if !childNamesToRemove.isEmpty {
            // 尝试删除子节点但复合节点不存在
            store.duplicateNodeAlert = NodeStore.DuplicateNodeAlert(
                message: "错误：复合节点 '\(compoundNodeName)' 不存在，无法删除子节点",
                isDuplicate: false,
                existingNode: nil,
                newNode: Node(text: compoundNodeName, layerId: currentLayer.id, tags: [])
            )
            return
        } else {
            // 创建新的复合节点
            createNewCompoundNode(name: compoundNodeName, childNames: childNamesToAdd, layerId: currentLayer.id)
        }
        
        // 成功处理后清空输入并关闭
        inputText = ""
        dismiss()
        
    }
    
    // 🆕 处理混合语法：复合节点引用 + 普通标签
    private func processMixedCompoundNodeInput(_ components: [String]) throws {
        
        guard !components.isEmpty else { return }
        
        let nodeText = components[0]
        var childNodeNames: [String] = []
        var normalTags: [Tag] = []
        var i = 1
        
        // 第一遍：提取所有 @节点引用
        while i < components.count {
            if components[i].hasPrefix("@") {
                let childName = String(components[i].dropFirst()) // 去掉@前缀
                childNodeNames.append(childName)
                i += 1
            } else {
                break // 遇到非@开头的，停止提取子节点
            }
        }
        
        // 第二遍：解析剩余的普通标签
        while i < components.count {
            let tagKey = components[i]
            
            // 🔧 特殊处理：如果是"loc"且后面跟坐标格式，直接处理整个坐标表达式
            if tagKey.lowercased() == "loc" && i + 1 < components.count {
                let nextComponent = components[i + 1]
                // 检查是否是坐标格式：@纬度,经度[名称] 或类似格式
                if nextComponent.hasPrefix("@") && (nextComponent.contains(",") || nextComponent.contains("[")) {
                    
                    // 解析坐标
                    var locationName: String = ""
                    var lat: Double = 0
                    var lng: Double = 0
                    var parsed = false
                    
                    let coordContent = nextComponent
                    
                    // 格式: @纬度,经度[名称]
                    if coordContent.hasPrefix("@") && coordContent.contains("[") && coordContent.contains("]") {
                        if let atIndex = coordContent.firstIndex(of: "@"),
                           let bracketIndex = coordContent.firstIndex(of: "["),
                           atIndex < bracketIndex && coordContent.index(after: atIndex) <= bracketIndex {
                            let coordString = String(coordContent[coordContent.index(after: atIndex)..<bracketIndex])
                            let coords = coordString.split(separator: ",")
                            
                            if coords.count == 2,
                               let latitude = Double(coords[0]),
                               let longitude = Double(coords[1]) {
                                lat = latitude
                                lng = longitude
                                
                                if let startBracket = coordContent.firstIndex(of: "["),
                                   let endBracket = coordContent.firstIndex(of: "]"),
                                   startBracket < endBracket && coordContent.index(after: startBracket) <= endBracket {
                                    locationName = String(coordContent[coordContent.index(after: startBracket)..<endBracket])
                                    parsed = true
                                }
                            }
                        }
                    }
                    
                    if parsed && !locationName.isEmpty {
                        let locationType = Tag.TagType.custom("loc")
                        let tag = store.createTag(type: locationType, value: locationName, latitude: lat, longitude: lng)
                        normalTags.append(tag)
                    } else {
                        // 解析失败，作为普通标签处理
                        let locationType = Tag.TagType.custom("loc")
                        let tag = Tag(type: locationType, value: nextComponent)
                        normalTags.append(tag)
                    }
                    
                    i += 2 // 跳过 loc 和坐标部分
                    continue
                }
            }
            
            // 检查是否是标签重命名语法: tagtype[newName]
            if tagKey.contains("[") && tagKey.contains("]") {
                if let startBracket = tagKey.firstIndex(of: "["),
                   let endBracket = tagKey.firstIndex(of: "]"),
                   startBracket < endBracket {
                    
                    let actualTagKey = String(tagKey[..<startBracket])
                    let newTypeName = String(tagKey[tagKey.index(after: startBracket)..<endBracket])
                    
                    // 处理标签重命名（复用现有逻辑）
                    if let existingMapping = tagManager.tagMappings.first(where: { $0.key == actualTagKey }) {
                        let oldTypeName = existingMapping.typeName
                        if oldTypeName != newTypeName {
                            let updatedMapping = TagMapping(
                                id: existingMapping.id,
                                key: actualTagKey,
                                typeName: newTypeName
                            )
                            tagManager.saveMapping(updatedMapping)
                        }
                    } else {
                        let newMapping = TagMapping(key: actualTagKey, typeName: newTypeName)
                        tagManager.addMapping(newMapping)
                    }
                    
                    // 使用实际的tagKey创建标签
                    if let tagType = tagManager.parseTokenToTagTypeWithStore(actualTagKey, store: store) {
                        if i + 1 < components.count {
                            let content = components[i + 1]
                            let tag = Tag(type: tagType, value: content, isShortcutType: true)
                            normalTags.append(tag)
                            i += 2
                        } else {
                            i += 1
                        }
                    } else {
                        i += 1
                    }
                    continue
                }
            }
            
            // 普通标签处理
            if let tagType = tagManager.parseTokenToTagTypeWithStore(tagKey, store: store) {
                if i + 1 < components.count {
                    let content = components[i + 1]
                    
                    // 检查是否是地图标签
                    if tagManager.isLocationTagKey(tagKey) {
                        // 地图标签处理逻辑（复用现有逻辑）
                        var locationName: String = ""
                        var lat: Double = 0
                        var lng: Double = 0
                        var parsed = false
                        
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
                        
                        if parsed && !locationName.isEmpty {
                            let tag = store.createTag(type: tagType, value: locationName, latitude: lat, longitude: lng)
                            normalTags.append(tag)
                        } else {
                            let tag = Tag(type: tagType, value: content)
                            normalTags.append(tag)
                        }
                    } else {
                        // 普通标签
                        let tag = Tag(type: tagType, value: content, isShortcutType: true)
                        normalTags.append(tag)
                    }
                    i += 2
                } else {
                    i += 1
                }
            } else {
                i += 1
            }
        }
        
        // 检查层级可用性
        guard let layerId = store.currentLayer?.id ?? store.layers.first?.id else {
            store.duplicateNodeAlert = NodeStore.DuplicateNodeAlert(
                message: "无法添加节点：请先创建至少一个层",
                isDuplicate: false,
                existingNode: nil,
                newNode: Node(text: nodeText, layerId: UUID(), tags: [])
            )
            return
        }
        
        // 如果有子节点引用，创建/更新复合节点
        if !childNodeNames.isEmpty {
            
            // 检查复合节点是否已存在
            if let existingCompoundNode = store.nodes.first(where: { 
                $0.text.lowercased() == nodeText.lowercased() && $0.isCompound 
            }) {
                // 更新已存在的复合节点
                updateExistingCompoundNode(existingCompoundNode, childNames: childNodeNames, additionalTags: normalTags)
            } else {
                // 创建新的复合节点
                createNewMixedCompoundNode(name: nodeText, childNames: childNodeNames, additionalTags: normalTags, layerId: layerId)
            }
        } else {
            // 没有子节点引用，按普通节点处理
            let newNode = Node(text: nodeText, layerId: layerId, tags: normalTags)
            let success = store.addNode(newNode)
            if success {
                inputText = ""
                dismiss()
            }
        }
    }
    
    // 🆕 更新已存在的复合节点，添加新的子节点和标签
    private func updateExistingCompoundNode(_ compoundNode: Node, childNames: [String], additionalTags: [Tag]) {
        var allTags = compoundNode.tags
        
        // 添加新的子节点引用
        for childName in childNames {
            let childReferenceTag = Tag(
                type: .custom("child"),
                value: childName
            )
            allTags.append(childReferenceTag)
        }
        
        // 添加普通标签
        allTags.append(contentsOf: additionalTags)
        
        // 计算更新后的层级
        let existingChildCount = compoundNode.tags.compactMap { tag in
            if case .custom(let key) = tag.type, key == "child" {
                return tag.value
            }
            return nil
        }.count
        
        _ = existingChildCount + childNames.count // 保持代码完整性，实际未使用
        let childDepth = calculateMaxChildDepth(childNames: childNames)
        let currentDepth = max(compoundNode.getCompoundDepth(allNodes: store.nodes), childDepth + 1)
        
        // 更新复合节点标签（简化的层级显示）
        let updatedTags = allTags.map { tag in
            if case .custom(let key) = tag.type, key == "compound" {
                return Tag(type: .custom("compound"), value: "\(currentDepth)级复合节点")
            }
            return tag
        }
        
        store.updateNodeTags(compoundNode.id, tags: updatedTags)
        store.updateNode(compoundNode.id, text: nil, phonetic: nil, meaning: "\(currentDepth)级复合节点")
        
        // 确保子节点存在
        ensureChildNodesExist(childNames: childNames, layerId: compoundNode.layerId)
        
        // 成功后关闭
        inputText = ""
        dismiss()
        
    }
    
    // 🆕 创建新的混合复合节点（包含子节点引用和普通标签）
    private func createNewMixedCompoundNode(name: String, childNames: [String], additionalTags: [Tag], layerId: UUID) {
        var compoundTags: [Tag] = []
        
        // 计算复合节点层级
        let childDepth = calculateMaxChildDepth(childNames: childNames)
        let currentDepth = childDepth + 1
        
        // 主复合节点标签（简化显示）
        let compoundTag = Tag(
            type: .custom("compound"),
            value: "\(currentDepth)级复合节点"
        )
        compoundTags.append(compoundTag)
        
        // 为每个子节点创建引用标签
        for childName in childNames {
            let childReferenceTag = Tag(
                type: .custom("child"),
                value: childName
            )
            compoundTags.append(childReferenceTag)
        }
        
        // 添加普通标签
        compoundTags.append(contentsOf: additionalTags)
        
        
        // 创建复合节点（简化的meaning显示）
        let compoundNode = Node(
            text: name,
            phonetic: nil,
            meaning: "\(currentDepth)级复合节点",
            layerId: layerId,
            tags: compoundTags
        )
        
        // 确保子节点存在
        ensureChildNodesExist(childNames: childNames, layerId: layerId)
        
        // 添加复合节点到store
        let success = store.addNode(compoundNode)
        if success {
            inputText = ""
            dismiss()
        }
        
    }
    
    // 🆕 确保子节点存在的辅助函数
    private func ensureChildNodesExist(childNames: [String], layerId: UUID) {
        for childName in childNames {
            if store.nodes.first(where: { $0.text.lowercased() == childName.lowercased() }) != nil {
            } else {
                let childNode = Node(
                    text: childName,
                    phonetic: nil,
                    meaning: nil,
                    layerId: layerId,
                    tags: []
                )
                _ = store.addNode(childNode)
            }
        }
    }
    
    private func handleDuplicateAlert(_ alert: NodeStore.DuplicateNodeAlert?) {
        if alert != nil {
            showingDuplicateAlert = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                store.duplicateNodeAlert = nil
            }
        }
    }
    
    private func setupView() {
        setupPrefilledNode()
        setupAutoFocus()
        setupLocationNotifications()
    }
    
    private func setupPrefilledNode() {
        if let node = prefilledNode {
            for (_, _) in node.tags.enumerated() {
            }
            
            // 使用动态版本，传入所有节点以获得实时的子节点信息
            inputText = node.dynamicCommandRepresentationWithDisplayNames(allNodes: store.nodes)
        }
    }
    
    private func setupAutoFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isInputFocused = true
        }
    }
    
    private func setupLocationNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("locationSelected"),
            object: nil,
            queue: .main
        ) { notification in
            if let locationData = notification.object as? [String: Any],
               let latitude = locationData["latitude"] as? Double,
               let longitude = locationData["longitude"] as? Double {
                
                // 始终只使用坐标，保持[]为空，让用户自己输入地名
                let locationCommand = "@\(latitude),\(longitude)[]"
                insertLocationIntoInput(locationCommand)
            } else if let locationName = notification.object as? String {
                insertLocationIntoInput("location \(locationName)")
            }
        }
        
        // 监听复合节点刷新通知
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("compoundNodeRefreshed"),
            object: nil,
            queue: .main
        ) { notification in
            // 检查是否是当前编辑的节点需要刷新
            if let node = prefilledNode,
               let compoundNodeId = notification.userInfo?["compoundNodeId"] as? UUID,
               compoundNodeId == node.id {
                
                // 使用MainActor.run确保线程安全
                Task { @MainActor in
                    // 重新生成输入文本
                    let updatedNode = store.nodes.first { $0.id == node.id } ?? node
                    inputText = updatedNode.dynamicCommandRepresentationWithDisplayNames(allNodes: store.nodes)
                    
                }
            }
        }
    }
    
    private func updateSuggestions(for input: String) {
        let words = input.split(separator: " ")
        guard let lastWord = words.last, !lastWord.isEmpty else { 
            suggestions = []
            selectedSuggestionIndex = -1
            return 
        }
        
        let query = String(lastWord)
        
        // 检查是否是节点引用格式（@节点名）
        if query.hasPrefix("@") {
            let nodeQuery = String(query.dropFirst()) // 去掉@前缀
            
            // 只从节点名搜索
            let nodeResults = fuzzySearchNodes(query: nodeQuery, limit: 10)
            
            // 为结果添加@前缀
            let nodesSuggestions = nodeResults.map { ("@\($0.0)", $0.1) }
            
            let sortedSuggestions = nodesSuggestions.sorted { $0.1 > $1.1 }.map { $0.0 }
            suggestions = Array(sortedSuggestions.prefix(10))
        } else {
            // 普通查询：混合搜索标签类型和节点名
            
            // 使用模糊搜索获取标签建议
            let tagResults = fuzzySearchStrings(Array(tagManager.mappingDictionary.keys), query: query, limit: 5)
            
            // 手动实现节点模糊搜索
            let nodeResults = fuzzySearchNodes(query: query, limit: 5)
            
            // 合并并按分数排序
            var allSuggestions: [(String, Double)] = []
            allSuggestions += tagResults.map { ($0.item, $0.score) }
            allSuggestions += nodeResults
            
            // 去重，保留分数更高的
            let uniqueSuggestions = Dictionary(allSuggestions, uniquingKeysWith: max)
            let sortedSuggestions = uniqueSuggestions.sorted { $0.value > $1.value }.map { $0.key }
            
            suggestions = Array(sortedSuggestions.prefix(10))
        }
        
        selectedSuggestionIndex = suggestions.isEmpty ? -1 : 0
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
        
        // 🔧 添加异常保护，避免命令解析时崩溃
        do {
            try processInputSafely()
        } catch {
            // 显示友好的错误信息
            store.duplicateNodeAlert = NodeStore.DuplicateNodeAlert(
                message: "命令处理失败: \(error.localizedDescription)",
                isDuplicate: false,
                existingNode: nil,
                newNode: Node(text: "错误", layerId: UUID(), tags: [])
            )
        }
    }
    
    /// 智能分词函数，识别括号结构，避免破坏坐标表达式
    private func smartTokenize(_ input: String) -> [String] {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var tokens: [String] = []
        var currentToken = ""
        var bracketDepth = 0
        var i = trimmedInput.startIndex
        
        while i < trimmedInput.endIndex {
            let char = trimmedInput[i]
            
            if char == "[" {
                bracketDepth += 1
                currentToken.append(char)
            } else if char == "]" {
                bracketDepth -= 1
                currentToken.append(char)
            } else if char == " " && bracketDepth == 0 {
                // 只有在括号外的空格才作为分词依据
                if !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
            } else {
                currentToken.append(char)
            }
            
            i = trimmedInput.index(after: i)
        }
        
        // 添加最后一个token
        if !currentToken.isEmpty {
            tokens.append(currentToken)
        }
        
        return tokens
    }
    
    private func processInputSafely() throws {
        let components = smartTokenize(inputText)
        
        guard !components.isEmpty else { 
            return 
        }
        
        // 🔧 检测是否包含节点引用（@节点名），如果有则进行混合处理
        let hasNodeReferences = components.contains { $0.hasPrefix("@") }
        if hasNodeReferences {
            try processMixedCompoundNodeInput(components)
            return
        }
        
        
        let nodeText = components[0]
        var tags: [Tag] = []
        var i = 1
        
        
        while i < components.count {
            let tagKey = components[i]
            
            // 🔧 特殊处理：如果是"loc"且后面跟坐标格式，直接处理整个坐标表达式
            if tagKey.lowercased() == "loc" && i + 1 < components.count {
                let nextComponent = components[i + 1]
                // 检查是否是坐标格式：@纬度,经度[名称] 或类似格式
                if nextComponent.hasPrefix("@") && (nextComponent.contains(",") || nextComponent.contains("[")) {
                    
                    // 解析坐标
                    var locationName: String = ""
                    var lat: Double = 0
                    var lng: Double = 0
                    var parsed = false
                    
                    let coordContent = nextComponent
                    
                    // 格式: @纬度,经度[名称]
                    if coordContent.hasPrefix("@") && coordContent.contains("[") && coordContent.contains("]") {
                        if let atIndex = coordContent.firstIndex(of: "@"),
                           let bracketIndex = coordContent.firstIndex(of: "["),
                           atIndex < bracketIndex && coordContent.index(after: atIndex) <= bracketIndex {
                            let coordString = String(coordContent[coordContent.index(after: atIndex)..<bracketIndex])
                            let coords = coordString.split(separator: ",")
                            
                            if coords.count == 2,
                               let latitude = Double(coords[0]),
                               let longitude = Double(coords[1]) {
                                lat = latitude
                                lng = longitude
                                
                                if let startBracket = coordContent.firstIndex(of: "["),
                                   let endBracket = coordContent.firstIndex(of: "]"),
                                   startBracket < endBracket && coordContent.index(after: startBracket) <= endBracket {
                                    locationName = String(coordContent[coordContent.index(after: startBracket)..<endBracket])
                                    parsed = true
                                }
                            }
                        }
                    }
                    
                    if parsed && !locationName.isEmpty {
                        let locationType = Tag.TagType.custom("loc")
                        let tag = store.createTag(type: locationType, value: locationName, latitude: lat, longitude: lng)
                        tags.append(tag)
                    } else {
                        // 解析失败，作为普通标签处理
                        let locationType = Tag.TagType.custom("loc")
                        let tag = Tag(type: locationType, value: nextComponent)
                        tags.append(tag)
                    }
                    
                    i += 2 // 跳过 loc 和坐标部分
                    continue
                }
            }
            
            // 检查是否是标签重命名语法: tagtype[newName]
            if tagKey.contains("[") && tagKey.contains("]") {
                if let startBracket = tagKey.firstIndex(of: "["),
                   let endBracket = tagKey.firstIndex(of: "]"),
                   startBracket < endBracket {
                    
                    let actualTagKey = String(tagKey[..<startBracket])
                    let newTypeName = String(tagKey[tagKey.index(after: startBracket)..<endBracket])
                    
                    
                    // 🔧 检查是否正在修改已存在的标签类型名称
                    if let existingMapping = tagManager.tagMappings.first(where: { $0.key == actualTagKey }) {
                        let oldTypeName = existingMapping.typeName
                        
                        // 如果新名称与旧名称不同，需要用户确认
                        if oldTypeName != newTypeName {
                            // 计算会受影响的节点数量
                            let affectedNodes = store.nodes.filter { node in
                                node.tags.contains { tag in
                                    if case .custom(let key) = tag.type {
                                        return key == actualTagKey
                                    }
                                    return false
                                }
                            }
                            
                            
                            // 暂停处理，显示确认对话框
                            store.tagTypeModificationAlert = NodeStore.TagTypeModificationAlert(
                                message: "你正在修改标签类型 '\(actualTagKey)' 的显示名称：\n从 '\(oldTypeName)' 改为 '\(newTypeName)'\n这将影响 \(affectedNodes.count) 个节点的显示。",
                                tagKey: actualTagKey,
                                oldTypeName: oldTypeName,
                                newTypeName: newTypeName,
                                affectedNodesCount: affectedNodes.count,
                                pendingCommand: inputText,
                                onConfirm: {
                                    // 用户确认修改，执行标签重命名
                                    let updatedMapping = TagMapping(
                                        id: existingMapping.id,
                                        key: actualTagKey,
                                        typeName: newTypeName
                                    )
                                    tagManager.saveMapping(updatedMapping)
                                    
                                    // 清除alert状态
                                    store.tagTypeModificationAlert = nil
                                    
                                    // 继续处理完整命令
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        // 简单清除输入
                                        inputText = ""
                                    }
                                },
                                onCancel: {
                                    // 用户取消修改，清空输入
                                    inputText = ""
                                    store.tagTypeModificationAlert = nil
                                }
                            )
                            
                            return // 暂停处理，等待用户确认
                        } else {
                            // 名称相同，正常处理
                        }
                    } else {
                        // 新标签映射，正常处理
                        let newMapping = TagMapping(key: actualTagKey, typeName: newTypeName)
                        tagManager.addMapping(newMapping)
                    }
                    
                    // 重命名完成后，继续处理标签创建
                    // 使用实际的tagKey来创建标签类型和标签
                    
                    if let tagType = tagManager.parseTokenToTagTypeWithStore(actualTagKey, store: store) {
                        if i + 1 < components.count { 
                            let content = components[i + 1]
                            
                            // 检查是否是地图标签（通过key识别）
                            if tagManager.isLocationTagKey(actualTagKey) {
                                // 地图标签处理逻辑（保持原有逻辑）
                                var locationName: String = ""
                                var lat: Double = 0
                                var lng: Double = 0
                                var parsed = false
                                
                                // 格式检查逻辑（保持原有的地图标签解析逻辑）
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
                                else if content.hasPrefix("@") && content.contains("[") && content.contains("]") {
                                    if let atIndex = content.firstIndex(of: "@"),
                                       let bracketIndex = content.firstIndex(of: "["),
                                       atIndex < bracketIndex && content.index(after: atIndex) <= bracketIndex {
                                        let coordString = String(content[content.index(after: atIndex)..<bracketIndex])
                                        let coords = coordString.split(separator: ",")
                                        
                                        if coords.count == 2,
                                           let latitude = Double(coords[0]),
                                           let longitude = Double(coords[1]) {
                                            lat = latitude
                                            lng = longitude
                                            
                                            if let startBracket = content.firstIndex(of: "["),
                                               let endBracket = content.firstIndex(of: "]"),
                                               startBracket < endBracket && content.index(after: startBracket) <= endBracket {
                                                locationName = String(content[content.index(after: startBracket)..<endBracket])
                                                parsed = true
                                            }
                                        }
                                    }
                                }
                                else if !content.contains("@") && !content.contains("[") && !content.contains("]") {
                                    if let existingTag = store.findLocationTagByName(content) {
                                        locationName = existingTag.value
                                        if let existingLat = existingTag.latitude, let existingLng = existingTag.longitude {
                                            lat = existingLat
                                            lng = existingLng
                                            parsed = true
                                        }
                                    }
                                }
                                
                                if parsed && !locationName.isEmpty {
                                    let tag = store.createTag(type: tagType, value: locationName, latitude: lat, longitude: lng)
                                    tags.append(tag)
                                } else if !content.contains("@") {
                                    let tag = Tag(type: tagType, value: content)
                                    tags.append(tag)
                                } else {
                                    let tag = Tag(type: tagType, value: content)
                                    tags.append(tag)
                                }
                            } else {
                                // 普通标签
                                let tag = Tag(type: tagType, value: content, isShortcutType: true)
                                tags.append(tag)
                            }
                            
                            i += 2 // 跳过tagType和value
                        } else {
                            i += 1
                        }
                    } else {
                        i += 1
                    }
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
                               let bracketIndex = content.firstIndex(of: "["),
                               atIndex < bracketIndex && content.index(after: atIndex) <= bracketIndex {
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
                                       startBracket < endBracket && content.index(after: startBracket) <= endBracket {
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
                                }
                            }
                        }
                        
                        if parsed && !locationName.isEmpty {
                            let tag = store.createTag(type: tagType, value: locationName, latitude: lat, longitude: lng)
                            tags.append(tag)
                        } else if !content.contains("@") {
                            // 如果是location标签但没有找到匹配的位置，提示用户
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
                // 触发警告
            store.duplicateNodeAlert = NodeStore.DuplicateNodeAlert(
                message: "无法添加节点：请先创建至少一个层",
                isDuplicate: false,
                existingNode: nil,
                newNode: Node(text: nodeText, layerId: UUID(), tags: [])
            )
            return
        }
        
        if let existingNode = prefilledNode {
            // 编辑模式：更新现有节点
            
            // 更新节点的基本信息
            store.updateNode(existingNode.id, text: nodeText, phonetic: nil, meaning: nil)
            
            // 更新节点的标签
            store.updateNodeTags(existingNode.id, tags: tags)
            
            inputText = ""
            dismiss()
        } else {
            // 添加模式：创建新节点
            let newNode = Node(text: nodeText, layerId: layerId, tags: tags)
            let success = store.addNode(newNode)
            inputText = ""
            if success {
                dismiss()
            }
            // 如果不成功，保持窗口打开让用户看到警告
        }
    }
    
    // 继续处理被标签修改确认中断的命令
    private func continueProcessingCommand() {
        guard let alert = store.tagTypeModificationAlert else { return }
        
        // 清除alert并继续处理原命令
        let savedCommand = alert.pendingCommand
        store.tagTypeModificationAlert = nil
        
        // 重新设置输入文本并处理
        inputText = savedCommand
        
        // 延迟一下，让alert消失后再处理
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            do {
                try self.processInputSafely()
                // 如果处理成功，清空输入并关闭窗口
                self.inputText = ""
                self.dismiss()
            } catch {
            }
        }
    }
    
    
    // 分离添加和删除操作
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
    
    // 从复合节点删除子节点
    private func removeChildrenFromCompoundNode(_ compoundNode: Node, childNames: [String]) {
        
        // 获取现有的子节点引用
        let existingChildReferences = compoundNode.tags.compactMap { tag in
            if case .custom(let key) = tag.type, key == "child" {
                return tag.value
            }
            return nil
        }
        
        // 找到要删除的子节点
        let childNamesToRemove = childNames.filter { childName in
            existingChildReferences.contains { existingChild in
                existingChild.lowercased() == childName.lowercased()
            }
        }
        
        guard !childNamesToRemove.isEmpty else {
            store.duplicateNodeAlert = NodeStore.DuplicateNodeAlert(
                message: "这些子节点不存在于复合节点中",
                isDuplicate: false,
                existingNode: compoundNode,
                newNode: compoundNode
            )
            return
        }
        
        
        // 过滤掉要删除的子节点标签
        let updatedTags = compoundNode.tags.filter { tag in
            if case .custom(let key) = tag.type, key == "child" {
                return !childNamesToRemove.contains { childName in
                    tag.value.lowercased() == childName.lowercased()
                }
            }
            return true // 保留非子节点引用标签
        }
        
        _ = existingChildReferences.count - childNamesToRemove.count
        // 计算更新后的层级深度
        let updatedDepth = compoundNode.getCompoundDepth(allNodes: store.nodes)
        let updatedMeaning = "\(updatedDepth)级复合节点"
        
        // 更新复合节点
        store.updateNodeTags(compoundNode.id, tags: updatedTags)
        store.updateNode(compoundNode.id, text: nil, phonetic: nil, meaning: updatedMeaning)
        
    }
    
    // 向已存在的复合节点添加子节点
    private func addChildrenToExistingCompoundNode(_ compoundNode: Node, childNames: [String]) {
        
        // 获取现有的子节点引用
        let existingChildReferences = compoundNode.tags.compactMap { tag in
            if case .custom(let key) = tag.type, key == "child" {
                return tag.value
            }
            return nil
        }
        
        // 过滤掉已经存在的子节点
        let newChildNames = childNames.filter { childName in
            !existingChildReferences.contains { existingChild in
                existingChild.lowercased() == childName.lowercased()
            }
        }
        
        guard !newChildNames.isEmpty else {
            store.duplicateNodeAlert = NodeStore.DuplicateNodeAlert(
                message: "这些子节点已经存在于复合节点中",
                isDuplicate: false,
                existingNode: compoundNode,
                newNode: compoundNode
            )
            return
        }
        
        
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
        // 计算更新后的层级深度
        let updatedDepth = compoundNode.getCompoundDepth(allNodes: store.nodes)
        let updatedMeaning = "\(updatedDepth)级复合节点"
        
        store.updateNodeTags(compoundNode.id, tags: updatedTags)
        store.updateNode(compoundNode.id, text: nil, phonetic: nil, meaning: updatedMeaning)
        
        // 创建或确保新子节点存在
        for childName in newChildNames {
            if store.nodes.first(where: { $0.text.lowercased() == childName.lowercased() }) != nil {
            } else {
                let childNode = Node(
                    text: childName,
                    phonetic: nil,
                    meaning: nil,
                    layerId: compoundNode.layerId,
                    tags: []
                )
                _ = store.addNode(childNode)
            }
        }
        
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
    
    // 创建新的复合节点
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
            // 处理 @节点名 格式，去掉 @ 前缀
            let actualChildName = childName.hasPrefix("@") ? String(childName.dropFirst()) : childName
            
            let childReferenceTag = Tag(
                type: .custom("child"),
                value: actualChildName
            )
            compoundTags.append(childReferenceTag)
        }
        
        
        // 创建复合节点
        let compoundNode = Node(
            text: name,
            phonetic: nil,
            meaning: "\(childDepth + 1)级复合节点",
            layerId: layerId,
            tags: compoundTags
        )
        
        // 创建或确保子节点存在
        for childName in childNames {
            // 处理 @节点名 格式，去掉 @ 前缀
            let actualChildName = childName.hasPrefix("@") ? String(childName.dropFirst()) : childName
            
            // 检查是否已存在
            if store.nodes.first(where: { $0.text.lowercased() == actualChildName.lowercased() }) != nil {
            } else {
                // 创建新的子节点
                let childNode = Node(
                    text: actualChildName,
                    phonetic: nil,
                    meaning: nil,
                    layerId: layerId,
                    tags: []
                )
                _ = store.addNode(childNode)
            }
        }
        
        // 添加复合节点到store
        _ = store.addNode(compoundNode)
        
    }
    
    private func openMapForLocationSelection() {
        isWaitingForLocationSelection = true
        
        // 🔧 修复：使用具体的窗口ID而不是通用标识符
        
        // 生成唯一的地图窗口ID
        let mapWindowId = UUID()
        
        // 发送包含具体窗口ID的通知
        let notificationData: [String: String] = [
            "requestSource": store.isSharedInstance ? "MAIN_WINDOW" : "INDEPENDENT_WINDOW",
            "windowId": windowId?.uuidString ?? "UNKNOWN",
            "targetMapWindowId": mapWindowId.uuidString
        ]
        
        NotificationCenter.default.post(
            name: NSNotification.Name("requestMapForLocationSelection"), 
            object: notificationData
        )
        
        // 🔧 延迟发送位置选择模式通知，确保地图窗口已经打开
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(
                name: NSNotification.Name("openMapForLocationSelection"), 
                object: ["requestTime": Date(), "targetWindowId": mapWindowId.uuidString]
            )
        }
    }
    
    private func insertLocationIntoInput(_ locationCommand: String) {
        
        // 在当前光标位置插入 "loc 坐标格式 "，用户需要在[]中填入地名
        let locationText = "loc \(locationCommand) "
        inputText += locationText
        isWaitingForLocationSelection = false
        
        
        // 重新聚焦到输入框
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isInputFocused = true
        }
    }
    
    // 手动实现节点模糊搜索
    private func fuzzySearchNodes(query: String, limit: Int) -> [(String, Double)] {
        guard !query.isEmpty else { return [] }
        
        let results = store.nodes.compactMap { node -> (String, Double)? in
            let score = fuzzyMatchScore(query: query, target: node.text)
            return score > 0 && node.text.lowercased() != query.lowercased()
                ? (node.text, score)
                : nil
        }
        
        return Array(results.sorted { $0.1 > $1.1 }.prefix(limit))
    }
    
    // 字符串数组模糊搜索
    private func fuzzySearchStrings(_ strings: [String], query: String, limit: Int) -> [(item: String, score: Double)] {
        guard !query.isEmpty else { return [] }
        
        let results = strings.compactMap { string -> (item: String, score: Double)? in
            let score = fuzzyMatchScore(query: query, target: string)
            return score > 0 && string.lowercased() != query.lowercased() 
                ? (item: string, score: score) 
                : nil
        }
        
        return Array(results.sorted { $0.score > $1.score }.prefix(limit))
    }
    
    // 模糊匹配算法
    private func fuzzyMatchScore(query: String, target: String) -> Double {
        let query = query.lowercased()
        let target = target.lowercased()
        let queryChars = Array(query)
        let targetChars = Array(target)
        
        // 完全匹配
        if target == query {
            return 1.0
        }
        
        // 前缀匹配给高分
        if target.hasPrefix(query) {
            return 0.9
        }
        
        // 包含匹配
        if target.contains(query) {
            return 0.7
        }
        
        // 字符序列匹配（不需要连续）
        var targetIndex = 0
        var matchedChars = 0
        
        for queryChar in queryChars {
            while targetIndex < targetChars.count {
                if targetChars[targetIndex] == queryChar {
                    matchedChars += 1
                    targetIndex += 1
                    break
                }
                targetIndex += 1
            }
        }
        
        if matchedChars == queryChars.count {
            // 根据匹配位置的紧密程度给分
            let ratio = Double(matchedChars) / Double(targetChars.count)
            return ratio * 0.6 // 最高0.6分
        }
        
        // 部分字符匹配
        if matchedChars > 0 {
            let ratio = Double(matchedChars) / Double(queryChars.count)
            return ratio * 0.3 // 最高0.3分
        }
        
        return 0.0
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
    @State private var showingTagModificationAlert = false
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { onDismiss() }
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "plus.circle.fill").foregroundColor(.blue).font(.title2)
                        TextField("输入：@引用节点1 @ 引用节点2 节点 shortcut[标签类型] 标签值", text: $inputText)
                            .textFieldStyle(.plain).font(.system(size: 16, weight: .medium))
                            .onChange(of: inputText) { _, newValue in updateSuggestions(for: newValue) }
                            .onKeyPress(.tab) { handleTabInQuickAdd() }
                            .onKeyPress(.upArrow) { handleUpArrowInQuickAdd() }
                            .onKeyPress(.downArrow) { handleDownArrowInQuickAdd() }
                        
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
                
            }.padding(20).frame(maxWidth: 600)
        }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .alert("重复检测", isPresented: $showingDuplicateAlert) {
            if let alert = store.duplicateNodeAlert {
                if alert.isContextConflict {
                    // 上下文冲突：提供强制添加选项
                    Button("取消", role: .cancel) { 
                        store.duplicateNodeAlert = nil
                    }
                    Button("忽略冲突，强制添加") {
                        // 强制添加节点
                        _ = store.forceAddNode(alert.newNode, ignoreConflicts: true)
                        store.duplicateNodeAlert = nil
                    }
                } else if alert.isDuplicate && alert.existingNode != nil {
                    // 节点重复，询问是否合并
                    Button("取消", role: .cancel) { 
                        store.duplicateNodeAlert = nil
                    }
                    Button("合并标签") {
                        // 执行标签合并
                        if let existingNode = alert.existingNode {
                            let newTags = alert.newNode.tags.filter { newTag in
                                !existingNode.tags.contains { existingTag in
                                    existingTag.type == newTag.type && existingTag.value.lowercased() == newTag.value.lowercased()
                                }
                            }
                            
                            for tag in newTags {
                                store.addTag(to: existingNode.id, tag: tag)
                            }
                        }
                        store.duplicateNodeAlert = nil
                    }
                    Button("创建新节点") {
                        // 强制添加新节点
                        _ = store.forceAddNode(alert.newNode, ignoreConflicts: true)
                        store.duplicateNodeAlert = nil
                    }
                } else {
                    // 其他错误或信息
                    Button("确定") { 
                        store.duplicateNodeAlert = nil
                    }
                }
            } else {
                Button("确定") { }
            }
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
        .alert("标签类型修改确认", isPresented: $showingTagModificationAlert) {
            if let alert = store.tagTypeModificationAlert {
                Button("取消", role: .cancel) {
                    alert.onCancel()
                }
                Button("确认修改") {
                    alert.onConfirm()
                }
            } else {
                Button("确定") { }
            }
        } message: {
            if let alert = store.tagTypeModificationAlert {
                Text(alert.message)
            }
        }
        .onReceive(store.$tagTypeModificationAlert) { alert in
            if alert != nil {
                showingTagModificationAlert = true
            } else {
                showingTagModificationAlert = false
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
        
        // 生成唯一的地图窗口ID
        let mapWindowId = UUID()
        
        // 打开地图窗口，带上目标窗口ID
        let notificationData: [String: String] = [
            "sourceWindowId": "MAIN_WINDOW",
            "targetMapWindowId": mapWindowId.uuidString
        ]
        NotificationCenter.default.post(name: NSNotification.Name("openMapWindow"), object: notificationData)
        
        // 设置为位置选择模式
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(
                name: NSNotification.Name("openMapForLocationSelection"), 
                object: ["requestTime": Date(), "targetWindowId": mapWindowId.uuidString]
            )
        }
    }
    
    private func updateSuggestions(for input: String) {
        let words = input.split(separator: " ")
        guard let lastWord = words.last, !lastWord.isEmpty else { 
            suggestions = []
            selectedSuggestionIndex = -1
            return 
        }
        
        let query = String(lastWord)
        
        // 检查是否是节点引用格式（@节点名）
        if query.hasPrefix("@") {
            let nodeQuery = String(query.dropFirst()) // 去掉@前缀
            
            // 只从节点名搜索
            let nodeResults = fuzzySearchNodes(query: nodeQuery, limit: 10)
            
            // 为结果添加@前缀
            let nodesSuggestions = nodeResults.map { ("@\($0.0)", $0.1) }
            
            let sortedSuggestions = nodesSuggestions.sorted { $0.1 > $1.1 }.map { $0.0 }
            suggestions = Array(sortedSuggestions.prefix(10))
        } else {
            // 普通查询：混合搜索标签类型和节点名
            
            // 使用模糊搜索获取标签建议
            let tagResults = fuzzySearchStrings(Array(tagManager.mappingDictionary.keys), query: query, limit: 5)
            
            // 手动实现节点模糊搜索
            let nodeResults = fuzzySearchNodes(query: query, limit: 5)
            
            // 合并并按分数排序
            var allSuggestions: [(String, Double)] = []
            allSuggestions += tagResults.map { ($0.item, $0.score) }
            allSuggestions += nodeResults
            
            // 去重，保留分数更高的
            let uniqueSuggestions = Dictionary(allSuggestions, uniquingKeysWith: max)
            let sortedSuggestions = uniqueSuggestions.sorted { $0.value > $1.value }.map { $0.key }
            
            suggestions = Array(sortedSuggestions.prefix(10))
        }
        
        selectedSuggestionIndex = suggestions.isEmpty ? -1 : 0
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
                               let bracketIndex = content.firstIndex(of: "["),
                               atIndex < bracketIndex && content.index(after: atIndex) <= bracketIndex {
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
                                       startBracket < endBracket && content.index(after: startBracket) <= endBracket {
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
    
    // MARK: - 键盘处理函数
    
    private func handleTabInQuickAdd() -> KeyPress.Result {
        if selectedSuggestionIndex >= 0 && selectedSuggestionIndex < suggestions.count {
            selectSuggestion(suggestions[selectedSuggestionIndex])
        }
        return .handled
    }
    
    private func handleUpArrowInQuickAdd() -> KeyPress.Result {
        if !suggestions.isEmpty {
            selectedSuggestionIndex = selectedSuggestionIndex <= 0 ? suggestions.count - 1 : selectedSuggestionIndex - 1
        }
        return .handled
    }
    
    private func handleDownArrowInQuickAdd() -> KeyPress.Result {
        if !suggestions.isEmpty {
            selectedSuggestionIndex = min(suggestions.count - 1, selectedSuggestionIndex + 1)
        }
        return .handled
    }
    
    // 手动实现节点模糊搜索
    private func fuzzySearchNodes(query: String, limit: Int) -> [(String, Double)] {
        guard !query.isEmpty else { return [] }
        
        let results = store.nodes.compactMap { node -> (String, Double)? in
            let score = fuzzyMatchScore(query: query, target: node.text)
            return score > 0 && node.text.lowercased() != query.lowercased()
                ? (node.text, score)
                : nil
        }
        
        return Array(results.sorted { $0.1 > $1.1 }.prefix(limit))
    }
    
    // 字符串数组模糊搜索
    private func fuzzySearchStrings(_ strings: [String], query: String, limit: Int) -> [(item: String, score: Double)] {
        guard !query.isEmpty else { return [] }
        
        let results = strings.compactMap { string -> (item: String, score: Double)? in
            let score = fuzzyMatchScore(query: query, target: string)
            return score > 0 && string.lowercased() != query.lowercased() 
                ? (item: string, score: score) 
                : nil
        }
        
        return Array(results.sorted { $0.score > $1.score }.prefix(limit))
    }
    
    // 模糊匹配算法
    private func fuzzyMatchScore(query: String, target: String) -> Double {
        let query = query.lowercased()
        let target = target.lowercased()
        let queryChars = Array(query)
        let targetChars = Array(target)
        
        // 完全匹配
        if target == query {
            return 1.0
        }
        
        // 前缀匹配给高分
        if target.hasPrefix(query) {
            return 0.9
        }
        
        // 包含匹配
        if target.contains(query) {
            return 0.7
        }
        
        // 字符序列匹配（不需要连续）
        var targetIndex = 0
        var matchedChars = 0
        
        for queryChar in queryChars {
            while targetIndex < targetChars.count {
                if targetChars[targetIndex] == queryChar {
                    matchedChars += 1
                    targetIndex += 1
                    break
                }
                targetIndex += 1
            }
        }
        
        if matchedChars == queryChars.count {
            // 根据匹配位置的紧密程度给分
            let ratio = Double(matchedChars) / Double(targetChars.count)
            return ratio * 0.6 // 最高0.6分
        }
        
        // 部分字符匹配
        if matchedChars > 0 {
            let ratio = Double(matchedChars) / Double(queryChars.count)
            return ratio * 0.3 // 最高0.3分
        }
        
        return 0.0
    }
}


// MARK: - Quick Search View

struct QuickSearchView: View {
    @EnvironmentObject private var store: NodeStore
    @State private var searchText: String = ""
    @State private var selectedIndex: Int = -1  // -1表示焦点在搜索框，0+表示结果项索引
    @FocusState private var isSearchFieldFocused: Bool
    let onDismiss: () -> Void
    let onNodeSelected: (Node) -> Void
    
    private var filteredNodes: [Node] {
        if searchText.isEmpty {
            return Array(store.nodes.prefix(10)) // 显示前10个
        } else {
            // 🔍 多重检索：按空格分割搜索词，节点必须同时满足所有搜索词
            let searchTerms = searchText.components(separatedBy: .whitespaces)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            guard !searchTerms.isEmpty else {
                return Array(store.nodes.prefix(10))
            }
            
            return store.nodes.filter { node in
                // 每个节点必须同时满足所有搜索词（AND逻辑）
                return searchTerms.allSatisfy { term in
                    // 每个搜索词可以匹配节点的任意字段（OR逻辑）
                    node.text.localizedCaseInsensitiveContains(term) ||
                    node.meaning?.localizedCaseInsensitiveContains(term) == true ||
                    node.markdown.localizedCaseInsensitiveContains(term) ||
                    node.tags.contains { tag in
                        tag.value.localizedCaseInsensitiveContains(term) ||
                        tag.type.rawValue.localizedCaseInsensitiveContains(term) ||
                        tag.type.displayName.localizedCaseInsensitiveContains(term)
                    }
                }
            }
        }
    }
    
    private var searchSection: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.blue)
                .font(.title2)
            
            TextField("搜索关键词（空格分隔多个条件）...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .focused($isSearchFieldFocused)
                .onSubmit {
                    if !isInIMEComposition() && selectedIndex == -1 && !filteredNodes.isEmpty {
                        selectedIndex = 0
                        selectCurrentNode()
                    }
                }
                .onChange(of: isSearchFieldFocused) { _, _ in }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8)
        )
    }
    
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(Array(filteredNodes.enumerated()), id: \.element.id) { index, word in
                    NodeSearchResultRow(
                        word: word,
                        searchText: searchText,
                        isSelected: selectedIndex >= 0 && index == selectedIndex
                    )
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedIndex >= 0 && index == selectedIndex ? 
                                  Color.blue.opacity(0.1) : Color.clear)
                    )
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onNodeSelected(word)
                        onDismiss()
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        )
        .frame(maxHeight: 400)
        .padding(.top, 8)
    }
    
    private var noResultsView: some View {
        VStack {
            Image(systemName: "magnifyingglass")
                .font(.title)
                .foregroundColor(.secondary)
            Text("没有找到匹配的结果")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(40)
    }
    
    private var helpSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("💡 搜索语法：")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("• 单个关键词：dumb")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("• 多重条件：dumb 手机（空格分隔，同时满足）")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("⌘+F")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.top, 12)
    }
    
    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            VStack(spacing: 0) {
                searchSection
                
                if !filteredNodes.isEmpty {
                    searchResultsList
                } else if !searchText.isEmpty {
                    noResultsView
                }
                
                helpSection
            }
            .padding(20)
            .frame(maxWidth: 600)
            // 搜索界面居中显示
        }
        .task {
            await MainActor.run {
                isSearchFieldFocused = true
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
            await MainActor.run {
                isSearchFieldFocused = true
            }
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.tab) {
            if filteredNodes.isEmpty { return .ignored }
            
            if selectedIndex == -1 {
                selectedIndex = 0
            } else if selectedIndex < filteredNodes.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.tab, phases: .down) { keyPress in
            guard keyPress.modifiers.contains(.shift) else { return .ignored }
            // 🔧 新增：Shift+Tab向上选择结果
            if filteredNodes.isEmpty { return .ignored }
            
            if selectedIndex <= 0 {
                selectedIndex = -1
            } else {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            } else if selectedIndex == 0 {
                selectedIndex = -1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex == -1 && !filteredNodes.isEmpty {
                selectedIndex = 0
            } else if selectedIndex < filteredNodes.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.return) {
            if !isInIMEComposition() && selectedIndex >= 0 {
                selectCurrentNode()
                return .handled
            }
            return .ignored
        }
        .onChange(of: filteredNodes) { _, _ in
            selectedIndex = -1
        }
    }
    
    private func selectCurrentNode() {
        guard selectedIndex < filteredNodes.count else { return }
        let selectedNode = filteredNodes[selectedIndex]
        onNodeSelected(selectedNode)
        onDismiss()
    }
    
    private func isInIMEComposition() -> Bool {
        if let currentEvent = NSApp.currentEvent {
            guard currentEvent.type == .keyDown || currentEvent.type == .keyUp else {
                return false
            }
            let hasMarkedText = !(currentEvent.charactersIgnoringModifiers?.isEmpty ?? true)
            return hasMarkedText
        }
        return false
    }
}

struct NodeSearchResultRow: View {
    let word: Node
    let searchText: String
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题行
            HStack(alignment: .top) {
                // 单词文本
                Text(highlightedText(word.text, searchText: searchText))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // 标签
                HStack(spacing: 4) {
                    ForEach(word.tags.prefix(3), id: \.id) { tag in
                        Text(tag.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.from(tagType: tag.type).opacity(0.2))
                            )
                            .foregroundColor(Color.from(tagType: tag.type))
                    }
                    if word.tags.count > 3 {
                        Text("+\(word.tags.count - 3)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 内容预览
            if let meaning = word.meaning, !meaning.isEmpty {
                Text(getContextPreview(text: meaning, searchText: searchText))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            
            // 显示匹配的上下文
            if let matchContext = getMatchContext(word: word, searchText: searchText) {
                HStack(spacing: 4) {
                    Image(systemName: "quote.bubble")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text(highlightedText(matchContext, searchText: searchText))
                        .font(.caption)
                        .foregroundColor(.blue)
                        .lineLimit(2)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }
    
    private func highlightedText(_ text: String, searchText: String) -> AttributedString {
        var attributedString = AttributedString(text)
        
        if !searchText.isEmpty {
            if let range = text.range(of: searchText, options: .caseInsensitive) {
                let nsRange = NSRange(range, in: text)
                if let attributedRange = Range(nsRange, in: attributedString) {
                    attributedString[attributedRange].backgroundColor = .yellow.opacity(0.3)
                    attributedString[attributedRange].foregroundColor = .primary
                }
            }
        }
        
        return attributedString
    }
    
    // 获取内容预览，优先显示包含搜索词的部分
    private func getContextPreview(text: String, searchText: String) -> String {
        guard !searchText.isEmpty else { return String(text.prefix(150)) }
        
        // 查找搜索词在文本中的位置
        if let range = text.range(of: searchText, options: .caseInsensitive) {
            let startIndex = text.startIndex
            let matchStart = text.distance(from: startIndex, to: range.lowerBound)
            
            // 获取匹配前后的上下文
            let contextRadius = 50
            let contextStart = max(0, matchStart - contextRadius)
            let contextEnd = min(text.count, matchStart + searchText.count + contextRadius)
            
            // 安全的字符串索引操作，避免越界
            guard contextStart >= 0 && contextEnd <= text.count && contextStart <= contextEnd else {
                return String(text.prefix(150))
            }
            
            let start = text.index(startIndex, offsetBy: contextStart)
            let end = text.index(startIndex, offsetBy: contextEnd)
            
            var preview = String(text[start..<end])
            
            // 如果不是从开头开始，添加省略号
            if contextStart > 0 {
                preview = "..." + preview
            }
            
            // 如果不是到结尾，添加省略号
            if contextEnd < text.count {
                preview = preview + "..."
            }
            
            return preview
        }
        
        // 如果没有匹配，返回前150个字符
        return String(text.prefix(150)) + (text.count > 150 ? "..." : "")
    }
    
    // 获取匹配的上下文（包括标签内容和markdown）
    private func getMatchContext(word: Node, searchText: String) -> String? {
        guard !searchText.isEmpty else { return nil }
        
        // 分割搜索词，支持多个关键词
        let searchTerms = searchText.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // 优先检查markdown内容是否匹配
        if !word.markdown.isEmpty {
            for term in searchTerms {
                if word.markdown.localizedCaseInsensitiveContains(term) {
                    // 获取markdown中包含搜索词的部分
                    return getMarkdownContext(markdown: word.markdown, searchText: term)
                }
            }
        }
        
        // 检查标签是否匹配
        for tag in word.tags {
            for term in searchTerms {
                // 检查标签值是否匹配
                if tag.value.localizedCaseInsensitiveContains(term) {
                    return "🏷️ \(tag.type.displayName): \(tag.value)"
                }
                // 检查标签类型的rawValue是否匹配（快捷键）
                if tag.type.rawValue.localizedCaseInsensitiveContains(term) {
                    return "🎯 标签快捷键: \(tag.type.rawValue)[\(tag.type.displayName)]"
                }
                // 检查标签类型的displayName是否匹配
                if tag.type.displayName.localizedCaseInsensitiveContains(term) {
                    return "🎯 标签类型: \(tag.type.displayName) (\(tag.value))"
                }
            }
        }
        
        // 检查音标是否匹配
        if let phonetic = word.phonetic {
            for term in searchTerms {
                if phonetic.localizedCaseInsensitiveContains(term) {
                    return "🔤 音标: \(phonetic)"
                }
            }
        }
        
        return nil
    }
    
    // 获取markdown中的匹配上下文
    private func getMarkdownContext(markdown: String, searchText: String) -> String? {
        guard let range = markdown.range(of: searchText, options: .caseInsensitive) else { return nil }
        
        let startIndex = markdown.startIndex
        let matchStart = markdown.distance(from: startIndex, to: range.lowerBound)
        
        // 获取匹配文本所在的自然段落
        let paragraphStart = markdown.lastIndex(of: "\n", before: range.lowerBound) ?? startIndex
        let paragraphEnd = markdown.firstIndex(of: "\n", after: range.upperBound) ?? markdown.endIndex
        
        // 提取段落内容
        let paragraph = String(markdown[paragraphStart..<paragraphEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 如果段落太长，只显示包含关键词的部分
        if paragraph.count > 150 {
            let contextRadius = 60
            let relativeMatchStart = matchStart - markdown.distance(from: startIndex, to: paragraphStart)
            let contextStart = max(0, relativeMatchStart - contextRadius)
            let contextEnd = min(paragraph.count, relativeMatchStart + searchText.count + contextRadius)
            
            // 安全的字符串索引操作，避免越界
            guard contextStart >= 0 && contextEnd <= paragraph.count && contextStart <= contextEnd else {
                return String(paragraph.prefix(150)) + "..."
            }
            
            let start = paragraph.index(paragraph.startIndex, offsetBy: contextStart)
            let end = paragraph.index(paragraph.startIndex, offsetBy: contextEnd)
            
            var preview = String(paragraph[start..<end])
            if contextStart > 0 {
                preview = "..." + preview
            }
            if contextEnd < paragraph.count {
                preview = preview + "..."
            }
            return "📝 " + preview
        }
        
        return "📝 " + paragraph
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

// MARK: - FocusedValues for Global Commands

struct ShowCardAction {
    let action: () -> Void
    
    init(_ action: @escaping () -> Void) {
        self.action = action
    }
    
    func callAsFunction() {
        action()
    }
}

struct ShowCommandPaletteKey: FocusedValueKey {
    typealias Value = ShowCardAction
}

struct AddNewNodeKey: FocusedValueKey {
    typealias Value = ShowCardAction
}

struct OpenQuickSearchKey: FocusedValueKey {
    typealias Value = ShowCardAction
}

struct OpenTagManagerKey: FocusedValueKey {
    typealias Value = ShowCardAction
}

struct OpenNodeManagerKey: FocusedValueKey {
    typealias Value = ShowCardAction
}

struct OpenMapWindowKey: FocusedValueKey {
    typealias Value = ShowCardAction
}

struct OpenGraphWindowKey: FocusedValueKey {
    typealias Value = ShowCardAction
}

struct ToggleSidebarKey: FocusedValueKey {
    typealias Value = ShowCardAction
}

struct OpenNewWindowKey: FocusedValueKey {
    typealias Value = ShowCardAction
}

struct SwitchToDetailTabKey: FocusedValueKey {
    typealias Value = ShowCardAction
}

struct SwitchToGraphTabKey: FocusedValueKey {
    typealias Value = ShowCardAction
}

struct ClearTagFilterKey: FocusedValueKey {
    typealias Value = ShowCardAction
}

struct OpenTagSearchKey: FocusedValueKey {
    typealias Value = ShowCardAction
}

struct RestorePreviousTagFilterStateKey: FocusedValueKey {
    typealias Value = ShowCardAction
}

extension FocusedValues {
    var showCommandPalette: ShowCardAction? {
        get { self[ShowCommandPaletteKey.self] }
        set { self[ShowCommandPaletteKey.self] = newValue }
    }
    
    var addNewNode: ShowCardAction? {
        get { self[AddNewNodeKey.self] }
        set { self[AddNewNodeKey.self] = newValue }
    }
    
    var openQuickSearch: ShowCardAction? {
        get { self[OpenQuickSearchKey.self] }
        set { self[OpenQuickSearchKey.self] = newValue }
    }
    
    var openTagManager: ShowCardAction? {
        get { self[OpenTagManagerKey.self] }
        set { self[OpenTagManagerKey.self] = newValue }
    }
    
    var openNodeManager: ShowCardAction? {
        get { self[OpenNodeManagerKey.self] }
        set { self[OpenNodeManagerKey.self] = newValue }
    }
    
    var openMapWindow: ShowCardAction? {
        get { self[OpenMapWindowKey.self] }
        set { self[OpenMapWindowKey.self] = newValue }
    }
    
    var openGraphWindow: ShowCardAction? {
        get { self[OpenGraphWindowKey.self] }
        set { self[OpenGraphWindowKey.self] = newValue }
    }
    
    var toggleSidebar: ShowCardAction? {
        get { self[ToggleSidebarKey.self] }
        set { self[ToggleSidebarKey.self] = newValue }
    }
    
    var openNewWindow: ShowCardAction? {
        get { self[OpenNewWindowKey.self] }
        set { self[OpenNewWindowKey.self] = newValue }
    }
    
    var switchToDetailTab: ShowCardAction? {
        get { self[SwitchToDetailTabKey.self] }
        set { self[SwitchToDetailTabKey.self] = newValue }
    }
    
    var switchToGraphTab: ShowCardAction? {
        get { self[SwitchToGraphTabKey.self] }
        set { self[SwitchToGraphTabKey.self] = newValue }
    }
    
    var clearTagFilter: ShowCardAction? {
        get { self[ClearTagFilterKey.self] }
        set { self[ClearTagFilterKey.self] = newValue }
    }
    
    var openTagSearch: ShowCardAction? {
        get { self[OpenTagSearchKey.self] }
        set { self[OpenTagSearchKey.self] = newValue }
    }
    
    var restorePreviousTagFilterState: ShowCardAction? {
        get { self[RestorePreviousTagFilterStateKey.self] }
        set { self[RestorePreviousTagFilterStateKey.self] = newValue }
    }
}

@main
struct WordTaggerApp: App {
    @StateObject private var store = NodeStore.shared
    @State private var showPalette = false
    @State private var showQuickAdd = false
    @State private var showQuickSearch = false
    @State private var showCompoundNodeAdd = false
    @State private var nodeToEditInManager: Node? = nil
    @State private var tagTypeForGraph: Tag.TagType?
    @Environment(\.openWindow) private var openWindow
    
    // 主窗口的唯一标识符
    private let mainWindowId = UUID()
    @State private var isOpeningWindow = false // 防止重复打开窗口的标志
    
    /// 紧急清理所有打开的对话框和sheet
    private func performEmergencySheetCleanup() {
        
        // 强制关闭所有sheet
        showPalette = false
        showQuickAdd = false
        showQuickSearch = false
        showCompoundNodeAdd = false
        nodeToEditInManager = nil
        tagTypeForGraph = nil
        
        // 清理Store中的alert状态
        store.duplicateNodeAlert = nil
        store.tagTypeModificationAlert = nil
        
        // 发送清理通知给所有子组件
        NotificationCenter.default.post(
            name: NSNotification.Name("emergencyWindowCleanup"),
            object: nil
        )
        
    }
    
    
    init() {
        // 禁用自动标签页功能
        NSWindow.allowsAutomaticWindowTabbing = false
        
        // 设置环境变量以抑制SQLite系统数据库访问警告
        setenv("SQLITE_ENABLE_FTS4", "0", 1)
        setenv("SQLITE_ENABLE_FTS5", "0", 1)
        setenv("SQLITE_SECURE_DELETE", "fast", 1)
        
        // 减少macOS系统服务的数据库查询
        UserDefaults.standard.set(false, forKey: "NSApplicationCrashOnExceptions")
        
        
        // 验证资源文件是否正确加载
        let verification = ResourceManager.verifyAllResourcesExist()
        if verification.success {
        } else {
            for _ in verification.missingFiles {
            }
        }
        
        // 延迟初始化Git自动同步，确保设置已加载
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            GitAutoSyncManager.shared.debugStatus()
            GitAutoSyncManager.shared.startMonitoring()
            
            // 确保监听启动后再执行启动时的自动提交
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                Task { @MainActor in
                    await GitStartupAutoCommitManager.shared.performStartupCommitAndPush()
                }
            }
        }
    }
    // 哈哈哈哈哈哈哈哈哈哈哈哈哈哈哈哈

    var body: some Scene {
        WindowGroup(WINDOW_TITLE) {
            ZStack {
                ContentView(windowId: mainWindowId)
                    .environmentObject(store)
                    .onAppear {
                        // 为主窗口注册窗口焦点管理
                        WindowFocusManager.shared.registerWindow(mainWindowId, type: .standard, displayName: "窗口")
                        WindowFocusManager.shared.setActiveWindow(mainWindowId)
                    }
                    .background(WindowClickTracker(windowId: mainWindowId))
                
                if showPalette {
                    ZStack {
                        // 背景遮罩 - 完全禁用点击响应，只通过ESC键关闭
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // 点击背景时不做任何事，防止误关闭
                            }
                        
                        CommandPaletteView(isPresented: $showPalette)
                            .environmentObject(store)
                            .transition(.asymmetric(insertion: AnyTransition.scale.combined(with: .opacity), removal: .opacity))
                    }
                }
                
                if showQuickSearch {
                    QuickSearchView(
                        onDismiss: { 
                            showQuickSearch = false 
                        },
                        onNodeSelected: { node in
                            
                            // 首先切换到节点所在的层
                            if let nodeLayer = store.layers.first(where: { $0.id == node.layerId }) {
                                store.setCurrentLayer(nodeLayer)
                            }
                            
                            // 然后选择节点
                            store.selectNode(node)
                        }
                    )
                    .environmentObject(store)
                    .onAppear {
                    }
                    // 移除动画效果，直接显示
                }
                
            }
            .animation(.easeInOut(duration: 0.2), value: showPalette)
            // QuickSearch 不使用动画，直接显示
            .onChange(of: showQuickSearch) { _, newValue in
            }
            .onKeyPress(.escape) {
                if showPalette {
                    showPalette = false
                    return .handled
                }
                if showQuickSearch {
                    showQuickSearch = false
                    return .handled
                }
                // 检查是否有其他sheet需要紧急关闭
                if showQuickAdd || showCompoundNodeAdd {
                    performEmergencySheetCleanup()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.init("c"), phases: .down) { keyPress in
                // Command+Option+C = 紧急清理所有sheet
                if keyPress.modifiers.contains([.command, .option]) {
                    performEmergencySheetCleanup()
                    return .handled
                }
                return .ignored
            }
            .sheet(isPresented: $showQuickAdd) {
                QuickAddSheetView(windowId: mainWindowId)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showCompoundNodeAdd) {
                CompoundNodeAddSheetView()
                    .environmentObject(store)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("forceCloseAllSheets"))) { _ in
                performEmergencySheetCleanup()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("showCommandPalette"))) { _ in
                // showCommandPalette 现在重定向到层结构图谱（兼容旧代码）
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true, commandName: "showCommandPalette") else {
                    return
                }
                // 🔧 传递源窗口ID以防止重复处理
                NotificationCenter.default.post(
                    name: NSNotification.Name("executeOpenWindow"), 
                    object: "layerGraph",
                    userInfo: ["sourceWindowId": mainWindowId.uuidString]
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openNewWindow"))) { notification in
                // openNewWindow 是全局命令，应该在任何活跃窗口中可用
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true, commandName: "openNewWindow") else {
                    return
                }
                
                
                // 防止重复打开：检查当前是否已有独立窗口
                guard !isOpeningWindow else {
                    return
                }
                
                isOpeningWindow = true
                
                // 直接使用环境中的openWindow打开窗口
                DispatchQueue.main.async {
                    // 通知ContentView执行openWindow
                    NotificationCenter.default.post(
                        name: NSNotification.Name("executeOpenWindow"),
                        object: "layerView"
                    )
                }
                
                // 500ms后重置标志
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isOpeningWindow = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("addNewNode"))) { _ in
                // addNewNode 是全局命令，应该在任何活跃窗口中可用
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true) else {
                    return
                }
                showQuickAdd = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openNodeManagerForEdit"))) { notification in
                // openNodeManagerForEdit 现在是全局命令，可以从任何窗口触发
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true, commandName: "openNodeManagerForEdit") else {
                    return
                }
                
                if let node = notification.object as? Node {
                    nodeToEditInManager = node
                    // 先打开节点管理窗口
                    NotificationCenter.default.post(name: Notification.Name("openNodeManager"), object: nil)
                    // 延迟发送编辑节点通知，确保窗口已打开
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NotificationCenter.default.post(name: Notification.Name("nodeManagerEditNode"), object: node)
                    }
                }
            }
            // openTagSearch通知已经由TagSidebarView直接处理，不需要在这里转发
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openQuickSearch"))) { _ in
                // openQuickSearch 是全局命令，应该在任何活跃窗口中可用
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true) else {
                    return
                }
                showQuickSearch = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openGraphWindow"))) { _ in
                // openGraphWindow 是全局命令，应该在任何活跃窗口中可用
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true) else {
                    return
                }
                NotificationCenter.default.post(name: NSNotification.Name("executeOpenGraphWindow"), object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("requestMapForLocationSelection"))) { notification in
                // 🔧 处理来自QuickAddSheetView的位置选择请求
                if let notificationData = notification.object as? [String: String],
                   let requestSource = notificationData["requestSource"],
                   let windowId = notificationData["windowId"] {
                    // 检查是否是发给这个窗口的请求
                    // 支持mainWindowId或ContentView使用的固定UUID
                    let contentViewMainId = "00000000-0000-0000-0000-000000000001"
                    if requestSource == "MAIN_WINDOW" && (windowId == mainWindowId.uuidString || windowId == contentViewMainId) {
                        NotificationCenter.default.post(name: NSNotification.Name("executeOpenMapWindow"), object: ["sourceWindowId": mainWindowId.uuidString])
                    } else {
                    }
                } else if let requestSource = notification.object as? String {
                    // 向后兼容旧格式
                    if requestSource == "MAIN_WINDOW" {
                        NotificationCenter.default.post(name: NSNotification.Name("executeOpenMapWindow"), object: ["sourceWindowId": mainWindowId.uuidString])
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openMapWindow"))) { notification in
                // 🔧 修复：检查通知是否包含源窗口信息，如果包含则只有匹配的窗口才处理
                if let sourceInfo = notification.object as? [String: String],
                   let targetSourceWindowId = sourceInfo["sourceWindowId"] {
                    
                    // 检查是否是发给主窗口的
                    if targetSourceWindowId == mainWindowId.uuidString || targetSourceWindowId == "MAIN_WINDOW" {
                        NotificationCenter.default.post(name: NSNotification.Name("executeOpenMapWindow"), object: ["sourceWindowId": mainWindowId.uuidString])
                    } else {
                    }
                    return
                }
                
                // 如果没有源窗口信息，使用原有的全局命令逻辑（向后兼容）
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true) else {
                    return
                }
                NotificationCenter.default.post(name: NSNotification.Name("executeOpenMapWindow"), object: ["sourceWindowId": mainWindowId.uuidString])
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openTagManager"))) { _ in
                // openTagManager 是全局命令，只在当前key窗口处理
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true, commandName: "openTagManager") else {
                    return
                }
                
                // 改为打开独立窗口
                openWindow(id: "tagManager")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openNodeManager"))) { _ in
                // openNodeManager 是全局命令，只在当前key窗口处理
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true, commandName: "openNodeManager") else {
                    return
                }
                
                NotificationCenter.default.post(name: NSNotification.Name("executeOpenNodeManager"), object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openTagTypeGraph"))) { notification in
                // openTagTypeGraph 应该总是由主窗口处理，因为只有主窗口有WindowGroup定义
                
                if let tagType = notification.object as? Tag.TagType {
                    
                    // 更新共享的TagGraphWindowManager状态
                    TagGraphWindowManager.shared.updateTagType(tagType)
                    
                    // 保持原有的tagTypeForGraph更新以确保向后兼容
                    tagTypeForGraph = tagType
                    
                    NotificationCenter.default.post(name: NSNotification.Name("executeOpenWindow"), object: "tagTypeGraph")
                } else {
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("executeOpenNodeManager"))) { notification in
                // 检查当前窗口是否应该响应此通知
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true, commandName: "executeOpenNodeManager") else {
                    return
                }
                
                // 通过ContentView的openWindow执行
                NotificationCenter.default.post(name: NSNotification.Name("executeOpenWindow"), object: "nodeManager")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("executeOpenMapWindow"))) { notification in
                // 🔧 关键修复：实际打开通用地图窗口并设置窗口映射
                
                // 🔧 打开通用地图窗口
                NotificationCenter.default.post(name: NSNotification.Name("executeOpenWindow"), object: "map")
                
                // 设置窗口映射信息
                if let sourceInfo = notification.object as? [String: String] {
                    // 延迟一点发送映射信息，确保地图窗口已经打开
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("mapWindowSetupMapping"),
                            object: sourceInfo
                        )
                    }
                } else {
                    // 使用主窗口的ID
                    let defaultSourceInfo = ["sourceWindowId": mainWindowId.uuidString]
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("mapWindowSetupMapping"),
                            object: defaultSourceInfo
                        )
                    }
                }
                
                // 🔧 注意：这里不应该自动发送位置选择模式通知
                // Command+M 应该只打开普通地图浏览模式
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("requestWindowMapping"))) { notification in
                // 处理窗口映射请求 - 解决时序问题
                
                if let requestInfo = notification.object as? [String: String],
                   let _ = requestInfo["childWindowId"],
                   let _ = requestInfo["windowType"] {
                    
                    // 🔧 重要修复：使用智能源窗口检测
                    let sourceWindowId = WindowFocusManager.shared.getSourceWindowId()
                    
                    // 发送映射信息
                    let mappingInfo = ["sourceWindowId": sourceWindowId]
                    NotificationCenter.default.post(
                        name: NSNotification.Name("mapWindowSetupMapping"),
                        object: mappingInfo
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("requestWindowMappingForMap"))) { notification in
                // 🔧 处理地图窗口的主动映射请求
                
                if let requestInfo = notification.object as? [String: String],
                   let mapWindowId = requestInfo["mapWindowId"] {
                    
                    // 检查主窗口是否应该响应（即主窗口是否是活跃窗口或最近活跃的非地图窗口）
                    if WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: false) {
                        let sourceWindowId = mainWindowId.uuidString
                        
                        // 🎯 发送带目标地图窗口ID的映射信息
                        let mappingInfo = [
                            "sourceWindowId": sourceWindowId,
                            "targetMapWindowId": mapWindowId
                        ]
                        NotificationCenter.default.post(
                            name: NSNotification.Name("mapWindowSetupMapping"),
                            object: mappingInfo
                        )
                    } else {
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("toggleSidebar"))) { _ in
                // toggleSidebar 是全局命令，只在当前key窗口处理
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true) else {
                    return
                }
                
                NotificationCenter.default.post(name: NSNotification.Name("executeToggleSidebar"), object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("switchToDetailTab"))) { _ in
                // 检查当前窗口是否应该响应此通知
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId) else {
                    return
                }
                // 发送执行命令，避免循环
                NotificationCenter.default.post(name: NSNotification.Name("executeDetailTabSwitch"), object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("switchToGraphTab"))) { _ in
                // 检查当前窗口是否应该响应此通知
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId) else {
                    return
                }
                // 发送执行命令，避免循环
                NotificationCenter.default.post(name: NSNotification.Name("executeGraphTabSwitch"), object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("clearTagFilter"))) { _ in
                // clearTagFilter是全局命令，应该在任何活跃窗口中可用
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true, commandName: "clearTagFilter") else {
                    return
                }
                store.clearTagFilter()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("restorePreviousTagFilterState"))) { _ in
                // restorePreviousTagFilterState是全局命令，应该在任何活跃窗口中可用
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true, commandName: "restorePreviousTagFilterState") else {
                    return
                }
                store.restorePreviousTagFilterState()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("switchToLayer"))) { notification in
                // 🔧 处理来自层图谱窗口的层切换请求
                guard let layer = notification.object as? Layer else {
                    return
                }
                
                if let userInfo = notification.userInfo,
                   let sourceWindowId = userInfo["sourceWindowId"] as? String,
                   !sourceWindowId.isEmpty {
                    
                    // 🔧 调试：打印窗口ID信息
                    
                    // 🔧 精确检查是否是发给这个特定主窗口的（支持多主窗口环境）
                    let isTargetingThisMainWindow = sourceWindowId == mainWindowId.uuidString
                    
                    if isTargetingThisMainWindow {
                        Task {
                            await store.switchToLayer(layer)
                        }
                    } else {
                    }
                } else {
                    // 如果没有指定源窗口，使用WindowFocusManager检查
                    guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: false, commandName: "switchToLayer") else {
                        return
                    }
                    Task {
                        await store.switchToLayer(layer)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("handleMapPinTap"))) { notification in
                guard let userInfo = notification.userInfo,
                      let targetNodeId = userInfo["targetNodeId"] as? String,
                      let targetLayerId = userInfo["targetLayerId"] as? String else {
                    return
                }
                
                // 🔧 从当前store实例中查找对应的节点和层
                guard let targetNodeUUID = UUID(uuidString: targetNodeId),
                      let targetNode = store.nodes.first(where: { $0.id == targetNodeUUID }) else {
                    return
                }
                
                guard let targetLayerUUID = UUID(uuidString: targetLayerId),
                      let targetLayer = store.layers.first(where: { $0.id == targetLayerUUID }) else {
                    return
                }
                
                // 🔧 重新设计通知路由逻辑：优先检查目标窗口ID，然后检查活跃状态
                // 如果指定了目标窗口ID，必须完全匹配才处理
                if let targetWindowId = userInfo["targetWindowId"] as? String {
                    // 🔧 支持主窗口的多种标识方式和短ID匹配
                    let mainWindowShortId = String(mainWindowId.uuidString.prefix(8))
                    let isMatchingMainWindow = (targetWindowId == mainWindowId.uuidString) || 
                                             (targetWindowId == mainWindowShortId) ||
                                             (targetWindowId == "MAIN_WINDOW")
                    if !isMatchingMainWindow {
                        return
                    }
                } else {
                    // 如果没有指定目标窗口ID，则使用WindowFocusManager进行活跃窗口检查
                    guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: false, commandName: "handleMapPinTap") else {
                        return
                    }
                }
                
                
                // 执行层切换和标签展开操作
                Task {
                    await store.switchToLayer(targetLayer)
                    
                    await MainActor.run {
                        store.expandLocationTagAndSelect(targetNode)
                        
                        // 发送通知切换到地图标签
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("switchToMapTab"),
                                object: targetNode
                            )
                        }
                    }
                }
            }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            // 全局命令组 - 使用 FocusedValues
            CommandGroup(replacing: .appInfo) {}
            
            // 🔧 移除默认的 Command+N "新建窗口" 菜单项
            // 我们希望 Command+N 用于清除标签筛选，而不是新建窗口
            CommandGroup(replacing: .newItem) {}
            
            // 全局命令处理器
            GlobalCommands()
        }
        .defaultSize(width: 1200, height: 800)
        
        // 🗺️ 地图窗口 - 显示节点的地理位置和地点标签
        // 使用通用WindowGroup，通过sourceWindowId进行智能路由
        WindowGroup(WINDOW_TITLE, id: "map") {
            MapWindow()
                .environmentObject(store) // 默认使用主store，具体路由由MapContainer中间层处理
        }
        .defaultSize(width: 1000, height: 700)
        
        // 📊 全局节点图谱窗口 - 显示节点关系的可视化图谱
        WindowGroup(WINDOW_TITLE, id: "graph") {
            GraphView()
                .environmentObject(store)
        }
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified)
        
        // ⚙️ 节点管理窗口 - 批量管理和编辑节点
        // 使用单例窗口管理器
        Window(WINDOW_TITLE, id: "nodeManager") {
            NodeManagerView(nodeToEdit: $nodeToEditInManager)
                .environmentObject(store)
        }
        .defaultSize(width: 1000, height: 700)
        
        // 🖼️ 全屏图谱窗口 - 大尺寸的节点关系图谱视图
        // SwiftUI原生方式
        WindowGroup(WINDOW_TITLE, id: "fullscreenGraph") {
            FullscreenGraphView()
                .environmentObject(store)
        }
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified)
        
        // 🏷️ 特定标签类型图谱窗口 - 显示单个标签类型的关系图
        WindowGroup(WINDOW_TITLE, id: "tagTypeGraph") {
            // 优先使用WindowManager中的标签类型，然后回退到tagTypeForGraph
            if let tagType = TagGraphWindowManager.shared.currentTagType ?? tagTypeForGraph {
                FullscreenTagTypeGraphView(tagType: tagType)
                    .environmentObject(store)
                    .onAppear {
                        // 确保WindowManager状态与实际显示的标签类型同步
                        if TagGraphWindowManager.shared.currentTagType != tagType {
                            TagGraphWindowManager.shared.updateTagType(tagType)
                        }
                    }
                    .onDisappear {
                        TagGraphWindowManager.shared.markWindowHidden()
                    }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    
                    Text("无效的标签类型")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    Text("请重新选择标签类型以查看图谱")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                }
            }
        }
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified)
        
        // 🌐 全局标签图谱窗口 - 显示所有标签类型的整体关系图谱
        WindowGroup(WINDOW_TITLE, id: "globalTagGraph") {
            GlobalTagGraphView()
                .environmentObject(store)
        }
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified)
        
        // 📊 层图谱窗口 - 显示层级之间的关系和层级内的节点分布
        WindowGroup(WINDOW_TITLE, id: "layerGraph") {
            LayerGraphWindowView()
                .environmentObject(store)
        }
        .defaultSize(width: 900, height: 650)
        
        // 🔄 独立层视图窗口 - 完全分离的数据状态，用于独立编辑和查看
        WindowGroup(WINDOW_TITLE, id: "layerView") {
            IndependentWindowWrapper()
        }
        .defaultSize(width: 1200, height: 800)
        
        // 🏷️ 标签管理窗口 - 管理标签映射和配置
        WindowGroup(WINDOW_TITLE, id: "tagManager") {
            TagManagerWindowView()
                .environmentObject(store)
        }
        .defaultSize(width: 700, height: 600)
        
        // ⚙️ 应用设置窗口 - 管理应用全局配置和偏好设置
        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

// MARK: - Tag Manager View (New Implementation)

struct TagManagerView: View {
    @ObservedObject private var tagManager = TagMappingManager.shared
    @EnvironmentObject private var store: NodeStore
    
    @State private var newKey: String = ""
    @State private var newTypeName: String = ""
    @State private var editingMapping: TagMapping?
    @State private var showSystemTags: Bool = false  // 默认隐藏系统标签
    @State private var showingTagEditSheet: Bool = false  // 控制标签编辑弹窗
    @State private var selectedModule: TagManagerModule = .tagManagement  // 当前选择的模块
    @State private var searchText: String = ""  // 搜索文本
    @FocusState private var isViewFocused: Bool
    @FocusState private var isSearchFieldFocused: Bool  // 搜索框焦点状态
    
    // 定义两个模块
    enum TagManagerModule: String, CaseIterable {
        case tagManagement = "标签管理"
        case usageAnalysis = "使用分析"
    }
    
    let onDismiss: () -> Void
    
    // 计算属性
    private var filteredMappings: [TagMapping] {
        let allMappings = tagManager.tagMappings
        
        return allMappings.filter { mapping in
            // 系统标签过滤
            if !showSystemTags && shouldHideSystemTag(mapping) {
                return false
            }
            
            // 搜索过滤
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                return mapping.key.lowercased().contains(searchLower) || 
                       mapping.typeName.lowercased().contains(searchLower)
            }
            
            return true
        }.sorted { $0.typeName.localizedCompare($1.typeName) == .orderedAscending }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 优化的标签栏布局
            HStack(spacing: 16) {
                // 填满空间的模块切换按钮组
                HStack(spacing: 0) {
                    ForEach(TagManagerModule.allCases, id: \.self) { module in
                        Button(action: { selectedModule = module }) {
                            Text(module.rawValue)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(selectedModule == module ? .white : Color(NSColor.labelColor))
                                .padding(.vertical, 8)
                                .padding(.horizontal, 20)
                                .frame(maxWidth: .infinity) // 让每个按钮占用相等的空间
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedModule == module ? Color.accentColor : Color.clear)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )
                )
                .frame(maxWidth: .infinity) // 让按钮组占用所有可用空间

                // 右侧：操作按钮
                HStack(spacing: 8) {
                    // 添加标签按钮
                    Button(action: {
                        showingTagEditSheet = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accentColor)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(Color.accentColor.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("添加新标签")
                }
            }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // 根据选择显示不同内容
                Group {
                    switch selectedModule {
                    case .tagManagement:
                        tagManagementContent
                    case .usageAnalysis:
                        EnhancedTagUsageView()
                            .environmentObject(store)
                    }
                }
            }
            .sheet(isPresented: $showingTagEditSheet) {
                TagEditFormView(
                    newKey: $newKey,
                    newTypeName: $newTypeName,
                    editingMapping: $editingMapping,
                    onSave: saveMapping,
                    onCancel: cancelEditing
                )
            }
        }

    // 标签管理内容 - 简化版
    private var tagManagementContent: some View {
        VStack(spacing: 0) {
            // 搜索框 - 简化样式
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))

                TextField("搜索标签...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isSearchFieldFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Divider()
                .padding(.top, 12)

            // 标签列表 - 移除高度限制，充分利用空间
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredMappings, id: \.id) { mapping in
                        TagMappingRow(
                            mapping: mapping,
                            onEdit: {
                                editingMapping = mapping
                                newKey = mapping.key
                                newTypeName = mapping.typeName
                                showingTagEditSheet = true
                            }
                        )
                    }
                }
                .padding(.bottom, 8) // 底部添加一点空隙
            }

        }
    }
}

// MARK: - Tag Edit Form View

struct TagEditFormView: View {
    @Binding var newKey: String
    @Binding var newTypeName: String
    @Binding var editingMapping: TagMapping?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isKeyFieldFocused: Bool
    @FocusState private var isTypeNameFieldFocused: Bool
    
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // 表单内容
            VStack(spacing: 16) {
                Text(editingMapping != nil ? "编辑标签" : "添加新标签")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("快捷键")
                            .font(.headline)
                            .foregroundColor(.primary)
                        TextField("例如: root", text: $newKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                            .focused($isKeyFieldFocused)
                            .onSubmit {
                                // Tab到下一个字段
                                isTypeNameFieldFocused = true
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("类型名称")
                            .font(.headline)
                            .foregroundColor(.primary)
                        TextField("例如: 词根", text: $newTypeName)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                            .focused($isTypeNameFieldFocused)
                            .onSubmit {
                                // 回车保存
                                handleSave()
                            }
                    }
                }
                
                // 按钮区域
                HStack(spacing: 16) {
                    Button("取消") {
                        handleCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut(.escape)
                    
                    Button(editingMapping != nil ? "保存" : "添加") {
                        handleSave()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(newKey.isEmpty || newTypeName.isEmpty)
                    .keyboardShortcut(.return)
                }
                .padding(.top, 8)
            }
            .padding(24)
            
            Spacer()
        }
        .frame(width: 400, height: 300)
        .onKeyPress(.escape) {
            handleCancel()
            return .handled
        }
        .onAppear {
            // 自动聚焦第一个字段
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if newKey.isEmpty {
                    isKeyFieldFocused = true
                } else {
                    isTypeNameFieldFocused = true
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleSave() {
        guard !newKey.isEmpty && !newTypeName.isEmpty else {
            return
        }
        onSave()
        dismiss()
    }
    
    private func handleCancel() {
        onCancel()
        dismiss()
    }
}

extension TagManagerView {
    
    private func saveMapping() {
        
        let mapping = TagMapping(
            id: editingMapping?.id ?? UUID(),
            key: newKey.lowercased(),
            typeName: newTypeName
        )
        
        if editingMapping != nil {
        }
        
        tagManager.saveMapping(mapping)
        resetForm()
    }
    
    private func resetForm() {
        newKey = ""
        newTypeName = ""
        editingMapping = nil
    }

    private func cancelEditing() {
        resetForm()
    }
    
    // 判断是否应该隐藏系统标签
    private func shouldHideSystemTag(_ mapping: TagMapping) -> Bool {
        // 隐藏核心系统标签以减少认知负荷
        // compound: 复合节点标记标签，系统内部使用
        // child: 子节点引用标签，系统内部使用
        // loc: 地点标签，地图功能使用
        let systemTagsToHide = ["compound", "child", "loc"]
        return systemTagsToHide.contains(mapping.key)
    }
    
    
    
}

struct TagMappingRow: View {
    let mapping: TagMapping
    let onEdit: () -> Void
    
    private var isBuiltInCore: Bool {
        TagMappingManager.shared.isBuiltInCoreTag(mapping.key)
    }
    
    var body: some View {
        return Button(action: isBuiltInCore ? {} : onEdit) {
            HStack {
                // 标签颜色指示器
                Circle()
                    .fill(Color.from(tagType: mapping.tagType))
                    .frame(width: 12, height: 12)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(mapping.key)
                            .font(.system(size: 18, weight: .medium))
                        
                        if isBuiltInCore {
                            Text("系统")
                                .font(.system(size: 12, weight: .bold))
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
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(mapping.typeName)
                    .font(.subheadline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.from(tagType: mapping.tagType).opacity(0.2))
                    )
                    .foregroundColor(Color.from(tagType: mapping.tagType))
                
                // 编辑图标（仅作为视觉提示）
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundColor(isBuiltInCore ? .gray : .blue)
                
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.clear)
            .contentShape(Rectangle())  // 确保整个区域都可以点击
        }
        .buttonStyle(.plain)
        .disabled(isBuiltInCore)
        .help(isBuiltInCore ? "系统标签不可编辑" : "点击编辑标签映射")
    }
}

// MARK: - Tag Manager Window Wrapper

struct TagManagerWindowView: View {
    var body: some View {
        TagManagerView {
            // 窗口模式下不需要onDismiss回调，因为用户可以直接关闭窗口
        }
        .frame(minWidth: 600, minHeight: 500)
        .navigationTitle("标签管理")
    }
}

// MARK: - 复合节点添加界面

struct CompoundNodeAddSheetView: View {
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) var dismiss
    @State private var inputText: String = ""
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索输入框 - 采用与QuickAddSheetView一致的样式
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundColor(.purple)
                
                TextField("输入格式：复合节点名 节点1 节点2 节点3...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isInputFocused)
                    .onKeyPress(.escape) {
                        inputText = ""
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            dismiss()
                        }
                        return .handled
                    }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 使用说明部分
            VStack(alignment: .leading, spacing: 12) {
                Text("💡 使用方法:")
                    .font(.caption)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(Color.purple.opacity(0.8))
                            .frame(width: 8, height: 8)
                        Text("创建1级复合节点：动物 狗 猫 鸟")
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    
                    HStack {
                        Circle()
                            .fill(Color.orange.opacity(0.8))
                            .frame(width: 8, height: 8)
                        Text("创建2级复合节点：生物 动物 植物")
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    
                    HStack {
                        Circle()
                            .fill(Color.red.opacity(0.8))
                            .frame(width: 8, height: 8)
                        Text("删除子节点：动物 -狗 -猫")
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }
                
                Text("复合节点可以无限嵌套，颜色会自动区分层级")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                
                HStack {
                    Text("快捷键: ⌘+Shift+R提交 • Esc关闭")
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
        .navigationTitle("添加复合节点")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    inputText = ""
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
            }
        }
        .alert("错误", isPresented: $showingErrorAlert) {
            Button("确定") { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // 自动聚焦到输入框
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
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
                removeChildrenFromCompoundNode(existingCompoundNode, childNames: childNamesToRemove)
            }
            if !childNamesToAdd.isEmpty {
                addChildrenToExistingCompoundNode(existingCompoundNode, childNames: childNamesToAdd)
            }
        } else {
            // 模式1: 创建新的复合节点
            if !childNamesToRemove.isEmpty {
                errorMessage = "无法从不存在的复合节点中删除子节点"
                showingErrorAlert = true
                return
            }
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
        
        // 获取现有的子节点引用
        let existingChildReferences = compoundNode.tags.compactMap { tag in
            if case .custom(let key) = tag.type, key == "child" {
                return tag.value
            }
            return nil
        }
        
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
        
        
        // 过滤掉要删除的子节点标签
        let updatedTags = compoundNode.tags.filter { tag in
            if case .custom(let key) = tag.type, key == "child" {
                return !childNamesToRemove.contains { childName in
                    tag.value.lowercased() == childName.lowercased()
                }
            }
            return true // 保留非子节点引用标签
        }
        
        _ = existingChildReferences.count - childNamesToRemove.count
        // 计算更新后的层级深度
        let updatedDepth = compoundNode.getCompoundDepth(allNodes: store.nodes)
        let updatedMeaning = "\(updatedDepth)级复合节点"
        
        // 更新复合节点
        store.updateNodeTags(compoundNode.id, tags: updatedTags)
        store.updateNode(compoundNode.id, text: nil, phonetic: nil, meaning: updatedMeaning)
        
        // 清除图谱缓存以刷新显示
        NodeGraphDataCache.shared.invalidateCache(for: compoundNode.id)
        
        // 强制触发UI更新 - 确保WordListView刷新
        DispatchQueue.main.async {
            store.objectWillChange.send()
            
            NotificationCenter.default.post(
                name: Notification.Name("nodesUpdated"),
                object: nil,
                userInfo: ["deletedChildNodes": childNamesToRemove.count]
            )
        }
        
    }
    
    private func addChildrenToExistingCompoundNode(_ compoundNode: Node, childNames: [String]) {
        
        // 获取现有的子节点引用
        let existingChildReferences = compoundNode.tags.compactMap { tag in
            if case .custom(let key) = tag.type, key == "child" {
                return tag.value
            }
            return nil
        }
        
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
        // 计算更新后的层级深度
        let updatedDepth = compoundNode.getCompoundDepth(allNodes: store.nodes)
        let updatedMeaning = "\(updatedDepth)级复合节点"
        
        store.updateNodeTags(compoundNode.id, tags: updatedTags)
        store.updateNode(compoundNode.id, text: nil, phonetic: nil, meaning: updatedMeaning)
        
        // 创建或确保新子节点存在
        var childNodesToCreate: [Node] = []
        for childName in newChildNames {
            if store.nodes.first(where: { $0.text.lowercased() == childName.lowercased() }) != nil {
            } else {
                let childNode = Node(
                    text: childName,
                    phonetic: nil,
                    meaning: nil,
                    layerId: compoundNode.layerId,
                    tags: []
                )
                childNodesToCreate.append(childNode)
            }
        }
        
        // 添加新创建的子节点到store
        for childNode in childNodesToCreate {
            _ = store.addNode(childNode)
        }
        
        // 清除图谱缓存以刷新显示
        NodeGraphDataCache.shared.invalidateCache(for: compoundNode.id)
        
        // 强制触发UI更新 - 确保WordListView刷新
        DispatchQueue.main.async {
            // 触发@Published属性更新
            store.objectWillChange.send()
            
            // 额外触发节点数组的更新通知
            NotificationCenter.default.post(
                name: Notification.Name("nodesUpdated"),
                object: nil,
                userInfo: ["newNodeCount": store.nodes.count]
            )
            
        }
        
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
            // 处理 @节点名 格式，去掉 @ 前缀
            let actualChildName = childName.hasPrefix("@") ? String(childName.dropFirst()) : childName
            
            let childReferenceTag = Tag(
                type: .custom("child"),
                value: actualChildName
            )
            compoundTags.append(childReferenceTag)
        }
        
        for _ in compoundTags.dropFirst() {
        }
        
        // 创建复合节点，只包含复合标签和子节点引用标签
        let compoundNode = Node(
            text: name,
            phonetic: nil,
            meaning: "复合节点：包含 \(childNames.joined(separator: ", "))",
            layerId: layerId,
            tags: compoundTags
        )
        
        // 创建或确保子节点存在
        var childNodes: [Node] = []
        for childName in childNames {
            // 检查是否已存在
            if store.nodes.first(where: { $0.text.lowercased() == childName.lowercased() }) != nil {
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
            }
        }
        
        // 添加到store
        _ = store.addNode(compoundNode)
        for childNode in childNodes {
            _ = store.addNode(childNode)
        }
        
    }
}

// MARK: - Independent Window Wrapper

struct IndependentWindowWrapper: View {
    @StateObject private var store = NodeStore.createIndependentInstance()
    @State private var showPalette = false
    @State private var showQuickAdd = false
    @State private var showQuickSearch = false
    @State private var showCompoundNodeAdd = false
    @State private var nodeToEditInManager: Node? = nil
    @State private var isOpeningWindow = false
    @Environment(\.openWindow) private var openWindow
    
    // 状态管理 - 用于快捷键响应
    @State private var showCommandPalette = false
    
    // 🔧 防重复打开地图窗口的标志
    @State private var isOpeningMapWindow = false
    
    // 生成唯一的窗口ID
    private let windowId = UUID()
    
    var body: some View {
        mainContentView
            .modifier(IndependentWindowModifier(
                showPalette: $showPalette,
                showQuickAdd: $showQuickAdd,
                showQuickSearch: $showQuickSearch,
                showCompoundNodeAdd: $showCompoundNodeAdd,
                showCommandPalette: $showCommandPalette,
                nodeToEditInManager: $nodeToEditInManager,
                isOpeningMapWindow: $isOpeningMapWindow,
                windowId: windowId,
                store: store,
                openWindow: openWindow
            ))
    }
    
    @ViewBuilder
    private var mainContentView: some View {
        ZStack {
            ContentView(windowId: windowId)
                .environmentObject(store)
                .background(WindowClickTracker(windowId: windowId))
                .onAppear {
                    // 🔧 为独立窗口注册窗口焦点管理 - 注册为主窗口类型，支持层图谱映射
                    WindowFocusManager.shared.registerWindow(windowId, type: .standard, displayName: "窗口")
                    WindowFocusManager.shared.setActiveWindow(windowId)
                }
                .onDisappear {
                    // 注销窗口
                    WindowFocusManager.shared.unregisterWindow(windowId)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("nodeUpdated"))) { notification in
                    // 🔧 处理节点更新通知，确保独立窗口UI能实时刷新
                    
                    if let updatedNode = notification.object as? Node {
                        
                        // 查找并更新store中的对应节点
                        if store.nodes.contains(where: { $0.id == updatedNode.id }) {
                            // 使用NodeStore的updateNode方法来正确更新节点
                            store.updateNode(updatedNode)
                            
                            // 如果当前选中的节点是更新的节点，也要更新选中节点引用
                            if store.selectedNode?.id == updatedNode.id {
                                store.setSelectedNode(updatedNode)
                            }
                        } else {
                        }
                    } else {
                    }
                }
            
            if showPalette {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                        }
                    
                    CommandPaletteView(isPresented: $showPalette)
                        .environmentObject(store)
                        .transition(.asymmetric(insertion: AnyTransition.scale.combined(with: .opacity), removal: .opacity))
                }
            }
            
            if showQuickSearch {
                QuickSearchView(
                    onDismiss: { 
                        showQuickSearch = false 
                    },
                    onNodeSelected: { node in
                        
                        if let nodeLayer = store.layers.first(where: { $0.id == node.layerId }) {
                            store.setCurrentLayer(nodeLayer)
                        }
                        
                        store.selectNode(node)
                    }
                )
                .environmentObject(store)
                .onAppear {
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showPalette)
        .onChange(of: showQuickSearch) { _, newValue in
        }
        .onKeyPress(.escape) {
            if showPalette {
                showPalette = false
                return .handled
            }
            if showQuickSearch {
                showQuickSearch = false
                return .handled
            }
            return .ignored
        }
    }
}

// MARK: - IndependentWindowModifier

struct SheetsModifier: ViewModifier {
    @Binding var showQuickAdd: Bool
    @Binding var showCompoundNodeAdd: Bool
    @Binding var showCommandPalette: Bool
    let windowId: UUID
    let store: NodeStore

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showQuickAdd) {
                QuickAddSheetView(windowId: windowId)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showCompoundNodeAdd) {
                CompoundNodeAddSheetView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showCommandPalette) {
                CommandPaletteSheetView(isPresented: $showCommandPalette)
                    .environmentObject(store)
            }
    }
}

struct FocusedValuesModifier: ViewModifier {
    @Binding var showCommandPalette: Bool
    @Binding var showQuickAdd: Bool
    @Binding var showQuickSearch: Bool
    @Binding var isOpeningMapWindow: Bool
    let windowId: UUID
    let openWindow: OpenWindowAction

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.showCommandPalette, ShowCardAction {
                showCommandPalette = true
            })
            .focusedSceneValue(\.addNewNode, ShowCardAction {
                showQuickAdd = true
            })
            .focusedSceneValue(\.openQuickSearch, ShowCardAction {
                showQuickSearch = true
            })
            .focusedSceneValue(\.openTagManager, ShowCardAction {
                openWindow(id: "tagManager")
            })
            .focusedSceneValue(\.openNodeManager, ShowCardAction {
                openWindow(id: "nodeManager")
            })
            .focusedSceneValue(\.openMapWindow, ShowCardAction {
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true) else {
                    return
                }

                guard !isOpeningMapWindow else {
                    return
                }

                isOpeningMapWindow = true
                openWindow(id: "map")

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let mappingInfo = ["sourceWindowId": windowId.uuidString]
                    NotificationCenter.default.post(
                        name: NSNotification.Name("mapWindowSetupMapping"),
                        object: mappingInfo
                    )
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    isOpeningMapWindow = false
                }
            })
            .focusedSceneValue(\.openGraphWindow, ShowCardAction {
                NodeGraphWindowManager.shared.showNodeGraphWindow()
            })
            .focusedSceneValue(\.toggleSidebar, ShowCardAction {
                NotificationCenter.default.post(
                    name: NSNotification.Name("executeToggleSidebar"),
                    object: nil,
                    userInfo: ["windowId": windowId.uuidString]
                )
            })
            .focusedSceneValue(\.openNewWindow, ShowCardAction {
                openWindow(id: "layerView")
            })
            .focusedSceneValue(\.switchToDetailTab, ShowCardAction {
                NotificationCenter.default.post(name: NSNotification.Name("switchToDetailTab"), object: nil)
            })
            .focusedSceneValue(\.switchToGraphTab, ShowCardAction {
                NotificationCenter.default.post(name: NSNotification.Name("switchToGraphTab"), object: nil)
            })
            .focusedSceneValue(\.clearTagFilter, ShowCardAction {
                NotificationCenter.default.post(name: NSNotification.Name("clearTagFilter"), object: nil)
            })
            .focusedSceneValue(\.restorePreviousTagFilterState, ShowCardAction {
                NotificationCenter.default.post(name: NSNotification.Name("restorePreviousTagFilterState"), object: nil)
            })
            .focusedSceneValue(\.openTagSearch, ShowCardAction {
                NotificationCenter.default.post(
                    name: NSNotification.Name("tagSidebarOpenTagSearch"),
                    object: nil,
                    userInfo: ["windowId": windowId.uuidString]
                )
            })
    }
}

struct IndependentWindowModifier: ViewModifier {
    @Binding var showPalette: Bool
    @Binding var showQuickAdd: Bool
    @Binding var showQuickSearch: Bool
    @Binding var showCompoundNodeAdd: Bool
    @Binding var showCommandPalette: Bool
    @Binding var nodeToEditInManager: Node?
    @Binding var isOpeningMapWindow: Bool
    let windowId: UUID
    let store: NodeStore
    let openWindow: OpenWindowAction
    
    func body(content: Content) -> some View {
        content
            .modifier(SheetsModifier(
                showQuickAdd: $showQuickAdd,
                showCompoundNodeAdd: $showCompoundNodeAdd,
                showCommandPalette: $showCommandPalette,
                windowId: windowId,
                store: store
            ))
            .modifier(FocusedValuesModifier(
                showCommandPalette: $showCommandPalette,
                showQuickAdd: $showQuickAdd,
                showQuickSearch: $showQuickSearch,
                isOpeningMapWindow: $isOpeningMapWindow,
                windowId: windowId,
                openWindow: openWindow
            ))
            .overlay {
                if showQuickSearch {
                    QuickSearchView(
                        onDismiss: {
                            showQuickSearch = false
                        },
                        onNodeSelected: { node in
                            if let nodeLayer = store.layers.first(where: { $0.id == node.layerId }) {
                                store.setCurrentLayer(nodeLayer)
                            }
                            store.selectNode(node)
                            showQuickSearch = false
                        }
                    )
                    .environmentObject(store)
                    .transition(.opacity)
                    .zIndex(1000)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("clearTagFilterFromKeyboard"))) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
                    store.clearTagFilter()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("executeOpenWindow"))) { notification in
                // 🔧 检查源窗口ID，确保只有一个窗口处理这个通知
                if let sourceWindowId = notification.userInfo?["sourceWindowId"] as? String {
                    // 如果指定了源窗口ID，只有匹配的窗口处理
                    guard sourceWindowId == windowId.uuidString else {
                        return
                    }
                } else {
                    // 如果没有源窗口ID，使用原有的活跃窗口检查
                    guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: false, commandName: "executeOpenWindow") else {
                        return
                    }
                }
                
                if let windowType = notification.object as? String {
                    
                    // 🔧 对于层图谱窗口，使用全局唯一检查
                    if windowType == "layerGraph" {
                        if !WindowFocusManager.shared.reserveGlobalLayerGraphWindow() {
                            // 获取已存在的层图谱窗口ID
                            if let existingLayerGraphId = WindowFocusManager.shared.getGlobalLayerGraphWindowId() {
                                // 发送通知激活层图谱窗口
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("focusLayerGraphWindow"),
                                    object: nil,
                                    userInfo: ["windowId": existingLayerGraphId]
                                )
                            }
                            return
                        }
                    }
                    
                    openWindow(id: windowType)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("showCommandPalette"))) { _ in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true, commandName: "showCommandPalette") else {
                    return
                }
                // 🔧 改为发送executeOpenWindow通知，统一窗口打开逻辑
                // 🔧 传递源窗口ID以防止重复处理
                NotificationCenter.default.post(
                    name: NSNotification.Name("executeOpenWindow"), 
                    object: "layerGraph",
                    userInfo: ["sourceWindowId": windowId.uuidString]
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("addNewNode"))) { _ in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true) else {
                    return
                }
                showQuickAdd = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openNodeManagerForEdit"))) { notification in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true, commandName: "openNodeManagerForEdit") else {
                    return
                }
                if let node = notification.object as? Node {
                    nodeToEditInManager = node
                    // 先打开节点管理窗口
                    NotificationCenter.default.post(name: Notification.Name("openNodeManager"), object: nil)
                    // 延迟发送编辑节点通知，确保窗口已打开
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NotificationCenter.default.post(name: Notification.Name("nodeManagerEditNode"), object: node)
                    }
                }
            }
            // openTagSearch通知已经由TagSidebarView直接处理，不需要在这里转发
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openQuickSearch"))) { _ in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true) else {
                    return
                }
                showQuickSearch = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openGraphWindow"))) { _ in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true) else {
                    return
                }
                NotificationCenter.default.post(name: NSNotification.Name("executeOpenGraphWindow"), object: "independent")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("requestMapForLocationSelection"))) { notification in
                // 🔧 处理来自QuickAddSheetView的位置选择请求
                if let notificationData = notification.object as? [String: String],
                   let requestSource = notificationData["requestSource"],
                   let requestWindowId = notificationData["windowId"] {
                    // 只处理发给这个特定独立窗口的请求
                    if requestSource == "INDEPENDENT_WINDOW" && requestWindowId == windowId.uuidString {
                        
                        // 🔧 防重复机制：检查是否正在打开地图窗口
                        guard !isOpeningMapWindow else {
                            return
                        }
                        
                        isOpeningMapWindow = true
                        openWindow(id: "map")
                        
                        // 设置窗口映射信息和位置选择模式
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            let mappingInfo = ["sourceWindowId": windowId.uuidString]
                            NotificationCenter.default.post(
                                name: NSNotification.Name("mapWindowSetupMapping"),
                                object: mappingInfo
                            )
                        }
                        
                        // 🔧 发送位置选择模式通知
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("openMapForLocationSelection"), 
                                object: ["requestTime": Date()]
                            )
                        }
                        
                        // 1秒后重置防重复标志
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isOpeningMapWindow = false
                        }
                    } else {
                    }
                } else if let requestSource = notification.object as? String {
                    // 向后兼容旧格式
                    if requestSource == "INDEPENDENT_WINDOW" {
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openMapWindow"))) { notification in
                // 🔧 修复：检查通知是否包含源窗口信息，如果包含则只有匹配的窗口才处理
                if let sourceInfo = notification.object as? [String: String],
                   let targetSourceWindowId = sourceInfo["sourceWindowId"] {
                    
                    // 检查是否是发给这个独立窗口的
                    if targetSourceWindowId == windowId.uuidString {
                        // 🔧 添加防重复机制
                        guard !isOpeningMapWindow else {
                            return
                        }
                        
                        isOpeningMapWindow = true
                        openWindow(id: "map")
                        
                        // 🔧 发送窗口映射信息
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            let mappingInfo = ["sourceWindowId": windowId.uuidString]
                            NotificationCenter.default.post(
                                name: NSNotification.Name("mapWindowSetupMapping"),
                                object: mappingInfo
                            )
                        }
                        
                        // 1秒后重置防重复标志
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isOpeningMapWindow = false
                        }
                    } else {
                    }
                    return
                }
                
                // 如果没有源窗口信息，使用原有的全局命令逻辑（向后兼容）
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true) else {
                    return
                }
                
                // 🔧 添加防重复机制
                guard !isOpeningMapWindow else {
                    return
                }
                
                isOpeningMapWindow = true
                openWindow(id: "map")
                
                // 🔧 发送窗口映射信息
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let mappingInfo = ["sourceWindowId": windowId.uuidString]
                    NotificationCenter.default.post(
                        name: NSNotification.Name("mapWindowSetupMapping"),
                        object: mappingInfo
                    )
                }
                
                // 1秒后重置防重复标志
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    isOpeningMapWindow = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openTagManager"))) { _ in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true, commandName: "openTagManager") else {
                    return
                }
                openWindow(id: "tagManager")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openNodeManager"))) { _ in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true, commandName: "openNodeManager") else {
                    return
                }
                NotificationCenter.default.post(name: NSNotification.Name("executeOpenNodeManager"), object: "independent")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("toggleSidebar"))) { _ in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true) else {
                    return
                }
                NotificationCenter.default.post(name: NSNotification.Name("executeToggleSidebar"), object: "independent")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("switchToDetailTab"))) { _ in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId) else {
                    return
                }
                // 发送执行命令，避免循环
                NotificationCenter.default.post(name: NSNotification.Name("executeDetailTabSwitch"), object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("switchToGraphTab"))) { _ in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId) else {
                    return
                }
                // 发送执行命令，避免循环
                NotificationCenter.default.post(name: NSNotification.Name("executeGraphTabSwitch"), object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("clearTagFilter"))) { _ in
                // clearTagFilter是全局命令，应该在任何活跃窗口中可用
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true, commandName: "clearTagFilter") else {
                    return
                }
                store.clearTagFilter()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("restorePreviousTagFilterState"))) { _ in
                // restorePreviousTagFilterState是全局命令，应该在任何活跃窗口中可用
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true, commandName: "restorePreviousTagFilterState") else {
                    return
                }
                store.restorePreviousTagFilterState()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("switchToLayer"))) { notification in
                // 🔧 处理来自层图谱窗口的层切换请求
                guard let layer = notification.object as? Layer else {
                    return
                }
                
                if let userInfo = notification.userInfo,
                   let sourceWindowId = userInfo["sourceWindowId"] as? String,
                   !sourceWindowId.isEmpty {
                    
                    // 🔧 调试：打印窗口ID信息
                    
                    // 检查是否是发给这个独立窗口的
                    if sourceWindowId == windowId.uuidString {
                        Task {
                            await store.switchToLayer(layer)
                        }
                    } else {
                    }
                } else {
                    // 如果没有指定源窗口，使用WindowFocusManager检查
                    guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: false, commandName: "switchToLayer") else {
                        return
                    }
                    Task {
                        await store.switchToLayer(layer)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("handleMapPinTap"))) { notification in
                guard let userInfo = notification.userInfo,
                      let targetNodeId = userInfo["targetNodeId"] as? String,
                      let targetLayerId = userInfo["targetLayerId"] as? String else {
                    return
                }
                
                // 🔧 从当前store实例中查找对应的节点和层
                guard let targetNodeUUID = UUID(uuidString: targetNodeId),
                      let targetNode = store.nodes.first(where: { $0.id == targetNodeUUID }) else {
                    return
                }
                
                guard let targetLayerUUID = UUID(uuidString: targetLayerId),
                      let targetLayer = store.layers.first(where: { $0.id == targetLayerUUID }) else {
                    return
                }
                
                // 🔧 重新设计通知路由逻辑：优先检查目标窗口ID，然后检查活跃状态
                // 如果指定了目标窗口ID，必须完全匹配才处理
                if let targetWindowId = userInfo["targetWindowId"] as? String {
                    if targetWindowId != windowId.uuidString {
                        return
                    }
                } else {
                    // 如果没有指定目标窗口ID，则使用WindowFocusManager进行活跃窗口检查
                    guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: false, commandName: "handleMapPinTap") else {
                        return
                    }
                }
                
                
                // 执行层切换和标签展开操作
                Task {
                    await store.switchToLayer(targetLayer)
                    
                    await MainActor.run {
                        store.expandLocationTagAndSelect(targetNode)
                        
                        // 发送通知切换到地图标签
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("switchToMapTab"),
                                object: targetNode
                            )
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("executeOpenNodeManager"))) { notification in
                // 只处理来自独立窗口的请求
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true, commandName: "executeOpenNodeManager") else {
                    return
                }
                
                if let source = notification.object as? String, source == "independent" {
                    openWindow(id: "nodeManager")
                } else {
                }
            }
            // 🚫 移除executeOpenMapWindow处理器，避免重复打开地图窗口
            // 现在直接在requestMapForLocationSelection处理器中打开地图窗口
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("requestWindowMapping"))) { notification in
                // 独立窗口处理窗口映射请求 - 这是关键修复！
                
                if let requestInfo = notification.object as? [String: String],
                   let _ = requestInfo["childWindowId"],
                   let _ = requestInfo["windowType"] {
                    
                    // 独立窗口的ID作为源窗口
                    let sourceWindowId = windowId.uuidString
                    
                    // 发送映射信息
                    let mappingInfo = ["sourceWindowId": sourceWindowId]
                    NotificationCenter.default.post(
                        name: NSNotification.Name("mapWindowSetupMapping"),
                        object: mappingInfo
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("requestWindowMappingForMap"))) { notification in
                // 🔧 处理地图窗口的主动映射请求
                
                if let requestInfo = notification.object as? [String: String],
                   let mapWindowId = requestInfo["mapWindowId"] {
                    
                    // 检查这个独立窗口是否应该响应（即它是否是活跃窗口或最近活跃的非地图窗口）
                    if WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: false) {
                        let sourceWindowId = windowId.uuidString
                        
                        // 🎯 发送带目标地图窗口ID的映射信息
                        let mappingInfo = [
                            "sourceWindowId": sourceWindowId,
                            "targetMapWindowId": mapWindowId
                        ]
                        NotificationCenter.default.post(
                            name: NSNotification.Name("mapWindowSetupMapping"),
                            object: mappingInfo
                        )
                    } else {
                    }
                }
            }
    }
}


// MARK: - Global Commands Handler

struct GlobalCommands: Commands {
    @FocusedValue(\.showCommandPalette) var showCommandPalette
    @FocusedValue(\.addNewNode) var addNewNode
    @FocusedValue(\.openQuickSearch) var openQuickSearch
    @FocusedValue(\.openTagManager) var openTagManager
    @FocusedValue(\.openNodeManager) var openNodeManager
    @FocusedValue(\.openMapWindow) var openMapWindow
    @FocusedValue(\.openGraphWindow) var openGraphWindow
    @FocusedValue(\.toggleSidebar) var toggleSidebar
    @FocusedValue(\.openNewWindow) var openNewWindow
    @FocusedValue(\.switchToDetailTab) var switchToDetailTab
    @FocusedValue(\.switchToGraphTab) var switchToGraphTab
    @FocusedValue(\.clearTagFilter) var clearTagFilter
    @FocusedValue(\.openTagSearch) var openTagSearch
    @FocusedValue(\.restorePreviousTagFilterState) var restorePreviousTagFilterState
    
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {}
        CommandMenu("shortcut") {
            Button("层结构图谱") {
                // 🔧 通过showCommandPalette发送，由WindowFocusManager统一控制
                NotificationCenter.default.post(name: NSNotification.Name("showCommandPalette"), object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command])
            
            Button("快速添加节点") {
                addNewNode?()
            }
            .keyboardShortcut("i", modifiers: [.command])
            .disabled(addNewNode == nil)
            
            Button("快速搜索") {
                openQuickSearch?()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(openQuickSearch == nil)
            
            Button("标签搜索") {
                openTagSearch?()
            }
            .keyboardShortcut("f", modifiers: [.command])
            
            Divider()
            
            Button("标签管理") {
                openTagManager?()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(openTagManager == nil)
            
            Button("节点管理") {
                openNodeManager?()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(openNodeManager == nil)
            
            Divider()
            
            Button("切换侧边栏") {
                toggleSidebar?()
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(toggleSidebar == nil)
            
            
            Button("清除标签筛选") {
                // 直接发送通知，让独立窗口处理
                NotificationCenter.default.post(name: NSNotification.Name("clearTagFilterFromKeyboard"), object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command])
            
            Button("恢复标签筛选") {
                restorePreviousTagFilterState?()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(restorePreviousTagFilterState == nil)
            
            // 测试用：手动保存状态
            Button("保存标签筛选状态 (测试)") {
                // 直接调用store的公共方法
                NodeStore.shared.saveCurrentTagFilterStatePublic()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            
            Divider()
            
            Button("打开地图") {
                openMapWindow?()
            }
            .keyboardShortcut("m", modifiers: [.command])
            .disabled(openMapWindow == nil)
            
            Button("节点图谱") {
                NodeGraphWindowManager.shared.showNodeGraphWindow()
            }
            .keyboardShortcut("g", modifiers: [.command])
            
            Button("全局标签图谱") {
                GlobalTagGraphWindowManager.shared.showGlobalTagGraphWindow()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            
            Button("节点看板") {
                NodeBoardWindowManager.shared.showNodeBoardWindow()
            }
            .keyboardShortcut("b", modifiers: [.command])
            
            Button("标签索引看板") {
                NewTagIndexWindowManager.shared.showTagIndexWindow()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            
            Divider()
            
            Button("详情面板：详情") {
                switchToDetailTab?()
            }
            .keyboardShortcut("l", modifiers: [.command])
            .disabled(switchToDetailTab == nil)
            
            Button("详情面板：图谱") {
                switchToGraphTab?()
            }
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(switchToGraphTab == nil)
            
            Button("切换到图谱视图") {
                switchToGraphTab?()
            }
            .keyboardShortcut("o", modifiers: [.command])
            .disabled(switchToGraphTab == nil)
            
            Divider()
            
            Button("新建独立窗口") {
                openNewWindow?()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(openNewWindow == nil)
        }
    }
}

// MARK: - Window Click Tracker

/// A view that tracks actual mouse clicks on its window and distinguishes them from system-generated focus changes
struct WindowClickTracker: NSViewRepresentable {
    let windowId: UUID
    
    func makeNSView(context: Context) -> NSView {
        let view = ClickDetectorView(windowId: windowId)
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // No updates needed
    }
    
    class ClickDetectorView: NSView {
        let windowId: UUID
        private var mouseDownTime: Date?
        private var lastClickNotificationTime: Date = Date.distantPast
        private let clickNotificationCooldown: TimeInterval = 0.5 // 防止重复通知
        
        init(windowId: UUID) {
            self.windowId = windowId
            super.init(frame: .zero)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window = window {
                // 监听窗口的鼠标按下事件
                window.acceptsMouseMovedEvents = true
            }
        }
        
        override func hitTest(_ point: NSPoint) -> NSView? {
            // 让事件穿透，不影响正常的UI交互
            return nil
        }
        
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            
            if let window = newWindow {
                // 使用responder chain来检测窗口上的鼠标点击
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidBecomeKey(_:)),
                    name: NSWindow.didBecomeKeyNotification,
                    object: window
                )
            } else if let window = window {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.didBecomeKeyNotification,
                    object: window
                )
            }
        }
        
        @objc private func windowDidBecomeKey(_ notification: Notification) {
            // 检查是否是由鼠标事件触发的窗口激活
            if let event = NSApp.currentEvent,
               event.type == .leftMouseDown || event.type == .rightMouseDown {
                // 这是真正的用户点击
                let now = Date()
                if now.timeIntervalSince(lastClickNotificationTime) > clickNotificationCooldown {
                    lastClickNotificationTime = now
                    
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("userClickedWindow"),
                            object: nil,
                            userInfo: [
                                "windowId": self.windowId.uuidString,
                                "windowType": "standard",
                                "isRealClick": true
                            ]
                        )
                    }
                }
            }
        }
        
        deinit {
            if let window = window {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.didBecomeKeyNotification,
                    object: window
                )
            }
        }
    }
}

