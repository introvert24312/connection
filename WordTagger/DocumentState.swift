import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - 文档状态管理
class DocumentState: ObservableObject {
    @Published var currentFileURL: URL?
    @Published var isModified: Bool = false
    @Published var content: String = ""
    @Published var lastSavedContent: String = ""
    
    // 自动保存
    private var autoSaveTimer: Timer?
    private let autoSaveInterval: TimeInterval = 30 // 30秒自动保存
    
    init() {
        startAutoSave()
    }
    
    deinit {
        autoSaveTimer?.invalidate()
    }
    
    // MARK: - 文件操作
    
    /// 新建文档
    func newDocument() {
        currentFileURL = nil
        content = ""
        lastSavedContent = ""
        isModified = false
    }
    
    /// 打开文档
    func openDocument() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType.plainText, UTType(filenameExtension: "md")!]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            loadDocument(from: url)
        }
    }
    
    /// 从URL加载文档
    func loadDocument(from url: URL) {
        do {
            let fileContent = try String(contentsOf: url, encoding: .utf8)
            currentFileURL = url
            content = fileContent
            lastSavedContent = fileContent
            isModified = false
        } catch {
            print("❌ 打开文件失败: \(error)")
            // TODO: 显示错误提示
        }
    }
    
    /// 保存文档
    func saveDocument() {
        if let url = currentFileURL {
            saveDocument(to: url)
        } else {
            saveDocumentAs()
        }
    }
    
    /// 另存为
    func saveDocumentAs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType(filenameExtension: "md")!]
        savePanel.nameFieldStringValue = "未命名.md"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            saveDocument(to: url)
            currentFileURL = url
        }
    }
    
    /// 保存到指定URL
    private func saveDocument(to url: URL) {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            lastSavedContent = content
            isModified = false
            currentFileURL = url
            print("✅ 文件已保存: \(url.lastPathComponent)")
        } catch {
            print("❌ 保存文件失败: \(error)")
            // TODO: 显示错误提示
        }
    }
    
    // MARK: - 内容更新
    
    /// 更新内容
    func updateContent(_ newContent: String) {
        content = newContent
        isModified = (newContent != lastSavedContent)
    }
    
    // MARK: - 自动保存
    
    private func startAutoSave() {
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: autoSaveInterval, repeats: true) { [weak self] _ in
            self?.autoSave()
        }
    }
    
    private func autoSave() {
        guard isModified, let url = currentFileURL else { return }
        
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            lastSavedContent = content
            isModified = false
            print("🔄 自动保存: \(url.lastPathComponent)")
        } catch {
            print("❌ 自动保存失败: \(error)")
        }
    }
    
    // MARK: - 窗口关闭处理
    
    /// 检查是否需要保存
    func checkForUnsavedChanges() -> Bool {
        guard isModified else { return true } // 没有修改，可以关闭
        
        let alert = NSAlert()
        alert.messageText = "未保存的更改"
        alert.informativeText = "文档已修改但未保存，是否保存更改？"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn: // 保存
            saveDocument()
            return !isModified // 如果保存成功（!isModified），则可以关闭
        case .alertSecondButtonReturn: // 不保存
            return true
        default: // 取消
            return false
        }
    }
    
    // MARK: - 工具方法
    
    var documentTitle: String {
        if let url = currentFileURL {
            let filename = url.deletingPathExtension().lastPathComponent
            return isModified ? "\(filename) •" : filename
        } else {
            return isModified ? "未命名 •" : "未命名"
        }
    }
    
    var hasFile: Bool {
        return currentFileURL != nil
    }
}

// MARK: - 图片资源管理
extension DocumentState {
    
    /// 获取文档的资源目录
    private var resourcesDirectory: URL? {
        guard let fileURL = currentFileURL else { return nil }
        let resourcesDirName = fileURL.deletingPathExtension().lastPathComponent + "_files"
        return fileURL.deletingLastPathComponent().appendingPathComponent(resourcesDirName)
    }
    
    /// 处理拖拽/粘贴的图片
    func handleImageDrop(imageData: Data, filename: String) -> String? {
        guard let resourcesDir = resourcesDirectory else {
            print("❌ 无法获取资源目录，请先保存文档")
            return nil
        }
        
        // 创建资源目录
        do {
            try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
        } catch {
            print("❌ 创建资源目录失败: \(error)")
            return nil
        }
        
        // 生成唯一文件名
        let fileExtension = URL(fileURLWithPath: filename).pathExtension
        let baseName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let timestamp = Int(Date().timeIntervalSince1970)
        let uniqueFilename = "\(baseName)_\(timestamp).\(fileExtension)"
        
        let imageURL = resourcesDir.appendingPathComponent(uniqueFilename)
        
        // 保存图片
        do {
            try imageData.write(to: imageURL)
            
            // 返回相对路径
            let relativePath = resourcesDir.lastPathComponent + "/" + uniqueFilename
            return relativePath
        } catch {
            print("❌ 保存图片失败: \(error)")
            return nil
        }
    }
}