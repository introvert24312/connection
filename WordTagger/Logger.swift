import Foundation

/// 应用日志系统 - 可根据构建配置控制日志输出
public struct Logger {
    
    // MARK: - Configuration
    
    /// 是否启用日志输出 - 根据构建配置自动设置
    private static let isLoggingEnabled: Bool = {
        #if DEBUG
        return true  // Debug模式下启用日志
        #else
        return false // Release模式下禁用日志
        #endif
    }()
    
    // MARK: - Logging Methods
    
    /// 通用日志方法
    /// - Parameters:
    ///   - message: 日志消息
    ///   - category: 日志类别
    ///   - file: 文件名
    ///   - function: 函数名
    ///   - line: 行号
    public static func log(
        _ message: String,
        category: LogCategory = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard isLoggingEnabled else { return }
        
        let fileName = (file as NSString).lastPathComponent
        let timestamp = DateFormatter.logTimestamp.string(from: Date())
        print("[\(timestamp)] \(category.emoji) \(category.rawValue): \(message) (\(fileName):\(line))")
    }
    
    /// 搜索相关日志
    public static func search(_ message: String, file: String = #file, line: Int = #line) {
        log(message, category: .search, file: file, line: line)
    }
    
    /// 层管理相关日志
    public static func layer(_ message: String, file: String = #file, line: Int = #line) {
        log(message, category: .layer, file: file, line: line)
    }
    
    /// 窗口管理相关日志
    public static func window(_ message: String, file: String = #file, line: Int = #line) {
        log(message, category: .window, file: file, line: line)
    }
    
    /// 图谱相关日志
    public static func graph(_ message: String, file: String = #file, line: Int = #line) {
        log(message, category: .graph, file: file, line: line)
    }
    
    /// 键盘事件相关日志
    public static func keyboard(_ message: String, file: String = #file, line: Int = #line) {
        log(message, category: .keyboard, file: file, line: line)
    }
    
    /// 错误日志
    public static func error(_ message: String, file: String = #file, line: Int = #line) {
        log(message, category: .error, file: file, line: line)
    }
    
    /// 警告日志
    public static func warning(_ message: String, file: String = #file, line: Int = #line) {
        log(message, category: .warning, file: file, line: line)
    }
    
    /// 成功操作日志
    public static func success(_ message: String, file: String = #file, line: Int = #line) {
        log(message, category: .success, file: file, line: line)
    }
    
    /// 调试日志
    public static func debug(_ message: String, file: String = #file, line: Int = #line) {
        log(message, category: .debug, file: file, line: line)
    }
}

// MARK: - Log Categories

public enum LogCategory: String, CaseIterable {
    case general = "General"
    case search = "Search"
    case layer = "Layer"
    case window = "Window" 
    case graph = "Graph"
    case keyboard = "Keyboard"
    case error = "Error"
    case warning = "Warning"
    case success = "Success"
    case debug = "Debug"
    
    var emoji: String {
        switch self {
        case .general: return "ℹ️"
        case .search: return "🔍"
        case .layer: return "📁"
        case .window: return "🪟"
        case .graph: return "🌐"
        case .keyboard: return "⌨️"
        case .error: return "❌"
        case .warning: return "⚠️"
        case .success: return "✅"
        case .debug: return "🐛"
        }
    }
}

// MARK: - Extensions

private extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Legacy Support

/// 临时兼容方法 - 用于替换现有的print语句
/// 使用时可以简单地将 print("xxx") 替换为 Logger.print("xxx")
public extension Logger {
    static func print(_ message: String) {
        log(message, category: .debug)
    }
}