import Foundation

/// 简单的窗口映射管理器 - 管理窗口之间的父子关系
@MainActor
class WindowMappingManager: ObservableObject {
    static let shared = WindowMappingManager()
    
    // 窗口映射关系：子窗口ID -> 源窗口ID
    private var windowMappings: [String: String] = [:]
    
    private init() {}
    
    /// 创建窗口映射关系
    /// - Parameters:
    ///   - childWindowId: 子窗口ID
    ///   - sourceWindowId: 源窗口ID
    func createMapping(childWindowId: String, sourceWindowId: String) {
        windowMappings[childWindowId] = sourceWindowId
        print("🔗 WindowMapping: 创建映射 - \(childWindowId.prefix(8)) <- \(sourceWindowId.prefix(8))")
    }
    
    /// 获取窗口的源窗口ID
    /// - Parameter windowId: 窗口ID
    /// - Returns: 源窗口ID（如果存在）
    func getSourceWindowId(for windowId: String) -> String? {
        return windowMappings[windowId]
    }
    
    /// 删除窗口映射
    /// - Parameter windowId: 要删除的窗口ID
    func removeMapping(for windowId: String) {
        windowMappings.removeValue(forKey: windowId)
        // 如果这个窗口是其他窗口的源窗口，也要清理
        windowMappings = windowMappings.filter { $0.value != windowId }
        print("🧹 WindowMapping: 清理映射 - \(windowId.prefix(8))")
    }
    
    /// 发送通知到源窗口
    /// - Parameters:
    ///   - notificationName: 通知名称
    ///   - fromWindowId: 发送方窗口ID
    ///   - userInfo: 附加信息
    func sendNotificationToSource(
        notificationName: String,
        fromWindowId: String,
        userInfo: [String: Any]? = nil
    ) {
        guard let targetWindowId = getSourceWindowId(for: fromWindowId) else {
            print("⚠️ WindowMapping: 未找到窗口 \(fromWindowId.prefix(8)) 的源窗口")
            return
        }
        
        var finalUserInfo = userInfo ?? [:]
        finalUserInfo["targetWindowId"] = targetWindowId
        finalUserInfo["fromWindowId"] = fromWindowId
        
        print("📤 WindowMapping: 发送 '\(notificationName)' 到 \(targetWindowId.prefix(8))")
        
        NotificationCenter.default.post(
            name: NSNotification.Name(notificationName),
            object: nil,
            userInfo: finalUserInfo
        )
    }
}