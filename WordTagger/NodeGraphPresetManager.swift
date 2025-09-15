import Foundation
import SwiftUI

// MARK: - 节点图谱预设数据结构

struct NodeGraphPreset: Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    let selectedNodeIds: [String]  // 使用String存储，避免UUID编码问题
    let selectedLayerIds: [String] // 使用String存储，避免UUID编码问题
    let createdAt: Date
    let lastUsed: Date
    
    init(id: String = UUID().uuidString, name: String, description: String? = nil, 
         selectedNodeIds: [String], selectedLayerIds: [String]) {
        self.id = id
        self.name = name
        self.description = description
        self.selectedNodeIds = selectedNodeIds
        self.selectedLayerIds = selectedLayerIds
        self.createdAt = Date()
        self.lastUsed = Date()
    }
}

// MARK: - 节点图谱预设集合

struct NodeGraphPresetCollection: Codable {
    var presets: [NodeGraphPreset]
    let lastModified: Date
    
    init(presets: [NodeGraphPreset] = []) {
        self.presets = presets
        self.lastModified = Date()
    }
}

// MARK: - 节点图谱预设管理器

@MainActor
class NodeGraphPresetManager: ObservableObject {
    static let shared = NodeGraphPresetManager()
    
    @Published var presets: [NodeGraphPreset] = []
    @Published var currentPreset: NodeGraphPreset?
    
    // 🆕 使用外部存储 - 完全照抄GlobalTagGraphSystem的逻辑
    private static let presetsFileName = "NodeGraph_Presets.json"
    private static let lastUsedPresetKey = "NodeGraph_LastUsedPresetId"
    
    private static var presetsFileURL: URL? {
        // 节点图谱预设文件路径 - 完全照抄GlobalTagGraphSystem
        guard let basePath = ExternalDataManager.shared.currentDataPath else {
            let documentDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            return documentDir.appendingPathComponent(presetsFileName)
        }
        let metadataDir = basePath.appendingPathComponent("data/metadata")
        return metadataDir.appendingPathComponent(presetsFileName)
    }
    
    private let instanceId = UUID().uuidString.prefix(8)  // 实例标识符
    
    private init() {
        print("🏗️ [节点图谱预设管理器-\(instanceId)] 创建新实例")
        loadPresets()
        // 🚫 全局节点图谱默认不加载任何预设
        // loadLastUsedPreset()
    }
    
    // MARK: - 🆕 预设管理 - 完全照抄GlobalTagGraphSystem的逻辑
    
    /// 保存当前状态为新预设 - 照抄GlobalTagGraphSystem.saveCurrentAsPreset
    func saveCurrentAsPreset(name: String, description: String? = nil, selectedNodeIds: Set<UUID>, selectedLayerIds: Set<UUID>) {
        print("💾 [节点图谱预设管理器-\(instanceId)] 保存当前状态为预设: \(name)")
        
        let preset = NodeGraphPreset(
            name: name,
            description: description,
            selectedNodeIds: selectedNodeIds.map { $0.uuidString },
            selectedLayerIds: selectedLayerIds.map { $0.uuidString }
        )
        
        // 检查是否已存在同名预设 - 完全照抄
        if let existingIndex = presets.firstIndex(where: { $0.name == name }) {
            presets[existingIndex] = preset
            print("🔄 [节点图谱预设管理器-\(instanceId)] 更新现有预设: \(name)")
        } else {
            presets.append(preset)
            print("🆕 [节点图谱预设管理器-\(instanceId)] 创建新预设: \(name)")
        }
        
        currentPreset = preset
        savePresets()  // 照抄GlobalTagGraphSystem.saveGraphPresets
        
        // 确保UI更新在主线程执行
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    /// 加载指定预设 - 照抄GlobalTagGraphSystem.loadPreset
    func loadPreset(_ preset: NodeGraphPreset) -> (selectedNodeIds: Set<UUID>, selectedLayerIds: Set<UUID>) {
        print("📖 [节点图谱预设管理器-\(instanceId)] 加载预设: \(preset.name)")
        
        // 转换字符串回UUID
        let nodeIds = Set(preset.selectedNodeIds.compactMap { UUID(uuidString: $0) })
        let layerIds = Set(preset.selectedLayerIds.compactMap { UUID(uuidString: $0) })
        
        // 更新当前预设
        currentPreset = preset
        
        // 保存为上次使用的预设 - 照抄
        saveAsLastUsedPreset(preset)
        
        print("✅ [节点图谱预设管理器-\(instanceId)] 预设加载完成")
        print("   - 节点: \(nodeIds.count) 个")
        print("   - 层级: \(layerIds.count) 个")
        
        return (selectedNodeIds: nodeIds, selectedLayerIds: layerIds)
    }
    
    /// 删除预设 - 完全照抄GlobalTagGraphSystem.deletePreset
    func deletePreset(_ preset: NodeGraphPreset) {
        print("🗑️ [节点图谱预设管理器-\(instanceId)] 删除预设: \(preset.name)")
        
        presets.removeAll { $0.id == preset.id }
        
        if currentPreset?.id == preset.id {
            currentPreset = nil
        }
        
        savePresets()
    }
    
    /// 重命名预设
    func renamePreset(_ preset: NodeGraphPreset, newName: String) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            let oldName = presets[index].name
            let updatedPreset = NodeGraphPreset(
                id: preset.id,
                name: newName,
                description: preset.description,
                selectedNodeIds: preset.selectedNodeIds,
                selectedLayerIds: preset.selectedLayerIds
            )
            presets[index] = updatedPreset
            
            // 如果是当前预设，也更新当前预设
            if currentPreset?.id == preset.id {
                currentPreset = updatedPreset
                saveAsLastUsedPreset(updatedPreset)
            }
            
            savePresets()
            print("✏️ [节点图谱预设管理器-\(instanceId)] 重命名预设 '\(oldName)' -> '\(newName)'")
        }
    }
    
    // MARK: - 数据持久化 - 完全照抄GlobalTagGraphSystem的逻辑
    
    /// 强制重新加载预设 - 供UI调用
    func reloadPresets() {
        print("🔄 [节点图谱预设管理器-\(instanceId)] 强制重新加载预设")
        loadPresets()
        objectWillChange.send()
    }
    
    /// 加载所有预设 - 完全照抄GlobalTagGraphSystem.loadGraphPresets
    private func loadPresets() {
        print("📖 [节点图谱预设管理器-\(instanceId)] 加载预设")
        
        guard let fileURL = Self.presetsFileURL else {
            print("❌ [节点图谱预设管理器-\(instanceId)] 无法获取预设文件路径")
            return
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("ℹ️ [节点图谱预设管理器-\(instanceId)] 预设文件不存在，使用默认空列表")
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601  // 照抄：添加日期解码策略
            let collection = try decoder.decode(NodeGraphPresetCollection.self, from: data)
            
            presets = collection.presets
            print("✅ [节点图谱预设管理器-\(instanceId)] 成功加载 \(presets.count) 个预设")
            
        } catch {
            print("❌ [节点图谱预设管理器-\(instanceId)] 加载预设失败: \(error)")
        }
    }
    
    /// 保存所有预设 - 完全照抄GlobalTagGraphSystem.saveGraphPresets
    private func savePresets() {
        print("💾 [节点图谱预设管理器-\(instanceId)] 保存预设到外部存储")
        
        guard let fileURL = Self.presetsFileURL else {
            print("❌ [节点图谱预设管理器-\(instanceId)] 无法获取预设文件路径")
            return
        }
        
        let collection = NodeGraphPresetCollection(presets: presets)
        
        do {
            // 确保metadata文件夹存在 - 完全照抄
            let metadataDir = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: metadataDir.path) {
                try FileManager.default.createDirectory(at: metadataDir, withIntermediateDirectories: true, attributes: nil)
                print("📁 [节点图谱预设管理器-\(instanceId)] 创建metadata文件夹")
            }
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            
            let data = try encoder.encode(collection)
            try data.write(to: fileURL)
            
            print("✅ [节点图谱预设管理器-\(instanceId)] 成功保存 \(presets.count) 个预设")
            
            // 触发自动同步到Git - 完全照抄
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("TriggerAutoSync"),
                    object: nil,
                    userInfo: ["reason": "NodeGraphPresetsChanged"]
                )
            }
            
        } catch {
            print("❌ [节点图谱预设管理器-\(instanceId)] 保存预设失败: \(error)")
        }
    }
    
    // MARK: - 上次使用预设管理 - 完全照抄GlobalTagGraphSystem
    
    /// 保存预设为上次使用的预设 - 完全照抄GlobalTagGraphSystem.saveAsLastUsedPreset
    private func saveAsLastUsedPreset(_ preset: NodeGraphPreset) {
        UserDefaults.standard.set(preset.id, forKey: Self.lastUsedPresetKey)
        print("💾 [节点图谱预设管理器-\(instanceId)] 保存上次使用的预设: \(preset.name) (ID: \(preset.id))")
    }
    
    /// 加载上次使用的预设 - 完全照抄GlobalTagGraphSystem.loadLastUsedPreset
    private func loadLastUsedPreset() {
        guard let lastUsedPresetId = UserDefaults.standard.string(forKey: Self.lastUsedPresetKey) else {
            print("ℹ️ [节点图谱预设管理器-\(instanceId)] 没有找到上次使用的预设")
            return
        }
        
        guard let lastUsedPreset = presets.first(where: { $0.id == lastUsedPresetId }) else {
            print("⚠️ [节点图谱预设管理器-\(instanceId)] 上次使用的预设不存在: \(lastUsedPresetId)")
            // 清除无效的引用
            UserDefaults.standard.removeObject(forKey: Self.lastUsedPresetKey)
            return
        }
        
        print("🔄 [节点图谱预设管理器-\(instanceId)] 恢复上次使用的预设: \(lastUsedPreset.name)")
        
        // 设置为当前预设（但不再次保存）
        currentPreset = lastUsedPreset
        
        print("✅ [节点图谱预设管理器-\(instanceId)] 上次使用的预设已恢复")
        print("   - 节点: \(lastUsedPreset.selectedNodeIds.count) 个")
        print("   - 层级: \(lastUsedPreset.selectedLayerIds.count) 个")
    }
    
    // MARK: - 便利属性
    
    /// 获取预设按创建时间排序
    var presetsSortedByCreation: [NodeGraphPreset] {
        presets.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// 获取预设按最近使用时间排序
    var presetsSortedByLastUsed: [NodeGraphPreset] {
        presets.sorted { $0.lastUsed > $1.lastUsed }
    }
}