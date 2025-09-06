import Foundation
import SwiftUI

// MARK: - 层图谱预设数据结构

struct LayerGraphPreset: Identifiable, Codable {
    let id: UUID
    var name: String
    var filteredLayerIds: Set<UUID>
    var createdAt: Date
    var lastUsedAt: Date
    
    init(name: String, filteredLayerIds: Set<UUID>) {
        self.id = UUID()
        self.name = name
        self.filteredLayerIds = filteredLayerIds
        self.createdAt = Date()
        self.lastUsedAt = Date()
    }
    
    mutating func updateLastUsed() {
        lastUsedAt = Date()
    }
}

// MARK: - 层图谱预设管理器

@MainActor
class LayerGraphPresetManager: ObservableObject {
    static let shared = LayerGraphPresetManager()
    
    @Published var presets: [LayerGraphPreset] = []
    @Published var currentPreset: LayerGraphPreset?
    
    private let userDefaultsKey = "layerGraphPresets"
    private let currentPresetKey = "layerGraphCurrentPreset"
    
    // 默认预设ID（内置）
    private let defaultPresetId = UUID()
    
    private init() {
        loadPresets()
    }
    
    // MARK: - 预设管理
    
    /// 获取默认预设（显示所有层）
    func getDefaultPreset(allLayers: [Layer]) -> LayerGraphPreset {
        let allLayerIds = Set(allLayers.map { $0.id })
        var defaultPreset = LayerGraphPreset(name: "默认", filteredLayerIds: allLayerIds)
        defaultPreset.id = defaultPresetId
        return defaultPreset
    }
    
    /// 保存预设
    func savePreset(name: String, filteredLayerIds: Set<UUID>) {
        let newPreset = LayerGraphPreset(name: name, filteredLayerIds: filteredLayerIds)
        presets.append(newPreset)
        saveToUserDefaults()
        print("💾 LayerGraphPresetManager: 保存预设 '\(name)' - \(filteredLayerIds.count)个层")
    }
    
    /// 加载预设
    func loadPreset(_ preset: LayerGraphPreset) {
        var updatedPreset = preset
        updatedPreset.updateLastUsed()
        
        // 更新预设列表中的记录
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = updatedPreset
        }
        
        currentPreset = updatedPreset
        saveCurrentPreset()
        print("📂 LayerGraphPresetManager: 加载预设 '\(preset.name)' - \(preset.filteredLayerIds.count)个层")
    }
    
    /// 删除预设
    func deletePreset(_ preset: LayerGraphPreset) {
        presets.removeAll { $0.id == preset.id }
        saveToUserDefaults()
        print("🗑️ LayerGraphPresetManager: 删除预设 '\(preset.name)'")
    }
    
    /// 重命名预设
    func renamePreset(_ preset: LayerGraphPreset, newName: String) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index].name = newName
            saveToUserDefaults()
            print("✏️ LayerGraphPresetManager: 重命名预设 '\(preset.name)' -> '\(newName)'")
        }
    }
    
    /// 获取当前预设或默认预设
    func getCurrentPreset(allLayers: [Layer]) -> LayerGraphPreset {
        if let current = currentPreset {
            return current
        } else {
            return getDefaultPreset(allLayers: allLayers)
        }
    }
    
    /// 更新默认预设的层列表（当有新层添加时）
    func updateDefaultPreset(allLayers: [Layer]) {
        let defaultPreset = getDefaultPreset(allLayers: allLayers)
        if currentPreset?.id == defaultPresetId {
            currentPreset = defaultPreset
        }
    }
    
    // MARK: - 数据持久化
    
    private func saveToUserDefaults() {
        do {
            let data = try JSONEncoder().encode(presets)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("❌ LayerGraphPresetManager: 保存预设失败 - \(error)")
        }
    }
    
    private func loadPresets() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            print("📂 LayerGraphPresetManager: 未找到已保存的预设")
            return
        }
        
        do {
            presets = try JSONDecoder().decode([LayerGraphPreset].self, from: data)
            loadCurrentPreset()
            print("📂 LayerGraphPresetManager: 加载了 \(presets.count) 个预设")
        } catch {
            print("❌ LayerGraphPresetManager: 加载预设失败 - \(error)")
        }
    }
    
    private func saveCurrentPreset() {
        do {
            if let current = currentPreset {
                let data = try JSONEncoder().encode(current)
                UserDefaults.standard.set(data, forKey: currentPresetKey)
            }
        } catch {
            print("❌ LayerGraphPresetManager: 保存当前预设失败 - \(error)")
        }
    }
    
    private func loadCurrentPreset() {
        guard let data = UserDefaults.standard.data(forKey: currentPresetKey) else {
            return
        }
        
        do {
            currentPreset = try JSONDecoder().decode(LayerGraphPreset.self, from: data)
        } catch {
            print("❌ LayerGraphPresetManager: 加载当前预设失败 - \(error)")
        }
    }
}