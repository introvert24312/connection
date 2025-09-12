import Foundation
import SwiftUI
import AppKit

// MARK: - 节点文件夹管理器

@MainActor
public class NodeFolderManager: ObservableObject {
    public static let shared = NodeFolderManager()
    
    @Published public private(set) var isInitialized = false
    @Published public private(set) var nodeFoldersPath: URL?
    
    private let externalDataManager = ExternalDataManager.shared
    private let fileManager = FileManager.default
    
    private init() {
        setupNodeFoldersDirectory()
        setupExternalDataListener()
    }
    
    // MARK: - 初始化和设置
    
    private func setupNodeFoldersDirectory() {
        guard let basePath = externalDataManager.currentDataPath else {
            isInitialized = false
            nodeFoldersPath = nil
            return
        }
        
        let nodeFolder = basePath.appendingPathComponent("NodeFolders")
        
        do {
            try fileManager.createDirectory(at: nodeFolder, withIntermediateDirectories: true)
            nodeFoldersPath = nodeFolder
            isInitialized = true
            print("📁 NodeFolders 目录已准备: \(nodeFolder.path)")
        } catch {
            print("❌ 创建 NodeFolders 目录失败: \(error)")
            isInitialized = false
            nodeFoldersPath = nil
        }
    }
    
    private func setupExternalDataListener() {
        // 监听外部数据路径变化
        NotificationCenter.default.addObserver(
            forName: .dataPathChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupNodeFoldersDirectory()
            }
        }
    }
    
    // MARK: - 文件夹路径管理
    
    /// 获取节点的文件夹路径（基于 UUID + 节点名）
    public func getFolderPath(for node: Node) -> URL? {
        guard let basePath = nodeFoldersPath else { return nil }
        let folderName = "\(node.id.uuidString.prefix(8))_\(sanitizeFolderName(node.text))"
        return basePath.appendingPathComponent(folderName)
    }
    
    /// 获取节点文件夹的显示名称
    public func getFolderDisplayName(for node: Node) -> String {
        return node.text
    }
    
    // MARK: - 文件夹操作
    
    /// 为节点创建文件夹
    public func createFolderForNode(_ node: Node) throws -> URL {
        guard externalDataManager.ensureAccess() else {
            throw NodeFolderError.noDataAccess
        }
        
        guard let folderPath = getFolderPath(for: node) else {
            throw NodeFolderError.invalidBasePath
        }
        
        // 如果文件夹已存在，直接返回
        if fileManager.fileExists(atPath: folderPath.path) {
            print("📁 节点文件夹已存在: \(folderPath.lastPathComponent)")
            return folderPath
        }
        
        try fileManager.createDirectory(at: folderPath, withIntermediateDirectories: true)
        print("📁 创建节点文件夹: \(folderPath.lastPathComponent)")
        
        // 创建一个简单的说明文件
        createReadmeFile(in: folderPath, for: node)
        
        return folderPath
    }
    
    /// 重命名节点文件夹（节点名称变化时自动调用）
    public func renameNodeFolder(from oldNode: Node, to newNode: Node) throws {
        guard externalDataManager.ensureAccess() else { 
            print("⚠️ 重命名文件夹时没有外部数据访问权限，跳过")
            return 
        }
        
        guard let basePath = nodeFoldersPath else { 
            print("⚠️ NodeFolders 基础路径不存在，跳过重命名")
            return 
        }
        
        // 基于 UUID 生成旧路径和新路径
        let oldFolderName = "\(oldNode.id.uuidString.prefix(8))_\(sanitizeFolderName(oldNode.text))"
        let newFolderName = "\(newNode.id.uuidString.prefix(8))_\(sanitizeFolderName(newNode.text))"
        
        let oldPath = basePath.appendingPathComponent(oldFolderName)
        let newPath = basePath.appendingPathComponent(newFolderName)
        
        // 只有在文件夹存在且名称确实发生变化时才重命名
        guard fileManager.fileExists(atPath: oldPath.path) else {
            print("📁 节点文件夹不存在，无需重命名: \(oldFolderName)")
            return
        }
        
        guard oldFolderName != newFolderName else {
            print("📁 节点文件夹名称未变化，无需重命名: \(oldFolderName)")
            return
        }
        
        do {
            try fileManager.moveItem(at: oldPath, to: newPath)
            print("📁 重命名节点文件夹: \(oldFolderName) → \(newFolderName)")
            
            // 更新说明文件
            updateReadmeFile(in: newPath, for: newNode, wasRenamed: true)
            
        } catch {
            print("❌ 重命名节点文件夹失败: \(error)")
            throw NodeFolderError.folderRenameFailed
        }
    }
    
    /// 在 Finder 中打开节点文件夹（Option + 点击节点时调用）
    public func openNodeFolderInFinder(_ node: Node) {
        Task { @MainActor in
            do {
                // 确保有外部数据访问权限
                guard externalDataManager.ensureAccess() else {
                    showNoAccessAlert()
                    return
                }
                
                let folderPath: URL
                if let existingPath = getFolderPath(for: node),
                   fileManager.fileExists(atPath: existingPath.path) {
                    folderPath = existingPath
                } else {
                    // 文件夹不存在，创建它
                    folderPath = try createFolderForNode(node)
                }
                
                // 在 Finder 中打开文件夹
                NSWorkspace.shared.open(folderPath)
                print("📂 在 Finder 中打开节点文件夹: \(folderPath.lastPathComponent)")
                
            } catch {
                print("❌ 打开节点文件夹失败: \(error)")
                showOpenFolderErrorAlert(for: node, error: error)
            }
        }
    }
    
    /// 检查节点是否已经有对应的文件夹
    public func hasFolder(for node: Node) -> Bool {
        guard let folderPath = getFolderPath(for: node) else { return false }
        return fileManager.fileExists(atPath: folderPath.path)
    }
    
    /// 获取节点文件夹的文件数量（不包括说明文件）
    public func getFileCount(for node: Node) -> Int {
        guard let folderPath = getFolderPath(for: node),
              fileManager.fileExists(atPath: folderPath.path) else {
            return 0
        }
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: folderPath.path)
            // 排除说明文件和隐藏文件
            return contents.filter { !$0.hasPrefix(".") && $0 != "节点说明.txt" }.count
        } catch {
            return 0
        }
    }
    
    // MARK: - 文件夹内容管理
    
    /// 创建节点说明文件
    private func createReadmeFile(in folderPath: URL, for node: Node) {
        let readmeFile = folderPath.appendingPathComponent("节点说明.txt")
        let readmeContent = generateReadmeContent(for: node, isUpdate: false)
        
        do {
            try readmeContent.write(to: readmeFile, atomically: true, encoding: .utf8)
            print("📝 创建节点说明文件: \(node.text)")
        } catch {
            print("⚠️ 创建说明文件失败: \(error)")
        }
    }
    
    /// 更新节点说明文件
    private func updateReadmeFile(in folderPath: URL, for node: Node, wasRenamed: Bool) {
        let readmeFile = folderPath.appendingPathComponent("节点说明.txt")
        let readmeContent = generateReadmeContent(for: node, isUpdate: true, wasRenamed: wasRenamed)
        
        do {
            try readmeContent.write(to: readmeFile, atomically: true, encoding: .utf8)
            print("📝 更新节点说明文件: \(node.text)")
        } catch {
            print("⚠️ 更新说明文件失败: \(error)")
        }
    }
    
    /// 生成说明文件内容
    private func generateReadmeContent(for node: Node, isUpdate: Bool, wasRenamed: Bool = false) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        let currentTime = dateFormatter.string(from: Date())
        
        var content = """
        节点文件夹: \(node.text)
        
        """
        
        if isUpdate {
            content += "最后更新: \(currentTime)\n"
            if wasRenamed {
                content += "操作: 节点重命名，文件夹同步更新\n"
            }
        } else {
            content += "创建时间: \(currentTime)\n"
        }
        
        content += """
        节点ID: \(node.id.uuidString)
        
        这个文件夹属于节点「\(node.text)」，你可以在这里存放与该节点相关的任何文件：
        
        • 文档和笔记
        • 图片和截图  
        • 代码片段
        • 参考资料
        • 其他相关文件
        
        使用说明：
        1. 通过 Option + 点击节点可以快速打开此文件夹
        2. 当节点重命名时，文件夹会自动同步重命名
        3. 文件夹内的所有内容会完整保留
        4. 删除节点不会自动删除此文件夹，需要手动清理
        
        ---
        由 WordTagger 自动生成
        """
        
        return content
    }
    
    // MARK: - 错误处理和用户提示
    
    private func showNoAccessAlert() {
        let alert = NSAlert()
        alert.messageText = "无法访问外部数据目录"
        alert.informativeText = "请在设置中重新选择外部数据目录以获取访问权限。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    private func showOpenFolderErrorAlert(for node: Node, error: Error) {
        let alert = NSAlert()
        alert.messageText = "打开节点文件夹失败"
        alert.informativeText = "无法为节点「\(node.text)」创建或打开文件夹。\n\n错误详情：\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    // MARK: - 辅助方法
    
    /// 清理文件夹名称，移除不安全的字符
    private func sanitizeFolderName(_ name: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/:\"*?<>|\\")
        return name.components(separatedBy: unsafe).joined(separator: "_")
    }
    
    // MARK: - 节点文件夹子目录管理
    
    /// 获取节点文件夹中的Images子目录路径
    public func getImagesPath(for node: Node) -> URL? {
        guard let nodeFolderPath = getFolderPath(for: node) else { return nil }
        return nodeFolderPath.appendingPathComponent("Images")
    }
    
    /// 获取节点文件夹中的Markdown子目录路径  
    public func getMarkdownPath(for node: Node) -> URL? {
        guard let nodeFolderPath = getFolderPath(for: node) else { return nil }
        return nodeFolderPath.appendingPathComponent("Markdown")
    }
    
    /// 创建节点文件夹的子目录结构（包括Images和Markdown文件夹）
    public func createNodeSubdirectories(for node: Node) throws {
        // 确保节点主文件夹存在
        let _ = try createFolderForNode(node)
        
        // 创建Images子目录
        if let imagesPath = getImagesPath(for: node) {
            try fileManager.createDirectory(at: imagesPath, withIntermediateDirectories: true)
            print("📁 创建节点Images子目录: \(imagesPath.lastPathComponent)")
        }
        
        // 创建Markdown子目录
        if let markdownPath = getMarkdownPath(for: node) {
            try fileManager.createDirectory(at: markdownPath, withIntermediateDirectories: true)
            print("📁 创建节点Markdown子目录: \(markdownPath.lastPathComponent)")
        }
    }
    
    /// 在节点文件夹中保存图片文件
    public func saveImageToNodeFolder(_ node: Node, fileName: String, data: Data) throws -> String {
        // 确保节点文件夹和Images子目录存在
        try createNodeSubdirectories(for: node)
        
        guard let imagesPath = getImagesPath(for: node) else {
            throw NodeFolderError.invalidBasePath
        }
        
        let imageFile = imagesPath.appendingPathComponent(fileName)
        try data.write(to: imageFile)
        print("🖼️ 图片已保存到节点文件夹: \(imageFile.path)")
        
        // 返回节点相对路径格式，便于markdown引用
        return "Images/\(fileName)"
    }
    
    /// 在节点文件夹中保存markdown文件
    public func saveMarkdownToNodeFolder(_ node: Node, content: String) throws -> URL {
        // 确保节点文件夹和Markdown子目录存在
        try createNodeSubdirectories(for: node)
        
        guard let markdownPath = getMarkdownPath(for: node) else {
            throw NodeFolderError.invalidBasePath
        }
        
        let fileName = "\(sanitizeFolderName(node.text)).md"
        let markdownFile = markdownPath.appendingPathComponent(fileName)
        
        try content.write(to: markdownFile, atomically: true, encoding: .utf8)
        print("📝 Markdown文件已保存到节点文件夹: \(markdownFile.path)")
        
        return markdownFile
    }
    
    /// 从节点文件夹中读取markdown文件
    public func loadMarkdownFromNodeFolder(_ node: Node) -> String? {
        guard let markdownPath = getMarkdownPath(for: node) else { return nil }
        
        let fileName = "\(sanitizeFolderName(node.text)).md"
        let markdownFile = markdownPath.appendingPathComponent(fileName)
        
        do {
            let content = try String(contentsOf: markdownFile, encoding: .utf8)
            print("📖 从节点文件夹加载Markdown: \(markdownFile.path)")
            return content
        } catch {
            print("⚠️ 从节点文件夹加载Markdown失败: \(error)")
            return nil
        }
    }
    
    /// 检查节点是否有markdown文件  
    public func hasMarkdownFile(for node: Node) -> Bool {
        guard let markdownPath = getMarkdownPath(for: node) else { return false }
        
        let fileName = "\(sanitizeFolderName(node.text)).md"
        let markdownFile = markdownPath.appendingPathComponent(fileName)
        
        return fileManager.fileExists(atPath: markdownFile.path)
    }
    
    // MARK: - 高级功能
    
    /// 删除节点对应的文件夹（可选功能）
    public func deleteFolder(for node: Node, moveToTrash: Bool = true) throws {
        guard let folderPath = getFolderPath(for: node),
              fileManager.fileExists(atPath: folderPath.path) else {
            print("📁 节点文件夹不存在，无需删除: \(node.text)")
            return
        }
        
        if moveToTrash {
            try fileManager.trashItem(at: folderPath, resultingItemURL: nil)
            print("🗑️ 节点文件夹已移至废纸篓: \(folderPath.lastPathComponent)")
        } else {
            try fileManager.removeItem(at: folderPath)
            print("🗑️ 节点文件夹已彻底删除: \(folderPath.lastPathComponent)")
        }
    }
    
    /// 获取所有节点文件夹的概览信息
    public func getFoldersOverview() -> [NodeFolderInfo] {
        guard let basePath = nodeFoldersPath,
              fileManager.fileExists(atPath: basePath.path) else {
            return []
        }
        
        do {
            let folderNames = try fileManager.contentsOfDirectory(atPath: basePath.path)
            return folderNames.compactMap { folderName in
                let folderURL = basePath.appendingPathComponent(folderName)
                
                // 解析文件夹名获取 UUID 前缀
                let components = folderName.components(separatedBy: "_")
                guard let uuidPrefix = components.first, components.count > 1 else {
                    return nil
                }
                
                let displayName = components.dropFirst().joined(separator: "_")
                
                do {
                    let contents = try fileManager.contentsOfDirectory(atPath: folderURL.path)
                    let fileCount = contents.filter { !$0.hasPrefix(".") && $0 != "节点说明.txt" }.count
                    let attributes = try fileManager.attributesOfItem(atPath: folderURL.path)
                    let creationDate = attributes[.creationDate] as? Date
                    
                    return NodeFolderInfo(
                        uuidPrefix: uuidPrefix,
                        displayName: displayName,
                        path: folderURL,
                        fileCount: fileCount,
                        createdAt: creationDate ?? Date()
                    )
                } catch {
                    return nil
                }
            }.sorted { $0.createdAt > $1.createdAt } // 按创建时间倒序
        } catch {
            print("❌ 获取文件夹概览失败: \(error)")
            return []
        }
    }
    
    /// 获取 NodeFolders 目录的总体统计信息
    public func getFoldersStatistics() -> NodeFoldersStatistics? {
        guard let basePath = nodeFoldersPath,
              fileManager.fileExists(atPath: basePath.path) else {
            return nil
        }
        
        do {
            let folderNames = try fileManager.contentsOfDirectory(atPath: basePath.path)
            var totalFiles = 0
            var totalSize: Int64 = 0
            
            for folderName in folderNames {
                let folderURL = basePath.appendingPathComponent(folderName)
                
                // 计算文件数和大小
                let contents = try fileManager.contentsOfDirectory(atPath: folderURL.path)
                let validFiles = contents.filter { !$0.hasPrefix(".") && $0 != "节点说明.txt" }
                totalFiles += validFiles.count
                
                // 计算文件夹大小
                let attributes = try fileManager.attributesOfItem(atPath: folderURL.path)
                if let size = attributes[.size] as? Int64 {
                    totalSize += size
                }
            }
            
            return NodeFoldersStatistics(
                totalFolders: folderNames.count,
                totalFiles: totalFiles,
                totalSize: totalSize,
                basePath: basePath
            )
            
        } catch {
            print("❌ 获取文件夹统计信息失败: \(error)")
            return nil
        }
    }
}

// MARK: - 错误定义

enum NodeFolderError: LocalizedError {
    case invalidBasePath
    case noDataAccess
    case folderCreationFailed
    case folderRenameFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidBasePath:
            return "无效的基础路径"
        case .noDataAccess:
            return "没有外部数据访问权限"
        case .folderCreationFailed:
            return "创建文件夹失败"
        case .folderRenameFailed:
            return "重命名文件夹失败"
        }
    }
}

// MARK: - 辅助模型

public struct NodeFolderInfo: Identifiable {
    public let id = UUID()
    public let uuidPrefix: String
    public let displayName: String
    public let path: URL
    public let fileCount: Int
    public let createdAt: Date
    
    public init(uuidPrefix: String, displayName: String, path: URL, fileCount: Int, createdAt: Date) {
        self.uuidPrefix = uuidPrefix
        self.displayName = displayName
        self.path = path
        self.fileCount = fileCount
        self.createdAt = createdAt
    }
}

public struct NodeFoldersStatistics {
    public let totalFolders: Int
    public let totalFiles: Int
    public let totalSize: Int64
    public let basePath: URL
    
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }
    
    public init(totalFolders: Int, totalFiles: Int, totalSize: Int64, basePath: URL) {
        self.totalFolders = totalFolders
        self.totalFiles = totalFiles
        self.totalSize = totalSize
        self.basePath = basePath
    }
}

// MARK: - Node 模型扩展
// 注意：由于NodeFolderManager使用@MainActor，Node的扩展属性被移除以避免并发问题
// 如需访问节点文件夹信息，请直接使用：NodeFolderManager.shared.method(for: node)