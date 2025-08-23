import Foundation
import SwiftUI

// MARK: - 外部数据服务

@MainActor
public class ExternalDataService: ObservableObject {
    @Published public var isSaving: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var lastSyncTime: Date?
    @Published public var syncStatus: SyncStatus = .idle
    
    private let dataManager = ExternalDataManager.shared
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    public static let shared = ExternalDataService()
    
    private init() {
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - 数据保存
    
    public func saveAllData(store: NodeStore) async throws {
        print("💾 ExternalDataService: 开始保存数据...")
        
        guard dataManager.isDataPathSelected else {
            print("❌ 没有选择数据路径")
            throw DataError.noDataPathSelected
        }
        
        print("📁 当前数据路径: \(dataManager.currentDataPath?.path ?? "nil")")
        
        // 检查并确保访问权限
        guard dataManager.ensureAccess() else {
            print("❌ 访问权限检查失败")
            throw DataError.accessDenied
        }
        
        print("✅ 访问权限检查成功")
        
        await MainActor.run { isSaving = true }
        
        do {
            // 打印当前数据状态
            await MainActor.run {
                print("📊 当前数据状态:")
                print("   - Layers: \(store.layers.count) 个")
                print("   - Nodes: \(store.nodes.count) 个")
                
                for (index, layer) in store.layers.enumerated() {
                    print("   - Layer[\(index)]: \(layer.displayName) (\(layer.name))")
                }
                
                for (index, node) in store.nodes.prefix(5).enumerated() {
                    print("   - Node[\(index)]: \(node.text) - Layer: \(node.layerId)")
                }
                
                if store.nodes.count > 5 {
                    print("   - ... 还有 \(store.nodes.count - 5) 个节点")
                }
            }
            
            // 在后台线程执行文件I/O操作
            try await withCheckedThrowingContinuation { continuation in
                Task.detached {
                    do {
                        print("💾 创建备份...")
                        // 创建备份
                        try await self.createBackup(store: store)
                        print("✅ 备份创建成功")
                        
                        print("💾 保存Layers...")
                        // 保存各个数据文件
                        try await self.saveLayers(store.layers)
                        print("✅ Layers保存成功")
                        
                        print("💾 保存Nodes...")
                        try await self.saveNodes(store.nodes)
                        print("✅ Nodes保存成功")
                        
                        print("💾 保存Words...")
                        try await self.saveNodes(store.nodes)
                        print("✅ Words保存成功")
                        
                        print("💾 保存Metadata...")
                        try await self.saveMetadata(store: store)
                        print("✅ Metadata保存成功")
                        
                        print("💾 保存TagMappings...")
                        try await self.saveTagMappings()
                        print("✅ TagMappings保存成功")
                        
                        continuation.resume()
                    } catch {
                        print("❌ 数据保存失败: \(error)")
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            await MainActor.run {
                lastSyncTime = Date()
                syncStatus = .success
                isSaving = false
            }
            
        } catch {
            await MainActor.run {
                syncStatus = .failed(error.localizedDescription)
                isSaving = false
            }
            throw error
        }
    }
    
    private func saveLayers(_ layers: [Layer]) async throws {
        guard let url = dataManager.getLayersURL() else {
            throw DataError.invalidPath
        }
        
        let data = try encoder.encode(layers)
        try data.write(to: url)
    }
    
    private func saveNodes(_ nodes: [Node]) async throws {
        guard let url = dataManager.getNodesURL() else {
            throw DataError.invalidPath
        }
        
        let data = try encoder.encode(nodes)
        try data.write(to: url)
    }
    
    private func saveMetadata(store: NodeStore) async throws {
        guard let url = dataManager.getMetadataURL() else {
            throw DataError.invalidPath
        }
        
        let metadata = DataMetadata(
            totalLayers: store.layers.count,
            totalNodes: store.nodes.count,
            totalTags: store.nodes.flatMap { $0.tags }.count,
            lastBackup: lastSyncTime,
            syncEnabled: true
        )
        
        let data = try encoder.encode(metadata)
        try data.write(to: url)
    }
    
    private func saveTagMappings() async throws {
        guard let url = dataManager.getTagMappingsURL() else {
            throw DataError.invalidPath
        }
        
        // 确保 tagmappings 文件夹存在
        let tagMappingsDir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: tagMappingsDir.path) {
            print("📁 创建 tagmappings 文件夹: \(tagMappingsDir.path)")
            try FileManager.default.createDirectory(at: tagMappingsDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        await MainActor.run {
            let tagMappings = TagMappingManager.shared.tagMappings
            print("💾 保存TagMappings: \(tagMappings.count) 个映射")
            for mapping in tagMappings {
                print("   - \(mapping.key) -> \(mapping.typeName)")
            }
        }
        
        let tagMappings = await MainActor.run {
            return TagMappingManager.shared.tagMappings
        }
        
        let data = try encoder.encode(tagMappings)
        try data.write(to: url)
    }
    
    // 单独保存标签映射的方法（用于实时同步）
    public func saveTagMappingsOnly() async throws {
        guard dataManager.isDataPathSelected else {
            throw DataError.noDataPathSelected
        }
        
        // 检查并确保访问权限
        guard dataManager.ensureAccess() else {
            throw DataError.accessDenied
        }
        
        try await saveTagMappings()
    }
    
    // 清理所有外部数据文件
    public func clearAllExternalData() async throws {
        guard dataManager.isDataPathSelected else {
            throw DataError.noDataPathSelected
        }
        
        // 检查并确保访问权限
        guard dataManager.ensureAccess() else {
            throw DataError.accessDenied
        }
        
        print("🗑️ ExternalDataService: 开始清理所有外部数据文件...")
        
        // 删除各个数据文件
        let filesToDelete = [
            dataManager.getLayersURL(),
            dataManager.getNodesURL(), 
            dataManager.getNodesURL(),
            dataManager.getMetadataURL(),
            dataManager.getTagMappingsURL()
        ].compactMap { $0 }
        
        for fileURL in filesToDelete {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    print("🗑️ 已删除: \(fileURL.lastPathComponent)")
                } catch {
                    print("⚠️ 删除文件失败: \(fileURL.lastPathComponent) - \(error)")
                    // 继续删除其他文件，不因单个文件失败而中断
                }
            }
        }
        
        // 清理备份文件夹
        if let basePath = dataManager.currentDataPath {
            let backupsPath = basePath.appendingPathComponent("backups")
            if FileManager.default.fileExists(atPath: backupsPath.path) {
                do {
                    try FileManager.default.removeItem(at: backupsPath)
                    print("🗑️ 已删除备份文件夹")
                } catch {
                    print("⚠️ 删除备份文件夹失败: \(error)")
                }
            }
        }
        
        print("✅ 外部数据文件清理完成")
    }
    
    // MARK: - 数据加载
    
    public func loadAllData() async throws -> (layers: [Layer], nodes: [Node]) {
        guard dataManager.isDataPathSelected else {
            throw DataError.noDataPathSelected
        }
        
        // 检查并确保访问权限
        guard dataManager.ensureAccess() else {
            throw DataError.accessDenied
        }
        
        await MainActor.run { isLoading = true }
        
        do {
            // 在后台线程执行文件I/O操作
            let (layers, nodes) = try await withCheckedThrowingContinuation { continuation in
                Task.detached {
                    do {
                        let layers = try await self.loadLayers()
                        let nodes = try await self.loadNodes()
                        
                        // 加载标签映射
                        try await self.loadTagMappings()
                        
                        continuation.resume(returning: (layers, nodes))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            await MainActor.run {
                syncStatus = .success
                isLoading = false
            }
            
            return (layers, nodes)
            
        } catch {
            await MainActor.run {
                syncStatus = .failed(error.localizedDescription)
                isLoading = false
            }
            throw error
        }
    }
    
    private func loadLayers() async throws -> [Layer] {
        guard let url = dataManager.getLayersURL() else {
            throw DataError.invalidPath
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [] // 返回空数组，稍后会创建默认层
        }
        
        let data = try Data(contentsOf: url)
        return try decoder.decode([Layer].self, from: data)
    }
    
    private func loadNodes() async throws -> [Node] {
        guard let url = dataManager.getNodesURL() else {
            throw DataError.invalidPath
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [] // 返回空数组
        }
        
        do {
            let data = try Data(contentsOf: url)
            
            // 验证JSON数据完整性
            if data.isEmpty {
                print("⚠️ 节点数据文件为空")
                return []
            }
            
            // 尝试解码JSON数据
            let nodes = try decoder.decode([Node].self, from: data)
            
            // 验证解码的节点数据
            print("📊 成功加载 \(nodes.count) 个节点")
            
            // 简单检查是否有明显损坏的数据
            let corruptedCount = nodes.filter { node in
                isCorruptedNodeData(node)
            }.count
            
            if corruptedCount > 0 {
                print("⚠️ 发现 \(corruptedCount) 个可能损坏的节点，将在加载后自动修复")
            }
            
            return nodes
            
        } catch let decodingError as DecodingError {
            print("❌ JSON解码错误: \(decodingError)")
            
            // 尝试从备份恢复
            if let backupNodes = try? await loadFromBackup() {
                print("🔄 从备份恢复了 \(backupNodes.count) 个节点")
                return backupNodes
            }
            
            throw DataError.corruptedData
        } catch {
            print("❌ 加载节点数据失败: \(error)")
            throw error
        }
    }
    
    /// 检查节点数据是否损坏
    private func isCorruptedNodeData(_ node: Node) -> Bool {
        // 检查文本字段
        if isTextFieldCorrupted(node.text) {
            return true
        }
        
        // 检查可选字段
        if let phonetic = node.phonetic, isTextFieldCorrupted(phonetic) {
            return true
        }
        
        if let meaning = node.meaning, isTextFieldCorrupted(meaning) {
            return true
        }
        
        // 检查标签值
        for tag in node.tags {
            if isTextFieldCorrupted(tag.value) {
                return true
            }
        }
        
        return false
    }
    
    /// 检查文本字段是否损坏
    private func isTextFieldCorrupted(_ text: String) -> Bool {
        // 空文本不算损坏
        if text.isEmpty {
            return false
        }
        
        // 检查是否包含明显的random字符组合（如"kdf dlf sdfj"）
        let randomWordsPattern = #"(\b[a-z]{1,4}\s){2,}[a-z]{1,4}\b"#
        if text.range(of: randomWordsPattern, options: .regularExpression) != nil {
            return true
        }
        
        return false
    }
    
    /// 从最新备份恢复数据
    private func loadFromBackup() async throws -> [Node]? {
        guard let basePath = dataManager.currentDataPath else { return nil }
        
        let backupsPath = basePath.appendingPathComponent("backups")
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: backupsPath, includingPropertiesForKeys: [.creationDateKey])
            
            let sortedFiles = files
                .filter { $0.pathExtension == "json" }
                .sorted { file1, file2 in
                    let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return date1 > date2
                }
            
            // 尝试从最新的备份恢复
            for backupFile in sortedFiles.prefix(3) { // 尝试最新的3个备份
                do {
                    print("🔄 尝试从备份恢复: \(backupFile.lastPathComponent)")
                    let data = try Data(contentsOf: backupFile)
                    let backupData = try decoder.decode(ExternalDataFormat.self, from: data)
                    
                    // 验证备份数据
                    if !backupData.nodes.isEmpty {
                        print("✅ 成功从备份恢复 \(backupData.nodes.count) 个节点")
                        return backupData.nodes
                    }
                } catch {
                    print("⚠️ 备份文件损坏: \(backupFile.lastPathComponent) - \(error)")
                    continue
                }
            }
            
        } catch {
            print("⚠️ 无法访问备份文件夹: \(error)")
        }
        
        return nil
    }
    
    
    private func loadTagMappings() async throws {
        guard let url = dataManager.getTagMappingsURL() else {
            throw DataError.invalidPath
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("🏷️ TagMappings文件不存在，使用默认值")
            return // 使用现有的默认映射
        }
        
        print("🏷️ 从外部存储加载TagMappings...")
        let data = try Data(contentsOf: url)
        let tagMappings = try decoder.decode([TagMapping].self, from: data)
        
        await MainActor.run {
            print("🏷️ 加载了 \(tagMappings.count) 个标签映射:")
            for mapping in tagMappings {
                print("   - \(mapping.key) -> \(mapping.typeName)")
            }
            
            // 直接更新TagMappingManager的数据，不触发保存到UserDefaults
            TagMappingManager.shared.tagMappings = tagMappings
        }
    }
    
    // MARK: - 备份管理
    
    private func createBackup(store: NodeStore) async throws {
        guard let backupURL = dataManager.getBackupURL(for: Date()) else {
            throw DataError.invalidPath
        }
        
        // 确保备份文件夹存在
        let backupDir = backupURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: backupDir.path) {
            print("📁 创建备份文件夹: \(backupDir.path)")
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        let config = DataConfig(
            version: "1.0",
            createdAt: Date(),
            lastModified: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        )
        
        let metadata = DataMetadata(
            totalLayers: store.layers.count,
            totalNodes: store.nodes.count,
            totalTags: store.nodes.flatMap { $0.tags }.count,
            syncEnabled: true
        )
        
        let tagMappings = await MainActor.run {
            return TagMappingManager.shared.tagMappings
        }
        
        let backupData = ExternalDataFormat(
            config: config,
            layers: store.layers,
            nodes: store.nodes,
            metadata: metadata,
            tagMappings: tagMappings
        )
        
        let data = try encoder.encode(backupData)
        try data.write(to: backupURL)
        
        // 清理旧备份（保留最近10个）
        cleanupOldBackups()
    }
    
    private func cleanupOldBackups() {
        guard let basePath = dataManager.currentDataPath else { return }
        
        let backupsPath = basePath.appendingPathComponent("backups")
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: backupsPath, includingPropertiesForKeys: [.creationDateKey])
            
            let sortedFiles = files
                .filter { $0.pathExtension == "json" }
                .sorted { file1, file2 in
                    let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return date1 > date2
                }
            
            // 保留最新的10个备份，删除其他的
            if sortedFiles.count > 10 {
                for file in sortedFiles.dropFirst(10) {
                    try FileManager.default.removeItem(at: file)
                }
            }
            
        } catch {
            print("清理备份文件失败: \(error)")
        }
    }
    
    // MARK: - 自动同步
    
    @MainActor
    public func startAutoSync(store: NodeStore) {
        // 每5分钟自动保存一次
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in
                try? await self.saveAllData(store: store)
            }
        }
    }
    
    // MARK: - 数据初始化
    
    public func initializeDataFolder() async throws {
        guard dataManager.isDataPathSelected else {
            throw DataError.noDataPathSelected
        }
        
        // 验证文件夹结构
        if !dataManager.validateDataStructure() {
            dataManager.resetDataFolder()
        }
        
        // 检查是否有现有数据
        let (layers, _) = try await loadAllData()
        
        // 如果没有数据，创建默认结构
        if layers.isEmpty {
            await createDefaultData()
        }
    }
    
    private func createDefaultData() async {
        let defaultLayers = [
            Layer(name: "english", displayName: "英语单词", color: "blue"),
            Layer(name: "statistics", displayName: "统计学", color: "green"),
            Layer(name: "psychology", displayName: "教育心理学", color: "orange")
        ]
        
        do {
            try await saveLayers(defaultLayers)
            try await saveNodes([]) // 空节点数组
            try await saveNodes([]) // 空单词数组
            
            let metadata = DataMetadata(
                totalLayers: defaultLayers.count,
                totalNodes: 0,
                totalTags: 0,
                syncEnabled: true
            )
            
            guard let url = dataManager.getMetadataURL() else { return }
            let data = try encoder.encode(metadata)
            try data.write(to: url)
            
        } catch {
            print("创建默认数据失败: \(error)")
        }
    }
}

// MARK: - 同步状态

public enum SyncStatus {
    case idle
    case syncing
    case success
    case failed(String)
    
    public var description: String {
        switch self {
        case .idle:
            return "等待同步"
        case .syncing:
            return "同步中..."
        case .success:
            return "同步成功"
        case .failed(let error):
            return "同步失败: \(error)"
        }
    }
    
    public var color: Color {
        switch self {
        case .idle:
            return .gray
        case .syncing:
            return .blue
        case .success:
            return .green
        case .failed:
            return .red
        }
    }
}

// MARK: - 数据错误

public enum DataError: LocalizedError {
    case noDataPathSelected
    case invalidPath
    case fileNotFound
    case permissionDenied
    case accessDenied
    case corruptedData
    case networkError
    
    public var errorDescription: String? {
        switch self {
        case .noDataPathSelected:
            return "未选择数据存储路径"
        case .invalidPath:
            return "无效的文件路径"
        case .fileNotFound:
            return "文件未找到"
        case .permissionDenied:
            return "没有文件访问权限"
        case .accessDenied:
            return "访问数据文件夹被拒绝，请重新选择文件夹"
        case .corruptedData:
            return "数据文件已损坏"
        case .networkError:
            return "网络连接错误"
        }
    }
}