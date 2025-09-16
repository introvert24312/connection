//
//  KeyboardEventManager.swift
//  WordTagger
//
//  Created by Kiro on 2025/8/19.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Window Types (temporary - should be in separate file)

/// 窗口类型枚举
enum WindowType: Hashable {
    case standard        // 标准窗口（原来的主窗口和独立窗口）
    case map            // 地图窗口
    case graph          // 图谱窗口
    case fullscreenGraph // 全屏图谱
    case nodeManager    // 节点管理
    case settings       // 设置
    case custom(String) // 自定义类型
    
    var displayName: String {
        switch self {
        case .standard: return "窗口"
        case .map: return "地图窗口"
        case .graph: return "图谱窗口"
        case .fullscreenGraph: return "全屏图谱"
        case .nodeManager: return "节点管理"
        case .settings: return "设置"
        case .custom(let name): return name
        }
    }
    
    var description: String {
        return displayName
    }
}

/// 窗口信息结构
struct WindowInfo: Hashable, Identifiable {
    let id: String
    let displayName: String
    let type: WindowType
    let registrationTime: Date
    
    init(id: String, displayName: String, type: WindowType) {
        self.id = id
        self.displayName = displayName
        self.type = type
        self.registrationTime = Date()
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Manages keyboard event state and prevents rapid-fire command execution
/// Enhanced with window-level event management support
class KeyboardEventManager: ObservableObject {
    // MARK: - Published Properties
    
    /// Set of currently active commands to prevent overlapping execution
    @Published private var activeCommands: Set<String> = []
    
    /// Tracks the last execution time for each command to implement cooldown
    @Published private var commandExecutionState: [String: Date] = [:]
    
    /// Indicates if the manager is in error recovery mode
    @Published var isInErrorRecovery: Bool = false
    
    /// Current error state information
    @Published var errorState: KeyboardErrorState?
    
    /// Window-specific command states
    @Published private var windowCommandStates: [UUID: WindowCommandState] = [:]
    
    /// Current active window context
    @Published private(set) var activeWindowContext: UUID?
    
    // MARK: - Private Properties
    
    /// Cooldown period between command executions (in seconds)
    private let commandCooldown: TimeInterval = 0.5
    
    /// Timer for automatic state cleanup
    private var cleanupTimer: Timer?
    
    /// Timer for error recovery timeout
    private var errorRecoveryTimer: Timer?
    
    /// Timer for automatic state reset
    private var stateResetTimer: Timer?
    
    /// Queue for managing command execution state
    private let commandQueue = DispatchQueue(label: "com.wordtagger.keyboard.commands", qos: .userInteractive)
    
    /// Maximum time to keep command states before automatic reset (in seconds)
    private let maxStateRetentionTime: TimeInterval = 30.0
    
    /// Error recovery timeout (in seconds)
    private let errorRecoveryTimeout: TimeInterval = 5.0
    
    /// Focus management state
    private var focusState: ApplicationFocusState = .normal
    
    /// Command execution history for debugging
    private var executionHistory: [CommandExecution] = []
    private let maxHistorySize = 50
    
    /// Integration with focus manager
    private var focusManagerObserver: AnyCancellable?
    
    // MARK: - Initialization
    
    init() {
        setupAutomaticCleanup()
        setupErrorRecovery()
        setupStateResetTimer()
        setupFocusManagerIntegration()
    }
    
    deinit {
        cleanupTimer?.invalidate()
        errorRecoveryTimer?.invalidate()
        stateResetTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// Checks if a command can be executed based on cooldown and active state (legacy method for backwards compatibility)
    /// - Parameter command: The command identifier to check
    /// - Returns: True if the command can be executed, false otherwise
    func canExecuteCommand(_ command: String) -> Bool {
        // Automatically detect if it's a global command
        let isGlobal = isGlobalCommand(command)
        return canExecuteCommand(command, isGlobalCommand: isGlobal)
    }
    
    /// Checks if a command can be executed based on cooldown and active state
    /// - Parameters:
    ///   - command: The command identifier to check
    ///   - isGlobalCommand: Whether this is a global command
    /// - Returns: True if the command can be executed, false otherwise
    func canExecuteCommand(_ command: String, isGlobalCommand: Bool) -> Bool {
        return commandQueue.sync {
            // If in error recovery mode, only allow recovery commands
            if isInErrorRecovery && !isRecoveryCommand(command) {
                recordCommandAttempt(command, result: .blockedByErrorRecovery)
                return false
            }
            
            // Check focus state
            if focusState == .corrupted {
                recordCommandAttempt(command, result: .blockedByFocusIssue)
                return false
            }
            
            // For global commands, skip the active window context check
            if !isGlobalCommand {
                // Check if we have an active window context (only for window-specific commands)
                guard activeWindowContext != nil else {
                    recordCommandAttempt(command, result: .blockedByFocusIssue)
                    print("⌨️ KeyboardEventManager: Command \(command) blocked - no active window context")
                    return false
                }
            } else {
                print("⌨️ KeyboardEventManager: Global command \(command) bypassing window context check")
            }
            
            // Check if command is currently active
            guard !activeCommands.contains(command) else {
                recordCommandAttempt(command, result: .blockedByActiveState)
                return false
            }
            
            // Check cooldown period
            if let lastExecution = commandExecutionState[command] {
                let timeSinceLastExecution = Date().timeIntervalSince(lastExecution)
                if timeSinceLastExecution <= commandCooldown {
                    recordCommandAttempt(command, result: .blockedByCooldown)
                    return false
                }
            }
            
            recordCommandAttempt(command, result: .allowed)
            return true
        }
    }
    
    /// Marks a command as executed and updates tracking state
    /// - Parameter command: The command identifier that was executed
    func markCommandExecuted(_ command: String) {
        commandQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // Add to active commands
                self.activeCommands.insert(command)
                
                // Record execution time
                self.commandExecutionState[command] = Date()
                
                // Record successful execution
                self.recordCommandExecution(command, success: true)
                
                // If this was a recovery command, check if we can exit error recovery
                if self.isInErrorRecovery && self.isRecoveryCommand(command) {
                    self.checkErrorRecoveryCompletion()
                }
                
                // Schedule removal from active commands after cooldown
                DispatchQueue.main.asyncAfter(deadline: .now() + self.commandCooldown) {
                    self.activeCommands.remove(command)
                }
            }
        }
    }
    
    /// Marks a command execution as failed and triggers error recovery if needed
    /// - Parameters:
    ///   - command: The command identifier that failed
    ///   - error: The error that occurred
    func markCommandFailed(_ command: String, error: KeyboardError) {
        commandQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // Record failed execution
                self.recordCommandExecution(command, success: false, error: error)
                
                // Remove from active commands if it was active
                self.activeCommands.remove(command)
                
                // Trigger error recovery based on error type
                self.handleCommandError(command, error: error)
            }
        }
    }
    
    /// Clears all command states - useful for cleanup operations
    func clearCommandState() {
        commandQueue.async { [weak self] in
            DispatchQueue.main.async {
                self?.activeCommands.removeAll()
                self?.commandExecutionState.removeAll()
            }
        }
    }
    
    /// Clears state for a specific command
    /// - Parameter command: The command identifier to clear
    func clearCommandState(for command: String) {
        commandQueue.async { [weak self] in
            DispatchQueue.main.async {
                self?.activeCommands.remove(command)
                self?.commandExecutionState.removeValue(forKey: command)
            }
        }
    }
    
    /// Checks if a specific command is currently active
    /// - Parameter command: The command identifier to check
    /// - Returns: True if the command is currently active
    func isCommandActive(_ command: String) -> Bool {
        return commandQueue.sync {
            return activeCommands.contains(command)
        }
    }
    
    /// Gets the time since a command was last executed
    /// - Parameter command: The command identifier to check
    /// - Returns: Time interval since last execution, or nil if never executed
    func timeSinceLastExecution(of command: String) -> TimeInterval? {
        return commandQueue.sync {
            guard let lastExecution = commandExecutionState[command] else {
                return nil
            }
            return Date().timeIntervalSince(lastExecution)
        }
    }
    
    // MARK: - Private Methods
    
    /// Sets up automatic cleanup of expired command states
    private func setupAutomaticCleanup() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: commandCooldown * 2, repeats: true) { [weak self] _ in
            self?.performAutomaticCleanup()
        }
    }
    
    /// Performs automatic cleanup of expired command execution states
    private func performAutomaticCleanup() {
        commandQueue.async { [weak self] in
            guard let self = self else { return }
            
            let now = Date()
            let cleanupThreshold = self.commandCooldown * 3
            
            // Use more efficient filtering
            let expiredCommands = self.commandExecutionState.compactMap { (command, executionTime) -> String? in
                let timeSinceExecution = now.timeIntervalSince(executionTime)
                return timeSinceExecution > cleanupThreshold ? command : nil
            }
            
            // Batch the cleanup operations
            if !expiredCommands.isEmpty {
                DispatchQueue.main.async {
                    // Remove expired commands in batch
                    for command in expiredCommands {
                        self.commandExecutionState.removeValue(forKey: command)
                        self.activeCommands.remove(command)
                    }
                    
                    // Clean up execution history
                    self.cleanupExecutionHistory()
                    
                    // Perform additional cleanup if many commands expired
                    if expiredCommands.count > 10 {
                        // Force additional cleanup for memory efficiency
                        self.executionHistory.removeAll { execution in
                            Date().timeIntervalSince(execution.timestamp) > self.maxStateRetentionTime
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Error Recovery Methods
    
    /// Sets up error recovery mechanisms
    private func setupErrorRecovery() {
        // Monitor for system focus changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleApplicationFocusChange(active: true)
        }
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleApplicationFocusChange(active: false)
        }
    }
    
    /// Sets up automatic state reset timer
    private func setupStateResetTimer() {
        stateResetTimer = Timer.scheduledTimer(withTimeInterval: maxStateRetentionTime, repeats: true) { [weak self] _ in
            self?.performAutomaticStateReset()
        }
    }
    
    /// Handles command execution errors and triggers appropriate recovery
    private func handleCommandError(_ command: String, error: KeyboardError) {
        switch error {
        case .focusLost:
            enterErrorRecovery(.focusLost)
            focusState = .corrupted
            
        case .eventConflict:
            enterErrorRecovery(.eventConflict)
            
        case .systemOverride:
            // System override is usually temporary, just clear the command
            clearCommandState(for: command)
            
        case .unexpectedState:
            enterErrorRecovery(.unexpectedState)
            
        case .timeout:
            // Timeout suggests the command got stuck
            clearCommandState(for: command)
            if activeCommands.count > 3 {
                // Too many stuck commands, enter recovery
                enterErrorRecovery(.timeout)
            }
        }
    }
    
    /// Enters error recovery mode
    private func enterErrorRecovery(_ errorType: KeyboardErrorType) {
        guard !isInErrorRecovery else { return }
        
        isInErrorRecovery = true
        errorState = KeyboardErrorState(
            type: errorType,
            timestamp: Date(),
            affectedCommands: Array(activeCommands)
        )
        
        // Clear all active commands to prevent further conflicts
        activeCommands.removeAll()
        
        // Start error recovery timeout
        errorRecoveryTimer?.invalidate()
        errorRecoveryTimer = Timer.scheduledTimer(withTimeInterval: errorRecoveryTimeout, repeats: false) { [weak self] _ in
            self?.forceExitErrorRecovery()
        }
        
        print("⚠️ KeyboardEventManager: Entered error recovery mode for \(errorType)")
    }
    
    /// Checks if error recovery can be completed
    private func checkErrorRecoveryCompletion() {
        guard isInErrorRecovery else { return }
        
        // Check if conditions are met to exit error recovery
        let canExit = activeCommands.isEmpty && focusState == .normal
        
        if canExit {
            exitErrorRecovery()
        }
    }
    
    /// Exits error recovery mode
    private func exitErrorRecovery() {
        guard isInErrorRecovery else { return }
        
        isInErrorRecovery = false
        errorState = nil
        errorRecoveryTimer?.invalidate()
        
        print("✅ KeyboardEventManager: Exited error recovery mode")
    }
    
    /// Forces exit from error recovery mode after timeout
    private func forceExitErrorRecovery() {
        print("🔄 KeyboardEventManager: Force exiting error recovery mode after timeout")
        
        // Clear all state
        clearCommandState()
        focusState = .normal
        exitErrorRecovery()
    }
    
    /// Handles application focus changes
    private func handleApplicationFocusChange(active: Bool) {
        if active {
            // Application became active, restore normal focus state
            focusState = .normal
            
            // If we were in error recovery due to focus issues, try to exit
            if isInErrorRecovery && errorState?.type == .focusLost {
                checkErrorRecoveryCompletion()
            }
        } else {
            // Application lost focus, clear any active commands
            clearCommandState()
        }
    }
    
    /// Performs automatic state reset for stuck states
    private func performAutomaticStateReset() {
        let now = Date()
        
        // Check for commands that have been active too long
        let stuckCommands = commandExecutionState.compactMap { (command, executionTime) -> String? in
            let timeSinceExecution = now.timeIntervalSince(executionTime)
            return timeSinceExecution > maxStateRetentionTime ? command : nil
        }
        
        if !stuckCommands.isEmpty {
            print("🧹 KeyboardEventManager: Clearing \(stuckCommands.count) stuck commands")
            
            for command in stuckCommands {
                clearCommandState(for: command)
            }
        }
        
        // If we've been in error recovery too long, force exit
        if isInErrorRecovery,
           let errorState = errorState,
           now.timeIntervalSince(errorState.timestamp) > maxStateRetentionTime {
            print("🔄 KeyboardEventManager: Force exiting long-running error recovery")
            forceExitErrorRecovery()
        }
    }
    
    /// Checks if a command is a recovery command
    private func isRecoveryCommand(_ command: String) -> Bool {
        // Recovery commands are typically escape, clear operations, or focus management
        return command == Commands.escape || 
               command == "clear-state" || 
               command == "focus-reset"
    }
    
    /// Records command execution attempt for debugging
    private func recordCommandAttempt(_ command: String, result: CommandAttemptResult) {
        let attempt = CommandExecution(
            command: command,
            timestamp: Date(),
            success: result == .allowed,
            result: result
        )
        
        executionHistory.append(attempt)
        
        // Keep history size manageable
        if executionHistory.count > maxHistorySize {
            executionHistory.removeFirst(executionHistory.count - maxHistorySize)
        }
    }
    
    /// Records command execution result
    private func recordCommandExecution(_ command: String, success: Bool, error: KeyboardError? = nil) {
        let execution = CommandExecution(
            command: command,
            timestamp: Date(),
            success: success,
            error: error
        )
        
        executionHistory.append(execution)
        
        // Keep history size manageable
        if executionHistory.count > maxHistorySize {
            executionHistory.removeFirst(executionHistory.count - maxHistorySize)
        }
    }
    
    /// Cleans up old execution history
    private func cleanupExecutionHistory() {
        let cutoffTime = Date().addingTimeInterval(-maxStateRetentionTime)
        executionHistory.removeAll { $0.timestamp < cutoffTime }
    }
    
    // MARK: - Public Error Recovery Methods
    
    /// Manually triggers error recovery reset
    func resetErrorState() {
        clearCommandState()
        focusState = .normal
        if isInErrorRecovery {
            forceExitErrorRecovery()
        }
    }
    
    /// Gets current error recovery status
    func getErrorRecoveryStatus() -> (isInRecovery: Bool, errorType: KeyboardErrorType?, duration: TimeInterval?) {
        guard let errorState = errorState else {
            return (isInErrorRecovery, nil, nil)
        }
        
        let duration = Date().timeIntervalSince(errorState.timestamp)
        return (isInErrorRecovery, errorState.type, duration)
    }
    
    /// Gets execution history for debugging
    func getExecutionHistory(limit: Int = 20) -> [CommandExecution] {
        return Array(executionHistory.suffix(limit))
    }
    
    // MARK: - Window Focus Management
    
    /// Checks if the current window is the key window and should receive keyboard events
    /// - Returns: True if the current context window is key and visible
    func isCurrentWindowKeyWindow() -> Bool {
        guard let keyWindow = NSApplication.shared.keyWindow else {
            print("⌨️ KeyboardEventManager: No key window found")
            return false
        }
        
        let isKey = keyWindow.isKeyWindow
        let isVisible = keyWindow.isVisible
        
        print("⌨️ KeyboardEventManager: Window state - isKey: \(isKey), isVisible: \(isVisible)")
        return isKey && isVisible
    }
    
    /// Validates that a command should be executed in the current window context
    /// - Parameters:
    ///   - command: Command to validate
    ///   - isGlobalCommand: Whether this is a global command (default: false)
    /// - Returns: True if command should be executed
    func validateCommandForCurrentWindow(_ command: String, isGlobalCommand: Bool = false) -> Bool {
        // For global commands, we don't need to check if the current window is key
        if !isGlobalCommand {
            // First check if we have a valid window context
            guard isCurrentWindowKeyWindow() else {
                print("⌨️ KeyboardEventManager: Command \(command) blocked - not key window")
                return false
            }
        } else {
            // For global commands, just check if there's any key window in the app
            guard NSApplication.shared.keyWindow != nil else {
                print("⌨️ KeyboardEventManager: Global command \(command) blocked - no key window in app")
                return false
            }
        }
        
        // Then check normal command validation
        return canExecuteCommand(command, isGlobalCommand: isGlobalCommand)
    }
}

// MARK: - Supporting Structures

/// Represents different types of keyboard errors
enum KeyboardError: Error, LocalizedError {
    case focusLost
    case eventConflict
    case systemOverride
    case unexpectedState
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .focusLost:
            return "Application focus was lost during command execution"
        case .eventConflict:
            return "Conflicting keyboard events detected"
        case .systemOverride:
            return "System intercepted the keyboard event"
        case .unexpectedState:
            return "Keyboard event manager is in an unexpected state"
        case .timeout:
            return "Command execution timed out"
        }
    }
}

/// Types of keyboard error recovery states
enum KeyboardErrorType {
    case focusLost
    case eventConflict
    case unexpectedState
    case timeout
}

/// Focus state of the application
enum ApplicationFocusState {
    case normal
    case corrupted
    case recovering
}

/// Result of a command execution attempt
enum CommandAttemptResult {
    case allowed
    case blockedByActiveState
    case blockedByCooldown
    case blockedByErrorRecovery
    case blockedByFocusIssue
}

/// Error state information
struct KeyboardErrorState {
    let type: KeyboardErrorType
    let timestamp: Date
    let affectedCommands: [String]
}

/// Command execution record for debugging
struct CommandExecution {
    let command: String
    let timestamp: Date
    let success: Bool
    let result: CommandAttemptResult?
    let error: KeyboardError?
    let windowId: UUID?
    
    init(command: String, timestamp: Date, success: Bool, result: CommandAttemptResult? = nil, error: KeyboardError? = nil, windowId: UUID? = nil) {
        self.command = command
        self.timestamp = timestamp
        self.success = success
        self.result = result
        self.error = error
        self.windowId = windowId
    }
}

// MARK: - Command Identifiers

extension KeyboardEventManager {
    /// Standard command identifiers for common keyboard shortcuts
    struct Commands {
        static let commandG = "command-g"
        static let commandW = "command-w"
        static let commandN = "command-n"
        static let commandO = "command-o"
        static let commandS = "command-s"
        static let commandZ = "command-z"
        static let commandY = "command-y"
        static let commandK = "command-k"  // Command+K - 命令面板
        static let commandB = "command-b"  // Command+B - 新建窗口
        static let escape = "escape"
        static let enter = "enter"
        static let tab = "tab"
        
        // Recovery commands
        static let clearState = "clear-state"
        static let focusReset = "focus-reset"
        
        // UI Navigation commands
        static let switchToTagFiltering = "switch-to-tag-filtering"
        static let switchToTagSearch = "switch-to-tag-search"
        
        // Global commands that don't require specific window activation
        static let globalCommands: Set<String> = [
            commandK,  // Command+K - 命令面板应该在任何活跃窗口中可用
            commandB,  // Command+B - 新建窗口是全局功能
            "clearAllTagFilters", // Command+N - 清除所有标签筛选状态
        ]
    }
    
    /// Checks if a command is a global command
    /// - Parameter command: Command identifier to check
    /// - Returns: True if it's a global command
    func isGlobalCommand(_ command: String) -> Bool {
        return Commands.globalCommands.contains(command)
    }
}

// MARK: - Window-Level Event Management Extension

extension KeyboardEventManager {
    
    /// Registers a window for event management
    /// - Parameters:
    ///   - windowId: Unique identifier for the window
    ///   - windowType: Type of the window
    func registerWindow(_ windowId: UUID, type: WindowType) {
        windowCommandStates[windowId] = WindowCommandState(
            windowId: windowId,
            windowType: type,
            activeCommands: Set<String>(),
            commandExecutionState: [:],
            isEnabled: true,
            lastFocusTime: Date()
        )
        
        print("⌨️ KeyboardEventManager: 注册窗口事件管理 - \(type.displayName)")
    }
    
    /// Unregisters a window from event management
    /// - Parameter windowId: Window identifier to unregister
    func unregisterWindow(_ windowId: UUID) {
        if let windowState = windowCommandStates.removeValue(forKey: windowId) {
            print("⌨️ KeyboardEventManager: 取消注册窗口事件管理 - \(windowState.windowType.displayName)")
        }
        
        // If this was the active window, clear the context
        if activeWindowContext == windowId {
            activeWindowContext = nil
        }
    }
    
    /// Sets the active window context
    /// - Parameter windowId: Window identifier to set as active
    func setActiveWindowContext(_ windowId: UUID?) {
        let previousContext = activeWindowContext
        activeWindowContext = windowId
        
        // Update last focus time for the window
        if let windowId = windowId {
            windowCommandStates[windowId]?.lastFocusTime = Date()
        }
        
        // Post notification about window context change
        let userInfo: [String: Any] = [
            "previousWindowId": previousContext?.uuidString ?? "nil",
            "currentWindowId": windowId?.uuidString ?? "nil"
        ]
        NotificationCenter.default.post(
            name: NSNotification.Name("KeyboardEventManager.WindowContextChanged"),
            object: self,
            userInfo: userInfo
        )
        
        print("⌨️ KeyboardEventManager: 活跃窗口上下文变更: \(previousContext?.uuidString.prefix(8) ?? "nil") -> \(windowId?.uuidString.prefix(8) ?? "nil")")
    }
    
    /// Checks if a command can be executed in a specific window context
    /// - Parameters:
    ///   - command: Command identifier
    ///   - windowId: Window identifier (if nil, uses active window)
    /// - Returns: True if command can be executed
    func canExecuteCommand(_ command: String, in windowId: UUID? = nil) -> Bool {
        let targetWindowId = windowId ?? activeWindowContext
        
        guard let targetId = targetWindowId,
              let windowState = windowCommandStates[targetId],
              windowState.isEnabled else {
            return canExecuteCommand(command) // Fall back to global check
        }
        
        // Check window-specific state
        return commandQueue.sync {
            // Global checks first
            guard canExecuteCommand(command) else { return false }
            
            // Window-specific checks
            guard !windowState.activeCommands.contains(command) else {
                recordCommandAttempt(command, result: .blockedByActiveState, windowId: targetId)
                return false
            }
            
            // Window-specific cooldown check
            if let lastExecution = windowState.commandExecutionState[command] {
                let timeSinceLastExecution = Date().timeIntervalSince(lastExecution)
                if timeSinceLastExecution <= commandCooldown {
                    recordCommandAttempt(command, result: .blockedByCooldown, windowId: targetId)
                    return false
                }
            }
            
            return true
        }
    }
    
    /// Marks a command as executed in a specific window context
    /// - Parameters:
    ///   - command: Command identifier
    ///   - windowId: Window identifier (if nil, uses active window)
    func markCommandExecuted(_ command: String, in windowId: UUID? = nil) {
        let targetWindowId = windowId ?? activeWindowContext
        
        // Always mark global execution
        markCommandExecuted(command)
        
        // Mark window-specific execution
        guard let targetId = targetWindowId else { return }
        
        commandQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.windowCommandStates[targetId]?.activeCommands.insert(command)
                self.windowCommandStates[targetId]?.commandExecutionState[command] = Date()
                
                // Schedule removal from window-specific active commands
                DispatchQueue.main.asyncAfter(deadline: .now() + self.commandCooldown) {
                    self.windowCommandStates[targetId]?.activeCommands.remove(command)
                }
            }
        }
    }
    
    /// Marks a command as failed in a specific window context
    /// - Parameters:
    ///   - command: Command identifier
    ///   - error: Error that occurred
    ///   - windowId: Window identifier (if nil, uses active window)
    func markCommandFailed(_ command: String, error: KeyboardError, in windowId: UUID? = nil) {
        let targetWindowId = windowId ?? activeWindowContext
        
        // Always mark global failure
        markCommandFailed(command, error: error)
        
        // Mark window-specific failure
        guard let targetId = targetWindowId else { return }
        
        commandQueue.async { [weak self] in
            DispatchQueue.main.async {
                self?.windowCommandStates[targetId]?.activeCommands.remove(command)
            }
        }
    }
    
    /// Enables or disables event management for a specific window
    /// - Parameters:
    ///   - enabled: Whether to enable event management
    ///   - windowId: Window identifier
    func setWindowEventManagementEnabled(_ enabled: Bool, for windowId: UUID) {
        windowCommandStates[windowId]?.isEnabled = enabled
        
        print("⌨️ KeyboardEventManager: 窗口事件管理状态变更 (\(windowId.uuidString.prefix(8))): \(enabled ? "启用" : "禁用")")
    }
    
    /// Gets window-specific debug information
    /// - Parameter windowId: Window identifier
    /// - Returns: Window command state if available
    func getWindowCommandState(_ windowId: UUID) -> WindowCommandState? {
        return windowCommandStates[windowId]
    }
    
    /// Gets all window command states for debugging
    /// - Returns: Dictionary of window states
    func getAllWindowCommandStates() -> [UUID: WindowCommandState] {
        return windowCommandStates
    }
    
    /// Sets up integration with WindowFocusManager
    private func setupFocusManagerIntegration() {
        // Listen for window focus changes
        focusManagerObserver = NotificationCenter.default
            .publisher(for: NSNotification.Name("windowFocusChanged"))
            .sink { [weak self] notification in
                if let windowInfo = notification.object as? WindowInfo {
                    // Convert String ID to UUID if possible, otherwise skip
                    if let uuid = UUID(uuidString: windowInfo.id) {
                        self?.setActiveWindowContext(uuid)
                    }
                }
            }
    }
    
    /// Enhanced command attempt recording with window context
    /// - Parameters:
    ///   - command: Command identifier
    ///   - result: Attempt result
    ///   - windowId: Window identifier (optional)
    private func recordCommandAttempt(_ command: String, result: CommandAttemptResult, windowId: UUID? = nil) {
        let attempt = CommandExecution(
            command: command,
            timestamp: Date(),
            success: result == .allowed,
            result: result,
            windowId: windowId
        )
        
        executionHistory.append(attempt)
        
        // Keep history size manageable
        if executionHistory.count > maxHistorySize {
            executionHistory.removeFirst(executionHistory.count - maxHistorySize)
        }
    }
}

// MARK: - Window Command State

/// Represents command state for a specific window
struct WindowCommandState {
    let windowId: UUID
    let windowType: WindowType
    var activeCommands: Set<String>
    var commandExecutionState: [String: Date]
    var isEnabled: Bool
    var lastFocusTime: Date
    
    init(windowId: UUID, windowType: WindowType, activeCommands: Set<String>, commandExecutionState: [String: Date], isEnabled: Bool, lastFocusTime: Date) {
        self.windowId = windowId
        self.windowType = windowType
        self.activeCommands = activeCommands
        self.commandExecutionState = commandExecutionState
        self.isEnabled = isEnabled
        self.lastFocusTime = lastFocusTime
    }
}

