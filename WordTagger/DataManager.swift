import Foundation
import AppKit

// MARK: - 数据导入导出模型

struct WordTaggerData: Codable {
    let version: String
    let exportDate: Date
    let words: [Word]
    let metadata: ExportMetadata
    
    struct ExportMetadata: Codable {
        let totalWords: Int
        let totalTags: Int
        let uniqueTags: Int
        let appVersion: String
        
        init(words: [Word]) {
            self.totalWords = words.count
            self.totalTags = words.flatMap { $0.tags }.count
            self.uniqueTags = Set(words.flatMap { $0.tags }).count
            self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        }
    }
    
    init(words: [Word]) {
        self.version = "1.0"
        self.exportDate = Date()
        self.words = words
        self.metadata = ExportMetadata(words: words)
    }
}

// MARK: - 数据管理器

class DataManager: ObservableObject {
    static let shared = DataManager()
    
    private init() {}
    
    // MARK: - 导出功能
    
    func exportData(words: [Word], completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = WordTaggerData(words: words)
                let jsonData = try JSONEncoder().encode(data)
                
                // 创建临时文件
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let dateString = dateFormatter.string(from: Date())
                let fileName = "WordTagger_Export_\(dateString).json"
                
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try jsonData.write(to: tempURL)
                
                DispatchQueue.main.async {
                    completion(.success(tempURL))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func showSavePanel(for tempURL: URL, completion: @escaping (Bool) -> Void) {
        let savePanel = NSSavePanel()
        savePanel.title = "导出单词数据"
        savePanel.message = "选择保存位置"
        savePanel.nameFieldStringValue = tempURL.lastPathComponent
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    // 如果目标文件已存在，删除它
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    
                    // 移动临时文件到目标位置
                    try FileManager.default.moveItem(at: tempURL, to: url)
                    completion(true)
                } catch {
                    print("保存文件失败: \(error)")
                    completion(false)
                }
            } else {
                // 清理临时文件
                try? FileManager.default.removeItem(at: tempURL)
                completion(false)
            }
        }
    }
    
    // MARK: - 导入功能
    
    func showOpenPanel(completion: @escaping (Result<[Word], Error>) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.title = "导入单词数据"
        openPanel.message = "选择要导入的JSON文件"
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                self.importData(from: url, completion: completion)
            } else {
                completion(.failure(DataError.userCancelled))
            }
        }
    }
    
    private func importData(from url: URL, completion: @escaping (Result<[Word], Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let jsonData = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                
                // 尝试解析为完整的WordTaggerData格式
                if let wordTaggerData = try? decoder.decode(WordTaggerData.self, from: jsonData) {
                    DispatchQueue.main.async {
                        completion(.success(wordTaggerData.words))
                    }
                    return
                }
                
                // 尝试直接解析为Word数组（向后兼容）
                if let words = try? decoder.decode([Word].self, from: jsonData) {
                    DispatchQueue.main.async {
                        completion(.success(words))
                    }
                    return
                }
                
                // 如果都失败了，抛出解析错误
                throw DataError.invalidFormat
                
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - 数据验证和处理
    
    func validateImportedData(_ words: [Word]) -> ImportValidationResult {
        var warnings: [String] = []
        var validWords: [Word] = []
        var duplicateCount = 0
        
        for word in words {
            // 检查必要字段
            if word.text.isEmpty {
                warnings.append("发现空单词文本，已跳过")
                continue
            }
            
            // 检查重复
            if validWords.contains(where: { $0.text.lowercased() == word.text.lowercased() }) {
                duplicateCount += 1
                continue
            }
            
            validWords.append(word)
        }
        
        if duplicateCount > 0 {
            warnings.append("跳过了 \(duplicateCount) 个重复单词")
        }
        
        return ImportValidationResult(
            validWords: validWords,
            warnings: warnings,
            originalCount: words.count,
            validCount: validWords.count
        )
    }
    
    // MARK: - 统计信息
    
    func generateExportSummary(words: [Word]) -> ExportSummary {
        let totalTags = words.flatMap { $0.tags }.count
        let uniqueTags = Set(words.flatMap { $0.tags }).count
        let tagTypes = Dictionary(grouping: words.flatMap { $0.tags }) { $0.type }
        
        var tagTypeCounts: [Tag.TagType: Int] = [:]
        for type in Tag.TagType.allCases {
            tagTypeCounts[type] = tagTypes[type]?.count ?? 0
        }
        
        return ExportSummary(
            totalWords: words.count,
            totalTags: totalTags,
            uniqueTags: uniqueTags,
            tagTypeCounts: tagTypeCounts,
            wordsWithLocation: words.filter { !$0.locationTags.isEmpty }.count
        )
    }
}

// MARK: - 辅助模型

struct ImportValidationResult {
    let validWords: [Word]
    let warnings: [String]
    let originalCount: Int
    let validCount: Int
    
    var hasWarnings: Bool {
        return !warnings.isEmpty
    }
    
    var isValid: Bool {
        return validCount > 0
    }
}

struct ExportSummary {
    let totalWords: Int
    let totalTags: Int
    let uniqueTags: Int
    let tagTypeCounts: [Tag.TagType: Int]
    let wordsWithLocation: Int
}

enum DataError: LocalizedError {
    case userCancelled
    case invalidFormat
    case fileNotFound
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "用户取消了操作"
        case .invalidFormat:
            return "文件格式无效，请确保这是一个有效的WordTagger数据文件"
        case .fileNotFound:
            return "找不到指定的文件"
        case .permissionDenied:
            return "没有权限访问该文件"
        }
    }
}