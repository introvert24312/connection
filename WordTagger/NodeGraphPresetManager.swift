import Foundation
import SwiftUI

// MARK: - 节点图谱预设数据结构

struct NodeGraphPreset: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String?
    var selectedNodeIds: Set<UUID>
    var selectedLayerIds: Set<UUID>
    var createdAt: Date
    var lastUsed: Date
    
    init(name: String, description: String? = nil, selectedNodeIds: Set<UUID>, selectedLayerIds: Set<UUID>, createdAt: Date, lastUsed: Date) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.selectedNodeIds = selectedNodeIds
        self.selectedLayerIds = selectedLayerIds
        self.createdAt = createdAt
        self.lastUsed = lastUsed
    }
    
    mutating func updateLastUsed() {
        lastUsed = Date()
    }
}

// MARK: - 节点图谱预设管理器

@MainActor
class NodeGraphPresetManager: ObservableObject {
    static let shared = NodeGraphPresetManager()
    
    @Published var presets: [NodeGraphPreset] = []
    @Published var currentPreset: NodeGraphPreset?
    
    private let userDefaultsKey = "nodeGraphPresets"
    private let currentPresetKey = "nodeGraphCurrentPreset"
    
    private init() {
        loadPresets()
    }
    
    // MARK: - 预设管理
    
    /// 保存预设
    func savePreset(_ preset: NodeGraphPreset) {
        presets.append(preset)
        saveToUserDefaults()
        print("💾 NodeGraphPresetManager: 保存预设 '\(preset.name)' - 节点:\(preset.selectedNodeIds.count), 层级:\(preset.selectedLayerIds.count)")
    }
    
    /// 加载预设
    func loadPreset(_ preset: NodeGraphPreset) -> (selectedNodeIds: Set<UUID>, selectedLayerIds: Set<UUID>) {
        var updatedPreset = preset
        updatedPreset.updateLastUsed()
        
        // 更新预设列表中的记录
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = updatedPreset
        }
        
        currentPreset = updatedPreset
        saveCurrentPreset()
        saveToUserDefaults()
        
        print("📂 NodeGraphPresetManager: 加载预设 '\(preset.name)' - 节点:\(preset.selectedNodeIds.count), 层级:\(preset.selectedLayerIds.count)")
        
        return (selectedNodeIds: preset.selectedNodeIds, selectedLayerIds: preset.selectedLayerIds)
    }
    
    /// 删除预设
    func deletePreset(_ preset: NodeGraphPreset) {
        presets.removeAll { $0.id == preset.id }
        
        // 如果删除的是当前预设，清除当前预设
        if currentPreset?.id == preset.id {
            currentPreset = nil
            UserDefaults.standard.removeObject(forKey: currentPresetKey)
        }
        
        saveToUserDefaults()
        print("🗑️ NodeGraphPresetManager: 删除预设 '\(preset.name)'")
    }
    
    /// 重命名预设
    func renamePreset(_ preset: NodeGraphPreset, newName: String) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            let oldName = presets[index].name
            presets[index].name = newName
            
            // 如果是当前预设，也更新当前预设
            if currentPreset?.id == preset.id {
                currentPreset?.name = newName
                saveCurrentPreset()
            }
            
            saveToUserDefaults()
            print("✏️ NodeGraphPresetManager: 重命名预设 '\(oldName)' -> '\(newName)'")
        }
    }
    
    /// 更新预设描述
    func updatePresetDescription(_ preset: NodeGraphPreset, newDescription: String?) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index].description = newDescription
            
            // 如果是当前预设，也更新当前预设
            if currentPreset?.id == preset.id {
                currentPreset?.description = newDescription
                saveCurrentPreset()
            }
            
            saveToUserDefaults()
            print("📝 NodeGraphPresetManager: 更新预设描述 '\(preset.name)'")
        }
    }
    
    /// 获取预设按创建时间排序
    var presetsSortedByCreation: [NodeGraphPreset] {
        presets.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// 获取预设按最近使用时间排序
    var presetsSortedByLastUsed: [NodeGraphPreset] {
        presets.sorted { $0.lastUsed > $1.lastUsed }
    }
    
    // MARK: - 数据持久化
    
    private func saveToUserDefaults() {
        do {
            let data = try JSONEncoder().encode(presets)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("❌ NodeGraphPresetManager: 保存预设失败 - \(error)")
        }
    }
    
    private func loadPresets() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            print("📂 NodeGraphPresetManager: 未找到已保存的预设")
            return
        }
        
        do {
            presets = try JSONDecoder().decode([NodeGraphPreset].self, from: data)
            loadCurrentPreset()
            print("📂 NodeGraphPresetManager: 加载了 \(presets.count) 个节点图谱预设")
        } catch {
            print("❌ NodeGraphPresetManager: 加载预设失败 - \(error)")
            // 如果解码失败，重置预设列表
            presets = []
        }
    }
    
    private func saveCurrentPreset() {
        do {
            if let current = currentPreset {
                let data = try JSONEncoder().encode(current)
                UserDefaults.standard.set(data, forKey: currentPresetKey)
            }
        } catch {
            print("❌ NodeGraphPresetManager: 保存当前预设失败 - \(error)")
        }
    }
    
    private func loadCurrentPreset() {
        guard let data = UserDefaults.standard.data(forKey: currentPresetKey) else {
            return
        }
        
        do {
            currentPreset = try JSONDecoder().decode(NodeGraphPreset.self, from: data)
        } catch {
            print("❌ NodeGraphPresetManager: 加载当前预设失败 - \(error)")
        }
    }
}