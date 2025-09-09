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
    print("🎯 Window title will be: '\(result)'")
    
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
    
    // 动态添加缺失的标签映射（带冲突检测）
    func addMappingIfNeeded(key: String, typeName: String) -> Bool {
        let normalizedKey = key.lowercased()
        
        // 检查是否已存在**完全相同的key**的映射
        if let existingIndex = tagMappings.firstIndex(where: { $0.key == normalizedKey }) {
            let existingMapping = tagMappings[existingIndex]
            
            // 只有当key完全相同时才考虑更新typeName
            // 这里我们不更新，因为可能破坏现有的映射关系
            if existingMapping.typeName != typeName {
                print("⚠️ 映射冲突：key '\(normalizedKey)' 已存在，typeName '\(existingMapping.typeName)' != '\(typeName)'，保持现有映射")
                return false // 返回false表示冲突
            } else {
                print("✅ 映射已存在且相同: \(normalizedKey) -> \(typeName)")
                return true // 返回true表示成功（已存在相同映射）
            }
        } else {
            // 不存在相同key的映射，可以安全添加
            let newMapping = TagMapping(key: normalizedKey, typeName: typeName)
            tagMappings.append(newMapping)
            saveToUserDefaults()
            print("🔄 自动添加标签映射: \(key) -> \(typeName)")
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
            print("🔄 更新现有标签映射: \(normalizedKey) -> \(mapping.typeName)")
        } else {
            tagMappings.append(newMapping)
            print("➕ 添加新标签映射: \(normalizedKey) -> \(mapping.typeName)")
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
            print("🔄 更新标签映射: \(normalizedKey) -> \(mapping.typeName)")
        } else {
            // 如果找不到现有映射，则添加新的
            addMapping(updatedMapping)
        }
    }
    
    /// 删除标签映射
    func removeMapping(_ mapping: TagMapping) {
        print("🗑️ TagMappingManager.removeMapping() 开始")
        print("   - 要删除的映射: id=\(mapping.id), key=\(mapping.key), typeName=\(mapping.typeName)")
        
        if let index = tagMappings.firstIndex(where: { $0.id == mapping.id }) {
            let removedMapping = tagMappings.remove(at: index)
            print("   - 已删除映射: \(removedMapping.key) -> \(removedMapping.typeName)")
            
            saveToUserDefaults()
            
            // 同步到外部存储
            Task {
                do {
                    try await ExternalDataService.shared.saveTagMappingsOnly()
                    print("✅ 删除后TagMappings已同步到外部存储")
                } catch {
                    print("⚠️ 删除后TagMappings同步到外部存储失败: \(error)")
                }
            }
            
            print("✅ TagMappingManager.removeMapping() 完成")
        } else {
            print("⚠️ 未找到要删除的映射: \(mapping.key)")
        }
    }
    
    /// 批量删除标签映射
    func removeMappings(_ mappings: [TagMapping]) {
        print("🗑️ TagMappingManager.removeMappings() 开始批量删除 \(mappings.count) 个映射")
        
        let idsToRemove = Set(mappings.map { $0.id })
        let removedCount = tagMappings.count
        
        tagMappings.removeAll { mapping in
            idsToRemove.contains(mapping.id)
        }
        
        let actualRemovedCount = removedCount - tagMappings.count
        print("   - 实际删除了 \(actualRemovedCount) 个映射")
        
        if actualRemovedCount > 0 {
            saveToUserDefaults()
            
            // 同步到外部存储
            Task {
                do {
                    try await ExternalDataService.shared.saveTagMappingsOnly()
                    print("✅ 批量删除后TagMappings已同步到外部存储")
                } catch {
                    print("⚠️ 批量删除后TagMappings同步到外部存储失败: \(error)")
                }
            }
        }
        
        print("✅ TagMappingManager.removeMappings() 完成")
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
        print("🔧 确保内置核心标签存在...")
        
        for coreTag in Self.builtInCoreTags {
            if !tagMappings.contains(where: { $0.key == coreTag.key }) {
                print("   + 添加内置核心标签: \(coreTag.key) -> \(coreTag.typeName)")
                tagMappings.append(coreTag)
            }
        }
        
        // 🔧 移除自动beef映射恢复逻辑，允许用户永久删除beef映射
        print("🔧 内置核心标签确保完成，不再自动恢复已删除的beef映射")
    }
    
    // 🔧 已移除自动beef映射恢复功能，允许用户永久删除beef映射
    // private func restoreMostRecentBeefMapping() -> TagMapping? { ... }
    
    // 修复节点中错误的标签类型
    @MainActor
    func fixNodeTagTypes(store: NodeStore) {
        print("🔧 开始修复节点中的错误标签类型...")
        
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
                        print("🔧 修复标签类型: .custom(\"\(customName)\") -> .custom(\"\(correctMapping.key)\")")
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
            print("🔧 更新节点 '\(node.text)' 的标签")
        }
        
        if fixedCount > 0 {
            print("✅ 修复了 \(fixedCount) 个错误的标签类型")
        } else {
            print("✅ 没有发现需要修复的标签类型")
        }
    }
    
    // 🔧 已移除强制重建beef映射功能，允许用户永久删除beef映射
    // func forceRebuildBeefMapping() { ... }
    
    // 重置为默认映射
    func resetToDefaults() {
        print("🔄 TagMappingManager.resetToDefaults() 开始")
        
        // 只包含内置核心标签，不再自动添加其他预设标签
        tagMappings = Self.builtInCoreTags
        
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
    
    // 重新扫描现有标签并更新映射
    @MainActor
    func rescanAndUpdateMappings() {
        print("🔄 TagMappingManager: 重新扫描现有标签...")
        
        // 保留现有的映射，只添加缺失的自动扫描映射
        let currentMappings = tagMappings
        let scannedMappings = getDefaultMappings()
        
        // 合并映射：保留现有映射，只添加新发现的
        var finalMappings = currentMappings
        
        for scannedMapping in scannedMappings {
            if !finalMappings.contains(where: { $0.key == scannedMapping.key }) {
                finalMappings.append(scannedMapping)
                print("   + 添加新扫描映射: \(scannedMapping.key) -> \(scannedMapping.typeName)")
            }
        }
        
        // 🔧 修复错误的映射：检查节点中的实际标签值来推断正确的显示名称
        fixIncorrectMappings(&finalMappings)
        
        tagMappings = finalMappings
        print("🔄 重新扫描完成，保留现有映射并添加新发现的映射")
        print("🔄 最终映射: \(tagMappings.map { "\($0.key)->\($0.typeName)" })")
        
        // 保存到外部存储
        Task {
            try? await ExternalDataService.shared.saveTagMappingsOnly()
        }
    }
    
    // 公开方法：立即修复标签映射
    public func fixTagMappings() async {
        await MainActor.run {
            print("🔧 手动触发标签映射修复...")
            var currentMappings = tagMappings
            fixIncorrectMappings(&currentMappings)
            tagMappings = currentMappings
        }
        
        // 保存到外部存储
        try? await ExternalDataService.shared.saveTagMappingsOnly()
    }
    
    // 修复错误的标签映射
    private func fixIncorrectMappings(_ mappings: inout [TagMapping]) {
        print("🔧 检查并修复错误的标签映射...")
        
        // 检查每个映射是否正确
        for (index, mapping) in mappings.enumerated() {
            // 特别检查 "oo" 映射的情况
            if mapping.key == "oo" && mapping.typeName == "oo" {
                let correctTypeName = "好看" // 基于用户反馈的正确映射
                print("🔧 修复 oo 映射: \(mapping.key) -> \(mapping.typeName) 应该是 -> \(correctTypeName)")
                
                let correctedMapping = TagMapping(
                    id: mapping.id,
                    key: mapping.key,
                    typeName: correctTypeName
                )
                mappings[index] = correctedMapping
                print("✅ 已修复 oo 映射")
            }
            
            // 通用修复逻辑：如果key和typeName相同，但实际使用中应该有更好的显示名称
            if mapping.key == mapping.typeName {
                // 这里可以添加更多的修复逻辑
                // 对于现在的问题，主要是修复 "oo" 的情况
                print("⚠️ 发现可能需要修复的映射: \(mapping.key) -> \(mapping.typeName)")
            }
        }
        
        print("🔧 映射修复检查完成")
    }
    
    // 获取默认映射
    @MainActor
    private func getDefaultMappings() -> [TagMapping] {
        // 只包含内置核心标签，不再自动添加commonTags
        var mappings = Self.builtInCoreTags
        
        // 扫描现有节点中的标签，自动创建缺失的映射
        let store = NodeStore.shared
        let allTags = store.allTags
        
        print("🔍 扫描现有标签创建映射: 发现 \(allTags.count) 个标签")
        
        // 详细调试输出
        for tag in allTags {
            print("   检查标签: value='\(tag.value)', type=\(tag.type), displayName='\(tag.type.displayName)'")
            if case .custom(let key) = tag.type {
                // 检查是否已有映射
                if !mappings.contains(where: { $0.key == key.lowercased() }) {
                    let newMapping = TagMapping(key: key.lowercased(), typeName: key)
                    mappings.append(newMapping)
                    print("   + 自动创建标签映射: \(key)")
                } else {
                    print("   = 已存在标签映射: \(key)")
                }
            } else {
                print("   - 非自定义标签，跳过: \(tag.type)")
            }
        }
        
        print("🔍 最终映射数量: \(mappings.count)")
        return mappings
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
        loadTagMappingsFromUserDefaults()
    }
    
    // 从UserDefaults加载（作为fallback）
    @MainActor
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
                        print("🔧 DEBUG: 添加按钮被点击")
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
                            store.duplicateNodeAlert = nil
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
                            if let details = alert.conflictDetails {
                                print("🔍 冲突详情: \(details)")
                            }
                            store.duplicateNodeAlert = nil
                        }
                    } else if alert.isDuplicate && alert.existingNode != nil {
                        // 节点重复，询问是否合并
                        Button("取消", role: .cancel) { 
                            store.duplicateNodeAlert = nil
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
                print("🚨 QuickAddSheetView: 收到紧急窗口清理通知，立即关闭")
                cleanupAndDismiss()
            }
            .onKeyPress(.escape) {
                print("🚪 QuickAddSheetView: Escape键被按下，强制关闭对话框")
                cleanupAndDismiss()
                return .handled
            }
            .onKeyPress(.init("p"), phases: .down) { keyPress in
                if keyPress.modifiers.contains(.command) && isInputFocused {
                    // 🔧 修复：只在当前窗口有焦点时响应Command+P
                    guard let windowId = windowId, WindowFocusManager.shared.isActiveWindow(windowId) else {
                        print("🚫 忽略Command+P - 当前窗口不是活动窗口")
                        return .ignored
                    }
                    
                    openMapForLocationSelection()
                    return .handled
                }
                return .ignored
            }
            .background(
                // 使用隐藏按钮来捕获快捷键
                Button("") {
                    print("⌨️ Command+Shift+R 通过按钮触发")
                    print("📝 当前输入文本: '\(inputText)'")
                    guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        print("⚠️ 输入为空，忽略Command+Shift+R")
                        return
                    }
                    processCompoundNodeInput()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .hidden()
            )
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
                TextField("输入: 节点 root 词根内容 memory 记忆内容... 试试用Command+Shift+R建立复合节点", text: $inputText)
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
        print("🚪 QuickAddSheetView: cleanupAndDismiss called")
        
        // 立即清理状态
        isInputFocused = false
        inputText = ""
        selectedSuggestionIndex = -1
        suggestions = []
        showingDuplicateAlert = false
        showingTagModificationAlert = false
        isWaitingForLocationSelection = false
        
        // 清理Store中可能遗留的alert状态
        store.duplicateNodeAlert = nil
        store.tagTypeModificationAlert = nil
        
        // 立即调用dismiss，不使用延迟
        dismiss()
        
        print("✅ QuickAddSheetView: 清理和关闭完成")
    }
    
    private func processCompoundNodeInput() {
        print("🔄 开始处理复合节点输入: \(inputText)")
        
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
        
        print("🔧 复合节点名: \(compoundNodeName)")
        print("🔧 子节点列表: \(childNodeNames)")
        
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
                print("🗑️ 从复合节点删除子节点: \(compoundNodeName)")
                removeChildrenFromCompoundNode(existingCompoundNode, childNames: childNamesToRemove)
            }
            if !childNamesToAdd.isEmpty {
                print("➕ 向复合节点添加子节点: \(compoundNodeName)")
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
            print("🏗️ 创建新复合节点: \(compoundNodeName)")
            createNewCompoundNode(name: compoundNodeName, childNames: childNamesToAdd, layerId: currentLayer.id)
        }
        
        // 成功处理后清空输入并关闭
        inputText = ""
        dismiss()
        
        print("✅ 复合节点命令处理完成")
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
            print("🔄 [QuickAdd] 编辑模式开始预填充节点: '\(node.text)'")
            print("🔄 [QuickAdd] 节点标签数量: \(node.tags.count)")
            for (index, tag) in node.tags.enumerated() {
                print("🔄 [QuickAdd] 标签[\(index)]: type=\(tag.type), rawValue='\(tag.type.rawValue)', displayName='\(tag.type.displayName)', value='\(tag.value)'")
            }
            
            inputText = node.commandRepresentationWithDisplayNames
            print("🔄 [QuickAdd] 编辑模式：预填充命令完成 - '\(inputText)'")
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
                
                if let locationName = locationData["name"] as? String {
                    let locationCommand = "@\(latitude),\(longitude)[\(locationName)]"
                    insertLocationIntoInput(locationCommand)
                    print("🎯 QuickAdd: Using location with name: \(locationName)")
                } else {
                    let locationCommand = "@\(latitude),\(longitude)[]"
                    insertLocationIntoInput(locationCommand)
                    print("🎯 QuickAdd: Using coordinates only, user needs to fill name")
                }
            } else if let locationName = notification.object as? String {
                insertLocationIntoInput("location \(locationName)")
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
        print("🔧 DEBUG: processInput() called with inputText: '\(inputText)'")
        print("🔧 DEBUG: inputText is empty: \(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)")
        print("🔧 DEBUG: prefilledNode: \(prefilledNode?.text ?? "nil")")
        print("🔧 DEBUG: current layer: \(store.currentLayer?.displayName ?? "nil")")
        
        // 🔧 添加异常保护，避免命令解析时崩溃
        do {
            try processInputSafely()
        } catch {
            print("❌ 命令处理异常: \(error)")
            // 显示友好的错误信息
            store.duplicateNodeAlert = NodeStore.DuplicateNodeAlert(
                message: "命令处理失败: \(error.localizedDescription)",
                isDuplicate: false,
                existingNode: nil,
                newNode: Node(text: "错误", layerId: UUID(), tags: [])
            )
        }
    }
    
    private func processInputSafely() throws {
        let components = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        
        guard !components.isEmpty else { 
            return 
        }
        
        
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
                            
                            print("🔔 检测到标签类型名称修改: '\(oldTypeName)' -> '\(newTypeName)', 影响 \(affectedNodes.count) 个节点")
                            
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
                                    print("✅ 用户确认标签类型修改")
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
                                    print("❌ 用户取消标签类型修改")
                                    inputText = ""
                                    store.tagTypeModificationAlert = nil
                                }
                            )
                            
                            return // 暂停处理，等待用户确认
                        } else {
                            // 名称相同，正常处理
                            print("✅ 标签类型名称未变化，继续处理")
                        }
                    } else {
                        // 新标签映射，正常处理
                        print("🆕 创建新的标签映射: \(actualTagKey) -> \(newTypeName)")
                        let newMapping = TagMapping(key: actualTagKey, typeName: newTypeName)
                        tagManager.addMapping(newMapping)
                    }
                    
                    // 重命名完成后，继续处理标签创建
                    // 使用实际的tagKey来创建标签类型和标签
                    print("🏷️ QuickAdd: 重命名完成，开始创建标签")
                    print("🏷️ QuickAdd: actualTagKey=\(actualTagKey), i=\(i), components.count=\(components.count)")
                    
                    if let tagType = tagManager.parseTokenToTagTypeWithStore(actualTagKey, store: store) {
                        if i + 1 < components.count { 
                            let content = components[i + 1]
                            print("🏷️ QuickAdd: 创建标签 - tagType=\(tagType), content=\(content)")
                            
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
                                    print("🏷️ QuickAdd: 创建地图标签成功 - \(locationName)")
                                } else if !content.contains("@") {
                                    let tag = Tag(type: tagType, value: content)
                                    tags.append(tag)
                                    print("🏷️ QuickAdd: 创建普通地点标签 - \(content)")
                                } else {
                                    let tag = Tag(type: tagType, value: content)
                                    tags.append(tag)
                                    print("🏷️ QuickAdd: 地图解析失败，创建普通标签 - \(content)")
                                }
                            } else {
                                // 普通标签
                                let tag = Tag(type: tagType, value: content, isShortcutType: true)
                                tags.append(tag)
                                print("🏷️ QuickAdd: 创建快捷键标签成功 - type=\(tagType), value=\(content), isShortcutType=true")
                            }
                            
                            i += 2 // 跳过tagType和value
                        } else {
                            print("🏷️ QuickAdd: 没有找到标签内容，跳过")
                            i += 1
                        }
                    } else {
                        print("🏷️ QuickAdd: 无法解析标签类型，跳过")
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
                print("❌ 继续处理命令时出错: \(error)")
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
            store.duplicateNodeAlert = NodeStore.DuplicateNodeAlert(
                message: "这些子节点不存在于复合节点中",
                isDuplicate: false,
                existingNode: compoundNode,
                newNode: compoundNode
            )
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
        
        print("✅ 复合节点删除操作完成，剩余子节点数: \(remainingChildCount)")
    }
    
    // 向已存在的复合节点添加子节点
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
            store.duplicateNodeAlert = NodeStore.DuplicateNodeAlert(
                message: "这些子节点已经存在于复合节点中",
                isDuplicate: false,
                existingNode: compoundNode,
                newNode: compoundNode
            )
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
        for childName in newChildNames {
            if let existingNode = store.nodes.first(where: { $0.text.lowercased() == childName.lowercased() }) {
                print("🔍 找到已存在的子节点: \(existingNode.text)")
            } else {
                let childNode = Node(
                    text: childName,
                    phonetic: nil,
                    meaning: nil,
                    layerId: compoundNode.layerId,
                    tags: []
                )
                let success = store.addNode(childNode)
                print("🆕 创建新子节点: \(childName) - \(success ? "成功" : "失败")")
            }
        }
        
        print("✅ 复合节点更新完成，总子节点数: \(existingChildReferences.count + newChildNames.count)")
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
        print("🏗️ 创建新复合节点: \(name)")
        
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
        
        // 创建复合节点
        let compoundNode = Node(
            text: name,
            phonetic: nil,
            meaning: "复合节点：包含 \(childNames.count) 个子节点",
            layerId: layerId,
            tags: compoundTags,
            isCompound: true
        )
        
        // 创建或确保子节点存在
        for childName in childNames {
            // 检查是否已存在
            if let existingNode = store.nodes.first(where: { $0.text.lowercased() == childName.lowercased() }) {
                print("🔍 找到已存在的子节点: \(existingNode.text)")
            } else {
                // 创建新的子节点
                let childNode = Node(
                    text: childName,
                    phonetic: nil,
                    meaning: nil,
                    layerId: layerId,
                    tags: []
                )
                _ = store.addNode(childNode)
                print("🆕 创建新子节点: \(childName)")
            }
        }
        
        // 添加复合节点到store
        _ = store.addNode(compoundNode)
        
        print("✅ 复合节点结构创建完成: \(name) (包含 \(childNames.count) 个子节点)")
    }
    
    private func openMapForLocationSelection() {
        print("📍 QuickAddSheetView: Opening map for location selection...")
        print("📍 QuickAddSheetView: Current store type: \(type(of: store)) - isSharedInstance: \(store.isSharedInstance)")
        print("📍 QuickAddSheetView: Window ID: \(windowId?.uuidString.prefix(8) ?? "nil")")
        isWaitingForLocationSelection = true
        
        // 🔧 修复：使用具体的窗口ID而不是通用标识符
        print("📍 QuickAddSheetView: 发送请求让特定窗口打开地图")
        
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
            print("📍 QuickAddSheetView: 发送位置选择模式通知（带时间戳和目标窗口ID）")
            NotificationCenter.default.post(
                name: NSNotification.Name("openMapForLocationSelection"), 
                object: ["requestTime": Date(), "targetWindowId": mapWindowId.uuidString]
            )
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
                        TextField("输入: 节点 root 词根内容 memory 记忆内容... 试试用Command+Shift+R建立复合节点", text: $inputText)
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
        print("📍 QuickAddView: Opening map for location selection...")
        
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
                    // 🔧 修复回车逻辑：只有在非输入法状态且搜索框有焦点时才选择第一个结果
                    if !isInIMEComposition() && selectedIndex == -1 && !filteredNodes.isEmpty {
                        selectedIndex = 0
                        selectCurrentNode()
                        print("🔍 TextField回车: 选择第一个搜索结果")
                    }
                }
                .onChange(of: isSearchFieldFocused) { _, newValue in
                    print("🔍 TextField焦点状态变化: \(newValue)")
                }
                .onAppear {
                    print("🔍 TextField出现")
                }
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
                        print("🖱️ 点击了节点: \(word.text)")
                        onNodeSelected(word)
                        onDismiss()
                    }
                    .onAppear {
                        print("🖱️ NodeSearchResultRow 出现: \(word.text)")
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
            print("🔍 QuickSearchView task: 异步任务开始，初始selectedIndex: \(selectedIndex)")
            // 立即尝试聚焦
            await MainActor.run {
                isSearchFieldFocused = true
                print("🔍 QuickSearchView task: 立即设置焦点")
            }
            
            // 等待并重试
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            await MainActor.run {
                isSearchFieldFocused = true
                print("🔍 QuickSearchView task: 0.1秒后设置焦点")
            }
            
            try? await Task.sleep(nanoseconds: 200_000_000) // 再等0.2秒(总共0.3秒)
            await MainActor.run {
                isSearchFieldFocused = true
                print("🔍 QuickSearchView task: 0.3秒后设置焦点")
            }
        }
        .onAppear {
            print("🔍 QuickSearchView.onAppear: 视图出现")
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.tab) {
            if filteredNodes.isEmpty { return .ignored }
            
            if selectedIndex == -1 {
                // Tab从搜索框进入第一个结果
                selectedIndex = 0
                print("🔍 Tab键: 进入第一个结果 (index: \(selectedIndex))")
            } else if selectedIndex < filteredNodes.count - 1 {
                // Tab到下一个结果
                selectedIndex += 1
                print("🔍 Tab键: 移动到下一个结果 (index: \(selectedIndex))")
            }
            return .handled
        }
        .onKeyPress(.tab, phases: .down) { keyPress in
            guard keyPress.modifiers.contains(.shift) else { return .ignored }
            // 🔧 新增：Shift+Tab向上选择结果
            if filteredNodes.isEmpty { return .ignored }
            
            if selectedIndex <= 0 {
                // 从第一个结果或搜索框回到搜索框
                selectedIndex = -1
                print("🔍 Shift+Tab键: 回到搜索框")
            } else {
                // Shift+Tab到上一个结果
                selectedIndex -= 1
                print("🔍 Shift+Tab键: 移动到上一个结果 (index: \(selectedIndex))")
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
                print("🔍 上箭头: 移动到结果 (index: \(selectedIndex))")
            } else if selectedIndex == 0 {
                // 从第一个结果回到搜索框
                selectedIndex = -1
                print("🔍 上箭头: 回到搜索框")
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex == -1 && !filteredNodes.isEmpty {
                // 从搜索框进入第一个结果
                selectedIndex = 0
                print("🔍 下箭头: 进入第一个结果 (index: \(selectedIndex))")
            } else if selectedIndex < filteredNodes.count - 1 {
                selectedIndex += 1
                print("🔍 下箭头: 移动到下一个结果 (index: \(selectedIndex))")
            }
            return .handled
        }
        .onKeyPress(.return) {
            // 🔧 修复输入法问题：只有在非输入法状态且有选中结果时才处理回车
            if !isInIMEComposition() && selectedIndex >= 0 {
                // 选择当前高亮的结果
                selectCurrentNode()
                print("🔍 回车键: 选择结果 (index: \(selectedIndex))")
                return .handled
            }
            // 让TextField的onSubmit处理其他情况
            return .ignored
        }
        .onChange(of: filteredNodes) { _, newNodes in
            selectedIndex = -1  // 当搜索结果改变时，重新回到搜索框焦点
            print("🔍 搜索结果更新，重置选择到搜索框 (index: -1)")
        }
    }
    
    private func selectCurrentNode() {
        guard selectedIndex < filteredNodes.count else { return }
        let selectedNode = filteredNodes[selectedIndex]
        onNodeSelected(selectedNode)
        onDismiss()
    }
    
    // 🔧 检查是否处于中文输入法编辑状态
    private func isInIMEComposition() -> Bool {
        // 检查当前事件是否来自输入法
        if let currentEvent = NSApp.currentEvent {
            // 只对键盘事件检查 charactersIgnoringModifiers
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
    @State private var showTagManager = false
    @State private var showCompoundNodeAdd = false
    @State private var nodeToEditInManager: Node? = nil
    @State private var tagTypeForGraph: Tag.TagType?
    
    // 主窗口的唯一标识符
    private let mainWindowId = UUID()
    @State private var isOpeningWindow = false // 防止重复打开窗口的标志
    
    /// 紧急清理所有打开的对话框和sheet
    private func performEmergencySheetCleanup() {
        print("🚨 WordTaggerApp: 执行紧急sheet清理...")
        
        // 强制关闭所有sheet
        showPalette = false
        showQuickAdd = false
        showQuickSearch = false
        showTagManager = false
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
        
        print("✅ WordTaggerApp: 紧急sheet清理完成")
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
        
        print("🚀 WordTagger 启动，已优化SQLite设置")
        
        // 验证资源文件是否正确加载
        let verification = ResourceManager.verifyAllResourcesExist()
        if verification.success {
            print("✅ 所有静态资源文件已正确加载")
            print("   - vditor CSS: \(ResourceManager.getVditorCSSPath() ?? "未找到")")
            print("   - vditor JS: \(ResourceManager.getVditorJSPath() ?? "未找到")")
            print("   - mermaid JS: \(ResourceManager.getMermaidJSPath() ?? "未找到")")
        } else {
            print("❌资源文件加载失败:")
            for missingFile in verification.missingFiles {
                print("   - \(missingFile)")
            }
        }
        
        // 延迟初始化Git自动同步，确保设置已加载
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("🔧 WordTaggerApp: 延迟启动Git自动同步监听")
            GitAutoSyncManager.shared.debugStatus()
            GitAutoSyncManager.shared.startMonitoring()
        }
    }
    // 哈哈哈哈哈哈哈哈哈哈哈哈哈哈哈哈

    var body: some Scene {
        WindowGroup(WINDOW_TITLE) {
            ZStack {
                ContentView(windowId: mainWindowId)
                    .environmentObject(store)
                    .frame(minWidth: 900, minHeight: 520)
                    .onAppear {
                        // 为主窗口注册窗口焦点管理
                        WindowFocusManager.shared.registerWindow(mainWindowId, type: .main, displayName: "主窗口")
                        WindowFocusManager.shared.setActiveWindow(mainWindowId)
                    }
                
                if showPalette {
                    ZStack {
                        // 背景遮罩 - 完全禁用点击响应，只通过ESC键关闭
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // 点击背景时不做任何事，防止误关闭
                                print("🛡️ 背景遮罩被点击，不关闭命令面板")
                            }
                        
                        CommandPaletteView(isPresented: $showPalette)
                            .environmentObject(store)
                            .transition(.asymmetric(insertion: AnyTransition.scale.combined(with: .opacity), removal: .opacity))
                    }
                }
                
                if showQuickSearch {
                    QuickSearchView(
                        onDismiss: { 
                            print("🔍 WordTaggerApp: QuickSearchView onDismiss 被调用")
                            showQuickSearch = false 
                        },
                        onNodeSelected: { node in
                            print("🔍 WordTaggerApp: QuickSearchView 选择了节点: \(node.text)")
                            
                            // 首先切换到节点所在的层
                            if let nodeLayer = store.layers.first(where: { $0.id == node.layerId }) {
                                print("🔄 切换到节点所在层: \(nodeLayer.displayName)")
                                store.setCurrentLayer(nodeLayer)
                            }
                            
                            // 然后选择节点
                            store.selectNode(node)
                        }
                    )
                    .environmentObject(store)
                    .onAppear {
                        print("🔍 WordTaggerApp: QuickSearchView 在 WordTaggerApp 中出现")
                    }
                    // 移除动画效果，直接显示
                }
                
                if showTagManager {
                    TagManagerView {
                        showTagManager = false
                    }
                    .transition(.asymmetric(insertion: AnyTransition.scale.combined(with: .opacity), removal: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showPalette)
            // QuickSearch 不使用动画，直接显示
            .animation(.easeInOut(duration: 0.2), value: showTagManager)
            .onChange(of: showQuickSearch) { _, newValue in
                print("🔍 WordTaggerApp: showQuickSearch 状态变化: \(newValue)")
            }
            .onKeyPress(.escape) {
                if showTagManager {
                    showTagManager = false
                    return .handled
                }
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
                    print("🚨 WordTaggerApp: Escape键检测到未关闭的sheet，执行紧急清理")
                    performEmergencySheetCleanup()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.init("c"), phases: .down) { keyPress in
                // Command+Option+C = 紧急清理所有sheet
                if keyPress.modifiers.contains([.command, .option]) {
                    print("🚨 WordTaggerApp: 检测到紧急清理快捷键：Command+Option+C")
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
                print("🚨 WordTaggerApp: 收到强制关闭所有sheet的通知")
                performEmergencySheetCleanup()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("showCommandPalette"))) { _ in
                // showCommandPalette 现在重定向到层结构图谱（兼容旧代码）
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true, commandName: "showCommandPalette") else {
                    print("🚫 主窗口: 忽略showCommandPalette通知 - 应用无活跃窗口或冷却期")
                    return
                }
                print("✅ 主窗口: 处理showCommandPalette通知 - 打开层结构图谱窗口")
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
                    print("🚫 主窗口: 忽略openNewWindow通知")
                    return
                }
                
                print("✅ 主窗口: 处理openNewWindow通知 - 打开独立窗口")
                
                // 防止重复打开：检查当前是否已有独立窗口
                guard !isOpeningWindow else {
                    print("🔔 [DEBUG] 窗口正在打开中，忽略重复请求")
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
                    print("🔔 [DEBUG] 重置isOpeningWindow标志")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("addNewNode"))) { _ in
                // addNewNode 是全局命令，应该在任何活跃窗口中可用
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true) else {
                    print("🚫 主窗口: 忽略addNewNode通知 - 应用无活跃窗口")
                    return
                }
                print("✅ 主窗口: 处理addNewNode通知 - 打开快速添加")
                showQuickAdd = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openNodeManagerForEdit"))) { notification in
                // openNodeManagerForEdit 不是全局命令，只有key窗口处理
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: false, commandName: "openNodeManagerForEdit") else {
                    print("🚫 主窗口: 忽略openNodeManagerForEdit通知 - 窗口非活跃状态")
                    return
                }
                
                if let node = notification.object as? Node {
                    print("📝 WordTaggerApp: 收到节点编辑请求，节点: \(node.text)")
                    nodeToEditInManager = node
                    // 先打开节点管理窗口
                    NotificationCenter.default.post(name: Notification.Name("openNodeManager"), object: nil)
                    // 延迟发送编辑节点通知，确保窗口已打开
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        print("📝 WordTaggerApp: 延迟发送编辑节点通知: \(node.text)")
                        NotificationCenter.default.post(name: Notification.Name("nodeManagerEditNode"), object: node)
                    }
                }
            }
            // openTagSearch通知已经由TagSidebarView直接处理，不需要在这里转发
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openQuickSearch"))) { _ in
                // openQuickSearch 是全局命令，应该在任何活跃窗口中可用
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true) else {
                    print("🚫 主窗口: 忽略openQuickSearch通知 - 应用无活跃窗口")
                    return
                }
                print("✅ 主窗口: 处理openQuickSearch通知 - 打开快速搜索")
                showQuickSearch = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openGraphWindow"))) { _ in
                // openGraphWindow 是全局命令，应该在任何活跃窗口中可用
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true) else {
                    print("🚫 主窗口: 忽略openGraphWindow通知 - 应用无活跃窗口")
                    return
                }
                print("✅ 主窗口: 处理openGraphWindow通知 - 打开图谱窗口")
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
                        print("📍 主窗口: 处理位置选择请求，打开地图 (窗口ID匹配)")
                        NotificationCenter.default.post(name: NSNotification.Name("executeOpenMapWindow"), object: ["sourceWindowId": mainWindowId.uuidString])
                    } else {
                        print("📍 主窗口: 忽略位置选择请求 - 窗口ID不匹配或非主窗口请求")
                        print("   - 请求源: \(requestSource), 目标窗口: \(windowId.prefix(8))")
                    }
                } else if let requestSource = notification.object as? String {
                    // 向后兼容旧格式
                    if requestSource == "MAIN_WINDOW" {
                        print("📍 主窗口: 处理位置选择请求（旧格式）")
                        NotificationCenter.default.post(name: NSNotification.Name("executeOpenMapWindow"), object: ["sourceWindowId": mainWindowId.uuidString])
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openMapWindow"))) { notification in
                // 🔧 修复：检查通知是否包含源窗口信息，如果包含则只有匹配的窗口才处理
                if let sourceInfo = notification.object as? [String: String],
                   let targetSourceWindowId = sourceInfo["sourceWindowId"] {
                    print("🎯 主窗口: 收到带源窗口ID的openMapWindow通知 - \(targetSourceWindowId.prefix(8))")
                    
                    // 检查是否是发给主窗口的
                    if targetSourceWindowId == mainWindowId.uuidString || targetSourceWindowId == "MAIN_WINDOW" {
                        print("✅ 主窗口: 处理指定给主窗口的openMapWindow通知")
                        NotificationCenter.default.post(name: NSNotification.Name("executeOpenMapWindow"), object: ["sourceWindowId": mainWindowId.uuidString])
                    } else {
                        print("🚫 主窗口: 忽略发给其他窗口的openMapWindow通知 - 目标: \(targetSourceWindowId.prefix(8))")
                    }
                    return
                }
                
                // 如果没有源窗口信息，使用原有的全局命令逻辑（向后兼容）
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true) else {
                    print("🚫 主窗口: 忽略openMapWindow通知 - 应用无活跃窗口")
                    return
                }
                print("✅ 主窗口: 处理全局openMapWindow通知 - 打开地图窗口")
                NotificationCenter.default.post(name: NSNotification.Name("executeOpenMapWindow"), object: ["sourceWindowId": mainWindowId.uuidString])
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openTagManager"))) { _ in
                // openTagManager 是全局命令，只在当前key窗口处理
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true, commandName: "openTagManager") else {
                    print("🚫 主窗口: 忽略openTagManager通知 - 非key窗口或冷却期")
                    return
                }
                
                print("✅ 主窗口: 处理openTagManager通知 - 打开标签管理")
                showTagManager = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openNodeManager"))) { _ in
                // openNodeManager 是全局命令，只在当前key窗口处理
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true, commandName: "openNodeManager") else {
                    print("🚫 主窗口: 忽略openNodeManager通知 - 非key窗口或冷却期")
                    return
                }
                
                print("✅ 主窗口: 处理openNodeManager通知 - 打开节点管理")
                NotificationCenter.default.post(name: NSNotification.Name("executeOpenNodeManager"), object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openTagTypeGraph"))) { notification in
                // openTagTypeGraph 应该总是由主窗口处理，因为只有主窗口有WindowGroup定义
                print("🎯 主窗口: 接收到openTagTypeGraph通知")
                
                if let tagType = notification.object as? Tag.TagType {
                    print("✅ 主窗口: 处理openTagTypeGraph通知 - 打开标签图谱: \(tagType.displayName)")
                    
                    // 更新共享的TagGraphWindowManager状态
                    TagGraphWindowManager.shared.updateTagType(tagType)
                    
                    // 保持原有的tagTypeForGraph更新以确保向后兼容
                    tagTypeForGraph = tagType
                    
                    NotificationCenter.default.post(name: NSNotification.Name("executeOpenWindow"), object: "tagTypeGraph")
                } else {
                    print("❌ 主窗口: openTagTypeGraph通知缺少标签类型信息")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("executeOpenNodeManager"))) { notification in
                // 检查当前窗口是否应该响应此通知
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true, commandName: "executeOpenNodeManager") else {
                    print("🚫 主窗口: 忽略executeOpenNodeManager通知 - 非key窗口或冷却期")
                    return
                }
                
                print("✅ 主窗口: 处理executeOpenNodeManager通知 - 通过ContentView打开节点管理")
                // 通过ContentView的openWindow执行
                NotificationCenter.default.post(name: NSNotification.Name("executeOpenWindow"), object: "nodeManager")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("executeOpenMapWindow"))) { notification in
                // 🔧 关键修复：实际打开通用地图窗口并设置窗口映射
                print("🗺️ 主窗口: 收到executeOpenMapWindow通知，打开通用地图窗口")
                print("🗺️ 主窗口: notification.object = \(notification.object ?? "nil")")
                
                // 🔧 打开通用地图窗口
                NotificationCenter.default.post(name: NSNotification.Name("executeOpenWindow"), object: "map")
                
                // 设置窗口映射信息
                if let sourceInfo = notification.object as? [String: String] {
                    print("🗺️ 主窗口: 转发窗口映射信息给通用地图窗口，sourceInfo: \(sourceInfo)")
                    // 延迟一点发送映射信息，确保地图窗口已经打开
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("mapWindowSetupMapping"),
                            object: sourceInfo
                        )
                    }
                } else {
                    print("⚠️ 主窗口: executeOpenMapWindow通知缺少sourceInfo，使用主窗口默认值")
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
                print("🔧 主窗口: 收到窗口映射请求")
                
                if let requestInfo = notification.object as? [String: String],
                   let childWindowId = requestInfo["childWindowId"],
                   let windowType = requestInfo["windowType"] {
                    print("🔧 主窗口: 处理窗口映射请求 - 窗口类型: \(windowType), 子窗口ID: \(childWindowId.prefix(8))")
                    
                    // 🔧 重要修复：使用智能源窗口检测
                    let sourceWindowId = WindowFocusManager.shared.getSourceWindowId()
                    print("🔧 主窗口: 智能确定源窗口ID: \(sourceWindowId.prefix(8))")
                    
                    // 发送映射信息
                    let mappingInfo = ["sourceWindowId": sourceWindowId]
                    NotificationCenter.default.post(
                        name: NSNotification.Name("mapWindowSetupMapping"),
                        object: mappingInfo
                    )
                    print("🔧 主窗口: 已发送窗口映射信息到 \(windowType) 窗口")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("requestWindowMappingForMap"))) { notification in
                // 🔧 处理地图窗口的主动映射请求
                print("🔧 主窗口: 收到地图窗口映射请求")
                
                if let requestInfo = notification.object as? [String: String],
                   let mapWindowId = requestInfo["mapWindowId"] {
                    print("🔧 主窗口: 处理地图窗口映射请求 - 地图窗口ID: \(mapWindowId.prefix(8))")
                    
                    // 检查主窗口是否应该响应（即主窗口是否是活跃窗口或最近活跃的非地图窗口）
                    if WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: false) {
                        let sourceWindowId = mainWindowId.uuidString
                        print("🔧 主窗口: 确定为源窗口，发送映射信息 - 源窗口ID: \(sourceWindowId.prefix(8))")
                        
                        // 🎯 发送带目标地图窗口ID的映射信息
                        let mappingInfo = [
                            "sourceWindowId": sourceWindowId,
                            "targetMapWindowId": mapWindowId
                        ]
                        NotificationCenter.default.post(
                            name: NSNotification.Name("mapWindowSetupMapping"),
                            object: mappingInfo
                        )
                        print("🔧 主窗口: 已发送目标映射信息到地图窗口 \(mapWindowId.prefix(8))")
                    } else {
                        print("🚫 主窗口: 不是活跃窗口，忽略地图窗口映射请求")
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("toggleSidebar"))) { _ in
                // toggleSidebar 是全局命令，只在当前key窗口处理
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true, commandName: "toggleSidebar") else {
                    print("🚫 主窗口: 忽略toggleSidebar通知 - 非key窗口或冷却期")
                    return
                }
                
                print("✅ 主窗口: 处理toggleSidebar通知")
                NotificationCenter.default.post(name: NSNotification.Name("executeToggleSidebar"), object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("switchToDetailTab"))) { _ in
                // 检查当前窗口是否应该响应此通知
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId) else {
                    print("🚫 主窗口: 忽略switchToDetailTab通知 - 窗口非活跃状态")
                    return
                }
                print("✅ 主窗口: 处理switchToDetailTab通知 - 发送执行命令")
                // 发送执行命令，避免循环
                NotificationCenter.default.post(name: NSNotification.Name("executeDetailTabSwitch"), object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("switchToGraphTab"))) { _ in
                // 检查当前窗口是否应该响应此通知
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId) else {
                    print("🚫 主窗口: 忽略switchToGraphTab通知 - 窗口非活跃状态")
                    return
                }
                print("✅ 主窗口: 处理switchToGraphTab通知 - 发送执行命令")
                // 发送执行命令，避免循环
                NotificationCenter.default.post(name: NSNotification.Name("executeGraphTabSwitch"), object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("clearTagFilter"))) { _ in
                // clearTagFilter是全局命令，应该在任何活跃窗口中可用
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true, commandName: "clearTagFilter") else {
                    print("🚫 主窗口: 忽略clearTagFilter通知 - 应用无活跃窗口")
                    return
                }
                print("✅ 主窗口: 处理clearTagFilter通知，清除标签筛选")
                store.clearTagFilter()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("restorePreviousTagFilterState"))) { _ in
                // restorePreviousTagFilterState是全局命令，应该在任何活跃窗口中可用
                guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: true, commandName: "restorePreviousTagFilterState") else {
                    print("🚫 主窗口: 忽略restorePreviousTagFilterState通知 - 应用无活跃窗口")
                    return
                }
                print("✅ 主窗口: 处理restorePreviousTagFilterState通知，恢复标签筛选")
                store.restorePreviousTagFilterState()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("switchToLayer"))) { notification in
                // 🔧 处理来自层图谱窗口的层切换请求
                guard let layer = notification.object as? Layer else {
                    print("⚠️ 主窗口: switchToLayer通知格式错误 - 缺少层对象")
                    return
                }
                
                if let userInfo = notification.userInfo,
                   let sourceWindowId = userInfo["sourceWindowId"] as? String,
                   !sourceWindowId.isEmpty {
                    
                    // 🔧 调试：打印窗口ID信息
                    print("🔍 主窗口: switchToLayer通知窗口ID检查")
                    print("   - 通知中的sourceWindowId: \(sourceWindowId.prefix(8))")
                    print("   - 主窗口的mainWindowId: \(mainWindowId.uuidString.prefix(8))")
                    print("   - WindowFocusManager中主窗口ID: \(WindowFocusManager.shared.getActiveWindowId()?.uuidString.prefix(8) ?? "nil")")
                    
                    // 🔧 精确检查是否是发给这个特定主窗口的（支持多主窗口环境）
                    let isTargetingThisMainWindow = sourceWindowId == mainWindowId.uuidString
                    
                    if isTargetingThisMainWindow {
                        print("🔄 主窗口: 处理来自层图谱的层切换请求 - 切换到层: \(layer.displayName)")
                        Task {
                            await store.switchToLayer(layer)
                        }
                    } else {
                        print("🚫 主窗口: 忽略发给其他窗口的switchToLayer通知 - 目标: \(sourceWindowId.prefix(8))")
                    }
                } else {
                    // 如果没有指定源窗口，使用WindowFocusManager检查
                    guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: false, commandName: "switchToLayer") else {
                        print("🚫 主窗口: 忽略switchToLayer通知 - 窗口非活跃状态")
                        return
                    }
                    print("✅ 主窗口: 作为活跃窗口处理层切换请求 - 切换到层: \(layer.displayName)")
                    Task {
                        await store.switchToLayer(layer)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("handleMapPinTap"))) { notification in
                print("🔔 主窗口: 收到handleMapPinTap通知")
                print("🔔 主窗口ID = \(mainWindowId.uuidString)")
                guard let userInfo = notification.userInfo,
                      let targetNodeId = userInfo["targetNodeId"] as? String,
                      let targetLayerId = userInfo["targetLayerId"] as? String else {
                    print("⚠️ 主窗口: handleMapPinTap通知格式错误 - 缺少节点ID或层ID")
                    return
                }
                print("🔔 主窗口: 通知包含 targetWindowId: \(userInfo["targetWindowId"] ?? "nil")")
                print("🔔 主窗口: routingMethod = \(userInfo["routingMethod"] ?? "nil")")
                print("🔔 主窗口: fromMapContainer = \(userInfo["fromMapContainer"] ?? "nil")")
                
                // 🔧 从当前store实例中查找对应的节点和层
                guard let targetNodeUUID = UUID(uuidString: targetNodeId),
                      let targetNode = store.nodes.first(where: { $0.id == targetNodeUUID }) else {
                    print("⚠️ 主窗口: 未在当前store中找到目标节点 - ID: \(targetNodeId.prefix(8))")
                    return
                }
                
                guard let targetLayerUUID = UUID(uuidString: targetLayerId),
                      let targetLayer = store.layers.first(where: { $0.id == targetLayerUUID }) else {
                    print("⚠️ 主窗口: 未在当前store中找到目标层 - ID: \(targetLayerId.prefix(8))")
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
                    print("🎯 检查窗口ID匹配:")
                    print("   - targetWindowId = \(targetWindowId)")
                    print("   - mainWindowId = \(mainWindowId.uuidString)")
                    print("   - mainWindowShortId = \(mainWindowShortId)")
                    print("   - isMatchingMainWindow = \(isMatchingMainWindow)")
                    if !isMatchingMainWindow {
                        print("🚫 主窗口: 忽略handleMapPinTap通知 - 目标窗口不匹配")
                        return
                    }
                    print("🎯 主窗口: 处理指定目标的地图节点点击")
                    print("   - 目标ID: \(targetWindowId.prefix(8))")
                    print("   - 路由方式: \(userInfo["routingMethod"] as? String ?? "unknown")")
                } else {
                    // 如果没有指定目标窗口ID，则使用WindowFocusManager进行活跃窗口检查
                    guard WindowFocusManager.shared.shouldHandleNotification(for: mainWindowId, isGlobalCommand: false, commandName: "handleMapPinTap") else {
                        print("🚫 主窗口: 忽略handleMapPinTap通知 - 窗口非活跃状态且无目标窗口ID")
                        return
                    }
                    print("✅ 主窗口: 作为活跃窗口处理地图节点点击")
                }
                
                print("🗺️ 主窗口: 处理地图标注点击 - 节点: \(targetNode.text), 层: \(targetLayer.displayName)")
                
                // 执行层切换和标签展开操作
                Task {
                    await store.switchToLayer(targetLayer)
                    
                    await MainActor.run {
                        store.expandLocationTagAndSelect(targetNode)
                        print("✅ 主窗口: 已切换到层 '\(targetLayer.displayName)' 并展开地点标签")
                        
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
                        print("🖼️ 标签图谱窗口: 窗口已显示，标签类型: \(tagType.displayName)")
                        // 确保WindowManager状态与实际显示的标签类型同步
                        if TagGraphWindowManager.shared.currentTagType != tagType {
                            TagGraphWindowManager.shared.updateTagType(tagType)
                        }
                    }
                    .onDisappear {
                        print("🖼️ 标签图谱窗口: 窗口已隐藏")
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
                    print("❌ 标签图谱窗口: 无有效标签类型")
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
        ZStack {
            // 透明背景（保留点击关闭功能）
            Color.clear
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            // 隐藏的聚焦元素，用于接收键盘事件
            Rectangle()
                .fill(Color.clear)
                .frame(width: 0, height: 0)
                .focusable()
                .focused($isViewFocused)
            
            VStack(spacing: 0) {
                // 标题栏 + 模块切换（合并到一行）
                HStack {
                    // 左侧：醒目的模块切换按钮组
                    HStack(spacing: 4) {
                        ForEach(TagManagerModule.allCases, id: \.self) { module in
                            Button {
                                selectedModule = module
                            } label: {
                                Text(module.rawValue)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(selectedModule == module ? .white : .primary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(selectedModule == module ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedModule == module ? Color.clear : Color(NSColor.separatorColor), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("切换到\(module.rawValue)模块")
                        }
                    }
                    
                    Spacer()
                    
                    // 右侧：功能按钮和关闭按钮
                    HStack(spacing: 12) {
                        // 显示系统标签开关
                        Button(action: { showSystemTags.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: showSystemTags ? "eye" : "eye.slash")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                Text("系统标签")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help(showSystemTags ? "隐藏系统标签" : "显示系统标签")
                        
                        // 重新扫描按钮
                        Button(action: {
                            tagManager.rescanAndUpdateMappings()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                Text("重新扫描")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("重新扫描现有标签并创建缺失的映射")
                        
                        // 关闭按钮
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
                
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
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.2), radius: 30, x: 0, y: 10)
            .frame(maxWidth: 750, maxHeight: 500)
            .padding(20)
        }
        .sheet(isPresented: $showingTagEditSheet) {
            TagEditFormView(
                newKey: $newKey,
                newTypeName: $newTypeName,
                editingMapping: $editingMapping,
                onSave: { saveMapping() },
                onCancel: { resetForm() }
            )
        }
        .onAppear {
            // 视图出现时自动聚焦，确保可以接收键盘事件
            isViewFocused = true
            
            // 延迟设置搜索框焦点，确保视图已完全加载
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
                print("🔍 TagManagerView: 设置搜索框焦点")
            }
            
            // 额外的延迟重新设置焦点，防止被其他组件抢夺
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if !isSearchFieldFocused {
                    isSearchFieldFocused = true
                    print("🔍 TagManagerView: 重新设置搜索框焦点")
                }
            }
        }
        .onKeyPress(.escape) {
            print("⌨️ TagManagerView: ESC键按下，准备关闭")
            onDismiss()
            return .handled
        }
    }
    
    // 标签管理内容
    private var tagManagementContent: some View {
        VStack(spacing: 0) {
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                
                TextField("搜索标签映射（快捷键或类型名称）...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isSearchFieldFocused)
                    .onChange(of: isSearchFieldFocused) { _, newValue in
                        print("🎯 TagManagerView: 搜索框焦点状态变更 = \(newValue)")
                    }
                
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
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // 现有标签列表
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredMappings, id: \.id) { mapping in
                            TagMappingRow(
                                mapping: mapping,
                                onEdit: {
                                    print("🎯 TagManagerView: 开始编辑映射")
                                    print("   - 选中映射: id=\(mapping.id), key=\(mapping.key), typeName=\(mapping.typeName)")
                                    editingMapping = mapping
                                    newKey = mapping.key
                                    newTypeName = mapping.typeName
                                    showingTagEditSheet = true
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
                
                // 功能按钮区域
                VStack(spacing: 12) {
                    // 添加新标签按钮（居中显示）
                    Button {
                        showingTagEditSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                            Text("添加新标签")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundColor(.accentColor)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
                
        }
    }
}

// MARK: - Tag Edit Form View

struct TagEditFormView: View {
    @Binding var newKey: String
    @Binding var newTypeName: String
    @Binding var editingMapping: TagMapping?
    @Environment(\.dismiss) private var dismiss
    
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
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("类型名称")
                            .font(.headline)
                            .foregroundColor(.primary)
                        TextField("例如: 词根", text: $newTypeName)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                    }
                }
                
                // 按钮区域
                HStack(spacing: 16) {
                    Button("取消") {
                        onCancel()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    
                    Button(editingMapping != nil ? "保存" : "添加") {
                        onSave()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(newKey.isEmpty || newTypeName.isEmpty)
                }
                .padding(.top, 8)
            }
            .padding(24)
            
            Spacer()
        }
        .frame(width: 400, height: 300)
    }
}

extension TagManagerView {
    
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
    let onDelete: () -> Void
    
    private var isBuiltInCore: Bool {
        TagMappingManager.shared.isBuiltInCoreTag(mapping.key)
    }
    
    var body: some View {
        let _ = print("🎨 TagMappingRow: 渲染 id=\(mapping.id), key=\(mapping.key), typeName=\(mapping.typeName)")
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
                
                // 删除按钮保持独立（避免误删）
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
            .contentShape(Rectangle())  // 确保整个区域都可以点击
        }
        .buttonStyle(.plain)
        .disabled(isBuiltInCore)
        .help(isBuiltInCore ? "系统标签不可编辑" : "点击编辑标签映射")
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
        _ = store.addNode(compoundNode)
        for childNode in childNodes {
            _ = store.addNode(childNode)
        }
        
        print("✅ 复合节点结构创建完成:")
        print("  复合节点: \(name) (包含 \(compoundTags.count) 个标签)")
        print("  子节点: \(childNames.joined(separator: ", "))")
    }
}

// MARK: - Independent Window Wrapper

struct IndependentWindowWrapper: View {
    @StateObject private var store = NodeStore.createIndependentInstance()
    @State private var showPalette = false
    @State private var showQuickAdd = false
    @State private var showQuickSearch = false
    @State private var showTagManager = false
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
                showTagManager: $showTagManager,
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
                .onAppear {
                    // 🔧 为独立窗口注册窗口焦点管理 - 注册为主窗口类型，支持层图谱映射
                    WindowFocusManager.shared.registerWindow(windowId, type: .main, displayName: "独立窗口")
                    WindowFocusManager.shared.setActiveWindow(windowId)
                }
                .onDisappear {
                    // 注销窗口
                    WindowFocusManager.shared.unregisterWindow(windowId)
                }
            
            if showPalette {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            print("🛡️ 独立窗口背景遮罩被点击，不关闭命令面板")
                        }
                    
                    CommandPaletteView(isPresented: $showPalette)
                        .environmentObject(store)
                        .transition(.asymmetric(insertion: AnyTransition.scale.combined(with: .opacity), removal: .opacity))
                }
            }
            
            if showQuickSearch {
                QuickSearchView(
                    onDismiss: { 
                        print("🔍 IndependentWindow: QuickSearchView onDismiss 被调用")
                        showQuickSearch = false 
                    },
                    onNodeSelected: { node in
                        print("🔍 IndependentWindow: QuickSearchView 选择了节点: \(node.text)")
                        
                        if let nodeLayer = store.layers.first(where: { $0.id == node.layerId }) {
                            print("🔄 切换到节点所在层: \(nodeLayer.displayName)")
                            store.setCurrentLayer(nodeLayer)
                        }
                        
                        store.selectNode(node)
                    }
                )
                .environmentObject(store)
                .onAppear {
                    print("🔍 IndependentWindow: QuickSearchView 出现")
                }
            }
            
            if showTagManager {
                TagManagerView {
                    showTagManager = false
                }
                .environmentObject(store)
                .transition(.asymmetric(insertion: AnyTransition.scale.combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showPalette)
        .animation(.easeInOut(duration: 0.2), value: showTagManager)
        .onChange(of: showQuickSearch) { _, newValue in
            print("🔍 IndependentWindow: showQuickSearch 状态变化: \(newValue)")
        }
        .onKeyPress(.escape) {
            if showTagManager {
                showTagManager = false
                return .handled
            }
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

struct IndependentWindowModifier: ViewModifier {
    @Binding var showPalette: Bool
    @Binding var showQuickAdd: Bool
    @Binding var showQuickSearch: Bool
    @Binding var showTagManager: Bool
    @Binding var showCompoundNodeAdd: Bool
    @Binding var showCommandPalette: Bool
    @Binding var nodeToEditInManager: Node?
    @Binding var isOpeningMapWindow: Bool
    let windowId: UUID
    let store: NodeStore
    let openWindow: OpenWindowAction
    
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
            // 禁用Sheet显示TagManager，改用overlay方式  
            // .sheet(isPresented: $showTagManager) {
            //     TagManagerSheetView(isPresented: $showTagManager)
            // }
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
                showTagManager = true
            })
            .focusedSceneValue(\.openNodeManager, ShowCardAction {
                openWindow(id: "nodeManager")
            })
            .focusedSceneValue(\.openMapWindow, ShowCardAction {
                // 🔧 检查是否应该处理这个命令
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true) else {
                    print("🗺️ 独立窗口: 忽略地图窗口打开请求 - 窗口非活跃状态")
                    return
                }
                
                // 🔧 添加防重复机制
                guard !isOpeningMapWindow else {
                    print("🚫 独立窗口: 地图窗口正在打开中，忽略focusedSceneValue重复请求")
                    return
                }
                
                isOpeningMapWindow = true
                print("🗺️ 独立窗口 (focusedSceneValue): 打开通用地图窗口")
                
                // 直接打开地图窗口
                openWindow(id: "map")
                
                // 发送窗口映射信息，确保地图知道来源窗口
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let mappingInfo = ["sourceWindowId": windowId.uuidString]
                    NotificationCenter.default.post(
                        name: NSNotification.Name("mapWindowSetupMapping"),
                        object: mappingInfo
                    )
                    print("🔗 独立窗口: 已发送窗口映射信息 (focusedSceneValue)")
                }
                
                // 1秒后重置防重复标志
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    isOpeningMapWindow = false
                }
            })
            .focusedSceneValue(\.openGraphWindow, ShowCardAction {
                openWindow(id: "graph")
            })
            .focusedSceneValue(\.toggleSidebar, ShowCardAction {
                NotificationCenter.default.post(name: NSNotification.Name("executeToggleSidebar"), object: "independent")
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
                print("🔑 IndependentWindow: Command+F 被触发")
                // 直接发送openTagSearch通知，让TagSidebarView处理
                NotificationCenter.default.post(name: NSNotification.Name("openTagSearch"), object: nil)
            })
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
                print("🔑 独立窗口: 收到键盘清除标签筛选通知")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
                    store.clearTagFilter()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("executeOpenWindow"))) { notification in
                // 🔧 检查源窗口ID，确保只有一个窗口处理这个通知
                if let sourceWindowId = notification.userInfo?["sourceWindowId"] as? String {
                    // 如果指定了源窗口ID，只有匹配的窗口处理
                    guard sourceWindowId == windowId.uuidString else {
                        print("🚫 独立窗口: 忽略executeOpenWindow通知 - 源窗口ID不匹配")
                        return
                    }
                } else {
                    // 如果没有源窗口ID，使用原有的活跃窗口检查
                    guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: false, commandName: "executeOpenWindow") else {
                        print("🚫 独立窗口: 忽略executeOpenWindow通知 - 窗口非活跃状态")
                        return
                    }
                }
                
                if let windowType = notification.object as? String {
                    print("✅ 独立窗口: 收到executeOpenWindow通知 - windowType: \(windowType)")
                    
                    // 🔧 对于层图谱窗口，使用原子性检查和预留
                    if windowType == "layerGraph" {
                        let currentWindowId = windowId.uuidString
                        if !WindowFocusManager.shared.reserveLayerGraphWindow(for: currentWindowId) {
                            print("⚠️ 独立窗口: 已有层图谱窗口，忽略重复打开请求")
                            return
                        }
                    }
                    
                    openWindow(id: windowType)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("showCommandPalette"))) { _ in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true, commandName: "showCommandPalette") else {
                    print("🚫 独立窗口: 忽略showCommandPalette通知 - 应用无活跃窗口或冷却期")
                    return
                }
                print("✅ 独立窗口: 处理showCommandPalette通知 - 发送executeOpenWindow通知")
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
                    print("🚫 独立窗口: 忽略addNewNode通知 - 应用无活跃窗口")
                    return
                }
                print("✅ 独立窗口: 处理addNewNode通知 - 打开快速添加")
                showQuickAdd = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openNodeManagerForEdit"))) { notification in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: false, commandName: "openNodeManagerForEdit") else {
                    print("🚫 独立窗口: 忽略openNodeManagerForEdit通知 - 窗口非活跃状态")
                    return
                }
                if let node = notification.object as? Node {
                    print("📝 IndependentWindow: 收到节点编辑请求，节点: \(node.text)")
                    nodeToEditInManager = node
                    // 先打开节点管理窗口
                    NotificationCenter.default.post(name: Notification.Name("openNodeManager"), object: nil)
                    // 延迟发送编辑节点通知，确保窗口已打开
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        print("📝 IndependentWindow: 延迟发送编辑节点通知: \(node.text)")
                        NotificationCenter.default.post(name: Notification.Name("nodeManagerEditNode"), object: node)
                    }
                }
            }
            // openTagSearch通知已经由TagSidebarView直接处理，不需要在这里转发
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openQuickSearch"))) { _ in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true) else {
                    print("🚫 独立窗口: 忽略openQuickSearch通知 - 应用无活跃窗口")
                    return
                }
                print("✅ 独立窗口: 处理openQuickSearch通知 - 打开快速搜索")
                showQuickSearch = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openGraphWindow"))) { _ in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true) else {
                    print("🚫 独立窗口: 忽略openGraphWindow通知 - 应用无活跃窗口")
                    return
                }
                print("✅ 独立窗口: 处理openGraphWindow通知 - 打开图谱窗口")
                NotificationCenter.default.post(name: NSNotification.Name("executeOpenGraphWindow"), object: "independent")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("requestMapForLocationSelection"))) { notification in
                // 🔧 处理来自QuickAddSheetView的位置选择请求
                if let notificationData = notification.object as? [String: String],
                   let requestSource = notificationData["requestSource"],
                   let requestWindowId = notificationData["windowId"] {
                    // 只处理发给这个特定独立窗口的请求
                    if requestSource == "INDEPENDENT_WINDOW" && requestWindowId == windowId.uuidString {
                        print("📍 独立窗口: 处理位置选择请求 (窗口ID匹配: \(windowId.uuidString.prefix(8)))")
                        
                        // 🔧 防重复机制：检查是否正在打开地图窗口
                        guard !isOpeningMapWindow else {
                            print("🚫 独立窗口: 地图窗口正在打开中，忽略重复请求")
                            return
                        }
                        
                        isOpeningMapWindow = true
                        print("🗺️ 独立窗口: 打开地图窗口")
                        openWindow(id: "map")
                        
                        // 设置窗口映射信息和位置选择模式
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            let mappingInfo = ["sourceWindowId": windowId.uuidString]
                            NotificationCenter.default.post(
                                name: NSNotification.Name("mapWindowSetupMapping"),
                                object: mappingInfo
                            )
                            print("🗺️ 独立窗口: 已发送窗口映射信息")
                        }
                        
                        // 🔧 发送位置选择模式通知
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            print("📍 独立窗口: 发送位置选择模式通知（带时间戳）")
                            NotificationCenter.default.post(
                                name: NSNotification.Name("openMapForLocationSelection"), 
                                object: ["requestTime": Date()]
                            )
                        }
                        
                        // 1秒后重置防重复标志
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isOpeningMapWindow = false
                            print("🔄 独立窗口: 重置地图窗口打开标志")
                        }
                    } else {
                        print("📍 独立窗口: 忽略位置选择请求 - 窗口ID不匹配")
                        print("   - 请求源: \(requestSource), 目标窗口: \(requestWindowId.prefix(8)), 当前窗口: \(windowId.uuidString.prefix(8))")
                    }
                } else if let requestSource = notification.object as? String {
                    // 向后兼容旧格式
                    if requestSource == "INDEPENDENT_WINDOW" {
                        print("⚠️ 独立窗口: 收到旧格式通知，无法确定目标窗口")
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openMapWindow"))) { notification in
                // 🔧 修复：检查通知是否包含源窗口信息，如果包含则只有匹配的窗口才处理
                if let sourceInfo = notification.object as? [String: String],
                   let targetSourceWindowId = sourceInfo["sourceWindowId"] {
                    print("🎯 独立窗口: 收到带源窗口ID的openMapWindow通知 - \(targetSourceWindowId.prefix(8))")
                    
                    // 检查是否是发给这个独立窗口的
                    if targetSourceWindowId == windowId.uuidString {
                        // 🔧 添加防重复机制
                        guard !isOpeningMapWindow else {
                            print("🚫 独立窗口: 地图窗口正在打开中，忽略openMapWindow重复请求")
                            return
                        }
                        
                        print("✅ 独立窗口: 处理指定给当前独立窗口的openMapWindow通知")
                        isOpeningMapWindow = true
                        openWindow(id: "map")
                        
                        // 🔧 发送窗口映射信息
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            let mappingInfo = ["sourceWindowId": windowId.uuidString]
                            NotificationCenter.default.post(
                                name: NSNotification.Name("mapWindowSetupMapping"),
                                object: mappingInfo
                            )
                            print("🔗 独立窗口: 已发送窗口映射信息 (指定openMapWindow)")
                        }
                        
                        // 1秒后重置防重复标志
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isOpeningMapWindow = false
                        }
                    } else {
                        print("🚫 独立窗口: 忽略发给其他窗口的openMapWindow通知 - 目标: \(targetSourceWindowId.prefix(8)), 当前: \(windowId.uuidString.prefix(8))")
                    }
                    return
                }
                
                // 如果没有源窗口信息，使用原有的全局命令逻辑（向后兼容）
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true) else {
                    print("🚫 独立窗口: 忽略openMapWindow通知 - 应用无活跃窗口")
                    return
                }
                
                // 🔧 添加防重复机制
                guard !isOpeningMapWindow else {
                    print("🚫 独立窗口: 地图窗口正在打开中，忽略全局openMapWindow重复请求")
                    return
                }
                
                print("✅ 独立窗口: 处理全局openMapWindow通知 - 打开地图窗口")
                isOpeningMapWindow = true
                openWindow(id: "map")
                
                // 🔧 发送窗口映射信息
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let mappingInfo = ["sourceWindowId": windowId.uuidString]
                    NotificationCenter.default.post(
                        name: NSNotification.Name("mapWindowSetupMapping"),
                        object: mappingInfo
                    )
                    print("🔗 独立窗口: 已发送窗口映射信息 (全局openMapWindow)")
                }
                
                // 1秒后重置防重复标志
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    isOpeningMapWindow = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openTagManager"))) { _ in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true, commandName: "openTagManager") else {
                    print("🚫 独立窗口: 忽略openTagManager通知 - 非key窗口或冷却期")
                    return
                }
                print("✅ 独立窗口: 处理openTagManager通知 - 打开标签管理")
                showTagManager = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openNodeManager"))) { _ in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true, commandName: "openNodeManager") else {
                    print("🚫 独立窗口: 忽略openNodeManager通知 - 非key窗口或冷却期")
                    return
                }
                print("✅ 独立窗口: 处理openNodeManager通知 - 打开节点管理")
                NotificationCenter.default.post(name: NSNotification.Name("executeOpenNodeManager"), object: "independent")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("toggleSidebar"))) { _ in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true, commandName: "toggleSidebar") else {
                    print("🚫 独立窗口: 忽略toggleSidebar通知 - 非key窗口或冷却期")
                    return
                }
                print("✅ 独立窗口: 处理toggleSidebar通知")
                NotificationCenter.default.post(name: NSNotification.Name("executeToggleSidebar"), object: "independent")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("switchToDetailTab"))) { _ in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId) else {
                    print("🚫 独立窗口: 忽略switchToDetailTab通知 - 窗口非活跃状态")
                    return
                }
                print("✅ 独立窗口: 处理switchToDetailTab通知 - 发送执行命令")
                // 发送执行命令，避免循环
                NotificationCenter.default.post(name: NSNotification.Name("executeDetailTabSwitch"), object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("switchToGraphTab"))) { _ in
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId) else {
                    print("🚫 独立窗口: 忽略switchToGraphTab通知 - 窗口非活跃状态")
                    return
                }
                print("✅ 独立窗口: 处理switchToGraphTab通知 - 发送执行命令")
                // 发送执行命令，避免循环
                NotificationCenter.default.post(name: NSNotification.Name("executeGraphTabSwitch"), object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("clearTagFilter"))) { _ in
                // clearTagFilter是全局命令，应该在任何活跃窗口中可用
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true, commandName: "clearTagFilter") else {
                    print("🚫 独立窗口: 忽略clearTagFilter通知 - 应用无活跃窗口")
                    return
                }
                print("✅ 独立窗口: 处理clearTagFilter通知，清除标签筛选")
                store.clearTagFilter()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("restorePreviousTagFilterState"))) { _ in
                // restorePreviousTagFilterState是全局命令，应该在任何活跃窗口中可用
                guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true, commandName: "restorePreviousTagFilterState") else {
                    print("🚫 独立窗口: 忽略restorePreviousTagFilterState通知 - 应用无活跃窗口")
                    return
                }
                print("✅ 独立窗口: 处理restorePreviousTagFilterState通知，恢复标签筛选")
                store.restorePreviousTagFilterState()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("switchToLayer"))) { notification in
                // 🔧 处理来自层图谱窗口的层切换请求
                guard let layer = notification.object as? Layer else {
                    print("⚠️ 独立窗口: switchToLayer通知格式错误 - 缺少层对象")
                    return
                }
                
                if let userInfo = notification.userInfo,
                   let sourceWindowId = userInfo["sourceWindowId"] as? String,
                   !sourceWindowId.isEmpty {
                    
                    // 🔧 调试：打印窗口ID信息
                    print("🔍 独立窗口: switchToLayer通知窗口ID检查")
                    print("   - 通知中的sourceWindowId: \(sourceWindowId.prefix(8))")
                    print("   - 独立窗口的windowId: \(windowId.uuidString.prefix(8))")
                    print("   - WindowFocusManager中活跃窗口ID: \(WindowFocusManager.shared.getActiveWindowId()?.uuidString.prefix(8) ?? "nil")")
                    
                    // 检查是否是发给这个独立窗口的
                    if sourceWindowId == windowId.uuidString {
                        print("🔄 独立窗口: 处理来自层图谱的层切换请求 - 切换到层: \(layer.displayName)")
                        Task {
                            await store.switchToLayer(layer)
                        }
                    } else {
                        print("🚫 独立窗口: 忽略发给其他窗口的switchToLayer通知 - 目标: \(sourceWindowId.prefix(8))")
                    }
                } else {
                    // 如果没有指定源窗口，使用WindowFocusManager检查
                    guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: false, commandName: "switchToLayer") else {
                        print("🚫 独立窗口: 忽略switchToLayer通知 - 窗口非活跃状态")
                        return
                    }
                    print("✅ 独立窗口: 作为活跃窗口处理层切换请求 - 切换到层: \(layer.displayName)")
                    Task {
                        await store.switchToLayer(layer)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("handleMapPinTap"))) { notification in
                print("🔔 独立窗口: 收到handleMapPinTap通知")
                guard let userInfo = notification.userInfo,
                      let targetNodeId = userInfo["targetNodeId"] as? String,
                      let targetLayerId = userInfo["targetLayerId"] as? String else {
                    print("⚠️ 独立窗口: handleMapPinTap通知格式错误 - 缺少节点ID或层ID")
                    return
                }
                print("🔔 独立窗口: 通知包含 targetWindowId: \(userInfo["targetWindowId"] ?? "nil")")
                
                // 🔧 从当前store实例中查找对应的节点和层
                guard let targetNodeUUID = UUID(uuidString: targetNodeId),
                      let targetNode = store.nodes.first(where: { $0.id == targetNodeUUID }) else {
                    print("⚠️ 独立窗口: 未在当前store中找到目标节点 - ID: \(targetNodeId.prefix(8))")
                    return
                }
                
                guard let targetLayerUUID = UUID(uuidString: targetLayerId),
                      let targetLayer = store.layers.first(where: { $0.id == targetLayerUUID }) else {
                    print("⚠️ 独立窗口: 未在当前store中找到目标层 - ID: \(targetLayerId.prefix(8))")
                    return
                }
                
                // 🔧 重新设计通知路由逻辑：优先检查目标窗口ID，然后检查活跃状态
                // 如果指定了目标窗口ID，必须完全匹配才处理
                if let targetWindowId = userInfo["targetWindowId"] as? String {
                    if targetWindowId != windowId.uuidString {
                        print("🚫 独立窗口: 忽略handleMapPinTap通知 - 目标窗口不匹配 (\(targetWindowId.prefix(8)))")
                        return
                    }
                    print("🎯 独立窗口: 处理指定目标的地图节点点击")
                } else {
                    // 如果没有指定目标窗口ID，则使用WindowFocusManager进行活跃窗口检查
                    guard WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: false, commandName: "handleMapPinTap") else {
                        print("🚫 独立窗口: 忽略handleMapPinTap通知 - 窗口非活跃状态且无目标窗口ID")
                        return
                    }
                    print("✅ 独立窗口: 作为活跃窗口处理地图节点点击")
                }
                
                print("🗺️ 独立窗口: 处理地图标注点击 - 节点: \(targetNode.text), 层: \(targetLayer.displayName)")
                
                // 执行层切换和标签展开操作
                Task {
                    await store.switchToLayer(targetLayer)
                    
                    await MainActor.run {
                        store.expandLocationTagAndSelect(targetNode)
                        print("✅ 独立窗口: 已切换到层 '\(targetLayer.displayName)' 并展开地点标签")
                        
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
                    print("🚫 独立窗口: 忽略executeOpenNodeManager通知 - 非key窗口或冷却期")
                    return
                }
                
                print("🔔 独立窗口: 收到executeOpenNodeManager通知，打开节点管理窗口")
                if let source = notification.object as? String, source == "independent" {
                    print("🎯 独立窗口: 处理来自独立窗口的节点管理请求")
                    openWindow(id: "nodeManager")
                } else {
                    print("🚫 独立窗口: 忽略来自主窗口的节点管理请求")
                }
            }
            // 🚫 移除executeOpenMapWindow处理器，避免重复打开地图窗口
            // 现在直接在requestMapForLocationSelection处理器中打开地图窗口
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("requestWindowMapping"))) { notification in
                // 独立窗口处理窗口映射请求 - 这是关键修复！
                print("🔧 独立窗口: 收到窗口映射请求")
                
                if let requestInfo = notification.object as? [String: String],
                   let childWindowId = requestInfo["childWindowId"],
                   let windowType = requestInfo["windowType"] {
                    print("🔧 独立窗口: 处理窗口映射请求 - 窗口类型: \(windowType), 子窗口ID: \(childWindowId.prefix(8))")
                    
                    // 独立窗口的ID作为源窗口
                    let sourceWindowId = windowId.uuidString
                    print("🔧 独立窗口: 使用独立窗口作为源窗口ID: \(sourceWindowId.prefix(8))")
                    
                    // 发送映射信息
                    let mappingInfo = ["sourceWindowId": sourceWindowId]
                    NotificationCenter.default.post(
                        name: NSNotification.Name("mapWindowSetupMapping"),
                        object: mappingInfo
                    )
                    print("🔧 独立窗口: 已发送窗口映射信息到 \(windowType) 窗口")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("requestWindowMappingForMap"))) { notification in
                // 🔧 处理地图窗口的主动映射请求
                print("🔧 独立窗口: 收到地图窗口映射请求")
                
                if let requestInfo = notification.object as? [String: String],
                   let mapWindowId = requestInfo["mapWindowId"] {
                    print("🔧 独立窗口: 处理地图窗口映射请求 - 地图窗口ID: \(mapWindowId.prefix(8))")
                    
                    // 检查这个独立窗口是否应该响应（即它是否是活跃窗口或最近活跃的非地图窗口）
                    if WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: false) {
                        let sourceWindowId = windowId.uuidString
                        print("🔧 独立窗口: 确定为源窗口，发送映射信息 - 源窗口ID: \(sourceWindowId.prefix(8))")
                        
                        // 🎯 发送带目标地图窗口ID的映射信息
                        let mappingInfo = [
                            "sourceWindowId": sourceWindowId,
                            "targetMapWindowId": mapWindowId
                        ]
                        NotificationCenter.default.post(
                            name: NSNotification.Name("mapWindowSetupMapping"),
                            object: mappingInfo
                        )
                        print("🔧 独立窗口: 已发送目标映射信息到地图窗口 \(mapWindowId.prefix(8))")
                    } else {
                        print("🚫 独立窗口: 不是活跃窗口，忽略地图窗口映射请求")
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
                print("🔑 GlobalCommands: 标签搜索菜单项被点击")
                if let action = openTagSearch {
                    print("🔑 GlobalCommands: openTagSearch action 存在，执行中...")
                    action()
                } else {
                    print("❌ GlobalCommands: openTagSearch action 为 nil")
                }
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(openTagSearch == nil)
            
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
                print("🔑 GlobalCommands: Command+T - 清除标签筛选（全局菜单触发）")
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
            
            Button("打开图谱") {
                openGraphWindow?()
            }
            .keyboardShortcut("g", modifiers: [.command])
            .disabled(openGraphWindow == nil)
            
            // 🆕 全局标签功能菜单项
            Button("全局标签图谱") {
                GlobalTagGraphWindowManager.shared.showGlobalTagGraphWindow()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            
            Button("标签索引看板") {
                NewTagIndexWindowManager.shared.showTagIndexWindow()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            
            Divider()
            
            Button("详情面板：详情") {
                switchToDetailTab?()
            }
            .keyboardShortcut("o", modifiers: [.command])
            .disabled(switchToDetailTab == nil)
            
            Button("详情面板：图谱") {
                switchToGraphTab?()
            }
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(switchToGraphTab == nil)
            
            Button("切换到图谱视图") {
                switchToGraphTab?()
            }
            .keyboardShortcut("l", modifiers: [.command])
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

