import Foundation
import SwiftUI
import AppKit

/// 专门管理多窗口环境下的焦点状态和快捷键分发
@MainActor
class WindowFocusManager: ObservableObject {
    // MARK: - Singleton
    static let shared = WindowFocusManager()
    
    // MARK: - Published Properties
    @Published private(set) var activeWindowInfo: WindowInfo?
    @Published private(set) var windowRegistry: [UUID: WindowInfo] = [:]
    @Published private(set) var keyboardEventManager: KeyboardEventManager?
    
    // MARK: - Private Properties
    private var windowObservers: [NSObjectProtocol] = []
    private let windowQueue = DispatchQueue(label: "com.wordtagger.window-focus", qos: .userInteractive)
    
    // NSWindow到UUID的映射，用于准确跟踪窗口
    private var windowToUUIDMap: [NSWindow: UUID] = [:]
    private var uuidToWindowMap: [UUID: WeakWindowReference] = [:]
    
    // 窗口映射系统 - 记录子窗口与源窗口的关系
    private var windowMappings: [String: String] = [:] // childWindowId -> sourceWindowId
    
    // 层图谱窗口管理 - 记录每个主窗口的层图谱窗口
    private var layerGraphWindows: [String: String] = [:] // mainWindowId -> layerGraphWindowId
    
    // 窗口激活历史 - 用于确定源窗口
    private var windowActivationHistory: [String] = [] // 按时间顺序记录窗口激活
    private let maxHistorySize = 10
    
    // 防止重复执行全局命令的冷却机制
    private var lastGlobalCommandTime: [String: Date] = [:]
    private let globalCommandCooldown: TimeInterval = 0.3 // 300ms冷却时间，防止多窗口重复执行
    
    // MARK: - Initialization
    private init() {
        setupWindowObservers()
        setupKeyboardEventManagerIntegration()
        
        // 设置定期清理任务
        startPeriodicCleanup()
    }
    
    deinit {
        // Clean up observers synchronously
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Window Registration
    
    /// 注册窗口到焦点管理系统
    /// - Parameters:
    ///   - windowId: 窗口唯一标识符
    ///   - windowType: 窗口类型
    ///   - displayName: 窗口显示名称
    func registerWindow(_ windowId: UUID, type: WindowType, displayName: String? = nil) {
        let info = WindowInfo(
            id: windowId.uuidString,
            displayName: displayName ?? type.displayName,
            type: type
        )
        
        windowRegistry[windowId] = info
        
        // 同时注册到KeyboardEventManager
        keyboardEventManager?.registerWindow(windowId, type: type)
        
        print("🏠 WindowFocusManager: 注册窗口 - \(info.displayName) (\(windowId.uuidString.prefix(8)))")
        
        // 延迟关联窗口，确保NSWindow完全初始化
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.attemptWindowAssociation(windowId: windowId)
        }
        
        // 添加额外的延迟重试机制
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.retryWindowAssociationIfNeeded(windowId: windowId)
        }
    }
    
    /// 注销窗口
    /// - Parameter windowId: 窗口标识符
    func unregisterWindow(_ windowId: UUID) {
        if let info = windowRegistry.removeValue(forKey: windowId) {
            print("🏠 WindowFocusManager: 注销窗口 - \(info.displayName) (\(windowId.uuidString.prefix(8)))")
        }
        
        // 🔧 增强的清理逻辑：确保完全清除映射关系
        var windowToClear: NSWindow? = nil
        
        // 从 UUID 到 Window 的映射中查找并清理
        if let windowRef = uuidToWindowMap.removeValue(forKey: windowId) {
            if let window = windowRef.window {
                windowToClear = window
                print("🧹 WindowFocusManager: 找到并清理UUID映射 - \(windowId.uuidString.prefix(8))")
            } else {
                print("🧹 WindowFocusManager: UUID映射的窗口弱引用已失效")
            }
        }
        
        // 从 Window 到 UUID 的映射中清理
        if let window = windowToClear {
            windowToUUIDMap.removeValue(forKey: window)
            print("🧹 WindowFocusManager: 清理双向映射 - \(window.title)")
        } else {
            // 如果没有找到窗口，也要检查是否有孤儿映射
            let orphanedMappings = windowToUUIDMap.filter { $0.value == windowId }
            for (window, _) in orphanedMappings {
                windowToUUIDMap.removeValue(forKey: window)
                print("🧹 WindowFocusManager: 清理孤儿窗口映射 - \(window.title)")
            }
        }
        
        // 清理窗口映射关系（子窗口到源窗口的映射）
        removeWindowMapping(for: windowId.uuidString)
        
        // 如果是当前活跃窗口，清除活跃状态
        if activeWindowInfo?.id == windowId.uuidString {
            activeWindowInfo = nil
            print("🏠 WindowFocusManager: 清除当前活跃窗口 - \(windowId.uuidString.prefix(8))")
        }
        
        // 同时从KeyboardEventManager注销
        keyboardEventManager?.unregisterWindow(windowId)
        
        print("📊 WindowFocusManager: 注销后映射统计 - windowToUUID: \(windowToUUIDMap.count), uuidToWindow: \(uuidToWindowMap.count)")
    }
    
    // MARK: - Focus Management
    
    /// 设置活跃窗口
    /// - Parameter windowId: 窗口标识符
    func setActiveWindow(_ windowId: UUID?) {
        windowQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                let previousWindow = self.activeWindowInfo
                
                if let windowId = windowId,
                   let windowInfo = self.windowRegistry[windowId] {
                    self.activeWindowInfo = windowInfo
                    self.keyboardEventManager?.setActiveWindowContext(windowId)
                    
                    // 🔧 记录窗口激活历史
                    let windowIdString = windowInfo.id
                    if let existingIndex = self.windowActivationHistory.firstIndex(of: windowIdString) {
                        // 如果已存在，移除旧记录
                        self.windowActivationHistory.remove(at: existingIndex)
                    }
                    // 添加到历史记录的最前面（最新的）
                    self.windowActivationHistory.insert(windowIdString, at: 0)
                    // 保持历史记录大小
                    if self.windowActivationHistory.count > self.maxHistorySize {
                        self.windowActivationHistory = Array(self.windowActivationHistory.prefix(self.maxHistorySize))
                    }
                    print("📜 WindowFocusManager: 更新窗口激活历史: [\(self.windowActivationHistory.map { $0.prefix(8) }.joined(separator: ", "))]")
                    
                    print("🏠 WindowFocusManager: 活跃窗口变更: \(previousWindow?.displayName ?? "nil")(\(previousWindow?.id.prefix(8) ?? "nil")) -> \(windowInfo.displayName)(\(windowInfo.id.prefix(8)))")
                    
                    // 检查是否有对应的NSWindow映射
                    if let windowRef = self.uuidToWindowMap[windowId],
                       let window = windowRef.window {
                        print("🔗 WindowFocusManager: 活跃窗口已关联NSWindow - \(window.title) (\(ObjectIdentifier(window)))")
                    } else {
                        print("⚠️ WindowFocusManager: 活跃窗口未关联NSWindow - 可能影响Command+K功能")
                    }
                    
                    // 发送窗口焦点变更通知
                    NotificationCenter.default.post(
                        name: NSNotification.Name("windowFocusChanged"),
                        object: windowInfo,
                        userInfo: [
                            "previousWindow": previousWindow?.id ?? "nil",
                            "currentWindow": windowInfo.id
                        ]
                    )
                } else {
                    self.activeWindowInfo = nil
                    self.keyboardEventManager?.setActiveWindowContext(nil)
                    
                    print("🏠 WindowFocusManager: 清除活跃窗口 - 之前: \(previousWindow?.displayName ?? "nil")(\(previousWindow?.id.prefix(8) ?? "nil"))")
                    
                    NotificationCenter.default.post(
                        name: NSNotification.Name("windowFocusChanged"),
                        object: nil,
                        userInfo: [
                            "previousWindow": previousWindow?.id ?? "nil",
                            "currentWindow": "nil"
                        ]
                    )
                }
            }
        }
    }
    
    /// 检查指定窗口是否为活跃窗口
    /// - Parameter windowId: 窗口标识符
    /// - Returns: 是否为活跃窗口
    func isActiveWindow(_ windowId: UUID) -> Bool {
        return activeWindowInfo?.id == windowId.uuidString
    }
    
    /// 获取当前活跃窗口的ID
    /// - Returns: 当前活跃窗口的UUID，如果没有活跃窗口则返回nil
    func getActiveWindowId() -> UUID? {
        guard let activeWindowInfo = activeWindowInfo,
              let uuid = UUID(uuidString: activeWindowInfo.id) else {
            return nil
        }
        return uuid
    }
    
    /// 获取源窗口ID（用于地图窗口映射）
    /// - Returns: 最合适的源窗口ID字符串
    func getSourceWindowId() -> String {
        // 策略1: 如果当前窗口是地图窗口，返回历史中的前一个非地图窗口
        if let activeWindow = activeWindowInfo,
           let activeUUID = UUID(uuidString: activeWindow.id),
           let activeWindowInfo = windowRegistry[activeUUID],
           activeWindowInfo.type == .map {
            
            // 在历史中查找非地图窗口
            for windowIdString in windowActivationHistory.dropFirst() { // 跳过当前窗口（地图窗口）
                if let uuid = UUID(uuidString: windowIdString),
                   let windowInfo = windowRegistry[uuid],
                   windowInfo.type != .map {
                    print("📜 WindowFocusManager: 从历史中找到源窗口 - \(windowInfo.displayName) (\(windowIdString.prefix(8)))")
                    return windowIdString
                }
            }
        }
        
        // 策略2: 返回当前活跃的非地图窗口
        if let activeWindow = activeWindowInfo,
           let activeUUID = UUID(uuidString: activeWindow.id),
           let activeWindowInfo = windowRegistry[activeUUID],
           activeWindowInfo.type != .map {
            print("📜 WindowFocusManager: 使用当前活跃窗口作为源窗口 - \(activeWindowInfo.displayName)")
            return activeWindow.id
        }
        
        // 策略3: 从历史中找最近的非地图窗口
        for windowIdString in windowActivationHistory {
            if let uuid = UUID(uuidString: windowIdString),
               let windowInfo = windowRegistry[uuid],
               windowInfo.type != .map {
                print("📜 WindowFocusManager: 从历史中找到非地图窗口作为源窗口 - \(windowInfo.displayName) (\(windowIdString.prefix(8)))")
                return windowIdString
            }
        }
        
        // 策略4: 回退到主窗口
        print("📜 WindowFocusManager: 回退到主窗口作为源窗口")
        return "MAIN_WINDOW"
    }
    
    /// 检查当前是否有活跃的key窗口
    /// - Returns: 是否有key窗口
    func hasActiveKeyWindow() -> Bool {
        guard let keyWindow = NSApplication.shared.keyWindow else { return false }
        return keyWindow.isKeyWindow && keyWindow.isVisible
    }
    
    // MARK: - Keyboard Shortcut Validation
    
    /// 验证快捷键是否应该在当前窗口执行
    /// - Parameters:
    ///   - command: 命令标识符
    ///   - windowId: 窗口标识符（可选，默认使用当前活跃窗口）
    /// - Returns: 是否应该执行
    func validateKeyboardShortcut(_ command: String, for windowId: UUID? = nil) -> Bool {
        // 检查是否是全局命令
        let isGlobal = keyboardEventManager?.isGlobalCommand(command) ?? false
        
        // 检查是否有key窗口
        guard hasActiveKeyWindow() else {
            print("🏠 WindowFocusManager: 快捷键验证失败 - 没有key窗口")
            return false
        }
        
        // 对于全局命令，不需要检查特定窗口激活状态
        if !isGlobal {
            // 如果指定了窗口ID，检查是否为活跃窗口
            if let windowId = windowId {
                guard isActiveWindow(windowId) else {
                    print("🏠 WindowFocusManager: 快捷键验证失败 - 窗口不是活跃状态 (\(windowId.uuidString.prefix(8)))")
                    return false
                }
            }
        } else {
            print("🏠 WindowFocusManager: 全局快捷键 \(command) 跳过窗口激活检查")
        }
        
        // 使用KeyboardEventManager验证命令
        return keyboardEventManager?.validateCommandForCurrentWindow(command, isGlobalCommand: isGlobal) ?? false
    }
    
    /// 检查全局命令是否在冷却期内
    /// - Parameter command: 命令名称
    /// - Returns: 是否在冷却期内
    private func isGlobalCommandInCooldown(_ command: String) -> Bool {
        guard let lastTime = lastGlobalCommandTime[command] else {
            return false
        }
        
        let timeSinceLastExecution = Date().timeIntervalSince(lastTime)
        return timeSinceLastExecution < globalCommandCooldown
    }
    
    /// 标记全局命令已执行
    /// - Parameter command: 命令名称
    private func markGlobalCommandExecuted(_ command: String) {
        lastGlobalCommandTime[command] = Date()
        print("🏠 WindowFocusManager: 全局命令 '\(command)' 开始冷却期")
    }

    /// 验证通知是否应该在指定窗口中处理
    /// - Parameters:
    ///   - windowId: 窗口标识符
    ///   - isGlobalCommand: 是否为全局命令（默认false）
    ///   - commandName: 命令名称（用于冷却检查）
    /// - Returns: 是否应该处理该通知
    func shouldHandleNotification(for windowId: UUID, isGlobalCommand: Bool = false, commandName: String? = nil) -> Bool {
        let windowShortId = windowId.uuidString.prefix(8)
        let debugCommandName = commandName ?? "未知命令"
        
        print("🔍 WindowFocusManager: 检查通知处理权限")
        print("   - 窗口ID: \(windowShortId)")
        print("   - 命令: \(debugCommandName)")
        print("   - 全局命令: \(isGlobalCommand)")
        print("   - 当前活跃窗口: \(activeWindowInfo?.displayName ?? "nil")")
        print("   - 有key窗口: \(hasActiveKeyWindow())")
        
        // 首先检查窗口是否已注册
        guard let windowInfo = windowRegistry[windowId] else {
            print("🏠 WindowFocusManager: 通知被忽略 - 窗口未注册 (\(windowShortId)) 命令: \(debugCommandName)")
            return false
        }
        
        // 检查是否有key窗口
        guard hasActiveKeyWindow() else {
            print("🏠 WindowFocusManager: 通知被忽略 - 没有key窗口 命令: \(debugCommandName)")
            return false
        }
        
        // 对于全局命令，检查冷却期并只允许一个窗口处理
        if isGlobalCommand {
            print("🌍 WindowFocusManager: 处理全局命令 \(debugCommandName) 在窗口 \(windowInfo.displayName)(\(windowShortId))")
            
            // 检查命令冷却期
            if let commandName = commandName, isGlobalCommandInCooldown(commandName) {
                let cooldownRemaining = globalCommandCooldown - (lastGlobalCommandTime[commandName].map { Date().timeIntervalSince($0) } ?? 0)
                print("🏠 WindowFocusManager: 全局命令被忽略 - 在冷却期内 (\(commandName)) 剩余: \(String(format: "%.3f", cooldownRemaining))s")
                return false
            }
            
            // 检查是否有当前活跃窗口，如果有则只让活跃窗口处理
            if let activeWindow = activeWindowInfo,
               let activeUUID = UUID(uuidString: activeWindow.id) {
                let shouldHandle = activeUUID == windowId
                if shouldHandle {
                    print("✅ WindowFocusManager: 全局通知允许执行 - 窗口是活跃窗口 \(windowInfo.displayName)(\(windowShortId)) 命令: \(debugCommandName)")
                    // 标记命令已执行
                    if let commandName = commandName {
                        markGlobalCommandExecuted(commandName)
                    }
                } else {
                    print("🚫 WindowFocusManager: 全局通知被忽略 - 窗口不是活跃窗口 \(windowInfo.displayName)(\(windowShortId)) 活跃窗口: \(activeWindow.displayName) 命令: \(debugCommandName)")
                }
                return shouldHandle
            }
            
            // 如果没有活跃窗口，尝试通过映射关系确定哪个窗口应该处理
            if let windowRef = uuidToWindowMap[windowId],
               let window = windowRef.window,
               window.isKeyWindow && window.isVisible {
                print("✅ WindowFocusManager: 全局通知允许执行 - 窗口是key窗口 \(windowInfo.displayName)(\(windowShortId)) 命令: \(debugCommandName)")
                // 同时将此窗口设置为活跃窗口
                setActiveWindow(windowId)
                // 标记命令已执行
                if let commandName = commandName {
                    markGlobalCommandExecuted(commandName)
                }
                return true
            } else {
                print("🚫 WindowFocusManager: 全局通知被忽略 - 窗口不是key窗口 \(windowInfo.displayName)(\(windowShortId)) 命令: \(debugCommandName)")
                return false
            }
        }
        
        // 对于窗口特定命令，检查是否为活跃窗口
        guard isActiveWindow(windowId) else {
            print("🏠 WindowFocusManager: 通知被忽略 - 窗口不是活跃状态 \(windowInfo.displayName)(\(windowShortId)) 命令: \(debugCommandName)")
            return false
        }
        
        print("✅ WindowFocusManager: 窗口特定通知允许执行 \(windowInfo.displayName)(\(windowShortId)) 命令: \(debugCommandName)")
        return true
    }
    
    /// 验证通知是否应该在当前活跃窗口中处理（不指定具体窗口ID）
    /// - Parameters:
    ///   - isGlobalCommand: 是否为全局命令（默认false）
    /// - Returns: 是否应该处理该通知
    func shouldHandleNotificationForActiveWindow(isGlobalCommand: Bool = false) -> Bool {
        // 检查是否有key窗口
        guard hasActiveKeyWindow() else {
            print("🏠 WindowFocusManager: 通知被忽略 - 没有key窗口")
            return false
        }
        
        // 对于全局命令，只要有key窗口就可以执行
        if isGlobalCommand {
            // 尝试刷新窗口状态（如果没有活跃窗口）
            if activeWindowInfo == nil {
                print("🔄 WindowFocusManager: 检测到全局命令但没有活跃窗口，尝试刷新")
                if let keyWindow = NSApplication.shared.keyWindow {
                    updateActiveWindowFromNSWindow(keyWindow)
                }
            }
            print("🏠 WindowFocusManager: 全局通知允许执行（活跃窗口）")
            return true
        }
        
        // 对于窗口特定命令，检查是否有活跃窗口
        guard activeWindowInfo != nil else {
            print("🏠 WindowFocusManager: 通知被忽略 - 没有活跃窗口")
            return false
        }
        
        return true
    }
    
    /// 检查通知名称是否为全局命令
    /// - Parameter notificationName: 通知名称
    /// - Returns: 是否为全局命令
    func isGlobalCommand(_ notificationName: String) -> Bool {
        let globalCommands: Set<String> = [
            "showCommandPalette",  // Command+K - 命令面板应该在任何活跃窗口中可用
            "addNewNode",          // Command+I - 添加新节点应该在任何活跃窗口中可用
            "toggleSidebar",       // Command+E - 切换侧边栏应该在任何活跃窗口中可用
            "openNewWindow",       // Command+B - 新建窗口是全局功能
            "openNodeManager",     // Command+Shift+W - 节点管理器
            "openTagManager",      // Command+Shift+I - 标签管理器
            "openMapWindow",       // Command+M - 地图窗口
            "openGraphWindow",     // Command+G - 图谱窗口
            "openQuickSearch",     // Command+Shift+F - 快速搜索
            "showSettings",        // 设置窗口
            "clearTagFilter",      // 清除标签筛选状态
            "restorePreviousTagFilterState", // Command+T - 恢复标签筛选状态
            // 🔧 移除 handleMapPinTap，改为窗口特定命令以避免所有窗口都接收通知
            // "handleMapPinTap",     // 地图节点点击 - 现在使用精确的窗口路由
            // 执行通知也应该被视为全局命令
            "executeOpenNodeManager", // 执行打开节点管理器
            "executeOpenMapWindow",   // 执行打开地图窗口
            "executeOpenGraphWindow", // 执行打开图谱窗口
            "executeToggleSidebar"    // 执行切换侧边栏
        ]
        
        return globalCommands.contains(notificationName)
    }
    
    /// 执行窗口特定的快捷键命令
    /// - Parameters:
    ///   - command: 命令标识符
    ///   - windowId: 窗口标识符
    ///   - action: 要执行的动作
    /// - Returns: 是否成功执行
    @discardableResult
    func executeKeyboardShortcut(_ command: String, for windowId: UUID, action: () -> Void) -> Bool {
        guard validateKeyboardShortcut(command, for: windowId) else {
            return false
        }
        
        // 标记命令开始执行
        keyboardEventManager?.markCommandExecuted(command, in: windowId)
        
        // 执行动作
        action()
        
        print("🏠 WindowFocusManager: 执行快捷键命令 - \(command) in \(windowId.uuidString.prefix(8))")
        return true
    }
    
    // MARK: - Private Methods
    
    /// 设置窗口观察器
    private func setupWindowObservers() {
        // 监听窗口成为key窗口
        let becameKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleWindowBecameKey(notification)
            }
        }
        windowObservers.append(becameKeyObserver)
        
        // 监听窗口失去key状态
        let resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleWindowResignKey(notification)
            }
        }
        windowObservers.append(resignKeyObserver)
        
        // 监听窗口关闭
        let willCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleWindowWillClose(notification)
            }
        }
        windowObservers.append(willCloseObserver)
        
        // 监听应用程序激活状态变化
        let appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleApplicationBecameActive()
            }
        }
        windowObservers.append(appActiveObserver)
        
        let appInactiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleApplicationResignActive()
            }
        }
        windowObservers.append(appInactiveObserver)
        
        // 监听Command+点击切换到主窗口并选中节点的通知
        let switchToMainObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("switchToMainWindowAndSelectNode"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                if let contentNode = notification.object as? Node {
                    self?.handleSwitchToMainWindowAndSelectNode(contentNode)
                }
            }
        }
        windowObservers.append(switchToMainObserver)
    }
    
    /// 设置与KeyboardEventManager的集成
    private func setupKeyboardEventManagerIntegration() {
        keyboardEventManager = KeyboardEventManager()
    }
    
    /// 处理窗口成为key窗口
    private func handleWindowBecameKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        print("🏠 WindowFocusManager: 窗口成为key - \(window.title) (\(ObjectIdentifier(window)))")
        
        // 更新活跃窗口映射
        updateActiveWindowFromNSWindow(window)
    }
    
    /// 处理窗口失去key状态
    private func handleWindowResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        print("🏠 WindowFocusManager: 窗口失去key - \(window.title) (\(ObjectIdentifier(window)))")
        
        // 检查是否是当前活跃窗口失去焦点
        if let uuid = windowToUUIDMap[window],
           activeWindowInfo?.id == uuid.uuidString {
            print("🏠 WindowFocusManager: 当前活跃窗口失去key状态 - \(uuid.uuidString.prefix(8))")
            // 不立即清除活跃状态，等待新的key窗口出现
        }
    }
    
    /// 处理窗口即将关闭
    private func handleWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        print("🏠 WindowFocusManager: 窗口即将关闭 - \(window.title) (\(ObjectIdentifier(window)))")
        
        // 查找并清理对应的窗口映射
        if let uuid = windowToUUIDMap[window] {
            print("🗑️ WindowFocusManager: 清理关闭窗口的映射 - \(uuid.uuidString.prefix(8))")
            windowToUUIDMap.removeValue(forKey: window)
            uuidToWindowMap.removeValue(forKey: uuid)
            
            // 如果是当前活跃窗口，清除活跃状态
            if activeWindowInfo?.id == uuid.uuidString {
                setActiveWindow(nil)
            }
        }
    }
    
    /// 处理应用程序变为活跃状态
    private func handleApplicationBecameActive() {
        print("🏠 WindowFocusManager: 应用程序变为活跃状态")
        print("📊 WindowFocusManager: 当前状态 - 注册窗口: \(windowRegistry.count), 映射关系: \(windowToUUIDMap.count), 活跃窗口: \(activeWindowInfo?.displayName ?? "nil")")
        
        // 重新评估当前的key窗口
        if let keyWindow = NSApplication.shared.keyWindow {
            print("🔄 WindowFocusManager: 重新评估key窗口 - \(keyWindow.title) (\(ObjectIdentifier(keyWindow)))")
            updateActiveWindowFromNSWindow(keyWindow)
        } else {
            print("⚠️ WindowFocusManager: 没有找到key窗口")
        }
    }
    
    /// 处理应用程序失去活跃状态
    private func handleApplicationResignActive() {
        print("🏠 WindowFocusManager: 应用程序失去活跃状态")
        
        // 可以选择保留当前活跃窗口信息，或者清除
        // 根据具体需求决定
    }
    
    /// 关联NSWindow与UUID
    /// - Parameters:
    ///   - window: NSWindow实例
    ///   - uuid: 对应的UUID
    private func associateWindowWithUUID(_ window: NSWindow, uuid: UUID) {
        // 🔧 增强的安全检查：确保映射的唯一性
        print("🔗 WindowFocusManager: 准备建立窗口映射 - \(window.title) <-> \(uuid.uuidString.prefix(8))")
        
        // 检查该窗口是否已经映射到其他UUID
        if let existingUUID = windowToUUIDMap[window] {
            if existingUUID != uuid {
                print("⚠️ WindowFocusManager: 窗口已映射到不同UUID - 现有: \(existingUUID.uuidString.prefix(8)), 新: \(uuid.uuidString.prefix(8))")
                // 清理旧的映射
                windowToUUIDMap.removeValue(forKey: window)
                uuidToWindowMap.removeValue(forKey: existingUUID)
                print("🧹 WindowFocusManager: 已清理旧的窗口映射")
            } else {
                print("✅ WindowFocusManager: 窗口已正确映射到相同UUID，无需重复操作")
                return
            }
        }
        
        // 检查该UUID是否已经映射到其他窗口
        if let existingWindowRef = uuidToWindowMap[uuid] {
            if let existingWindow = existingWindowRef.window {
                if existingWindow != window {
                    print("⚠️ WindowFocusManager: UUID已映射到不同窗口 - 现有: \(existingWindow.title), 新: \(window.title)")
                    // 检查现有窗口是否仍然有效
                    if existingWindow.isVisible && existingWindow.parent == nil && !existingWindow.isMiniaturized {
                        print("⚠️ WindowFocusManager: 现有窗口仍然有效，但允许重新映射以支持窗口切换")
                        // 清理旧映射，允许新映射
                        windowToUUIDMap.removeValue(forKey: existingWindow)
                        uuidToWindowMap.removeValue(forKey: uuid)
                        print("🔧 WindowFocusManager: 已清理旧映射，准备建立新映射")
                    } else {
                        print("🧹 WindowFocusManager: 现有窗口已失效，清理映射")
                        windowToUUIDMap.removeValue(forKey: existingWindow)
                        uuidToWindowMap.removeValue(forKey: uuid)
                    }
                } else {
                    print("✅ WindowFocusManager: UUID已正确映射到相同窗口，无需重复操作")
                    return
                }
            } else {
                // 弱引用已失效，清理映射
                print("🧹 WindowFocusManager: 清理失效的弱引用映射")
                uuidToWindowMap.removeValue(forKey: uuid)
            }
        }
        
        // 建立双向映射
        windowToUUIDMap[window] = uuid
        uuidToWindowMap[uuid] = WeakWindowReference(window: window)
        
        print("🔗 WindowFocusManager: 成功建立窗口映射 - \(window.title) <-> \(uuid.uuidString.prefix(8))")
        print("📊 WindowFocusManager: 当前映射统计 - windowToUUID: \(windowToUUIDMap.count), uuidToWindow: \(uuidToWindowMap.count)")
    }
    
    /// 从NSWindow更新活跃窗口信息
    private func updateActiveWindowFromNSWindow(_ window: NSWindow) {
        print("🔍 WindowFocusManager: 更新活跃窗口 - 窗口标题: '\(window.title)', 是否key: \(window.isKeyWindow), 是否可见: \(window.isVisible)")
        
        // 方式1：直接通过已建立的映射查找
        if let uuid = windowToUUIDMap[window] {
            if windowRegistry[uuid] != nil {
                print("🎯 WindowFocusManager: 通过直接映射找到窗口 - \(uuid.uuidString.prefix(8))")
                setActiveWindow(uuid)
                return
            } else {
                // 清理无效映射
                windowToUUIDMap.removeValue(forKey: window)
                uuidToWindowMap.removeValue(forKey: uuid)
            }
        }
        
        // 方式2：尝试建立新的映射关系
        // 根据当前注册窗口的数量和类型进行智能匹配
        let registeredWindows = Array(windowRegistry.keys)
        
        if registeredWindows.count == 1 {
            let uuid = registeredWindows[0]
            // 检查是否已有窗口映射到这个UUID
            if let existingWindow = uuidToWindowMap[uuid]?.window {
                print("⚠️ WindowFocusManager: UUID已被占用 - 现有窗口: \(existingWindow.title), 新窗口: \(window.title)")
                // 如果是相同的窗口，直接使用现有映射
                if existingWindow == window {
                    print("✅ WindowFocusManager: 相同窗口，使用现有映射")
                    setActiveWindow(uuid)
                    return
                }
                // 如果现有窗口已失效或不可见，清理映射
                if !existingWindow.isVisible || existingWindow.parent != nil {
                    windowToUUIDMap.removeValue(forKey: existingWindow)
                    uuidToWindowMap.removeValue(forKey: uuid)
                    print("🧹 WindowFocusManager: 清理失效窗口映射")
                } else {
                    print("⚠️ WindowFocusManager: UUID仍被其他有效窗口占用，尝试重新分配")
                    // 不要直接返回，继续尝试其他方法
                }
            }
            
            // 如果只有一个注册窗口且UUID未被占用，直接关联
            associateWindowWithUUID(window, uuid: uuid)
            print("🔄 WindowFocusManager: 单窗口自动关联 - \(uuid.uuidString.prefix(8))")
            setActiveWindow(uuid)
            return
        }
        
        // 方式3：通过窗口特征进行匹配，支持重试机制
        let matchResult = findBestWindowMatch(for: window)
        if let uuid = matchResult {
            associateWindowWithUUID(window, uuid: uuid)
            let windowInfo = windowRegistry[uuid]!
            print("🎯 WindowFocusManager: 智能匹配成功 - \(windowInfo.displayName) (\(uuid.uuidString.prefix(8)))")
            setActiveWindow(uuid)
            return
        }
        
        // 如果都没有找到合适的关联，记录调试信息但不放弃
        print("⚠️ WindowFocusManager: 暂时无法关联窗口 '\(window.title)' - 将继续重试")
        print("📋 WindowFocusManager: 已注册窗口: \(windowRegistry.count), 已映射窗口: \(windowToUUIDMap.count)")
        print("📋 WindowFocusManager: 已注册窗口列表: \(windowRegistry.map { "\($0.value.displayName)(\($0.key.uuidString.prefix(8)))" }.joined(separator: ", "))")
        
        // 安排延迟重试
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.retryWindowAssociation(for: window)
        }
    }
    
    /// 清理资源
    private func cleanup() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }
    
    // MARK: - Debug Methods
    
    /// 获取当前窗口状态信息（用于调试）
    func getDebugInfo() -> [String: Any] {
        let keyWindow = NSApplication.shared.keyWindow
        return [
            "activeWindow": activeWindowInfo?.displayName ?? "nil",
            "activeWindowId": activeWindowInfo?.id.prefix(8) ?? "nil",
            "registeredWindows": windowRegistry.count,
            "hasKeyWindow": hasActiveKeyWindow(),
            "keyWindowTitle": keyWindow?.title ?? "nil",
            "keyWindowId": keyWindow.map { "\(ObjectIdentifier($0))" } ?? "nil",
            "windowMappings": windowToUUIDMap.count,
            "windowList": windowRegistry.map { (uuid, info) in
                let hasMapping = uuidToWindowMap[uuid]?.window != nil
                return "\(info.displayName) (\(uuid.uuidString.prefix(8)))[映射:\(hasMapping ? "✓" : "✗")]"
            }
        ]
    }
    
    /// 强制刷新窗口状态（调试用）
    func forceRefreshWindowState() {
        print("🔄 WindowFocusManager: 强制刷新窗口状态")
        print("📊 当前调试信息: \(getDebugInfo())")
        
        // 如果有key窗口但没有活跃窗口，尝试重新建立映射
        if let keyWindow = NSApplication.shared.keyWindow,
           keyWindow.isKeyWindow && keyWindow.isVisible,
           activeWindowInfo == nil {
            print("🔧 WindowFocusManager: 检测到key窗口但没有活跃窗口，尝试重新建立映射")
            updateActiveWindowFromNSWindow(keyWindow)
        }
    }
    
    /// 开始定期清理任务
    private func startPeriodicCleanup() {
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupStaleWindowMappings()
            }
        }
    }
    
    /// 清理过期的窗口映射
    @MainActor
    private func cleanupStaleWindowMappings() {
        var staleMappingsRemoved = 0
        
        // 清理失效的 uuidToWindow 映射
        for (uuid, windowRef) in uuidToWindowMap {
            if windowRef.window == nil {
                uuidToWindowMap.removeValue(forKey: uuid)
                staleMappingsRemoved += 1
                print("🧹 定期清理: 移除失效的UUID映射 - \(uuid.uuidString.prefix(8))")
            }
        }
        
        // 清理失效的 windowToUUID 映射
        for (window, uuid) in windowToUUIDMap {
            if !window.isVisible || window.parent != nil {
                windowToUUIDMap.removeValue(forKey: window)
                uuidToWindowMap.removeValue(forKey: uuid)
                staleMappingsRemoved += 1
                print("🧹 定期清理: 移除失效的窗口映射 - \(window.title)")
            }
        }
        
        if staleMappingsRemoved > 0 {
            print("🧹 定期清理完成: 移除了 \(staleMappingsRemoved) 个过期映射")
            print("📊 清理后映射统计 - windowToUUID: \(windowToUUIDMap.count), uuidToWindow: \(uuidToWindowMap.count)")
        }
    }
    
    // MARK: - Window Association Helper Methods
    
    /// 尝试建立窗口与UUID的关联关系
    /// - Parameter windowId: 要关联的窗口UUID
    private func attemptWindowAssociation(windowId: UUID) {
        print("🔗 WindowFocusManager: 尝试建立窗口关联 - \(windowId.uuidString.prefix(8))")
        
        // 检查是否已有映射
        if uuidToWindowMap[windowId]?.window != nil {
            print("✅ WindowFocusManager: 窗口已存在映射关系 - \(windowId.uuidString.prefix(8))")
            return
        }
        
        // 查找当前的key窗口
        guard let keyWindow = NSApplication.shared.keyWindow,
              keyWindow.isKeyWindow && keyWindow.isVisible else {
            print("⚠️ WindowFocusManager: 没有找到可用的key窗口进行关联")
            return
        }
        
        // 检查窗口是否已被其他UUID占用
        if let existingUUID = windowToUUIDMap[keyWindow] {
            print("⚠️ WindowFocusManager: 窗口已被其他UUID占用 - 现有UUID: \(existingUUID.uuidString.prefix(8))")
            return
        }
        
        // 建立映射关系
        associateWindowWithUUID(keyWindow, uuid: windowId)
        
        // 如果这是唯一的窗口，设置为活跃窗口
        if activeWindowInfo == nil {
            setActiveWindow(windowId)
        }
        
        print("✅ WindowFocusManager: 窗口关联建立成功 - \(windowId.uuidString.prefix(8))")
    }
    
    /// 如果需要，重试窗口关联
    /// - Parameter windowId: 要重试关联的窗口UUID
    private func retryWindowAssociationIfNeeded(windowId: UUID) {
        // 检查是否已有有效映射
        if let windowRef = uuidToWindowMap[windowId],
           windowRef.window != nil {
            print("✅ WindowFocusManager: 窗口关联已存在，无需重试 - \(windowId.uuidString.prefix(8))")
            return
        }
        
        print("🔄 WindowFocusManager: 开始重试窗口关联 - \(windowId.uuidString.prefix(8))")
        attemptWindowAssociation(windowId: windowId)
    }
    
    /// 重试窗口关联（用于延迟重试）
    /// - Parameter window: 要重试关联的NSWindow
    private func retryWindowAssociation(for window: NSWindow) {
        print("🔄 WindowFocusManager: 重试窗口关联 - \(window.title) (\(ObjectIdentifier(window)))")
        
        // 再次尝试通过智能匹配建立关联
        let registeredWindows = Array(windowRegistry.keys)
        
        if registeredWindows.count == 1 {
            // 如果只有一个注册窗口，直接关联
            let uuid = registeredWindows[0]
            associateWindowWithUUID(window, uuid: uuid)
            print("🔄 WindowFocusManager: 重试成功 - 单窗口关联 \(uuid.uuidString.prefix(8))")
            setActiveWindow(uuid)
        } else {
            // 尝试智能匹配
            if let uuid = findBestWindowMatch(for: window) {
                associateWindowWithUUID(window, uuid: uuid)
                let windowInfo = windowRegistry[uuid]!
                print("🎯 WindowFocusManager: 重试成功 - 智能匹配 \(windowInfo.displayName) (\(uuid.uuidString.prefix(8)))")
                setActiveWindow(uuid)
            } else {
                print("❌ WindowFocusManager: 重试失败 - 仍无法找到合适的匹配")
            }
        }
    }
    
    /// 为NSWindow寻找最佳的UUID匹配
    /// - Parameter window: 要匹配的NSWindow
    /// - Returns: 匹配的UUID，如果没有找到则返回nil
    private func findBestWindowMatch(for window: NSWindow) -> UUID? {
        print("🎯 WindowFocusManager: 为窗口寻找最佳匹配 - '\(window.title)'")
        
        let registeredWindows = Array(windowRegistry.keys)
        guard !registeredWindows.isEmpty else {
            print("⚠️ WindowFocusManager: 没有已注册的窗口")
            return nil
        }
        
        // 策略1: 根据窗口标题匹配
        let windowTitle = window.title.lowercased()
        for uuid in registeredWindows {
            if let windowInfo = windowRegistry[uuid] {
                let displayName = windowInfo.displayName.lowercased()
                
                // 完全匹配
                if windowTitle == displayName {
                    print("✅ WindowFocusManager: 找到完全匹配 - '\(windowInfo.displayName)'")
                    return uuid
                }
                
                // 包含匹配
                if windowTitle.contains(displayName) || displayName.contains(windowTitle) {
                    print("✅ WindowFocusManager: 找到包含匹配 - '\(windowInfo.displayName)'")
                    return uuid
                }
            }
        }
        
        // 策略2: 根据窗口类型匹配
        for uuid in registeredWindows {
            if let windowInfo = windowRegistry[uuid] {
                switch windowInfo.type {
                case .map:
                    if windowTitle.contains("地图") || windowTitle.contains("map") {
                        print("✅ WindowFocusManager: 根据类型匹配到地图窗口 - '\(windowInfo.displayName)'")
                        return uuid
                    }
                case .graph:
                    if windowTitle.contains("图谱") || windowTitle.contains("graph") || windowTitle.contains("标签") {
                        print("✅ WindowFocusManager: 根据类型匹配到图谱窗口 - '\(windowInfo.displayName)'")
                        return uuid
                    }
                case .main:
                    if windowTitle.contains("wordtagger") || windowTitle.isEmpty {
                        print("✅ WindowFocusManager: 根据类型匹配到主窗口 - '\(windowInfo.displayName)'")
                        return uuid
                    }
                case .independent:
                    if windowTitle.contains("独立") || windowTitle.contains("independent") {
                        print("✅ WindowFocusManager: 根据类型匹配到独立窗口 - '\(windowInfo.displayName)'")
                        return uuid
                    }
                default:
                    break
                }
            }
        }
        
        // 策略3: 如果没有其他匹配，返回第一个未关联的窗口
        for uuid in registeredWindows {
            if uuidToWindowMap[uuid]?.window == nil {
                if let windowInfo = windowRegistry[uuid] {
                    print("✅ WindowFocusManager: 使用第一个未关联的窗口 - '\(windowInfo.displayName)'")
                    return uuid
                }
            }
        }
        
        print("❌ WindowFocusManager: 无法找到合适的窗口匹配")
        return nil
    }
}

// MARK: - Supporting Types

/// 弱引用包装器用于存储NSWindow引用
class WeakWindowReference {
    weak var window: NSWindow?
    
    init(window: NSWindow) {
        self.window = window
    }
}

// MARK: - SwiftUI Integration

/// 用于在SwiftUI视图中注册窗口的ViewModifier
struct WindowRegistrationModifier: ViewModifier {
    let windowId: UUID
    let windowType: WindowType
    let displayName: String?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                WindowFocusManager.shared.registerWindow(
                    windowId,
                    type: windowType,
                    displayName: displayName
                )
            }
            .onDisappear {
                WindowFocusManager.shared.unregisterWindow(windowId)
            }
    }
}

extension View {
    /// 为视图注册窗口焦点管理
    /// - Parameters:
    ///   - windowId: 窗口标识符
    ///   - windowType: 窗口类型
    ///   - displayName: 显示名称（可选）
    /// - Returns: 修改后的视图
    func registerWindow(
        _ windowId: UUID,
        type windowType: WindowType,
        displayName: String? = nil
    ) -> some View {
        modifier(WindowRegistrationModifier(
            windowId: windowId,
            windowType: windowType,
            displayName: displayName
        ))
    }
}

// MARK: - WindowFocusManager 窗口映射扩展

extension WindowFocusManager {
    /// 创建窗口映射关系
    /// - Parameters:
    ///   - childWindowId: 子窗口ID
    ///   - sourceWindowId: 源窗口ID
    func createWindowMapping(childWindowId: String, sourceWindowId: String) {
        windowMappings[childWindowId] = sourceWindowId
        print("🔗 WindowFocusManager: 创建窗口映射 - \\(childWindowId.prefix(8)) <- \\(sourceWindowId.prefix(8))")
    }
    
    /// 获取窗口的源窗口ID
    /// - Parameter windowId: 窗口ID
    /// - Returns: 源窗口ID（如果存在）
    func getSourceWindowId(for windowId: String) -> String? {
        return windowMappings[windowId]
    }
    
    /// 删除窗口映射
    /// - Parameter windowId: 要删除的窗口ID
    func removeWindowMapping(for windowId: String) {
        windowMappings.removeValue(forKey: windowId)
        // 如果这个窗口是其他窗口的源窗口，也要清理
        windowMappings = windowMappings.filter { $0.value != windowId }
        
        // 🔧 同时清理层图谱窗口映射
        if let mainWindowId = layerGraphWindows.first(where: { $0.value == windowId })?.key {
            layerGraphWindows.removeValue(forKey: mainWindowId)
            print("🧹 WindowFocusManager: 清理层图谱窗口映射 - 主窗口(\(mainWindowId.prefix(8))) -> 层图谱(\(windowId.prefix(8)))")
        }
        
        // 🔧 如果是主窗口关闭，也要清理它的层图谱窗口预留/映射
        layerGraphWindows.removeValue(forKey: windowId)
        
        print("🧹 WindowFocusManager: 清理窗口映射 - \\(windowId.prefix(8))")
    }
    
    /// 检查主窗口是否已有层图谱窗口
    /// - Parameter mainWindowId: 主窗口ID
    /// - Returns: 如果已有层图谱窗口返回true
    func hasLayerGraphWindow(for mainWindowId: String) -> Bool {
        return layerGraphWindows[mainWindowId] != nil
    }
    
    /// 原子性地检查并预留层图谱窗口位置
    /// - Parameter mainWindowId: 主窗口ID
    /// - Returns: 如果成功预留返回true，如果已存在返回false
    func reserveLayerGraphWindow(for mainWindowId: String) -> Bool {
        if layerGraphWindows[mainWindowId] != nil {
            print("🚫 WindowFocusManager: 层图谱窗口已存在，拒绝预留 - 主窗口(\(mainWindowId.prefix(8)))")
            return false
        }
        
        // 预留位置，使用占位符
        layerGraphWindows[mainWindowId] = "RESERVED"
        print("🔒 WindowFocusManager: 预留层图谱窗口位置 - 主窗口(\(mainWindowId.prefix(8)))")
        return true
    }
    
    /// 为主窗口注册层图谱窗口
    /// - Parameters:
    ///   - mainWindowId: 主窗口ID
    ///   - layerGraphWindowId: 层图谱窗口ID
    func registerLayerGraphWindow(mainWindowId: String, layerGraphWindowId: String) {
        let previousValue = layerGraphWindows[mainWindowId]
        layerGraphWindows[mainWindowId] = layerGraphWindowId
        
        if previousValue == "RESERVED" {
            print("🔗 WindowFocusManager: 层图谱窗口注册成功（预留位置） - 主窗口(\(mainWindowId.prefix(8))) -> 层图谱(\(layerGraphWindowId.prefix(8)))")
        } else {
            print("🔗 WindowFocusManager: 注册层图谱窗口映射 - 主窗口(\(mainWindowId.prefix(8))) -> 层图谱(\(layerGraphWindowId.prefix(8)))")
        }
    }
    
    /// 获取主窗口的层图谱窗口ID
    /// - Parameter mainWindowId: 主窗口ID
    /// - Returns: 层图谱窗口ID，如果没有则返回nil
    func getLayerGraphWindow(for mainWindowId: String) -> String? {
        let value = layerGraphWindows[mainWindowId]
        // 如果是预留状态，返回nil
        return value == "RESERVED" ? nil : value
    }
    
    /// 清理预留的层图谱窗口位置（用于窗口创建失败时的清理）
    /// - Parameter mainWindowId: 主窗口ID
    func clearReservedLayerGraphWindow(for mainWindowId: String) {
        if layerGraphWindows[mainWindowId] == "RESERVED" {
            layerGraphWindows.removeValue(forKey: mainWindowId)
            print("🧹 WindowFocusManager: 清理预留的层图谱窗口位置 - 主窗口(\(mainWindowId.prefix(8)))")
        }
    }
    
    /// 处理Command+点击从子窗口切换到主窗口并选中节点
    /// - Parameter contentNode: 要选中的节点
    func handleSwitchToMainWindowAndSelectNode(_ contentNode: Node) {
        print("⌘ WindowFocusManager: 处理Command+点击切换到主窗口并选中节点")
        print("   - 目标节点: \(contentNode.text)")
        print("   - 节点ID: \(contentNode.id)")
        print("   - 节点层ID: \(contentNode.layerId)")
        print("   - 当前注册窗口数量: \(windowRegistry.count)")
        
        // 打印所有注册窗口的详情
        print("   - 已注册窗口:")
        for (uuid, info) in windowRegistry {
            print("     * \(info.displayName) (类型: \(info.type)) - \(uuid.uuidString.prefix(8))")
        }
        
        // 查找主窗口（类型为.main的窗口）
        guard let (mainWindowId, mainWindowInfo) = windowRegistry.first(where: { $0.value.type == .main }) else {
            print("❌ WindowFocusManager: 找不到类型为.main的窗口")
            return
        }
        
        print("   - 找到主窗口: \(mainWindowInfo.displayName) (\(mainWindowId.uuidString.prefix(8)))")
        
        guard let mainWindow = uuidToWindowMap[mainWindowId]?.window else {
            print("❌ WindowFocusManager: 主窗口UUID映射不存在或窗口已关闭")
            return
        }
        
        print("   - 主窗口NSWindow存在: \(mainWindow.title)")
        
        // 切换到主窗口
        print("🔄 切换到主窗口...")
        mainWindow.makeKeyAndOrderFront(NSApp)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // 发送选择节点的通知给主窗口的Store
        print("📡 准备发送selectNodeFromCommandClick通知...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("📡 发送selectNodeFromCommandClick通知: \(contentNode.text)")
            NotificationCenter.default.post(
                name: NSNotification.Name("selectNodeFromCommandClick"),
                object: contentNode,
                userInfo: ["sourceAction": "commandClickFromGraph"]
            )
            print("✅ selectNodeFromCommandClick通知已发送")
        }
        
        print("✅ WindowFocusManager: 成功切换到主窗口并发送选中节点通知")
    }
    
    // MARK: - Additional Helper Methods
    
    /// 获取当前活跃窗口的ID字符串
    /// - Returns: 活跃窗口ID字符串，如果没有活跃窗口则返回nil
    func getActiveWindowIdString() -> String? {
        return activeWindowInfo?.id
    }
    
    /// 获取主窗口的ID（返回第一个找到的主窗口）
    /// - Returns: 主窗口的ID字符串，如果没有主窗口则返回nil
    func getMainWindowId() -> String? {
        return windowRegistry.first(where: { $0.value.type == .main })?.key.uuidString
    }
    
    /// 获取当前活跃的主窗口ID（优先返回活跃的主窗口）
    /// - Returns: 活跃主窗口的ID字符串，如果没有则返回第一个主窗口的ID
    func getActiveMainWindowId() -> String? {
        // 优先返回当前活跃的主窗口
        if let activeWindowId = getActiveWindowId(),
           let activeWindowInfo = windowRegistry[activeWindowId],
           activeWindowInfo.type == .main {
            return activeWindowId.uuidString
        }
        
        // 回退到第一个主窗口
        return getMainWindowId()
    }
    
    /// 获取窗口激活历史（用于调试和窗口映射）
    /// - Returns: 窗口激活历史数组，按时间顺序（最新的在前）
    func getWindowActivationHistory() -> [String] {
        return windowActivationHistory
    }
    
    /// 从激活历史中查找最近的主窗口
    /// - Parameter excludeWindowId: 要排除的窗口ID（通常是当前窗口）
    /// - Returns: 最近的主窗口ID，如果没有找到则返回nil
    func getRecentMainWindowFromHistory(excluding excludeWindowId: String? = nil) -> String? {
        for windowIdString in windowActivationHistory {
            // 跳过要排除的窗口
            if let exclude = excludeWindowId, windowIdString == exclude {
                continue
            }
            
            // 检查是否是主窗口
            if let uuid = UUID(uuidString: windowIdString),
               let windowInfo = windowRegistry[uuid],
               windowInfo.type == .main {
                return windowIdString
            }
        }
        return nil
    }
    
    /// 检查给定的窗口ID是否是主窗口
    /// - Parameter windowId: 要检查的窗口ID
    /// - Returns: 如果是主窗口返回true，否则返回false
    func isMainWindow(_ windowId: String) -> Bool {
        // 检查UUID格式的窗口ID
        if let uuid = UUID(uuidString: windowId),
           let windowInfo = windowRegistry[uuid] {
            return windowInfo.type == .main
        }
        
        // 检查windowMappings中是否有这个ID对应主窗口
        for (registeredUUID, info) in windowRegistry {
            if info.type == .main && registeredUUID.uuidString == windowId {
                return true
            }
        }
        
        return false
    }
}