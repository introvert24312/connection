import Foundation
import SwiftUI

// MARK: - 外部数据管理器

public class ExternalDataManager: ObservableObject {
    @Published public var currentDataPath: URL?
    @Published public var isDataPathSelected: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var lastError: String?
    
    private let fileManager = FileManager.default
    private let userDefaults = UserDefaults.standard
    private let dataPathKey = "WordTagger_ExternalDataPath"
    private let bookmarkKey = "WordTagger_DataPathBookmark"
    
    public static let shared = ExternalDataManager()
    
    private init() {
        loadSavedDataPath()
    }
    
    // MARK: - 数据路径管理
    
    public func selectDataFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择数据存储文件夹"
        panel.message = "建议选择：Documents、Desktop 或自建文件夹\n避免选择：Downloads、临时文件夹"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        
        // 建议用户从Documents文件夹开始选择
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            panel.directoryURL = documentsURL
        }
        
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.setDataPath(url, createBookmark: true)
            }
        }
    }
    
    public func setDataPath(_ url: URL, createBookmark: Bool = false) {
        do {
            // 如果需要创建bookmark，先获取访问权限
            var shouldStopAccessing = false
            if createBookmark {
                shouldStopAccessing = url.startAccessingSecurityScopedResource()
            }
            
            // 创建Security-Scoped Bookmark
            if createBookmark {
                let bookmarkData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                userDefaults.set(bookmarkData, forKey: bookmarkKey)
            }
            
            currentDataPath = url
            isDataPathSelected = true
            
            // 保存路径到UserDefaults（作为备用）
            userDefaults.set(url.path, forKey: dataPathKey)
            
            // 确保文件夹存在
            createDataStructure(at: url)
            
            // 释放安全范围资源
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
            
            lastError = nil
            
        } catch {
            lastError = "设置数据路径失败: \(error.localizedDescription)"
            print("⚠️ 设置数据路径失败: \(error)")
        }
    }
    
    private func loadSavedDataPath() {
        // 首先尝试使用Security-Scoped Bookmark
        if let bookmarkData = userDefaults.data(forKey: bookmarkKey) {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                if !isStale && fileManager.fileExists(atPath: url.path) {
                    currentDataPath = url
                    isDataPathSelected = true
                    return
                } else if isStale {
                    // Bookmark已过期，清除它
                    userDefaults.removeObject(forKey: bookmarkKey)
                }
            } catch {
                print("⚠️ 加载bookmark失败: \(error)")
                userDefaults.removeObject(forKey: bookmarkKey)
            }
        }
        
        // 如果bookmark不可用，尝试使用保存的路径（仅用于显示，可能没有访问权限）
        if let savedPath = userDefaults.string(forKey: dataPathKey) {
            let url = URL(fileURLWithPath: savedPath)
            if fileManager.fileExists(atPath: url.path) {
                currentDataPath = url
                isDataPathSelected = true
                lastError = "需要重新选择数据文件夹以获取访问权限"
            } else {
                // 路径不存在，清除保存的设置
                userDefaults.removeObject(forKey: dataPathKey)
            }
        }
    }
    
    // MARK: - 数据结构创建
    
    private func createDataStructure(at baseURL: URL) {
        do {
            // 创建主数据文件夹结构
            let structurePaths = [
                baseURL.appendingPathComponent("data"),
                baseURL.appendingPathComponent("data/layers"),
                baseURL.appendingPathComponent("data/nodes"),
                baseURL.appendingPathComponent("data/tags"),
                baseURL.appendingPathComponent("data/metadata"),
                baseURL.appendingPathComponent("backups")
            ]
            
            for path in structurePaths {
                try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
            }
            
            // 创建配置文件
            createConfigFile(at: baseURL)
            
        } catch {
            lastError = "创建数据结构失败: \(error.localizedDescription)"
        }
    }
    
    private func createConfigFile(at baseURL: URL) {
        let configURL = baseURL.appendingPathComponent("wordtagger-config.json")
        
        if !fileManager.fileExists(atPath: configURL.path) {
            let config = DataConfig(
                version: "1.0",
                createdAt: Date(),
                lastModified: Date(),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            )
            
            do {
                let data = try JSONEncoder().encode(config)
                try data.write(to: configURL)
            } catch {
                lastError = "创建配置文件失败: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - 数据文件路径
    
    public func getLayersURL() -> URL? {
        guard let basePath = currentDataPath else { return nil }
        return basePath.appendingPathComponent("data/layers/layers.json")
    }
    
    public func getNodesURL() -> URL? {
        guard let basePath = currentDataPath else { return nil }
        return basePath.appendingPathComponent("data/nodes/nodes.json")
    }
    
    public func getMetadataURL() -> URL? {
        guard let basePath = currentDataPath else { return nil }
        return basePath.appendingPathComponent("data/metadata/metadata.json")
    }
    
    public func getBackupURL(for date: Date) -> URL? {
        guard let basePath = currentDataPath else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = formatter.string(from: date)
        return basePath.appendingPathComponent("backups/backup_\(dateString).json")
    }
    
    // MARK: - 数据验证
    
    public func validateDataStructure() -> Bool {
        guard let basePath = currentDataPath else { return false }
        
        let requiredPaths = [
            "data",
            "data/layers",
            "data/nodes", 
            "data/metadata",
            "backups",
            "wordtagger-config.json"
        ]
        
        for path in requiredPaths {
            let fullPath = basePath.appendingPathComponent(path)
            if !fileManager.fileExists(atPath: fullPath.path) {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - 权限管理
    
    public func ensureAccess() -> Bool {
        guard let url = currentDataPath else { return false }
        
        // 首先尝试使用Security-Scoped Bookmark
        if let bookmarkData = userDefaults.data(forKey: bookmarkKey) {
            do {
                var isStale = false
                let bookmarkURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                if !isStale && bookmarkURL.startAccessingSecurityScopedResource() {
                    // 测试访问权限
                    let testResult = testWritePermission(at: bookmarkURL)
                    if testResult {
                        currentDataPath = bookmarkURL
                        return true
                    } else {
                        bookmarkURL.stopAccessingSecurityScopedResource()
                    }
                }
            } catch {
                print("⚠️ 使用bookmark失败: \(error)")
            }
        }
        
        // 如果bookmark不可用，测试当前路径
        if testWritePermission(at: url) {
            return true
        }
        
        // 没有权限，需要重新选择
        lastError = "没有文件夹访问权限，请重新选择数据文件夹"
        return false
    }
    
    private func testWritePermission(at url: URL) -> Bool {
        let testFile = url.appendingPathComponent(".wordtagger_test")
        do {
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try fileManager.removeItem(at: testFile)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - 清理和重置
    
    public func clearDataPath() {
        currentDataPath = nil
        isDataPathSelected = false
        userDefaults.removeObject(forKey: dataPathKey)
        userDefaults.removeObject(forKey: bookmarkKey)
        lastError = nil
    }
    
    public func resetDataFolder() {
        guard let basePath = currentDataPath else { return }
        
        do {
            // 删除现有数据
            let dataPath = basePath.appendingPathComponent("data")
            if fileManager.fileExists(atPath: dataPath.path) {
                try fileManager.removeItem(at: dataPath)
            }
            
            // 重新创建结构
            createDataStructure(at: basePath)
            
        } catch {
            lastError = "重置数据文件夹失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - 数据配置模型

public struct DataConfig: Codable {
    let version: String
    let createdAt: Date
    var lastModified: Date
    let appVersion: String
    
    public init(version: String, createdAt: Date, lastModified: Date, appVersion: String) {
        self.version = version
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.appVersion = appVersion
    }
}

// MARK: - 外部数据存储模型

public struct ExternalDataFormat: Codable {
    let config: DataConfig
    let layers: [Layer]
    let nodes: [Node]
    let metadata: DataMetadata
    
    public init(config: DataConfig, layers: [Layer], nodes: [Node], metadata: DataMetadata) {
        self.config = config
        self.layers = layers
        self.nodes = nodes
        self.metadata = metadata
    }
}

public struct DataMetadata: Codable {
    let totalLayers: Int
    let totalNodes: Int
    let totalTags: Int
    let lastBackup: Date?
    let syncEnabled: Bool
    
    public init(totalLayers: Int, totalNodes: Int, totalTags: Int, lastBackup: Date? = nil, syncEnabled: Bool = false) {
        self.totalLayers = totalLayers
        self.totalNodes = totalNodes
        self.totalTags = totalTags
        self.lastBackup = lastBackup
        self.syncEnabled = syncEnabled
    }
}