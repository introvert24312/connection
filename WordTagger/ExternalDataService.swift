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
    
    public func saveAllData(store: WordStore) async throws {
        guard dataManager.isDataPathSelected else {
            throw DataError.noDataPathSelected
        }
        
        // 检查并确保访问权限
        guard dataManager.ensureAccess() else {
            throw DataError.accessDenied
        }
        
        await MainActor.run { isSaving = true }
        
        do {
            // 在后台线程执行文件I/O操作
            try await withCheckedThrowingContinuation { continuation in
                Task.detached {
                    do {
                        // 创建备份
                        try await self.createBackup(store: store)
                        
                        // 保存各个数据文件
                        try await self.saveLayers(store.layers)
                        try await self.saveNodes(store.nodes)
                        try await self.saveMetadata(store: store)
                        
                        continuation.resume()
                    } catch {
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
    
    private func saveMetadata(store: WordStore) async throws {
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
        
        let data = try Data(contentsOf: url)
        return try decoder.decode([Node].self, from: data)
    }
    
    // MARK: - 备份管理
    
    private func createBackup(store: WordStore) async throws {
        guard let backupURL = dataManager.getBackupURL(for: Date()) else {
            throw DataError.invalidPath
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
        
        let backupData = ExternalDataFormat(
            config: config,
            layers: store.layers,
            nodes: store.nodes,
            metadata: metadata
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
    public func startAutoSync(store: WordStore) {
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
        let (layers, nodes) = try await loadAllData()
        
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