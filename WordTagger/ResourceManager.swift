import Foundation

class ResourceManager {
    
    /// 获取Bundle中Resources目录的路径
    static func getResourcesPath() -> String? {
        return Bundle.main.path(forResource: "Resources", ofType: nil)
    }
    
    /// 获取vditor目录的路径
    static func getVditorPath() -> String? {
        guard let resourcesPath = getResourcesPath() else { return nil }
        return (resourcesPath as NSString).appendingPathComponent("vditor")
    }
    
    /// 获取mermaid目录的路径
    static func getMermaidPath() -> String? {
        guard let resourcesPath = getResourcesPath() else { return nil }
        return (resourcesPath as NSString).appendingPathComponent("mermaid")
    }
    
    /// 获取vditor的CSS文件路径
    static func getVditorCSSPath() -> String? {
        guard let vditorPath = getVditorPath() else { return nil }
        return (vditorPath as NSString).appendingPathComponent("index.css")
    }
    
    /// 获取vditor的JS文件路径
    static func getVditorJSPath() -> String? {
        guard let vditorPath = getVditorPath() else { return nil }
        return (vditorPath as NSString).appendingPathComponent("index.min.js")
    }
    
    /// 获取mermaid的JS文件路径
    static func getMermaidJSPath() -> String? {
        guard let mermaidPath = getMermaidPath() else { return nil }
        return (mermaidPath as NSString).appendingPathComponent("mermaid.min.js")
    }
    
    /// 验证所有资源文件是否存在
    static func verifyAllResourcesExist() -> (success: Bool, missingFiles: [String]) {
        let fileChecks = [
            ("vditor CSS", getVditorCSSPath()),
            ("vditor JS", getVditorJSPath()),
            ("mermaid JS", getMermaidJSPath())
        ]
        
        var missingFiles: [String] = []
        
        for (name, path) in fileChecks {
            guard let filePath = path else {
                missingFiles.append("\(name) - path not found")
                continue
            }
            
            if !FileManager.default.fileExists(atPath: filePath) {
                missingFiles.append("\(name) - file does not exist at: \(filePath)")
            }
        }
        
        return (success: missingFiles.isEmpty, missingFiles: missingFiles)
    }
    
    /// 读取资源文件内容（用于验证文件可读性）
    static func readResourceContent(path: String?) -> String? {
        guard let path = path else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
}