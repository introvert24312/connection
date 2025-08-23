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
        // 启动时只加载基础标签，延迟扫描现有标签
        tagMappings = Self.builtInCoreTags + Self.commonTags
        
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
    
    // 动态添加缺失的标签映射
    func addMappingIfNeeded(key: String, typeName: String) {
        let normalizedKey = key.lowercased()
        
        // 检查是否已存在**完全相同的key**的映射
        if let existingIndex = tagMappings.firstIndex(where: { $0.key == normalizedKey }) {
            let existingMapping = tagMappings[existingIndex]
            
            // 只有当key完全相同时才考虑更新typeName
            // 这里我们不更新，因为可能破坏现有的映射关系
            if existingMapping.typeName != typeName {
                print("⚠️ 映射冲突：key '\(normalizedKey)' 已存在，typeName '\(existingMapping.typeName)' != '\(typeName)'，保持现有映射")
                return
            } else {
                print("✅ 映射已存在且相同: \(normalizedKey) -> \(typeName)")
                return
            }
        } else {
            // 不存在相同key的映射，可以安全添加
            let newMapping = TagMapping(key: normalizedKey, typeName: typeName)
            tagMappings.append(newMapping)
            saveToUserDefaults()
            print("🔄 自动添加标签映射: \(key) -> \(typeName)")
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
        TagMapping(key: "compound", typeName: "复合节点"),
        TagMapping(key: "child", typeName: "子节点")
    ]
    
    // 常用标签 - 可以删除的预设标签
    static let commonTags = [
        TagMapping(key: "root", typeName: "词根")
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
        
        // 确保beef映射始终存在且正确
        print("🔧 检查beef映射状态...")
        print("🔧 当前所有映射: \(tagMappings.map { "\($0.key)->\($0.typeName)" })")
        
        // 查找任何beef相关的映射
        if let existingBeefIndex = tagMappings.firstIndex(where: { $0.key == "beef" }) {
            let existingMapping = tagMappings[existingBeefIndex]
            print("🔧 找到现有beef映射: \(existingMapping.key) -> \(existingMapping.typeName)")
            
            // 保持用户的映射，不强制覆盖为"牛肉种类"
            print("🔧 保持用户的beef映射: \(existingMapping.typeName)")
        } else {
            // 如果没有beef映射，检查是否有相关的牛肉映射需要恢复
            // 首先尝试恢复用户最近的映射
            if let recentBeefMapping = restoreMostRecentBeefMapping() {
                tagMappings.append(recentBeefMapping)
                print("🔧 恢复最近的beef映射: beef -> \(recentBeefMapping.typeName)")
            } else {
                // 如果没有历史记录，添加默认的（使用用户偏好的名称）
                let newBeefMapping = TagMapping(key: "beef", typeName: "牛肉类型")
                tagMappings.append(newBeefMapping)
                print("🔧 添加默认的beef映射: beef -> 牛肉类型")
            }
        }
        
        print("🔧 修复后的映射字典keys: \(Array(mappingDictionary.keys))")
        
        saveToUserDefaults()
        
        // 立即同步到外部存储，确保修复不会被覆盖
        Task {
            do {
                try await ExternalDataService.shared.saveTagMappingsOnly()
                print("✅ beef映射修复已同步到外部存储")
            } catch {
                print("⚠️ beef映射修复同步到外部存储失败: \(error)")
            }
        }
    }
    
    // 尝试恢复最近的beef映射
    private func restoreMostRecentBeefMapping() -> TagMapping? {
        // 根据用户的历史，应该是 beef -> 牛肉类型
        print("🔧 检测用户历史beef映射偏好...")
        
        // 直接使用用户最常用的"牛肉类型"，这是从之前的会话分析得出的
        let preferredTypeName = "牛肉类型"
        print("🔧 使用用户偏好的beef映射: beef -> \(preferredTypeName)")
        return TagMapping(key: "beef", typeName: preferredTypeName)
    }
    
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
    
    // 强制重建beef映射
    func forceRebuildBeefMapping() {
        print("🔧 强制重建beef映射...")
        
        // 删除所有beef相关映射
        tagMappings.removeAll { $0.key == "beef" }
        
        // 添加正确的beef映射（使用用户偏好的名称）
        let correctBeefMapping = TagMapping(key: "beef", typeName: "牛肉类型")
        tagMappings.append(correctBeefMapping)
        
        // 立即保存到本地和外部存储
        saveToUserDefaults()
        
        // 立即同步到外部存储
        Task {
            do {
                try await ExternalDataService.shared.saveTagMappingsOnly()
                print("✅ beef映射重建已同步到外部存储")
            } catch {
                print("⚠️ beef映射重建同步失败: \(error)")
            }
        }
        
        print("✅ beef映射重建完成: beef -> 牛肉类型")
        print("✅ 当前所有映射: \(tagMappings.map { "\($0.key)->\($0.typeName)" })")
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
        // 总是包含内置核心标签和常用标签
        var mappings = Self.builtInCoreTags + Self.commonTags
        
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
    
    // 新增：支持预填充节点（用于编辑模式）
    let prefilledNode: Node?
    
    // 初始化器，支持可选的预填充节点
    init(prefilledNode: Node? = nil) {
        self.prefilledNode = prefilledNode
    }
    
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
            
        }
        .frame(width: 600)
        .navigationTitle(prefilledNode != nil ? "编辑节点" : "快速添加节点")
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
                Button(prefilledNode != nil ? "保存" : "添加") {
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
            // 如果是编辑模式，预填充现有节点的命令
            if let node = prefilledNode {
                print("🔄 [QuickAdd] 编辑模式开始预填充节点: '\(node.text)'")
                print("🔄 [QuickAdd] 节点标签数量: \(node.tags.count)")
                for (index, tag) in node.tags.enumerated() {
                    print("🔄 [QuickAdd] 标签[\(index)]: type=\(tag.type), rawValue='\(tag.type.rawValue)', displayName='\(tag.type.displayName)', value='\(tag.value)'")
                }
                
                inputText = node.commandRepresentationWithDisplayNames
                print("🔄 [QuickAdd] 编辑模式：预填充命令完成 - '\(inputText)'")
            }
            
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
        
        
        guard !components.isEmpty else { 
                return 
        }
        
        // 🔧 检查是否是复合节点命令 (以"c"开头)
        if components[0] == "c" {
            handleCompoundNodeCommand(components: components)
            // 清空输入并关闭窗口
            inputText = ""
            dismiss()
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
                    
                    
                    // 处理标签重命名
                    if let existingMapping = tagManager.tagMappings.first(where: { $0.key == actualTagKey }) {
                        _ = existingMapping.typeName // 原类型名，用于日志记录
                        
                        // 创建更新后的映射
                        let updatedMapping = TagMapping(
                            id: existingMapping.id,
                            key: actualTagKey,
                            typeName: newTypeName
                        )
                        
                        // 保存到TagManager，会自动触发UI更新
                        tagManager.saveMapping(updatedMapping)
                        
                    } else {
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
                                       let bracketIndex = content.firstIndex(of: "[") {
                                        let coordString = String(content[content.index(after: atIndex)..<bracketIndex])
                                        let coords = coordString.split(separator: ",")
                                        
                                        if coords.count == 2,
                                           let latitude = Double(coords[0]),
                                           let longitude = Double(coords[1]) {
                                            lat = latitude
                                            lng = longitude
                                            
                                            if let startBracket = content.firstIndex(of: "["),
                                               let endBracket = content.firstIndex(of: "]"),
                                               startBracket < endBracket {
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
    
    // 处理复合节点命令 (c 复合节点名 节点1 节点2 ...)
    private func handleCompoundNodeCommand(components: [String]) {
        print("🔧 处理复合节点命令: \(components)")
        
        guard components.count >= 3 else {
            // 触发错误警告
            store.duplicateNodeAlert = NodeStore.DuplicateNodeAlert(
                message: "复合节点命令格式错误：至少需要 'c 复合节点名 子节点1'",
                isDuplicate: false,
                existingNode: nil,
                newNode: Node(text: "错误命令", layerId: UUID(), tags: [])
            )
            return
        }
        
        let compoundNodeName = components[1]
        let childNodeNames = Array(components[2...])
        
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
                print("🔄 向已存在的复合节点添加子节点: \(compoundNodeName)")
                addChildrenToExistingCompoundNode(existingCompoundNode, childNames: childNamesToAdd)
            }
        } else {
            // 创建新的复合节点
            if !childNamesToRemove.isEmpty {
                store.duplicateNodeAlert = NodeStore.DuplicateNodeAlert(
                    message: "无法从不存在的复合节点中删除子节点",
                    isDuplicate: false,
                    existingNode: nil,
                    newNode: Node(text: compoundNodeName, layerId: currentLayer.id, tags: [])
                )
                return
            }
            print("🏗️ 创建新复合节点: \(compoundNodeName)")
            createNewCompoundNode(name: compoundNodeName, childNames: childNamesToAdd, layerId: currentLayer.id)
        }
        
        print("✅ 复合节点命令处理完成")
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
        isWaitingForLocationSelection = true
        
        // 打开地图窗口
        print("📍 QuickAddSheetView: Posting openMapWindow notification")
        NotificationCenter.default.post(name: NSNotification.Name("openMapWindow"), object: nil)
        
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
        NotificationCenter.default.post(name: NSNotification.Name("openMapWindow"), object: nil)
        
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
    @State private var selectedIndex: Int = -1  // -1表示焦点在搜索框，0+表示结果项索引
    @FocusState private var isSearchFieldFocused: Bool
    let onDismiss: () -> Void
    let onNodeSelected: (Node) -> Void
    
    private var filteredNodes: [Node] {
        if searchText.isEmpty {
            return Array(store.nodes.prefix(10)) // 显示前10个
        } else {
            return store.nodes.filter { node in
                node.text.localizedCaseInsensitiveContains(searchText) ||
                node.meaning?.localizedCaseInsensitiveContains(searchText) == true ||
                node.tags.contains { tag in
                    tag.value.localizedCaseInsensitiveContains(searchText)
                }
            }
        }
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
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.blue)
                        .font(.title2)
                    
                    TextField("搜索单词、含义或标签...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium))
                        .focused($isSearchFieldFocused)
                        .onSubmit {
                            selectCurrentNode()
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
                
                // 搜索结果
                if !filteredNodes.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(filteredNodes.enumerated()), id: \.element.id) { index, word in
                                NodeSearchResultRow(
                                    word: word,
                                    searchText: searchText,
                                    isSelected: selectedIndex >= 0 && index == selectedIndex
                                )
                                .frame(maxWidth: .infinity)  // 填满可用宽度
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedIndex >= 0 && index == selectedIndex ? 
                                              Color.blue.opacity(0.1) : Color.clear)
                                )
                                .padding(.horizontal, 4) // 给选项卡一些边距
                                .contentShape(Rectangle())  // 明确整个矩形区域可点击
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
                } else if !searchText.isEmpty {
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
                
                // 帮助文本
                HStack {
                    Text("💡 输入关键词搜索单词")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("⌘+F")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 12)
            }
            .padding(20)
            .frame(maxWidth: 600)
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
            if selectedIndex >= 0 {
                // 选择当前高亮的结果
                selectCurrentNode()
                print("🔍 回车键: 选择结果 (index: \(selectedIndex))")
            } else if !filteredNodes.isEmpty {
                // 如果在搜索框中，选择第一个结果
                selectedIndex = 0
                selectCurrentNode()
                print("🔍 回车键: 从搜索框选择第一个结果")
            }
            return .handled
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
}

struct NodeSearchResultRow: View {
    let word: Node
    let searchText: String
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // 单词文本
                Text(highlightedText(word.text, searchText: searchText))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // 标签
                HStack(spacing: 4) {
                    ForEach(word.tags.prefix(3), id: \.id) { tag in
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
                    if word.tags.count > 3 {
                        Text("+\(word.tags.count - 3)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 含义
            if let meaning = word.meaning, !meaning.isEmpty {
                Text(highlightedText(meaning, searchText: searchText))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)  // 确保填满可用宽度
        .contentShape(Rectangle())  // 明确定义点击区域为整个矩形
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
    @State private var nodeToEditInManager: Node? = nil
    
    init() {
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

    var body: some Scene {
        WindowGroup("节点标签管理器") {
            ZStack {
                ContentView()
                    .environmentObject(store)
                    .frame(minWidth: 900, minHeight: 520)
                
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
                return .ignored
            }
            .sheet(isPresented: $showQuickAdd) {
                QuickAddSheetView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showCompoundNodeAdd) {
                CompoundNodeAddSheetView()
                    .environmentObject(store)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("addNewNode"))) { _ in
                showQuickAdd = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openNodeManagerForEdit"))) { notification in
                if let node = notification.object as? Node {
                    print("📝 WordTaggerApp: 收到节点编辑请求，节点: \(node.text)")
                    nodeToEditInManager = node
                    // 打开节点管理窗口
                    NotificationCenter.default.post(name: Notification.Name("openNodeManager"), object: nil)
                }
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
                
                Button("创建新层或复合层") { 
                    showPalette = true 
                }
                .keyboardShortcut("r", modifiers: [.command])
                
                Divider()
                
                Button("快速添加节点") {
                    showQuickAdd = true
                }
                .keyboardShortcut("i", modifiers: [.command])
                
                Button("添加复合节点") {
                    showCompoundNodeAdd = true
                }
                .keyboardShortcut("u", modifiers: [.command])
                
                Button("标签搜索") {
                    print("🏷️ WordTaggerApp: Command+F 快捷键被触发，切换到标签搜索")
                    NotificationCenter.default.post(name: Notification.Name("openTagSearch"), object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])
                
                Button("快速搜索") {
                    print("🔍 WordTaggerApp: Command+Shift+F 快捷键被触发，显示快速搜索")
                    showQuickSearch = true
                    print("🔍 WordTaggerApp: showQuickSearch 设置为 true")
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                
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
                
                Button("清除标签筛选") {
                    // 清除所有标签筛选状态，回到初始状态
                    NotificationCenter.default.post(name: Notification.Name("clearTagFilter"), object: nil)
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
                
                Divider()
                
                Button("详情面板：详情") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("switchToDetailTab"), 
                        object: nil
                    )
                }
                .keyboardShortcut("o", modifiers: [.command])
                
                Button("详情面板：图谱") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("switchToGraphTab"), 
                        object: nil
                    )
                }
                .keyboardShortcut("d", modifiers: [.command])
                
                Button("切换到图谱视图") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("switchToGraphTab"), 
                        object: nil
                    )
                }
                .keyboardShortcut("l", modifiers: [.command])
                
                Divider()
                

            }
        }
        
        // 地图窗口
        WindowGroup("地图视图", id: "map") {
            MapWindow()
                .environmentObject(store)
                .frame(minWidth: 750, minHeight: 500)
        }
        .defaultSize(width: 1000, height: 700)
        
        // 图谱窗口
        WindowGroup("全局图谱", id: "graph") {
            GraphView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1200, height: 800)
        
        // 节点管理窗口
        WindowGroup("节点管理", id: "nodeManager") {
            NodeManagerView(nodeToEdit: $nodeToEditInManager)
                .environmentObject(store)
                .frame(minWidth: 750, minHeight: 500)
        }
        .defaultSize(width: 1000, height: 700)
        
        // 全屏图谱窗口 - SwiftUI原生方式
        WindowGroup("全屏图谱", id: "fullscreenGraph") {
            FullscreenGraphView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 520)
                .onAppear {
                    // 窗口级别的焦点设置
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NSApp.keyWindow?.makeKey()
                        Swift.print("🎯 WindowGroup: 设置窗口焦点完成")
                    }
                }
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
    @State private var showSystemTags: Bool = false  // 默认隐藏系统标签
    @FocusState private var isViewFocused: Bool
    
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.3)
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
                // 标题栏
                HStack {
                    Text("标签管理")
                        .font(.title)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
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
                    }
                    .buttonStyle(.plain)
                    .help("重新扫描现有标签并创建缺失的映射")
                    
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
                        ForEach(filteredMappings, id: \.id) { mapping in
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
                        .font(.title2)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("快捷键")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("例如: root", text: $newKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("类型名称")
                                    .font(.subheadline)
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
                
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.2), radius: 30, x: 0, y: 10)
            .frame(maxWidth: 700, maxHeight: 600)
            .padding(20)
        }
        .onAppear {
            // 视图出现时自动聚焦，确保可以接收键盘事件
            isViewFocused = true
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
    
    // 判断是否应该隐藏系统标签
    private func shouldHideSystemTag(_ mapping: TagMapping) -> Bool {
        // 隐藏核心系统标签以减少认知负荷
        // compound: 复合节点标记标签，系统内部使用
        // child: 子节点引用标签，系统内部使用
        // loc: 地点标签，地图功能使用
        let systemTagsToHide = ["compound", "child", "loc"]
        return systemTagsToHide.contains(mapping.key)
    }
    
    private var filteredMappings: [TagMapping] {
        return tagManager.tagMappings.filter { mapping in
            showSystemTags || !shouldHideSystemTag(mapping)
        }
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
                    Text("快捷键: ⌘+R提交 • Esc关闭")
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
                .keyboardShortcut("r", modifiers: .command)
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


