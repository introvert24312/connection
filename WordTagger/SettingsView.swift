import SwiftUI
import CoreLocation
import MapKit
import UniformTypeIdentifiers

// MARK: - Git自动同步管理器

public final class GitAutoSyncManager: ObservableObject, @unchecked Sendable {
    private var autoSyncTimer: Timer?
    private var isMonitoring = false
    private var pendingSync = false
    private var lastConfigCheck: Date?
    private var configCheckTimer: Timer?
    private var isCurrentlySyncing = false  // 防止重入
    private var lastSyncAttempt: Date?
    
    public static let shared = GitAutoSyncManager()
    
    private init() {}
    
    // 添加公共属性用于状态检查
    public var monitoringStatus: (isMonitoring: Bool, isConfigured: Bool, autoSyncEnabled: Bool) {
        let userDefaults = UserDefaults.standard
        let isGitEnabled = userDefaults.bool(forKey: "WordTagger_GitEnabled")
        let autoSyncEnabled = userDefaults.object(forKey: "WordTagger_AutoSyncEnabled") as? Bool ?? true
        return (isMonitoring, isGitEnabled, autoSyncEnabled)
    }
    
    public func startMonitoring(force: Bool = false) {
        let timestamp = Date()
        print("🔧 GitAutoSyncManager.startMonitoring() 被调用 [\(timestamp)]")
        
        if isMonitoring && !force {
            print("🔧 GitAutoSyncManager: 已在监听中，跳过重复启动 (使用force=true强制重启)")
            return
        }
        
        // 打印详细的配置状态
        let userDefaults = UserDefaults.standard
        let isGitEnabled = userDefaults.bool(forKey: "WordTagger_GitEnabled")
        let autoSyncEnabled = userDefaults.object(forKey: "WordTagger_AutoSyncEnabled") as? Bool ?? true
        let gitRemoteURL = userDefaults.string(forKey: "WordTagger_GitRemoteURL") ?? ""
        let gitBranch = userDefaults.string(forKey: "WordTagger_GitBranch") ?? ""
        let gitUsername = userDefaults.string(forKey: "WordTagger_GitUsername") ?? ""
        let gitToken = userDefaults.string(forKey: "WordTagger_GitToken") ?? ""
        
        print("🔍 GitAutoSyncManager: 详细配置状态检查")
        print("   - isGitEnabled: \(isGitEnabled)")
        print("   - autoSyncEnabled: \(autoSyncEnabled)")
        print("   - gitRemoteURL: '\(gitRemoteURL)'")
        print("   - gitBranch: '\(gitBranch)'")
        print("   - gitUsername: '\(gitUsername.isEmpty ? "未设置" : "已设置")'")
        let tokenStatus = gitToken.isEmpty ? "未设置" : "已设置(\(gitToken.count)字符)"
        print("   - gitToken: '\(tokenStatus)'")
        // 异步获取外部数据路径信息
        Task { @MainActor in
            let dataPath = ExternalDataManager.shared.currentDataPath
            let isDataPathSelected = ExternalDataManager.shared.isDataPathSelected
            
            print("   - 外部数据路径: \(dataPath?.path ?? "未设置")")
            print("   - 完整Git配置: \(isGitEnabled && !gitRemoteURL.isEmpty && !gitUsername.isEmpty && !gitToken.isEmpty && isDataPathSelected)")
            
            guard isGitEnabled else {
                print("❌ Git自动同步: Git未启用，停止监听")
                self.stopMonitoring()
                return
            }
            
            guard autoSyncEnabled else {
                print("❌ Git自动同步: 自动同步未启用，停止监听") 
                self.stopMonitoring()
                return
            }
            
            guard !gitRemoteURL.isEmpty else {
                print("❌ Git自动同步: 远程URL为空，停止监听")
                self.stopMonitoring()
                return
            }
            
            guard !gitUsername.isEmpty else {
                print("❌ Git自动同步: GitHub用户名为空，停止监听")
                self.stopMonitoring()
                return
            }
            
            guard !gitToken.isEmpty else {
                print("❌ Git自动同步: GitHub Token为空，停止监听")
                self.stopMonitoring()
                return
            }
            
            guard isDataPathSelected else {
                print("❌ Git自动同步: 外部数据路径未设置，停止监听")
                self.stopMonitoring()
                return
            }
            
            // 配置验证通过，启动监听
            self.isMonitoring = true
            self.lastConfigCheck = timestamp
            print("✅ GitAutoSyncManager: 启动监听 [\(timestamp)]")
            print("🔧 当前Git配置完整性验证通过: enabled=\(isGitEnabled), autoSync=\(autoSyncEnabled), url=已设置, auth=已设置, dataPath=已设置")
            
            // 移除之前的观察者（防止重复）
            NotificationCenter.default.removeObserver(self)
            self.setupNotificationObservers()
            
            // 启动配置检查定时器（每30秒检查一次配置变化）
            self.startConfigMonitoring()
            
            print("✅ Git自动同步监听已启动，监听通知: nodeUpdated, nodesUpdated, tagTypeNameChanged, compoundNodeRefreshed, ExternalDataPathChanged")
        }
    }
    
    private func setupNotificationObservers() {
        // 监听节点更新通知
        NotificationCenter.default.addObserver(
            forName: Notification.Name("nodeUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            print("📝 GitAutoSyncManager: 检测到节点更新通知 [\(Date())]")
            if let node = notification.object as? Node {
                print("📝 更新的节点: '\(node.text)'")
            } else if notification.object == nil {
                print("📝 节点删除通知 (object=nil)")
            } else {
                print("📝 通知对象类型: \(type(of: notification.object))")
            }
            self?.scheduleAutoSync(reason: "节点更新")
        }
        
        // 监听批量节点更新通知
        NotificationCenter.default.addObserver(
            forName: Notification.Name("nodesUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            print("📝 GitAutoSyncManager: 检测到批量节点更新通知 [\(Date())]")
            if let userInfo = notification.userInfo {
                print("📝 更新信息: \(userInfo)")
            }
            self?.scheduleAutoSync(reason: "批量节点更新")
        }
        
        // 监听标签类型更改通知
        NotificationCenter.default.addObserver(
            forName: Notification.Name("tagTypeNameChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📝 GitAutoSyncManager: 检测到标签类型更改通知 [\(Date())]")
            self?.scheduleAutoSync(reason: "标签类型更改")
        }
        
        // 监听复合节点刷新通知
        NotificationCenter.default.addObserver(
            forName: Notification.Name("compoundNodeRefreshed"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📝 GitAutoSyncManager: 检测到复合节点刷新通知 [\(Date())]")
            self?.scheduleAutoSync(reason: "复合节点刷新")
        }
        
        // 监听外部数据路径变化通知
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ExternalDataPathChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📝 GitAutoSyncManager: 检测到外部数据路径变化通知 [\(Date())]")
            self?.scheduleAutoSync(reason: "外部数据路径变化")
        }
    }
    
    private func startConfigMonitoring() {
        configCheckTimer?.invalidate()
        configCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.checkConfigurationChanges()
        }
        print("🔄 GitAutoSyncManager: 配置监控定时器已启动 (每30秒检查)")
    }
    
    private func checkConfigurationChanges() {
        let userDefaults = UserDefaults.standard
        let isGitEnabled = userDefaults.bool(forKey: "WordTagger_GitEnabled")
        let autoSyncEnabled = userDefaults.object(forKey: "WordTagger_AutoSyncEnabled") as? Bool ?? true
        let gitRemoteURL = userDefaults.string(forKey: "WordTagger_GitRemoteURL") ?? ""
        let gitUsername = userDefaults.string(forKey: "WordTagger_GitUsername") ?? ""
        let gitToken = userDefaults.string(forKey: "WordTagger_GitToken") ?? ""
        
        Task { @MainActor in
            let hasDataPath = ExternalDataManager.shared.isDataPathSelected
            let isFullyConfigured = isGitEnabled && autoSyncEnabled && !gitRemoteURL.isEmpty && !gitUsername.isEmpty && !gitToken.isEmpty && hasDataPath
            
            if self.isMonitoring && !isFullyConfigured {
                print("⚠️ GitAutoSyncManager: 配置不完整，停止监听")
                print("   - Git启用: \(isGitEnabled)")
                print("   - 自动同步: \(autoSyncEnabled)")
                print("   - URL设置: \(!gitRemoteURL.isEmpty)")
                print("   - 用户名设置: \(!gitUsername.isEmpty)")
                print("   - Token设置: \(!gitToken.isEmpty)")
                print("   - 数据路径设置: \(hasDataPath)")
                self.stopMonitoring()
            } else if !self.isMonitoring && isFullyConfigured {
                print("🔄 GitAutoSyncManager: 配置已完整，重新启动监听")
                self.startMonitoring()
            }
        }
    }
    
    public func stopMonitoring() {
        guard isMonitoring else { 
            print("🔧 GitAutoSyncManager: 已经停止监听，无需重复操作")
            return 
        }
        
        isMonitoring = false
        pendingSync = false
        isCurrentlySyncing = false  // 重置同步状态
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
        configCheckTimer?.invalidate()
        configCheckTimer = nil
        NotificationCenter.default.removeObserver(self)
        lastConfigCheck = nil
        lastSyncAttempt = nil
        
        // 如果GitSyncStatusManager还在工作状态，强制停止
        Task { @MainActor in
            if GitSyncStatusManager.shared.isWorking {
                print("🔧 GitAutoSyncManager: 强制停止GitSyncStatusManager工作状态")
                GitSyncStatusManager.shared.finishWorking(
                    success: false,
                    finalStatus: "自动同步已停止"
                )
            }
        }
        
        print("🔧 GitAutoSyncManager: 已停止Git自动同步监听 [\(Date())]")
    }
    
    private func scheduleAutoSync(reason: String = "未知原因") {
        let timestamp = Date()
        print("📝 GitAutoSyncManager.scheduleAutoSync() 被调用 - 原因: \(reason) [\(timestamp)]")
        
        guard isMonitoring else {
            print("⚠️ GitAutoSyncManager: 未在监听状态，跳过同步调度 - 原因: \(reason)")
            return
        }
        
        // 再次验证配置
        let userDefaults = UserDefaults.standard
        let isGitEnabled = userDefaults.bool(forKey: "WordTagger_GitEnabled")
        let autoSyncEnabled = userDefaults.object(forKey: "WordTagger_AutoSyncEnabled") as? Bool ?? true
        let gitRemoteURL = userDefaults.string(forKey: "WordTagger_GitRemoteURL") ?? ""
        let gitUsername = userDefaults.string(forKey: "WordTagger_GitUsername") ?? ""
        let gitToken = userDefaults.string(forKey: "WordTagger_GitToken") ?? ""
        
        Task { @MainActor in
            let hasDataPath = ExternalDataManager.shared.isDataPathSelected
            let isFullyConfigured = isGitEnabled && autoSyncEnabled && !gitRemoteURL.isEmpty && !gitUsername.isEmpty && !gitToken.isEmpty && hasDataPath
            
            guard isFullyConfigured else {
                print("⚠️ GitAutoSyncManager: 配置检查失败，停止同步调度 - 原因: \(reason)")
                print("   - Git启用: \(isGitEnabled)")
                print("   - 自动同步启用: \(autoSyncEnabled)")
                print("   - URL设置: \(!gitRemoteURL.isEmpty)")
                print("   - 用户名设置: \(!gitUsername.isEmpty)")
                print("   - Token设置: \(!gitToken.isEmpty)")
                print("   - 数据路径设置: \(hasDataPath)")
                return
            }
            
            guard !self.pendingSync else {
                print("📝 GitAutoSyncManager: 已有待执行的同步，刷新计时器 - 原因: \(reason)")
                self.autoSyncTimer?.invalidate()
                self.autoSyncTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                    self?.performAutoSync(triggeredBy: reason)
                }
                return
            }
            
            print("📝 GitAutoSyncManager: 安排5秒后自动同步 - 原因: \(reason)")
            self.pendingSync = true
            
            // 防止频繁同步，延迟5秒执行
            self.autoSyncTimer?.invalidate()
            self.autoSyncTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] timer in
                print("⏰ GitAutoSyncManager: 定时器触发，执行自动同步 - 原因: \(reason)")
                self?.performAutoSync(triggeredBy: reason)
                timer.invalidate()
            }
        }
    }
    
    private func performAutoSync(triggeredBy reason: String = "未知原因") {
        let timestamp = Date()
        print("🔄 GitAutoSyncManager.performAutoSync() 开始 - 触发原因: \(reason) [\(timestamp)]")
        
        guard isMonitoring else {
            print("⚠️ GitAutoSyncManager: 监听已停止，取消自动同步 - 触发原因: \(reason)")
            pendingSync = false
            return
        }
        
        // 防重入保护
        guard !isCurrentlySyncing else {
            print("⚠️ GitAutoSyncManager: 已有同步在进行中，忽略新的同步请求 - 触发原因: \(reason)")
            pendingSync = false
            return
        }
        
        // 防止频繁同步（至少间隔10秒）
        if let lastAttempt = lastSyncAttempt, Date().timeIntervalSince(lastAttempt) < 10 {
            print("⚠️ GitAutoSyncManager: 距上次同步不足10秒，跳过 - 触发原因: \(reason)")
            pendingSync = false
            return
        }
        
        pendingSync = false
        isCurrentlySyncing = true
        lastSyncAttempt = Date()
        
        // 重新验证配置
        let userDefaults = UserDefaults.standard
        let isGitEnabled = userDefaults.bool(forKey: "WordTagger_GitEnabled")
        let autoSyncEnabled = userDefaults.object(forKey: "WordTagger_AutoSyncEnabled") as? Bool ?? true
        let gitRemoteURL = userDefaults.string(forKey: "WordTagger_GitRemoteURL") ?? ""
        
        print("🔍 GitAutoSyncManager: 执行前配置验证")
        print("   - isGitEnabled: \(isGitEnabled)")
        print("   - autoSyncEnabled: \(autoSyncEnabled)")
        print("   - gitRemoteURL: '\(gitRemoteURL)'")
        
        guard isGitEnabled && autoSyncEnabled else {
            print("❌ GitAutoSyncManager: Git配置已变更，停止自动同步 - Git启用: \(isGitEnabled), 自动同步: \(autoSyncEnabled)")
            isCurrentlySyncing = false
            return
        }
        
        guard !gitRemoteURL.isEmpty else {
            print("❌ GitAutoSyncManager: 远程URL为空，无法执行同步")
            isCurrentlySyncing = false
            return
        }
        
        // 创建一个临时的GitSyncHelper来执行同步
        Task { @MainActor in
            defer {
                // 无论成功失败都要重置同步状态
                self.isCurrentlySyncing = false
                print("🔧 GitAutoSyncManager: 重置同步状态 isCurrentlySyncing = false")
            }
            
            do {
                // 启动同步状态指示器
                GitSyncStatusManager.shared.startWorking(operation: "自动同步中...")
                print("🔧 GitAutoSyncManager: 已启动状态指示器")
                
                print("🚀 GitAutoSyncManager: 创建GitSyncHelper并开始同步...")
                let helper = GitSyncHelper()
                
                // 添加超时保护
                let syncTask = Task {
                    try await helper.performSync()
                }
                
                // 等待同步完成或超时（60秒）
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await syncTask.value
                    }
                    
                    group.addTask {
                        try await Task.sleep(nanoseconds: 60_000_000_000) // 60秒
                        throw GitSyncError.commandFailed("timeout", "同步操作超时")
                    }
                    
                    try await group.next()
                    group.cancelAll()
                }
                
                print("✅ GitAutoSyncManager: 自动同步完成 - 触发原因: \(reason) [\(Date())]")
                
                // 更新状态管理器
                let newCount = userDefaults.integer(forKey: "WordTagger_TotalSyncCount") + 1
                userDefaults.set(Date(), forKey: "WordTagger_LastGitSync")
                userDefaults.set(newCount, forKey: "WordTagger_TotalSyncCount")
                
                GitSyncStatusManager.shared.finishWorking(
                    success: true, 
                    finalStatus: "自动同步完成"
                )
                print("📊 GitAutoSyncManager: 同步完成，状态指示器已停止 - 总同步次数: \(newCount)")
                
            } catch {
                print("❌ GitAutoSyncManager: 自动同步失败 - 触发原因: \(reason), 错误: \(error)")
                
                // 更新错误状态并停止工作指示器
                GitSyncStatusManager.shared.finishWorking(
                    success: false,
                    finalStatus: "自动同步失败",
                    error: "自动同步失败 (\(reason)): \(error.localizedDescription)"
                )
            }
        }
    }
    
    // 紧急重置方法 - 强制停止所有同步操作并重置状态
    public func emergencyReset() {
        print("🚨 GitAutoSyncManager: 执行紧急重置")
        isCurrentlySyncing = false
        pendingSync = false
        lastSyncAttempt = nil
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
        
        Task { @MainActor in
            if GitSyncStatusManager.shared.isWorking {
                GitSyncStatusManager.shared.finishWorking(
                    success: false,
                    finalStatus: "同步已重置"
                )
            }
        }
        print("✅ GitAutoSyncManager: 紧急重置完成")
    }
    
    // 添加公共方法用于调试和状态检查
    public func debugStatus() {
        let userDefaults = UserDefaults.standard
        let isGitEnabled = userDefaults.bool(forKey: "WordTagger_GitEnabled")
        let autoSyncEnabled = userDefaults.object(forKey: "WordTagger_AutoSyncEnabled") as? Bool ?? true
        let gitRemoteURL = userDefaults.string(forKey: "WordTagger_GitRemoteURL") ?? ""
        let gitBranch = userDefaults.string(forKey: "WordTagger_GitBranch") ?? ""
        let gitUsername = userDefaults.string(forKey: "WordTagger_GitUsername") ?? ""
        let gitToken = userDefaults.string(forKey: "WordTagger_GitToken") ?? ""
        
        Task { @MainActor in
            let hasDataPath = ExternalDataManager.shared.isDataPathSelected
            let isFullyConfigured = isGitEnabled && autoSyncEnabled && !gitRemoteURL.isEmpty && !gitUsername.isEmpty && !gitToken.isEmpty && hasDataPath
            
            print("🔍 === GitAutoSyncManager 状态诊断 [\(Date())] ===")
            print("   监听状态: \(self.isMonitoring ? "✅ 监听中" : "❌ 未监听")")
            print("   同步状态: \(self.isCurrentlySyncing ? "🔄 正在同步" : "✅ 空闲")")
            print("   待同步状态: \(self.pendingSync ? "⏳ 有待执行同步" : "✅ 无待执行同步")")
            print("   上次同步尝试: \(self.lastSyncAttempt?.description ?? "无")")
            print("   Git启用: \(isGitEnabled ? "✅ 已启用" : "❌ 未启用")")
            print("   自动同步启用: \(autoSyncEnabled ? "✅ 已启用" : "❌ 未启用")")
            print("   远程URL: \(gitRemoteURL.isEmpty ? "❌ 空" : "✅ 已设置")")
            print("   分支: \(gitBranch.isEmpty ? "❌ 空" : "✅ \(gitBranch)")")
            print("   GitHub用户名: \(gitUsername.isEmpty ? "❌ 未设置" : "✅ 已设置")")
            print("   GitHub Token: \(gitToken.isEmpty ? "❌ 未设置" : "✅ 已设置(\(gitToken.count)字符)")")
            print("   外部数据路径: \(hasDataPath ? "✅ 已设置" : "❌ 未设置")")
            print("   配置完整性: \(isFullyConfigured ? "✅ 完整" : "❌ 不完整")")
            print("   最后配置检查: \(self.lastConfigCheck?.description ?? "无")")
            print("   定时器状态: 自动同步=\(self.autoSyncTimer != nil ? "运行中" : "停止"), 配置检查=\(self.configCheckTimer != nil ? "运行中" : "停止")")
            print("   GitSyncStatusManager工作状态: \(GitSyncStatusManager.shared.isWorking ? "🔄 工作中" : "✅ 空闲")")
            print("🔍 =====================================")
        }
    }
}

// MARK: - Git同步助手

class GitSyncHelper {
    func performSync() async throws {
        print("🔄 GitSyncHelper: 开始执行Git同步")
        
        let userDefaults = UserDefaults.standard
        let remoteURL = userDefaults.string(forKey: "WordTagger_GitRemoteURL") ?? ""
        let username = userDefaults.string(forKey: "WordTagger_GitUsername") ?? ""
        let token = userDefaults.string(forKey: "WordTagger_GitToken") ?? ""
        
        print("🔄 GitSyncHelper: 配置检查")
        print("   - remoteURL: \(remoteURL.isEmpty ? "空" : "已设置")")
        print("   - username: \(username.isEmpty ? "空" : "已设置")")
        print("   - token: \(token.isEmpty ? "空" : "已设置(\(token.count)字符)")")
        
        guard !remoteURL.isEmpty && !username.isEmpty && !token.isEmpty else {
            print("❌ GitSyncHelper: Git配置不完整")
            throw GitSyncError.configurationMissing
        }
        
        guard let dataPath = await ExternalDataManager.shared.currentDataPath else {
            print("❌ GitSyncHelper: 数据路径未设置")
            throw GitSyncError.dataPathNotSet
        }
        
        print("🔄 GitSyncHelper: 数据路径: \(dataPath.path)")
        
        // 执行Git同步操作
        try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    print("🔄 GitSyncHelper: 添加文件到Git暂存区")
                    let _ = try await runGitCommand(["add", "."], at: dataPath)
                    
                    print("🔄 GitSyncHelper: 检查Git状态")
                    let statusResult = try await runGitCommand(["status", "--porcelain"], at: dataPath)
                    
                    if statusResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        print("📝 GitSyncHelper: 没有数据变化，跳过同步")
                        continuation.resume()
                        return
                    }
                    
                    print("🔄 GitSyncHelper: 发现变化，创建提交")
                    // 提交变化
                    let commitMessage = "Auto-sync: \(Date().formatted())"
                    let _ = try await runGitCommand(["commit", "-m", commitMessage], at: dataPath)
                    
                    print("🔄 GitSyncHelper: 推送到远程仓库")
                    // 构建带认证的URL进行推送
                    let authenticatedURL = buildAuthenticatedURL(cleanURL: remoteURL, username: username, token: token)
                    
                    // 设置远程URL（带认证）
                    let _ = try await runGitCommand(["remote", "set-url", "origin", authenticatedURL], at: dataPath)
                    
                    // 推送到远程
                    let _ = try await runGitCommand(["push", "origin", "HEAD"], at: dataPath)
                    
                    print("✅ GitSyncHelper: 同步完成，更新记录")
                    // 更新同步记录
                    userDefaults.set(Date(), forKey: "WordTagger_LastGitSync")
                    let currentCount = userDefaults.integer(forKey: "WordTagger_TotalSyncCount")
                    userDefaults.set(currentCount + 1, forKey: "WordTagger_TotalSyncCount")
                    
                    continuation.resume()
                } catch {
                    print("❌ GitSyncHelper: 同步失败: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func runGitCommand(_ arguments: [String], at workingDirectory: URL) async throws -> String {
        // 查找Git路径
        guard let gitPath = findGitPath() else {
            print("❌ GitSyncHelper: Git可执行文件未找到")
            throw GitSyncError.gitNotFound
        }
        
        print("🔄 GitSyncHelper: 执行Git命令: \(gitPath) \(arguments.joined(separator: " "))")
        print("🔄 GitSyncHelper: 工作目录: \(workingDirectory.path)")
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: gitPath)
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            
            // 设置环境变量
            var environment: [String: String] = [:]
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin"
            environment["GIT_TERMINAL_PROMPT"] = "0" // 禁用交互式提示
            environment["GIT_CONFIG_NOSYSTEM"] = "1" // 避免读取系统Git配置
            environment["GIT_CONFIG_GLOBAL"] = "/dev/null" // 避免读取全局Git配置
            environment["HOME"] = NSHomeDirectory() // 确保HOME路径正确
            environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            process.environment = environment
            
            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe
            
            process.terminationHandler = { process in
                let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                
                print("🔄 GitSyncHelper: Git命令退出状态: \(process.terminationStatus)")
                if !output.isEmpty {
                    print("🔄 GitSyncHelper: Git标准输出: \(output)")
                }
                if !errorOutput.isEmpty {
                    print("🔄 GitSyncHelper: Git错误输出: \(errorOutput)")
                }
                
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let fullError = errorOutput.isEmpty ? "命令执行失败" : errorOutput
                    continuation.resume(throwing: GitSyncError.commandFailed(arguments.joined(separator: " "), fullError))
                }
            }
            
            do {
                try process.run()
            } catch {
                print("❌ GitSyncHelper: Git命令执行异常: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func findGitPath() -> String? {
        let possiblePaths = [
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git", 
            "/usr/bin/git"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                print("✅ GitSyncHelper: 找到Git: \(path)")
                return path
            }
        }
        
        print("❌ GitSyncHelper: 未找到Git可执行文件")
        return nil
    }
    
    private func buildAuthenticatedURL(cleanURL: String, username: String, token: String) -> String {
        // 如果URL已经包含认证信息，直接返回
        if cleanURL.contains("@") {
            return cleanURL
        }
        
        // GitHub标准认证：https://token@github.com/user/repo.git
        if !token.isEmpty {
            let authenticatedURL = cleanURL.replacingOccurrences(of: "https://", with: "https://\(token)@")
            print("🔄 GitSyncHelper: 构建认证URL（Token认证）")
            return authenticatedURL
        }
        
        return cleanURL
    }
}

enum GitSyncError: Error {
    case configurationMissing
    case dataPathNotSet
    case gitNotFound
    case commandFailed(String, String)
}

// MARK: - GitHub同步状态管理器

@MainActor
public class GitSyncStatusManager: ObservableObject {
    @Published public var isEnabled: Bool = false
    @Published public var isWorking: Bool = false
    @Published public var status: String = "未配置"
    @Published public var lastSyncTime: Date?
    @Published public var lastError: String?
    @Published public var totalSyncCount: Int = 0
    
    public static let shared = GitSyncStatusManager()
    
    private init() {
        loadStatus()
    }
    
    // MARK: - 状态更新
    
    public func updateStatus(
        isEnabled: Bool? = nil,
        isWorking: Bool? = nil,
        status: String? = nil,
        lastSyncTime: Date? = nil,
        lastError: String? = nil,
        totalSyncCount: Int? = nil
    ) {
        if let isEnabled = isEnabled { self.isEnabled = isEnabled }
        if let isWorking = isWorking { self.isWorking = isWorking }
        if let status = status { self.status = status }
        if let lastSyncTime = lastSyncTime { self.lastSyncTime = lastSyncTime }
        if let lastError = lastError { self.lastError = lastError }
        if let totalSyncCount = totalSyncCount { self.totalSyncCount = totalSyncCount }
        
        saveStatus()
        
        print("🔄 GitSyncStatusManager状态更新:")
        print("   - isEnabled: \(self.isEnabled)")
        print("   - isWorking: \(self.isWorking)")
        print("   - status: \(self.status)")
        print("   - totalSyncCount: \(self.totalSyncCount)")
    }
    
    public func startWorking(operation: String) {
        isWorking = true
        status = operation
        lastError = nil
        print("🟡 GitHub同步开始: \(operation)")
    }
    
    public func finishWorking(success: Bool, finalStatus: String, error: String? = nil) {
        isWorking = false
        status = finalStatus
        if success {
            lastSyncTime = Date()
            totalSyncCount += 1
            lastError = nil
            print("🟢 GitHub同步完成: \(finalStatus)")
        } else {
            lastError = error
            print("🔴 GitHub同步失败: \(error ?? "未知错误")")
        }
        saveStatus()
    }
    
    // MARK: - 状态计算
    
    public var statusColor: Color {
        if !isEnabled {
            return .secondary
        } else if isWorking {
            return .orange
        } else if lastError != nil {
            return .red
        } else {
            return .green
        }
    }
    
    public var statusIcon: String {
        if !isEnabled {
            return "externaldrive.badge.questionmark"
        } else if isWorking {
            return "externaldrive.badge.timemachine"
        } else if lastError != nil {
            return "externaldrive.badge.xmark"
        } else {
            return "externaldrive.badge.checkmark"
        }
    }
    
    public var displayStatus: String {
        if !isEnabled {
            return "GitHub同步未配置"
        } else if isWorking {
            return status
        } else if let error = lastError {
            return "同步错误: \(error)"
        } else {
            return "GitHub同步就绪"
        }
    }
    
    // MARK: - 持久化
    
    private func loadStatus() {
        let userDefaults = UserDefaults.standard
        isEnabled = userDefaults.bool(forKey: "GitSync_IsEnabled")
        status = userDefaults.string(forKey: "GitSync_Status") ?? "未配置"
        totalSyncCount = userDefaults.integer(forKey: "GitSync_TotalCount")
        
        if let lastSync = userDefaults.object(forKey: "GitSync_LastSyncTime") as? Date {
            lastSyncTime = lastSync
        }
        
        lastError = userDefaults.string(forKey: "GitSync_LastError")
    }
    
    private func saveStatus() {
        let userDefaults = UserDefaults.standard
        userDefaults.set(isEnabled, forKey: "GitSync_IsEnabled")
        userDefaults.set(status, forKey: "GitSync_Status")
        userDefaults.set(totalSyncCount, forKey: "GitSync_TotalCount")
        
        if let lastSync = lastSyncTime {
            userDefaults.set(lastSync, forKey: "GitSync_LastSyncTime")
        }
        
        userDefaults.set(lastError, forKey: "GitSync_LastError")
    }
}

// MARK: - GitHub同步状态指示器组件

struct GitSyncStatusIndicator: View {
    @StateObject private var statusManager = GitSyncStatusManager.shared
    @State private var showingTooltip = false
    
    var body: some View {
        HStack(spacing: 6) {
            // 状态圆点
            Circle()
                .fill(statusManager.statusColor)
                .frame(width: 8, height: 8)
                .scaleEffect(statusManager.isWorking ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), 
                          value: statusManager.isWorking)
            
            // 状态图标
            Image(systemName: statusManager.statusIcon)
                .font(.caption)
                .foregroundColor(statusManager.statusColor)
                .rotationEffect(.degrees(statusManager.isWorking ? 360 : 0))
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), 
                          value: statusManager.isWorking)
            
            // 状态文本（可选）
            if statusManager.isWorking {
                Text(statusManager.status)
                    .font(.caption2)
                    .foregroundColor(statusManager.statusColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusManager.statusColor.opacity(0.1))
        .cornerRadius(8)
        .onTapGesture {
            showingTooltip.toggle()
        }
        .help(statusManager.displayStatus)
        .popover(isPresented: $showingTooltip) {
            GitSyncStatusPopover()
        }
    }
}

// MARK: - 状态详情弹出框

struct GitSyncStatusPopover: View {
    @StateObject private var statusManager = GitSyncStatusManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack {
                Image(systemName: statusManager.statusIcon)
                    .foregroundColor(statusManager.statusColor)
                Text("GitHub同步状态")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("×") {
                    dismiss()
                }
                .font(.title2)
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // 当前状态
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle()
                        .fill(statusManager.statusColor)
                        .frame(width: 10, height: 10)
                    
                    Text(statusManager.displayStatus)
                        .font(.body)
                        .fontWeight(.medium)
                }
                
                if let lastSync = statusManager.lastSyncTime {
                    Text("上次同步: \(formatTime(lastSync))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if statusManager.totalSyncCount > 0 {
                    Text("总同步次数: \(statusManager.totalSyncCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // 快速操作
            if statusManager.isEnabled && !statusManager.isWorking {
                Divider()
                
                HStack {
                    Text("快速操作:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("打开设置") {
                        // 这里可以添加打开设置的逻辑
                        dismiss()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding()
        .frame(width: 250)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 紧凑状态指示器（用于工具栏）

struct CompactGitSyncIndicator: View {
    @StateObject private var statusManager = GitSyncStatusManager.shared
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusManager.statusColor)
                .frame(width: 6, height: 6)
                .scaleEffect(statusManager.isWorking ? 1.3 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), 
                          value: statusManager.isWorking)
            
            if statusManager.isEnabled {
                Text("\(statusManager.totalSyncCount)")
                    .font(.caption2)
                    .foregroundColor(statusManager.statusColor)
                    .fontWeight(.medium)
            }
        }
        .help(statusManager.displayStatus)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: NodeStore
    @AppStorage("searchThreshold") private var searchThreshold: Double = 0.3
    @AppStorage("enableDebugMode") private var enableDebugMode: Bool = false
    @AppStorage("maxSearchResults") private var maxSearchResults: Int = 50
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 30.0
    
    var body: some View {
        TabView {
            // 常规设置
            GeneralSettingsView()
                .tabItem {
                    Label("常规", systemImage: "gear")
                }
            
            // 搜索设置
            SearchSettingsView(
                searchThreshold: $searchThreshold,
                maxSearchResults: $maxSearchResults
            )
            .tabItem {
                Label("搜索", systemImage: "magnifyingglass")
            }
            
            // 层管理
            LayerManagementView()
                .tabItem {
                    Label("层管理", systemImage: "square.stack.3d.up")
                }
                .environmentObject(store)
            
            // 数据管理
            DataManagementView()
                .tabItem {
                    Label("数据", systemImage: "externaldrive")
                }
            
            // Git 同步
            GitSyncSettingsView()
                .tabItem {
                    Label("GitHub同步", systemImage: "externaldrive.connected.to.line.below")
                }
            
            // 关于
            AboutView()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - 常规设置

struct GeneralSettingsView: View {
    @AppStorage("enableDebugMode") private var enableDebugMode: Bool = false
    @AppStorage("enableGraphDebug") private var enableGraphDebug: Bool = false
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 30.0
    @AppStorage("showPhoneticByDefault") private var showPhoneticByDefault: Bool = true
    @AppStorage("globalGraphInitialScale") private var globalGraphInitialScale: Double = 1.0
    @AppStorage("detailGraphInitialScale") private var detailGraphInitialScale: Double = 1.0
    @AppStorage("fullscreenGraphInitialScale") private var fullscreenGraphInitialScale: Double = 1.0
    @AppStorage("layerStructureGraphInitialScale") private var layerStructureGraphInitialScale: Double = 0.9
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 界面设置
                GroupBox("界面设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "默认显示音标",
                            description: "在节点列表中自动显示音标信息"
                        ) {
                            Toggle("", isOn: $showPhoneticByDefault)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "全局图谱初始缩放",
                            description: "全局图谱窗口打开时的默认缩放级别"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(String(format: "%.1f", globalGraphInitialScale))x")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                
                                Slider(value: $globalGraphInitialScale, in: 0.5...3.0, step: 0.1)
                                    .frame(width: 120)
                            }
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "详情图谱初始缩放",
                            description: "节点详情图谱的默认缩放级别"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(String(format: "%.1f", detailGraphInitialScale))x")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                
                                Slider(value: $detailGraphInitialScale, in: 0.5...3.0, step: 0.1)
                                    .frame(width: 120)
                            }
                        }
                        
                        SettingRow(
                            title: "全屏图谱初始缩放",
                            description: "Command+D打开的全屏图谱默认缩放级别"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(String(format: "%.1f", fullscreenGraphInitialScale))x")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                
                                Slider(value: $fullscreenGraphInitialScale, in: 0.5...3.0, step: 0.1)
                                    .frame(width: 120)
                            }
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "层结构图谱初始缩放",
                            description: "命令面板中层结构图谱的默认缩放级别"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(String(format: "%.1f", layerStructureGraphInitialScale))x")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                
                                Slider(value: $layerStructureGraphInitialScale, in: 0.5...3.0, step: 0.1)
                                    .frame(width: 120)
                            }
                        }
                        
                        Divider()
                        
                        // 全局图谱选中状态管理
                        GlobalGraphSelectionSettingsView()
                    }
                    .padding(12)
                }
                
                // 性能设置
                GroupBox("性能设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "自动保存间隔",
                            description: "自动保存数据的时间间隔（秒）"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(Int(autoSaveInterval))秒")
                                    .foregroundColor(.secondary)
                                    .frame(width: 50, alignment: .trailing)
                                
                                Stepper("", 
                                       value: $autoSaveInterval, 
                                       in: 10...300, 
                                       step: 10)
                            }
                        }
                    }
                    .padding(12)
                }
                
                // 开发设置
                GroupBox("开发选项") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "调试模式",
                            description: "显示调试信息和性能指标"
                        ) {
                            Toggle("", isOn: $enableDebugMode)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "图谱调试信息",
                            description: "在WebView中显示图谱数据验证信息"
                        ) {
                            Toggle("", isOn: $enableGraphDebug)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        if enableGraphDebug {
                            Text("⚠️ 启用后会在图谱中显示详细的节点和边数据，用于调试数据传递问题")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.top, 4)
                        }
                    }
                    .padding(12)
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - 搜索设置

struct SearchSettingsView: View {
    @Binding var searchThreshold: Double
    @Binding var maxSearchResults: Int
    @AppStorage("enableFuzzySearch") private var enableFuzzySearch: Bool = true
    @AppStorage("searchInPhonetic") private var searchInPhonetic: Bool = true
    @AppStorage("searchInMeaning") private var searchInMeaning: Bool = true
    @AppStorage("searchInTags") private var searchInTags: Bool = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 搜索范围
                GroupBox("搜索范围") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "搜索音标",
                            description: "在音标字段中搜索匹配内容"
                        ) {
                            Toggle("", isOn: $searchInPhonetic)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "搜索含义",
                            description: "在节点含义中搜索匹配内容"
                        ) {
                            Toggle("", isOn: $searchInMeaning)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "搜索标签",
                            description: "在标签内容中搜索匹配内容"
                        ) {
                            Toggle("", isOn: $searchInTags)
                                .toggleStyle(SwitchToggleStyle())
                        }
                    }
                    .padding(12)
                }
                
                // 搜索算法
                GroupBox("搜索算法") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "模糊搜索",
                            description: "允许拼写错误和近似匹配"
                        ) {
                            Toggle("", isOn: $enableFuzzySearch)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        if enableFuzzySearch {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("匹配阈值")
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(String(format: "%.1f", searchThreshold))
                                        .foregroundColor(.secondary)
                                }
                                
                                Slider(value: $searchThreshold, in: 0.1...0.9, step: 0.1)
                                
                                Text("较低的值需要更精确的匹配")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(12)
                }
                
                // 结果限制
                GroupBox("结果设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "最大搜索结果",
                            description: "限制单次搜索返回的最大结果数量"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(maxSearchResults)")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                
                                Stepper("", 
                                       value: $maxSearchResults, 
                                       in: 10...200, 
                                       step: 10)
                            }
                        }
                    }
                    .padding(12)
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - 层管理

struct LayerManagementView: View {
    @EnvironmentObject private var store: NodeStore
    @State private var showingCreateLayerSheet = false
    @State private var showingDeleteAlert = false
    @State private var layerToDelete: Layer?
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部：当前活跃层状态条
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "target")
                        .foregroundColor(.blue)
                        .font(.body)
                    
                    Text("当前活跃层:")
                        .font(.body)
                        .fontWeight(.medium)
                    
                    if let currentLayer = store.currentLayer {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.from(currentLayer.color))
                                .frame(width: 12, height: 12)
                            
                            Text(currentLayer.displayName)
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("(\(currentLayer.name))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    } else {
                        Text("未选择")
                            .font(.body)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                
                Spacer()
                
                // 快速统计
                if store.currentLayer != nil {
                    HStack(spacing: 12) {
                        VStack(spacing: 2) {
                            Text("\(store.getNodesInCurrentLayer().count)")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                            Text("节点")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 2) {
                            Text("\(store.getNodesInCurrentLayer().count)")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            Text("节点")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 主内容区域
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 层管理区域
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("层管理")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Button(action: {
                                showingCreateLayerSheet = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("创建新层")
                                }
                                .font(.body)
                                .fontWeight(.medium)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                        
                        // 层列表
                        if store.layers.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "square.stack.3d.up")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray.opacity(0.6))
                                
                                VStack(spacing: 8) {
                                    Text("暂无层级")
                                        .font(.title3)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    
                                    Text("创建第一个层来开始组织您的节点和数据")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                
                                Button(action: {
                                    showingCreateLayerSheet = true
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                        Text("创建第一个层")
                                    }
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            )
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(store.sortedLayers, id: \.id) { layer in
                                    LayerRowView(
                                        layer: layer,
                                        wordCount: store.nodes.filter { $0.layerId == layer.id }.count,
                                        nodeCount: store.nodes.filter { $0.layerId == layer.id }.count,
                                        isActive: store.currentLayer?.id == layer.id,
                                        onActivate: {
                                            Task {
                                                await store.switchToLayer(layer)
                                            }
                                        },
                                        onDelete: {
                                            layerToDelete = layer
                                            showingDeleteAlert = true
                                        },
                                        onEdit: { newName in
                                            store.updateLayerDisplayName(layer: layer, newDisplayName: newName)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .sheet(isPresented: $showingCreateLayerSheet) {
            CreateLayerSheet()
                .environmentObject(store)
        }
        .alert("删除层", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {
                layerToDelete = nil
            }
            Button("删除", role: .destructive) {
                if let layer = layerToDelete {
                    store.deleteLayer(layer)
                    layerToDelete = nil
                }
            }
        } message: {
            if let layer = layerToDelete {
                let nodeCount = store.nodes.filter { $0.layerId == layer.id }.count
                Text("确定要删除层 \"\(layer.displayName)\" 吗？\n这将同时删除该层中的 \(nodeCount) 个节点，此操作无法撤销。")
            }
        }
    }
}

struct LayerRowView: View {
    let layer: Layer
    let wordCount: Int
    let nodeCount: Int
    let isActive: Bool
    let onActivate: () -> Void
    let onDelete: () -> Void
    let onEdit: (String) -> Void
    
    @State private var isEditing: Bool = false
    @State private var editingName: String = ""
    
    var body: some View {
        HStack(spacing: 16) {
            // 左侧：颜色指示器和状态
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.from(layer.color))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if isEditing {
                            TextField("层名称", text: $editingName)
                                .font(.headline)
                                .fontWeight(isActive ? .bold : .semibold)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    saveEdit()
                                }
                                .onAppear {
                                    editingName = layer.displayName
                                }
                        } else {
                            Text(layer.displayName)
                                .font(.headline)
                                .fontWeight(isActive ? .bold : .semibold)
                                .foregroundColor(.primary)
                        }
                        
                        if isActive {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                Text("活跃")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                    }
                    
                    Text(layer.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 中间：数据统计
            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    Text("\(wordCount)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("节点")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 2) {
                    Text("\(nodeCount)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("节点")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // 右侧：操作按钮
            HStack(spacing: 8) {
                if isEditing {
                    // 编辑模式下的按钮
                    Button(action: saveEdit) {
                        Image(systemName: "checkmark")
                            .font(.body)
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("保存")
                    
                    Button(action: cancelEdit) {
                        Image(systemName: "xmark")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("取消")
                } else {
                    // 正常模式下的按钮
                    if !isActive {
                        Button(action: onActivate) {
                            HStack(spacing: 4) {
                                Image(systemName: "target")
                                    .font(.caption)
                                Text("激活")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    
                    Button(action: startEdit) {
                        Image(systemName: "pencil")
                            .font(.body)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("编辑名称")
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.body)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("删除层")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.blue.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isActive ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1.5)
                )
        )
        .shadow(color: isActive ? Color.blue.opacity(0.1) : Color.clear, radius: 4, x: 0, y: 2)
    }
    
    private func startEdit() {
        isEditing = true
        editingName = layer.displayName
    }
    
    private func saveEdit() {
        let trimmedName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && trimmedName != layer.displayName {
            onEdit(trimmedName)
        }
        isEditing = false
    }
    
    private func cancelEdit() {
        isEditing = false
        editingName = layer.displayName
    }
}

struct CreateLayerSheet: View {
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var displayName: String = ""
    @State private var selectedColor: String = "blue"
    
    let availableColors = [
        ("blue", Color.blue),
        ("green", Color.green),
        ("orange", Color.orange),
        ("red", Color.red),
        ("purple", Color.purple),
        ("pink", Color.pink),
        ("yellow", Color.yellow),
        ("teal", Color.teal),
        ("indigo", Color.indigo),
        ("brown", Color.brown)
    ]
    
    var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏
            HStack {
                Text("创建新层")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button("取消") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("创建") {
                        let newLayer = store.createLayer(
                            name: name.isEmpty ? displayName.lowercased().replacingOccurrences(of: " ", with: "_") : name,
                            displayName: displayName.isEmpty ? name : displayName,
                            color: selectedColor
                        )
                        
                        // 如果这是第一个层，自动激活
                        if store.layers.count == 1 {
                            Task {
                                await store.switchToLayer(newLayer)
                            }
                        }
                        
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isFormValid)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 主内容区域
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 层信息区域
                    GroupBox("层信息") {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("层名称（英文）")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                TextField("例如: work, study, hobby", text: $name)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("显示名称（中文）")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                TextField("例如: 工作, 学习, 爱好", text: $displayName)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding()
                    }
                    
                    // 层颜色区域
                    GroupBox("层颜色") {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("选择用于标识此层的颜色")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                                ForEach(availableColors, id: \.0) { colorName, color in
                                    ColorButton(
                                        colorName: colorName,
                                        color: color,
                                        isSelected: selectedColor == colorName,
                                        onTap: { selectedColor = colorName }
                                    )
                                }
                            }
                        }
                        .padding()
                    }
                    
                    // 预览区域
                    if isFormValid {
                        GroupBox("预览") {
                            LayerPreviewRow(
                                selectedColor: selectedColor,
                                displayName: !displayName.isEmpty ? displayName : (!name.isEmpty ? name : "新层"),
                                name: !name.isEmpty ? name : (!displayName.isEmpty ? displayName.lowercased() : "new_layer")
                            )
                            .padding()
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 500, height: 550)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Helper Views for CreateLayerSheet

struct ColorButton: View {
    let colorName: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                )
                .scaleEffect(isSelected ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .help(colorName.capitalized)
    }
}

struct LayerPreviewRow: View {
    let selectedColor: String
    let displayName: String
    let name: String
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.from(selectedColor))
                .frame(width: 14, height: 14)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                    .fontWeight(.semibold)
                Text(name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 数据管理

struct DataManagementView: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var dataManager = ExternalDataManager.shared
    @StateObject private var dataService = ExternalDataService.shared
    @State private var showingClearDataAlert = false
    @State private var showingResultAlert = false
    @State private var resultMessage = ""
    @State private var isSuccess = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 外部数据存储设置
                ExternalDataStoragePanel()
                
                // 图片管理组件
                ImageManagementSection()
                
                // 数据统计组件
                DataStatisticsSection()
                    .environmentObject(store)
                
                // 数据维护组件
                DataMaintenanceSection()
                    .environmentObject(store)
                
                // 危险操作组件
                DangerousOperationsSection()
                    .environmentObject(store)
                
                Spacer()
            }
            .padding()
        }
        .alert("确认清除数据", isPresented: $showingClearDataAlert) {
            Button("取消", role: .cancel) { }
            Button("清除", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("此操作将删除所有节点和标签数据，且无法撤销。")
        }
        .alert(isSuccess ? "成功" : "错误", isPresented: $showingResultAlert) {
            Button("确定") { }
        } message: {
            Text(resultMessage)
        }
    }
    
    private func clearAllData() {
        // 清除内存数据
        store.clearAllData()
        
        // 如果有外部数据存储，清除所有外部文件（包括标签映射）
        if dataManager.isDataPathSelected {
            Task {
                do {
                    // 使用新的清理方法，彻底删除所有外部数据文件
                    try await dataService.clearAllExternalData()
                    await MainActor.run {
                        resultMessage = "所有数据已完全清除（包括外部存储和标签设置）"
                        isSuccess = true
                        showingResultAlert = true
                    }
                } catch {
                    await MainActor.run {
                        resultMessage = "数据已清除，但清理外部存储失败: \(error.localizedDescription)"
                        isSuccess = false
                        showingResultAlert = true
                    }
                }
            }
        } else {
            resultMessage = "所有数据已清除"
            isSuccess = true
            showingResultAlert = true
        }
    }
    
    private func openImagesFolder() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let imagesURL = documentsURL.appendingPathComponent("WordTagger/Images")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true, attributes: nil)
        
        // 打开文件夹
        NSWorkspace.shared.open(imagesURL)
    }
    
    private func showInFinder() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let imagesURL = documentsURL.appendingPathComponent("WordTagger/Images")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true, attributes: nil)
        
        // 在 Finder 中显示
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: imagesURL.path)
    }
}

struct SettingRow<Content: View>: View {
    let title: String
    let description: String
    let content: () -> Content
    
    init(title: String, description: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.description = description
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                content()
            }
        }
    }
}

struct StatRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - 关于页面

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Connection")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("版本 1.0.0")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("功能特点:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    FeatureRow(icon: "tag.fill", text: "智能标签系统")
                    FeatureRow(icon: "magnifyingglass", text: "模糊搜索功能")
                    FeatureRow(icon: "map", text: "地图可视化")
                    FeatureRow(icon: "command", text: "命令面板快捷操作")
                    FeatureRow(icon: "icloud", text: "数据导入导出")
                }
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Text("基于 SwiftUI 构建")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("© 2024 Connection. All rights reserved.")
                    .font(.caption2)
                    .foregroundColor(Color.secondary)
            }
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(text)
                .font(.body)
        }
    }
}

// MARK: - 全局图谱选中状态设置
struct GlobalGraphSelectionSettingsView: View {
    @StateObject private var selectionManager = GlobalGraphSelectionManager.shared
    
    var body: some View {
        SettingRow(
            title: "全局图谱选中状态",
            description: "管理全局图谱中的节点选中状态持久化"
        ) {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Text("\(selectionManager.selectedNodeIds.count)个选中")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Button("清除选中") {
                        selectionManager.clearAllSelections()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                if selectionManager.selectedNodeIds.count > 0 {
                    Text("选中的节点ID: \(selectionManager.selectedNodeIds.sorted().map(String.init).joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

// MARK: - 外部数据存储面板

struct ExternalDataStoragePanel: View {
    @StateObject private var dataManager = ExternalDataManager.shared
    @StateObject private var dataService = ExternalDataService.shared
    @EnvironmentObject private var store: NodeStore
    
    var body: some View {
        GroupBox(label: Text("外部数据存储").font(.headline)) {
            VStack(alignment: .leading, spacing: 12) {
                
                if dataManager.isDataPathSelected {
                    // 当前路径
                    VStack(alignment: .leading, spacing: 4) {
                        Text("存储位置:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(dataManager.currentDataPath?.path ?? "未设置")
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(4)
                    }
                    
                    // 同步状态
                    HStack {
                        Circle()
                            .fill(store.isLoading ? .blue : (dataService.isSaving ? .orange : .green))
                            .frame(width: 6, height: 6)
                        
                        Text(store.isLoading ? "加载数据..." : (dataService.isSaving ? "同步中..." : "已同步"))
                            .font(.caption)
                        
                        Spacer()
                        
                        if let lastSync = dataService.lastSyncTime {
                            Text(formatTime(lastSync))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("未设置外部数据存储位置")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("📁 选择文件夹来启用外部数据存储")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                
                // 错误提示
                if let error = dataManager.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
                }
                
                // 操作按钮
                HStack {
                    Button(dataManager.isDataPathSelected ? "更改位置" : "设置存储") {
                        Task {
                            // 清除之前的错误
                            dataManager.lastError = nil
                            dataManager.selectDataFolder()
                            
                            // 选择完成后自动保存并刷新
                            if dataManager.isDataPathSelected {
                                await store.forceSaveToExternalStorage()
                                // 触发数据重新加载
                                NotificationCenter.default.post(
                                    name: .dataPathChanged,
                                    object: dataManager,
                                    userInfo: ["newPath": dataManager.currentDataPath ?? URL(fileURLWithPath: "")]
                                )
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isLoading || dataService.isSaving)
                    
                    if dataManager.isDataPathSelected {
                        Button("清除") {
                            dataManager.clearDataPath()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // 如果有错误，显示重试按钮
                    if dataManager.lastError != nil {
                        Button("重试") {
                            Task {
                                dataManager.lastError = nil
                                dataManager.selectDataFolder()
                                
                                // 重试成功后也自动保存并刷新
                                if dataManager.isDataPathSelected {
                                    await store.forceSaveToExternalStorage()
                                    NotificationCenter.default.post(
                                        name: .dataPathChanged,
                                        object: dataManager,
                                        userInfo: ["newPath": dataManager.currentDataPath ?? URL(fileURLWithPath: "")]
                                    )
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - 数据文件夹设置弹窗

struct DataFolderSetupView: View {
    @StateObject private var dataManager = ExternalDataManager.shared
    @StateObject private var dataService = ExternalDataService.shared
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            // 标题
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                
                Text("设置数据存储位置")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("选择一个文件夹来存储Connection的数据")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // 当前路径显示
            if let currentPath = dataManager.currentDataPath {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前数据路径:")
                        .font(.headline)
                    
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)
                        
                        Text(currentPath.path)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            
            // 错误信息
            if let error = dataManager.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    
                    Text(error)
                        .font(.body)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            // 同步状态
            if dataManager.isDataPathSelected {
                HStack {
                    Circle()
                        .fill(dataService.isSaving ? .orange : .green)
                        .frame(width: 8, height: 8)
                    
                    Text(dataService.isSaving ? "同步中..." : "已同步")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let lastSync = dataService.lastSyncTime {
                        Text("• 上次同步: \(formatTime(lastSync))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // 操作按钮
            VStack(spacing: 12) {
                // 选择文件夹按钮
                Button(action: {
                    dataManager.selectDataFolder()
                }) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text(dataManager.isDataPathSelected ? "更改数据文件夹" : "选择数据文件夹")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                // 完成按钮
                if dataManager.isDataPathSelected {
                    Button(action: {
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "checkmark")
                            Text("完成设置")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                
                // 取消按钮
                Button(action: {
                    isPresented = false
                }) {
                    Text("取消")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
            }
        }
        .padding(32)
        .frame(width: 500, height: 600)
        .background(Color(.windowBackgroundColor))
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - GitHub同步设置

struct GitSyncSettingsView: View {
    @StateObject private var dataManager = ExternalDataManager.shared
    @StateObject private var statusManager = GitSyncStatusManager.shared
    @EnvironmentObject private var store: NodeStore
    @State private var remoteURLInput: String = ""
    @State private var branchInput: String = "master"
    @State private var githubUsername: String = ""
    @State private var githubToken: String = ""
    @State private var showingSetupAlert = false
    @State private var showingConfirmDialog = false
    @State private var isGitEnabled: Bool = false
    @State private var syncStatus: String = "未配置"
    @State private var isWorking: Bool = false
    @State private var lastSyncTime: Date?
    @State private var lastError: String?
    @State private var syncHistory: [SyncRecord] = []
    @State private var lastCommitHash: String?
    @State private var totalSyncCount: Int = 0
    @State private var showingSyncHistory = false
    @State private var showingTokenHelp = false
    @State private var autoSyncEnabled: Bool = true
    @State private var autoSyncTimer: Timer?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // 状态概览
                GroupBox("GitHub同步状态") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Circle()
                                .fill(isGitEnabled ? (isWorking ? .orange : .green) : .secondary)
                                .frame(width: 8, height: 8)
                            
                            Text(syncStatus)
                                .font(.body)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            if isWorking {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else if isGitEnabled {
                                Button("查看历史") {
                                    showingSyncHistory = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        
                        // 详细统计信息
                        if isGitEnabled {
                            Divider()
                            
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                                GridRow {
                                    Text("总同步次数:")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                    Text("\(totalSyncCount) 次")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    
                                    if let lastSync = lastSyncTime {
                                        Text("上次同步:")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                        Text(formatDateTime(lastSync))
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                }
                                
                                if let commitHash = lastCommitHash {
                                    GridRow {
                                        Text("最新提交:")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                        Text(String(commitHash.prefix(8)))
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.blue)
                                        
                                        Spacer()
                                        Spacer()
                                    }
                                }
                            }
                        }
                        
                        if let error = lastError {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                    
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                
                                // 如果是403权限错误，提供详细的解决方案
                                if error.contains("403") {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("解决方案：")
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .foregroundColor(.orange)
                                        
                                        Text("1. 检查Personal Access Token是否正确")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        
                                        Text("2. 确保Token具有'repo'权限（完整仓库访问）")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        
                                        Text("3. 检查仓库是否为私有仓库且你有访问权限")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        
                                        Text("4. Token可能已过期，请重新生成")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                        }
                        
                        // 成功提示
                        if let lastRecord = syncHistory.last, lastRecord.success, lastRecord.timestamp > Date().addingTimeInterval(-10) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                
                                Text("最近操作: \(lastRecord.operation.rawValue)成功")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                        }
                    }
                    .padding(12)
                }
                
                // 仓库配置
                GroupBox("GitHub仓库配置") {
                    VStack(alignment: .leading, spacing: 16) {
                        
                        if !dataManager.isDataPathSelected {
                            // 提示用户先设置数据路径
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("需要先设置数据存储路径")
                                        .font(.body)
                                        .fontWeight(.medium)
                                    
                                    Text("请在\"数据\"标签页中设置外部数据存储位置")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                // GitHub仓库URL
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("GitHub仓库URL")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    TextField("https://github.com/username/my-wordtagger-data.git", text: $remoteURLInput)
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isGitEnabled)
                                    
                                    Text("创建一个新的GitHub仓库来存储你的学习数据")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                // GitHub认证信息
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("GitHub认证")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        
                                        Button("帮助") {
                                            showingTokenHelp = true
                                        }
                                        .font(.caption)
                                        .buttonStyle(.borderless)
                                        .foregroundColor(.blue)
                                    }
                                    
                                    TextField("GitHub用户名", text: $githubUsername)
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isGitEnabled)
                                    
                                    SecureField("Personal Access Token", text: $githubToken)
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isGitEnabled)
                                    
                                    Text("需要GitHub Personal Access Token进行认证")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                // 分支名称
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("分支名称")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    TextField("master", text: $branchInput)
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isGitEnabled)
                                }
                                
                                // 当前配置显示
                                if isGitEnabled {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                            Text("已配置的仓库")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text("仓库:")
                                                    .foregroundColor(.secondary)
                                                Text(remoteURLInput)
                                                    .font(.system(.caption, design: .monospaced))
                                            }
                                            
                                            HStack {
                                                Text("用户:")
                                                    .foregroundColor(.secondary)
                                                Text(githubUsername.isEmpty ? "未设置" : githubUsername)
                                                    .font(.system(.caption, design: .monospaced))
                                            }
                                            
                                            HStack {
                                                Text("分支:")
                                                    .foregroundColor(.secondary)
                                                Text(branchInput)
                                                    .font(.system(.caption, design: .monospaced))
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(.controlBackgroundColor))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                
                // 操作按钮
                if dataManager.isDataPathSelected {
                    GroupBox("操作") {
                        VStack(alignment: .leading, spacing: 12) {
                            if isGitEnabled {
                                // 自动同步设置
                                HStack {
                                    Toggle("自动同步", isOn: $autoSyncEnabled)
                                        .onChange(of: autoSyncEnabled) { _, enabled in
                                            print("🔧 GitSyncSettingsView: 自动同步开关变更: \(enabled)")
                                            if enabled {
                                                startAutoSyncMonitoring()
                                            } else {
                                                stopAutoSyncMonitoring()
                                            }
                                            saveSettings()
                                        }
                                    Spacer()
                                    Text(autoSyncEnabled ? "数据变化时自动同步" : "需手动同步")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                                
                                Divider()
                                
                                // 已配置时的操作
                                HStack(spacing: 12) {
                                    Button("同步到GitHub") {
                                        syncToGitHub()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isWorking)
                                    
                                    Button("从GitHub拉取") {
                                        pullFromGitHub()
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isWorking)
                                    
                                    Button("强制推送") {
                                        forcePushToGitHub()
                                    }
                                    .buttonStyle(.bordered)
                                    .foregroundColor(.orange)
                                    .disabled(isWorking)
                                    
                                    Button("强制拉取") {
                                        forcePullFromGitHub()
                                    }
                                    .buttonStyle(.bordered)
                                    .foregroundColor(.red)
                                    .disabled(isWorking)
                                    
                                    Button("修复数据") {
                                        fixCorruptedData()
                                    }
                                    .buttonStyle(.bordered)
                                    .foregroundColor(.orange)
                                    .disabled(isWorking)
                                    
                                    Button("停止同步") {
                                        print("🚨 用户点击停止同步按钮")
                                        GitAutoSyncManager.shared.emergencyReset()
                                        GitAutoSyncManager.shared.debugStatus()
                                    }
                                    .buttonStyle(.bordered)
                                    .foregroundColor(.red)
                                    .help("如果Git图标一直转动，点击此按钮强制停止")
                                    
                                    Spacer()
                                    
                                    Button("重新配置") {
                                        showingConfirmDialog = true
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isWorking)
                                }
                            } else {
                                // 未配置时的设置按钮
                                Button("设置GitHub同步") {
                                    let repoURL = remoteURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let username = githubUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let token = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
                                    
                                    if repoURL.isEmpty || username.isEmpty || token.isEmpty {
                                        showingSetupAlert = true
                                    } else {
                                        setupGitRepository()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isWorking)
                            }
                        }
                        .padding(12)
                    }
                }
                
                // 使用说明
                GroupBox("使用说明") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("🎯 功能说明")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• 将你的学习数据（节点、标签、层等）自动同步到GitHub")
                                Text("• 支持多设备间的数据同步")
                                Text("• 数据变化时自动推送到GitHub")
                                Text("• 可以从其他设备拉取最新数据")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("⚠️ 系统要求")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• 需要安装Git命令行工具")
                                Text("• 如果出现权限错误，请在终端运行：")
                                Text("  xcode-select --install")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.blue)
                                Text("• 或下载完整版Xcode以获得命令行工具")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("📝 设置步骤")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("1. 在GitHub上创建一个新的私有仓库（推荐）")
                                Text("2. 复制仓库的HTTPS地址")
                                Text("3. 在上方填入仓库URL并点击\"设置GitHub同步\"")
                                Text("4. 系统会自动初始化Git并连接到你的仓库")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("🔄 未来使用")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• 在新设备上：clone你的GitHub仓库到本地文件夹")
                                Text("• 在WordTagger设置中选择该文件夹作为数据存储位置")
                                Text("• 系统会自动识别Git配置并启用同步功能")
                                Text("• 你的所有学习数据就能在多设备间同步了！")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                }
                
                Spacer()
            }
            .padding()
        }
        .onAppear {
            loadSettings()
            setupAutoSync()
        }
        .onDisappear {
            stopAutoSyncMonitoring()
        }
        .sheet(isPresented: $showingSyncHistory) {
            SyncHistoryView(history: syncHistory, onClearHistory: clearSyncHistory)
        }
        .alert("请完整填写GitHub信息", isPresented: $showingSetupAlert) {
            Button("确定") { }
        } message: {
            Text("请填写GitHub仓库URL、用户名和Personal Access Token")
        }
        .sheet(isPresented: $showingTokenHelp) {
            GitHubTokenHelpView()
        }
        .confirmationDialog("重新配置GitHub同步", isPresented: $showingConfirmDialog, titleVisibility: .visible) {
            Button("重新配置", role: .destructive) {
                disableGit()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("这将清除当前的GitHub配置，但不会删除已有的数据。")
        }
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // MARK: - Git操作函数
    
    private func loadSettings() {
        let userDefaults = UserDefaults.standard
        isGitEnabled = userDefaults.bool(forKey: "WordTagger_GitEnabled")
        remoteURLInput = userDefaults.string(forKey: "WordTagger_GitRemoteURL") ?? ""
        branchInput = userDefaults.string(forKey: "WordTagger_GitBranch") ?? "master"
        githubUsername = userDefaults.string(forKey: "WordTagger_GitUsername") ?? ""
        githubToken = userDefaults.string(forKey: "WordTagger_GitToken") ?? ""
        totalSyncCount = userDefaults.integer(forKey: "WordTagger_TotalSyncCount")
        autoSyncEnabled = userDefaults.object(forKey: "WordTagger_AutoSyncEnabled") as? Bool ?? true
        lastCommitHash = userDefaults.string(forKey: "WordTagger_LastCommitHash")
        
        if let lastSync = userDefaults.object(forKey: "WordTagger_LastGitSync") as? Date {
            lastSyncTime = lastSync
        }
        
        // 加载同步历史
        if let historyData = userDefaults.data(forKey: "WordTagger_SyncHistory"),
           let decodedHistory = try? JSONDecoder().decode([SyncRecord].self, from: historyData) {
            syncHistory = decodedHistory
        }
        
        updateSyncStatus()
        
        // 同步到全局状态管理器
        statusManager.updateStatus(
            isEnabled: isGitEnabled,
            status: syncStatus,
            lastSyncTime: lastSyncTime,
            lastError: lastError,
            totalSyncCount: totalSyncCount
        )
    }
    
    private func saveSettings() {
        let userDefaults = UserDefaults.standard
        userDefaults.set(isGitEnabled, forKey: "WordTagger_GitEnabled")
        userDefaults.set(remoteURLInput, forKey: "WordTagger_GitRemoteURL")
        userDefaults.set(branchInput, forKey: "WordTagger_GitBranch")
        userDefaults.set(githubUsername, forKey: "WordTagger_GitUsername")
        userDefaults.set(githubToken, forKey: "WordTagger_GitToken")
        userDefaults.set(totalSyncCount, forKey: "WordTagger_TotalSyncCount")
        userDefaults.set(autoSyncEnabled, forKey: "WordTagger_AutoSyncEnabled")
        
        if let lastSync = lastSyncTime {
            userDefaults.set(lastSync, forKey: "WordTagger_LastGitSync")
        }
        
        if let commitHash = lastCommitHash {
            userDefaults.set(commitHash, forKey: "WordTagger_LastCommitHash")
        }
        
        // 保存同步历史（只保留最近50条记录）
        let recentHistory = Array(syncHistory.sorted { $0.timestamp > $1.timestamp }.prefix(50))
        if let historyData = try? JSONEncoder().encode(recentHistory) {
            userDefaults.set(historyData, forKey: "WordTagger_SyncHistory")
        }
    }
    
    private func clearSyncHistory() {
        syncHistory.removeAll()
        totalSyncCount = 0
        lastSyncTime = nil
        lastCommitHash = nil
        saveSettings()
        
        // 同步到状态管理器
        statusManager.updateStatus(
            isEnabled: isGitEnabled,
            status: syncStatus,
            lastSyncTime: lastSyncTime,
            lastError: lastError,
            totalSyncCount: totalSyncCount
        )
    }
    
    private func updateSyncStatus() {
        if !isGitEnabled || remoteURLInput.isEmpty {
            syncStatus = "未配置"
        } else if isWorking {
            syncStatus = "同步中..."
        } else if lastError != nil {
            syncStatus = "错误"
        } else {
            syncStatus = "就绪"
        }
    }
    
    private func findGitPath() async -> String? {
        // 首先尝试静态路径
        let staticPaths = [
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
            "/usr/bin/git"
        ]
        
        for path in staticPaths {
            if FileManager.default.fileExists(atPath: path) {
                print("✅ 找到Git: \(path)")
                return path
            }
        }
        
        // 如果静态路径都失败，尝试使用which命令
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = ["git"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            var environment: [String: String] = [:]
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            process.environment = environment
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                        print("✅ 通过which找到Git: \(path)")
                        return path
                    }
                }
            }
        } catch {
            print("❌ which命令失败: \(error)")
        }
        
        print("❌ 所有方法都未能找到Git")
        return nil
    }
    
    private func recordSyncOperation(
        operation: SyncRecord.SyncOperation,
        success: Bool,
        commitHash: String? = nil,
        filesChanged: Int = 0,
        errorMessage: String? = nil
    ) {
        let record = SyncRecord(
            timestamp: Date(),
            operation: operation,
            success: success,
            commitHash: commitHash,
            filesChanged: filesChanged,
            errorMessage: errorMessage
        )
        
        syncHistory.append(record)
        
        if success {
            totalSyncCount += 1
            if let hash = commitHash {
                lastCommitHash = hash
            }
        }
        
        saveSettings()
        // 不立即更新状态，让调用者控制状态更新
    }
    
    private func getCommitHash(at workingDirectory: URL) async -> String? {
        do {
            guard let validGitPath = await findGitPath() else {
                print("❌ 获取commit hash失败: Git未找到")
                return nil
            }
            
            let pipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: validGitPath)
            process.arguments = ["rev-parse", "HEAD"]
            process.currentDirectoryURL = workingDirectory
            process.standardOutput = pipe
            
            // 设置环境变量
            var environment: [String: String] = [:]
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin"
            environment["GIT_TERMINAL_PROMPT"] = "0"
            environment["GIT_CONFIG_NOSYSTEM"] = "1"
            environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
            environment["HOME"] = NSHomeDirectory()
            environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            process.environment = environment
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let hash = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    print("✅ 获取到commit hash: \(String(hash.prefix(8)))")
                    return hash
                }
            } else {
                print("⚠️ 获取commit hash失败: 退出状态 \(process.terminationStatus)")
            }
        } catch {
            print("❌ 获取commit hash异常: \(error)")
        }
        return nil
    }
    
    private func setupGitRepository() {
        guard let dataPath = dataManager.currentDataPath else {
            lastError = "请先设置数据存储路径"
            updateSyncStatus()
            statusManager.updateStatus(lastError: lastError)
            return
        }
        
        isWorking = true
        syncStatus = "设置中..."
        lastError = nil
        statusManager.startWorking(operation: "初始化Git仓库")
        
        Task {
            do {
                // 首先配置Git用户信息（如果没有的话）
                try await configureGitUser(at: dataPath)
                
                // 运行Git命令初始化仓库
                try await runGitCommand(["init"], at: dataPath)
                
                // 使用不含认证信息的URL
                let cleanURL = remoteURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // 检查远程仓库是否已存在，如果存在则更新，否则添加
                do {
                    try await runGitCommand(["remote", "get-url", "origin"], at: dataPath)
                    // 如果执行成功，说明origin已存在，更新它
                    print("🔧 远程origin已存在，更新URL...")
                    try await runGitCommand(["remote", "set-url", "origin", cleanURL], at: dataPath)
                } catch {
                    // 如果执行失败，说明origin不存在，添加它
                    print("🔧 远程origin不存在，添加新的...")
                    try await runGitCommand(["remote", "add", "origin", cleanURL], at: dataPath)
                }
                
                // 清理credential helper配置
                print("🔧 清理Git配置...")
                do {
                    try await runGitCommand(["config", "--local", "--unset-all", "credential.helper"], at: dataPath)
                } catch {
                    // 忽略错误
                }
                
                await MainActor.run {
                    print("✅ Git设置成功，更新UI状态...")
                    isGitEnabled = true
                    isWorking = false
                    syncStatus = "设置完成"
                    recordSyncOperation(operation: .setup, success: true, filesChanged: 0)
                    saveSettings()
                    
                    statusManager.finishWorking(success: true, finalStatus: "GitHub同步已配置")
                    
                    // 立即同步所有状态到全局状态管理器
                    statusManager.updateStatus(
                        isEnabled: isGitEnabled,
                        status: syncStatus,
                        lastSyncTime: lastSyncTime,
                        lastError: lastError,
                        totalSyncCount: totalSyncCount
                    )
                    
                    print("🎯 当前状态: isGitEnabled=\(isGitEnabled), isWorking=\(isWorking), syncStatus=\(syncStatus)")
                    
                    // 3秒后重置状态为"就绪"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        print("🔄 3秒后重置状态为就绪")
                        self.updateSyncStatus()
                        // 重置后也要同步状态
                        self.statusManager.updateStatus(
                            isEnabled: self.isGitEnabled,
                            status: self.syncStatus,
                            lastSyncTime: self.lastSyncTime,
                            lastError: self.lastError,
                            totalSyncCount: self.totalSyncCount
                        )
                    }
                }
                
            } catch {
                await MainActor.run {
                    let errorMessage = error.localizedDescription
                    print("❌ setupGitRepository失败: \(errorMessage)")
                    
                    // 输出完整的错误信息用于调试
                    if let gitError = error as? GitError {
                        print("❌ Git命令: \(gitError)")
                        switch gitError {
                        case .commandFailed(let command, let output):
                            print("❌ 失败的命令: \(command)")
                            print("❌ 原始错误输出: \(output)")
                        }
                    }
                    
                    lastError = "Git设置失败: \(errorMessage)"
                    recordSyncOperation(
                        operation: .setup,
                        success: false,
                        errorMessage: errorMessage
                    )
                    statusManager.finishWorking(success: false, finalStatus: "GitHub同步配置失败", error: errorMessage)
                    isWorking = false
                }
            }
        }
    }
    
    private func configureGitUser(at workingDirectory: URL) async throws {
        do {
            // 尝试获取当前用户信息
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["config", "--local", "user.name"]
            process.currentDirectoryURL = workingDirectory
            
            var environment: [String: String] = [:]
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin"
            environment["GIT_TERMINAL_PROMPT"] = "0"
            environment["GIT_CONFIG_NOSYSTEM"] = "1"
            environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
            environment["HOME"] = NSHomeDirectory()
            environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            process.environment = environment
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                // 用户信息不存在，设置默认值
                try await runGitCommand(["config", "--local", "user.name", "WordTagger User"], at: workingDirectory)
                try await runGitCommand(["config", "--local", "user.email", "wordtagger@local.app"], at: workingDirectory)
                print("✅ 已配置默认Git用户信息")
            } else {
                print("✅ Git用户信息已存在")
            }
        } catch {
            // 如果获取失败，直接设置默认值
            try await runGitCommand(["config", "--local", "user.name", "WordTagger User"], at: workingDirectory)
            try await runGitCommand(["config", "--local", "user.email", "wordtagger@local.app"], at: workingDirectory)
            print("✅ 已设置默认Git用户信息")
        }
    }
    
    private func syncToGitHub() {
        guard let dataPath = dataManager.currentDataPath else {
            lastError = "数据路径未设置"
            updateSyncStatus()
            statusManager.updateStatus(lastError: lastError)
            return
        }
        
        isWorking = true
        syncStatus = "推送中..."
        lastError = nil
        statusManager.startWorking(operation: "同步到GitHub")
        
        // 详细诊断信息
        print("🔍 GitHub同步诊断信息:")
        print("   仓库URL: \(remoteURLInput)")
        print("   用户名: \(githubUsername)")
        print("   Token长度: \(githubToken.count)字符")
        print("   分支名: \(branchInput)")
        print("   数据路径: \(dataPath.path)")
        
        Task {
            do {
                print("🔧 开始GitHub同步...")
                
                let username = githubUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                let token = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanURL = remoteURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard !token.isEmpty else {
                    throw GitError.commandFailed("auth", "GitHub Token为空")
                }
                
                print("🔧 检查并清理敏感文件...")
                let credentialsFile = dataPath.appendingPathComponent(".git-credentials")
                if FileManager.default.fileExists(atPath: credentialsFile.path) {
                    print("⚠️ 发现.git-credentials文件，正在删除...")
                    try? FileManager.default.removeItem(at: credentialsFile)
                }
                
                let gitignoreFile = dataPath.appendingPathComponent(".gitignore")
                if !FileManager.default.fileExists(atPath: gitignoreFile.path) {
                    print("🔧 创建.gitignore文件...")
                    let gitignoreContent = """
.git-credentials
.DS_Store
*.tmp
"""
                    try gitignoreContent.write(to: gitignoreFile, atomically: true, encoding: .utf8)
                }
                
                print("🔧 设置GitHub认证...")
                let authenticatedURL = buildAuthenticatedURL(cleanURL: cleanURL, username: username, token: token)
                try await runGitCommand(["remote", "set-url", "origin", authenticatedURL], at: dataPath)
                
                do {
                    try await runGitCommand(["config", "--local", "--unset-all", "credential.helper"], at: dataPath)
                    print("🔧 已清理credential helper配置")
                } catch {
                    print("🔧 无需清理credential helper配置")
                }
                
                print("🔧 检查工作区状态...")
                try await runGitCommand(["status", "--porcelain"], at: dataPath)
                
                print("🔧 添加文件到暂存区...")
                try await runGitCommand(["add", "."], at: dataPath)
                
                print("🔧 检查暂存区状态...")
                do {
                    try await runGitCommand(["diff", "--cached", "--exit-code"], at: dataPath)
                    print("ℹ️ 暂存区没有更改")
                    await MainActor.run {
                        syncStatus = "没有更改"
                        statusManager.finishWorking(success: true, finalStatus: "数据已是最新")
                        isWorking = false
                    }
                    return
                } catch {
                    print("🔧 暂存区有更改，准备提交...")
                }
                
                print("🔧 创建提交...")
                let commitMessage = "Auto-sync WordTagger data - \(Date().formatted())"
                try await runGitCommand(["commit", "-m", commitMessage], at: dataPath)
                
                print("🔧 检查远程分支状态...")
                do {
                    try await runGitCommand(["fetch", "origin", branchInput], at: dataPath)
                    print("🔧 已获取远程更新")
                } catch {
                    print("⚠️ 获取远程更新失败，继续推送: \(error)")
                }
                
                print("🔧 尝试推送到GitHub...")
                do {
                    try await runGitCommand(["push", "origin", branchInput], at: dataPath)
                    print("✅ 推送成功")
                } catch {
                    print("⚠️ 普通推送失败，尝试合并后推送...")
                    print("❌ 推送失败详情: \(error)")
                    
                    if error.localizedDescription.contains("GH013") || error.localizedDescription.contains("secret") {
                        print("🚨 检测到GitHub安全保护，尝试使用BFG清理...")
                        throw GitError.commandFailed("security", "仓库中仍有敏感信息，请手动清理或使用强制推送")
                    }
                    
                    do {
                        try await runGitCommand(["pull", "origin", branchInput, "--rebase"], at: dataPath)
                        try await runGitCommand(["push", "origin", branchInput], at: dataPath)
                        print("✅ 合并后推送成功")
                    } catch {
                        print("❌ 合并推送也失败: \(error)")
                        throw error
                    }
                }
                
                // 获取最新的commit hash
                let commitHash = await getCommitHash(at: dataPath)
                
                await MainActor.run {
                    lastSyncTime = Date()
                    syncStatus = "同步完成"
                    
                    // 记录成功的同步操作
                    recordSyncOperation(
                        operation: .push,
                        success: true,
                        commitHash: commitHash,
                        filesChanged: 1
                    )
                    
                    isWorking = false
                    
                    // 立即更新状态管理器
                    print("🔧 更新状态管理器...")
                    print("🔧 当前同步状态: \(syncStatus)")
                    print("🔧 是否工作中: \(isWorking)")
                    
                    // 先调用finishWorking结束工作状态
                    statusManager.finishWorking(success: true, finalStatus: "已同步到GitHub")
                    print("✅ 已调用finishWorking")
                    
                    // 再更新详细状态
                    statusManager.updateStatus(
                        isEnabled: isGitEnabled,
                        status: syncStatus,
                        lastSyncTime: lastSyncTime,
                        lastError: lastError,
                        totalSyncCount: totalSyncCount
                    )
                    print("✅ 已更新详细状态")
                    
                    // 强制刷新UI状态
                    print("🔧 刷新UI状态...")
                    
                    // 3秒后重置状态
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.updateSyncStatus()
                        self.statusManager.updateStatus(
                            isEnabled: self.isGitEnabled,
                            status: self.syncStatus,
                            lastSyncTime: self.lastSyncTime,
                            lastError: self.lastError,
                            totalSyncCount: self.totalSyncCount
                        )
                        print("✅ 状态重置完成")
                    }
                }
                
            } catch {
                await MainActor.run {
                    let errorMessage = error.localizedDescription
                    print("❌ GitHub同步失败: \(errorMessage)")
                    
                    // 输出完整的错误信息用于调试
                    if let gitError = error as? GitError {
                        print("❌ Git命令: \(gitError)")
                        switch gitError {
                        case .commandFailed(let command, let output):
                            print("❌ 失败的命令: \(command)")
                            print("❌ 原始错误输出: \(output)")
                        }
                    }
                    
                    lastError = "同步失败: \(errorMessage)"
                    
                    // 记录失败的同步操作
                    recordSyncOperation(
                        operation: .push,
                        success: false,
                        errorMessage: errorMessage
                    )
                    
                    statusManager.finishWorking(success: false, finalStatus: "同步到GitHub失败", error: errorMessage)
                    isWorking = false
                }
            }
        }
    }
    
    private func pullFromGitHub() {
        guard let dataPath = dataManager.currentDataPath else {
            lastError = "数据路径未设置"
            updateSyncStatus()
            statusManager.updateStatus(lastError: lastError)
            return
        }
        
        isWorking = true
        syncStatus = "拉取中..."
        lastError = nil
        statusManager.startWorking(operation: "从GitHub拉取")
        
        Task {
            do {
                print("🔧 开始从GitHub拉取...")
                
                // 构建带认证的URL
                let cleanURL = remoteURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                let username = githubUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                let token = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard !token.isEmpty else {
                    throw GitError.commandFailed("auth", "GitHub Token为空")
                }
                
                let authenticatedURL = buildAuthenticatedURL(cleanURL: cleanURL, username: username, token: token)
                print("🔧 设置远程URL用于拉取")
                try await runGitCommand(["remote", "set-url", "origin", authenticatedURL], at: dataPath)
                
                // 清理credential helper配置
                do {
                    try await runGitCommand(["config", "--local", "--unset-all", "credential.helper"], at: dataPath)
                } catch {
                    // 忽略错误
                }
                
                print("🔧 从GitHub拉取最新数据...")
                try await runGitCommand(["pull", "origin", branchInput], at: dataPath)
                
                // 获取最新的commit hash
                let commitHash = await getCommitHash(at: dataPath)
                
                await MainActor.run {
                    lastSyncTime = Date()
                    syncStatus = "拉取完成"
                    
                    // 记录成功的拉取操作
                    recordSyncOperation(
                        operation: .pull,
                        success: true,
                        commitHash: commitHash,
                        filesChanged: 1 // 简化计算
                    )
                    
                    statusManager.finishWorking(success: true, finalStatus: "已从GitHub拉取")
                    isWorking = false
                    
                    // 立即同步所有状态到全局状态管理器
                    statusManager.updateStatus(
                        isEnabled: isGitEnabled,
                        status: syncStatus,
                        lastSyncTime: lastSyncTime,
                        lastError: lastError,
                        totalSyncCount: totalSyncCount
                    )
                    
                    // 3秒后重置状态
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.updateSyncStatus()
                        // 重置后也要同步状态
                        self.statusManager.updateStatus(
                            isEnabled: self.isGitEnabled,
                            status: self.syncStatus,
                            lastSyncTime: self.lastSyncTime,
                            lastError: self.lastError,
                            totalSyncCount: self.totalSyncCount
                        )
                    }
                    
                    // 通知数据已更新
                    NotificationCenter.default.post(
                        name: Notification.Name("ExternalDataPathChanged"),
                        object: nil,
                        userInfo: ["newPath": dataPath]
                    )
                }
                
            } catch {
                await MainActor.run {
                    let errorMessage = error.localizedDescription
                    print("❌ pullFromGitHub失败: \(errorMessage)")
                    
                    // 输出完整的错误信息用于调试
                    if let gitError = error as? GitError {
                        print("❌ Git命令: \(gitError)")
                        switch gitError {
                        case .commandFailed(let command, let output):
                            print("❌ 失败的命令: \(command)")
                            print("❌ 原始错误输出: \(output)")
                        }
                    }
                    
                    lastError = "拉取失败: \(errorMessage)"
                    
                    // 记录失败的拉取操作
                    recordSyncOperation(
                        operation: .pull,
                        success: false,
                        errorMessage: errorMessage
                    )
                    
                    statusManager.finishWorking(success: false, finalStatus: "从GitHub拉取失败", error: errorMessage)
                    isWorking = false
                }
            }
        }
    }
    
    private func forcePushToGitHub() {
        guard let dataPath = dataManager.currentDataPath else {
            return
        }
        
        Task {
            await MainActor.run {
                isWorking = true
                syncStatus = "强制清理并推送中..."
            }
            
            do {
                let token = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanURL = remoteURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                
                print("🔧 开始强制推送流程...")
                
                // 删除敏感文件
                let credentialsFile = dataPath.appendingPathComponent(".git-credentials")
                if FileManager.default.fileExists(atPath: credentialsFile.path) {
                    try? FileManager.default.removeItem(at: credentialsFile)
                    print("🔧 删除了.git-credentials文件")
                }
                
                // 创建.gitignore
                let gitignoreFile = dataPath.appendingPathComponent(".gitignore")
                let gitignoreContent = """
.git-credentials
.DS_Store
*.tmp
"""
                try gitignoreContent.write(to: gitignoreFile, atomically: true, encoding: .utf8)
                print("🔧 创建/更新了.gitignore文件")
                
                let authenticatedURL = cleanURL.replacingOccurrences(of: "https://", with: "https://\(token)@")
                try await runGitCommand(["remote", "set-url", "origin", authenticatedURL], at: dataPath)
                
                // 使用git-filter-repo清理敏感文件（如果可用）
                print("🔧 尝试清理Git历史中的敏感文件...")
                do {
                    // 先尝试使用git filter-repo（更现代的工具）
                    try await runGitCommand(["filter-repo", "--invert-paths", "--path", ".git-credentials", "--force"], at: dataPath)
                    print("✅ 使用git filter-repo成功清理")
                } catch {
                    print("⚠️ git filter-repo不可用，尝试其他方法: \(error)")
                    
                    // 如果filter-repo不可用，使用传统方法
                    do {
                        // 直接删除包含敏感信息的文件并提交
                        try await runGitCommand(["rm", "--cached", ".git-credentials"], at: dataPath)
                        print("🔧 从暂存区删除敏感文件")
                    } catch {
                        print("⚠️ 删除暂存文件失败，继续: \(error)")
                    }
                }
                
                try await runGitCommand(["add", "."], at: dataPath)
                try await runGitCommand(["commit", "-m", "Clean sensitive files and force push - \(Date().formatted())", "--allow-empty"], at: dataPath)
                
                print("🔧 执行强制推送...")
                try await runGitCommand(["push", "origin", branchInput, "--force-with-lease"], at: dataPath)
                
                print("✅ 强制推送完成")
                await MainActor.run {
                    isWorking = false
                    syncStatus = "强制推送完成"
                    lastSyncTime = Date()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.syncStatus = "就绪"
                    }
                }
                
            } catch {
                print("❌ 强制推送失败: \(error)")
                await MainActor.run {
                    isWorking = false
                    syncStatus = "强制推送失败"
                    lastError = error.localizedDescription
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.syncStatus = "就绪"
                    }
                }
            }
        }
    }
    
    private func forcePullFromGitHub() {
        guard let dataPath = dataManager.currentDataPath else {
            return
        }
        
        Task {
            await MainActor.run {
                isWorking = true
                syncStatus = "强制拉取中..."
            }
            
            do {
                let token = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanURL = remoteURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                
                let authenticatedURL = cleanURL.replacingOccurrences(of: "https://", with: "https://\(token)@")
                try await runGitCommand(["remote", "set-url", "origin", authenticatedURL], at: dataPath)
                try await runGitCommand(["fetch", "origin", branchInput], at: dataPath)
                try await runGitCommand(["reset", "--hard", "origin/\(branchInput)"], at: dataPath)
                
                await MainActor.run {
                    isWorking = false
                    syncStatus = "强制拉取完成"
                    lastSyncTime = Date()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.syncStatus = "就绪"
                    }
                    
                    NotificationCenter.default.post(
                        name: Notification.Name("ExternalDataPathChanged"),
                        object: nil,
                        userInfo: ["newPath": dataPath]
                    )
                }
                
            } catch {
                await MainActor.run {
                    isWorking = false
                    syncStatus = "强制拉取失败"
                    lastError = error.localizedDescription
                    print("❌ \(error)")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.syncStatus = "就绪"
                    }
                }
            }
        }
    }
    
    private func disableGit() {
        print("🔧 GitSyncSettingsView: 禁用Git同步")
        isGitEnabled = false
        remoteURLInput = ""
        branchInput = "master"
        githubUsername = ""
        githubToken = ""
        lastError = nil
        stopAutoSyncMonitoring()
        saveSettings()
        updateSyncStatus()
        
        statusManager.updateStatus(
            isEnabled: false,
            status: "未配置"
        )
        statusManager.lastError = nil
    }
    
    // MARK: - 数据修复功能
    
    private func fixCorruptedData() {
        print("🔧 开始检测和修复数据corruption...")
        
        Task {
            await MainActor.run {
                isWorking = true
                syncStatus = "检测损坏数据中..."
            }
            
            // 检查损坏的节点
            var corruptedCount = 0
            var corruptedReasons: [String] = []
            
            for node in store.nodes {
                var nodeReasons: [String] = []
                
                if isCorruptedText(node.text) {
                    let reason = "节点文本损坏: '\(node.text)'"
                    nodeReasons.append(reason)
                }
                
                if let phonetic = node.phonetic, isCorruptedText(phonetic) {
                    let reason = "音标损坏: '\(phonetic)'"
                    nodeReasons.append(reason)
                }
                
                if let meaning = node.meaning, isCorruptedText(meaning) {
                    let reason = "含义损坏: '\(meaning)'"
                    nodeReasons.append(reason)
                }
                
                for tag in node.tags {
                    if isCorruptedText(tag.value) {
                        let reason = "标签损坏: '\(tag.value)'"
                        nodeReasons.append(reason)
                    }
                }
                
                if !nodeReasons.isEmpty {
                    corruptedCount += 1
                    let combinedReason = nodeReasons.joined(separator: "; ")
                    corruptedReasons.append(combinedReason)
                }
            }
            
            await MainActor.run {
                if corruptedCount == 0 {
                    print("✅ 未发现损坏的数据")
                    syncStatus = "数据完整"
                } else {
                    print("⚠️ 发现 \(corruptedCount) 个损坏的节点:")
                    for (index, reason) in corruptedReasons.enumerated() {
                        print("  \(index + 1). \(reason)")
                    }
                    
                    syncStatus = "发现\(corruptedCount)个损坏节点"
                }
                
                isWorking = false
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self.syncStatus = "就绪"
                }
            }
        }
    }
    
    // 辅助方法：检测corruption
    private func isCorruptedText(_ text: String) -> Bool {
        if text.isEmpty { return false }
        
        // 检查是否包含"kdf dlf sdfj"这样的随机字符组合
        let randomPattern = #"(\b[a-z]{1,4}\s){2,}[a-z]{1,4}\b"#
        if text.range(of: randomPattern, options: .regularExpression) != nil {
            return true
        }
        
        // 检查是否包含过多无意义字符
        let totalLength = text.count
        let meaningfulChars = text.filter { char in
            char.isLetter || char.isNumber || char.isWhitespace || "[](){}.,!?;:\"'-".contains(char)
        }.count
        
        return totalLength > 0 && Double(meaningfulChars) / Double(totalLength) < 0.7
    }
    
    // 辅助方法：清理文本
    private func sanitizeNodeText(_ text: String) -> String {
        if text.isEmpty || !isCorruptedText(text) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        var sanitized = text
        
        // 移除"kdf dlf sdfj"这样的模式
        let randomPattern = #"(\b[a-z]{1,4}\s){2,}[a-z]{1,4}\b"#
        sanitized = sanitized.replacingOccurrences(
            of: randomPattern,
            with: "",
            options: .regularExpression
        )
        
        // 清理多余空白
        sanitized = sanitized.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        
        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - 自动同步功能
    
    private func setupAutoSync() {
        print("🔧 GitSyncSettingsView: 设置自动同步")
        if isGitEnabled && autoSyncEnabled {
            print("🔧 GitSyncSettingsView: 启动GitAutoSyncManager监听")
            GitAutoSyncManager.shared.startMonitoring()
        } else {
            print("🔧 GitSyncSettingsView: 停止GitAutoSyncManager监听")
            GitAutoSyncManager.shared.stopMonitoring()
        }
    }
    
    private func startAutoSyncMonitoring() {
        // 使用统一的GitAutoSyncManager
        print("🔧 GitSyncSettingsView: 委托给GitAutoSyncManager处理监听")
        GitAutoSyncManager.shared.debugStatus()
        GitAutoSyncManager.shared.startMonitoring(force: true) // 强制重启以确保配置更新
    }
    
    private func stopAutoSyncMonitoring() {
        // 使用统一的GitAutoSyncManager
        print("🔧 GitSyncSettingsView: 委托给GitAutoSyncManager停止监听")
        GitAutoSyncManager.shared.stopMonitoring()
        GitAutoSyncManager.shared.debugStatus()
    }
    
    private func runGitCommand(_ arguments: [String], at workingDirectory: URL) async throws {
        // 首先查找Git路径
        guard let gitPath = await findGitPath() else {
            throw GitError.commandFailed("git", "Git未找到，请确保已安装Git\n已检查路径: /opt/homebrew/bin/git, /usr/local/bin/git, /usr/bin/git")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            
            process.executableURL = URL(fileURLWithPath: gitPath)
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            
            // 设置环境变量以避免一些Sandbox问题
            var environment: [String: String] = [:]
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin"
            environment["GIT_TERMINAL_PROMPT"] = "0" // 禁用交互式提示
            environment["GIT_CONFIG_NOSYSTEM"] = "1" // 避免读取系统Git配置
            environment["GIT_CONFIG_GLOBAL"] = "/dev/null" // 避免读取全局Git配置
            environment["HOME"] = NSHomeDirectory() // 确保HOME路径正确
            environment["GIT_ASKPASS"] = "" // 禁用密码提示程序
            environment["SSH_ASKPASS"] = "" // 禁用SSH密码提示
            // 特别针对Homebrew Git的设置
            environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            process.environment = environment
            
            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe
            
            do {
                print("🔧 执行Git命令: \(gitPath) \(arguments.joined(separator: " "))")
                print("🔧 工作目录: \(workingDirectory.path)")
                
                try process.run()
                process.waitUntilExit()
                
                let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                
                print("🔧 Git命令退出状态: \(process.terminationStatus)")
                if !output.isEmpty {
                    print("🔧 Git标准输出:")
                    print(output)
                }
                if !errorOutput.isEmpty {
                    print("🔧 Git错误输出:")
                    print(errorOutput)
                }
                
                // 对于push命令，记录完整的错误信息
                if arguments.contains("push") && process.terminationStatus != 0 {
                    print("❌ PUSH失败详情:")
                    print("   命令: git \(arguments.joined(separator: " "))")
                    print("   工作目录: \(workingDirectory.path)")
                    print("   退出码: \(process.terminationStatus)")
                    print("   标准输出: \(output)")
                    print("   错误输出: \(errorOutput)")
                }
                
                if process.terminationStatus != 0 {
                    let fullError = errorOutput.isEmpty ? "命令执行失败" : errorOutput
                    throw GitError.commandFailed(arguments.joined(separator: " "), fullError)
                }
                
                continuation.resume(returning: ())
            } catch {
                print("❌ Git命令执行异常: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func buildAuthenticatedURL() -> String {
        let cleanURL = remoteURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = githubUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanToken = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return buildAuthenticatedURL(cleanURL: cleanURL, username: cleanUsername, token: cleanToken)
    }
    
    private func buildAuthenticatedURL(cleanURL: String, username: String, token: String) -> String {
        // 如果URL已经包含认证信息，直接返回
        if cleanURL.contains("@") {
            return cleanURL
        }
        
        // GitHub标准认证：https://token@github.com/user/repo.git
        if !token.isEmpty {
            let authenticatedURL = cleanURL.replacingOccurrences(of: "https://", with: "https://\(token)@")
            print("🔧 构建认证URL")
            return authenticatedURL
        }
        
        return cleanURL
    }
}

private enum GitError: LocalizedError {
    case commandFailed(String, String)
    
    var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let output):
            return "Git命令失败: \(command)\n输出: \(output)"
        }
    }
}

// MARK: - 同步记录数据结构
struct SyncRecord: Codable, Identifiable {
    var id = UUID()
    let timestamp: Date
    let operation: SyncOperation
    let success: Bool
    let commitHash: String?
    let filesChanged: Int
    let errorMessage: String?
    
    enum SyncOperation: String, Codable {
        case push = "推送"
        case pull = "拉取"
        case setup = "初始化"
    }
    
    var displayTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
}

// MARK: - 同步历史视图
struct SyncHistoryView: View {
    let history: [SyncRecord]
    let onClearHistory: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("同步历史")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                if !history.isEmpty {
                    Button("清理历史") {
                        showingClearAlert = true
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
                
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 内容
            if history.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("暂无同步记录")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("开始使用GitHub同步功能后，这里会显示详细的同步历史")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(history.sorted { $0.timestamp > $1.timestamp }) { record in
                        SyncRecordRow(record: record)
                    }
                }
            }
        }
        .frame(width: 600, height: 400)
        .alert("确认清理历史", isPresented: $showingClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清理", role: .destructive) {
                onClearHistory()
                dismiss()
            }
        } message: {
            Text("此操作将清除所有同步历史记录，且无法撤销。")
        }
    }
}

struct SyncRecordRow: View {
    let record: SyncRecord
    
    var body: some View {
        HStack(spacing: 12) {
            // 状态图标
            Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(record.success ? .green : .red)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(record.operation.rawValue)
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(record.displayTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let commitHash = record.commitHash {
                    Text("提交: \(String(commitHash.prefix(8)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if record.filesChanged > 0 {
                    Text("文件变化: \(record.filesChanged) 个")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                if let error = record.errorMessage {
                    Text("错误: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - GitHub Token帮助视图

struct GitHubTokenHelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("如何获取GitHub Personal Access Token")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 内容
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("步骤说明")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                Text("1.")
                                    .fontWeight(.medium)
                                    .frame(width: 20, alignment: .leading)
                                Text("打开GitHub，点击右上角头像 → Settings")
                            }
                            
                            HStack(alignment: .top) {
                                Text("2.")
                                    .fontWeight(.medium)
                                    .frame(width: 20, alignment: .leading)
                                Text("在左侧菜单中找到 Developer settings → Personal access tokens → Tokens (classic)")
                            }
                            
                            HStack(alignment: .top) {
                                Text("3.")
                                    .fontWeight(.medium)
                                    .frame(width: 20, alignment: .leading)
                                Text("点击 \"Generate new token (classic)\"")
                            }
                            
                            HStack(alignment: .top) {
                                Text("4.")
                                    .fontWeight(.medium)
                                    .frame(width: 20, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("填写Token信息：")
                                    Text("• Note: 给Token起个名字，如 \"WordTagger Sync\"")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("• Expiration: 建议选择1年")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("• Scopes: 勾选 \"repo\" (完整仓库访问权限)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            HStack(alignment: .top) {
                                Text("5.")
                                    .fontWeight(.medium)
                                    .frame(width: 20, alignment: .leading)
                                Text("点击 \"Generate token\" 并立即复制生成的Token")
                            }
                            
                            HStack(alignment: .top) {
                                Text("6.")
                                    .fontWeight(.medium)
                                    .frame(width: 20, alignment: .leading)
                                Text("将复制的Token粘贴到WordTagger的 \"Personal Access Token\" 字段")
                            }
                        }
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("⚠️ 安全提醒")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("• Token生成后只显示一次，请立即复制保存")
                                .font(.body)
                            Text("• 不要将Token分享给其他人")
                                .font(.body)
                            Text("• Token具有完整的仓库访问权限，请妥善保管")
                                .font(.body)
                            Text("• 如果Token泄露，请立即到GitHub删除并重新生成")
                                .font(.body)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("📖 使用说明")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("配置完成后，WordTagger将能够：")
                                .font(.body)
                            Text("• 自动将你的学习数据推送到GitHub仓库")
                                .font(.body)
                            Text("• 从GitHub拉取最新的数据更新")
                                .font(.body)
                            Text("• 实现多设备间的数据同步")
                                .font(.body)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    // 快捷按钮
                    HStack {
                        Button("在浏览器中打开GitHub设置") {
                            if let url = URL(string: "https://github.com/settings/tokens") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Spacer()
                        
                        Button("关闭") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top)
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - 数据管理子组件

struct ImageManagementSection: View {
    var body: some View {
        GroupBox("图片管理") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "photo.stack")
                        .foregroundColor(.blue)
                    Text("Markdown 图片存储")
                        .fontWeight(.medium)
                    Spacer()
                }
                
                Text("所有通过编辑器上传的图片都保存在此文件夹中")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Button("打开图片文件夹") {
                        openImagesFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button("在 Finder 中显示") {
                        showInFinder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(12)
        }
    }
    
    private func openImagesFolder() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let imagesURL = documentsURL.appendingPathComponent("WordTagger/Images")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true, attributes: nil)
        
        // 打开文件夹
        NSWorkspace.shared.open(imagesURL)
    }
    
    private func showInFinder() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let imagesURL = documentsURL.appendingPathComponent("WordTagger/Images")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true, attributes: nil)
        
        // 在 Finder 中显示
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: imagesURL.path)
    }
}

struct DataStatisticsSection: View {
    @EnvironmentObject private var store: NodeStore
    
    var body: some View {
        GroupBox("数据统计") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("数据概览")
                        .fontWeight(.semibold)
                        .gridColumnAlignment(.leading)
                    Spacer()
                }
                
                Divider()
                    .gridCellUnsizedAxes(.horizontal)
                
                GridRow {
                    Text("层数量")
                        .foregroundColor(.secondary)
                    Text("\(store.layers.count)")
                        .fontWeight(.medium)
                }
                
                GridRow {
                    Text("节点总数")
                        .foregroundColor(.secondary)
                    Text("\(store.nodes.count)")
                        .fontWeight(.medium)
                }
                
                GridRow {
                    Text("标签总数")
                        .foregroundColor(.secondary)
                    Text("\(store.allTags.count)")
                        .fontWeight(.medium)
                }
                
                GridRow {
                    Text("地点标签")
                        .foregroundColor(.secondary)
                    Text("\(store.allTags.filter { $0.hasCoordinates }.count)")
                        .fontWeight(.medium)
                }
                
                Divider()
                    .gridCellUnsizedAxes(.horizontal)
                
                ForEach(Tag.TagType.predefinedCases, id: \.self) { type in
                    GridRow {
                        Text("\(type.displayName)标签")
                            .foregroundColor(.secondary)
                        Text("\(store.nodesCount(forTagType: type)) 个节点")
                            .fontWeight(.medium)
                    }
                }
            }
            .padding(12)
        }
    }
}

struct DataMaintenanceSection: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var dataManager = ExternalDataManager.shared
    @StateObject private var dataService = ExternalDataService.shared
    @State private var showingResultAlert = false
    @State private var resultMessage = ""
    @State private var isSuccess = false
    
    var body: some View {
        GroupBox("数据维护") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundColor(.blue)
                    Text("数据完整性检查")
                        .fontWeight(.medium)
                    Spacer()
                }
                
                Text("检测并自动修复损坏的节点数据，如乱码文本、无效标签等")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Button("检测并修复数据") {
                        Task { @MainActor in
                            let fixedCount = store.detectAndFixCorruptedNodes()
                            if fixedCount > 0 {
                                resultMessage = "已修复 \(fixedCount) 个损坏的数据项"
                                isSuccess = true
                            } else {
                                resultMessage = "未发现损坏的数据，所有数据完好"
                                isSuccess = true
                            }
                            showingResultAlert = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.blue)
                    
                    Button("强制重新加载数据") {
                        Task { @MainActor in
                            if dataManager.isDataPathSelected {
                                // 重新加载外部数据
                                do {
                                    let (layers, nodes) = try await dataService.loadAllData()
                                    await store.replaceAllData(layers: layers, nodes: nodes)
                                    
                                    // 运行数据修复
                                    let fixedCount = store.detectAndFixCorruptedNodes()
                                    
                                    // 简化消息创建逻辑
                                    if fixedCount > 0 {
                                        resultMessage = "数据已重新加载，修复了 \(fixedCount) 个问题"
                                    } else {
                                        resultMessage = "数据已重新加载，未发现问题"
                                    }
                                    isSuccess = true
                                    showingResultAlert = true
                                } catch {
                                    resultMessage = "重新加载数据失败: \(error.localizedDescription)"
                                    isSuccess = false
                                    showingResultAlert = true
                                }
                            } else {
                                resultMessage = "请先设置外部数据存储路径"
                                isSuccess = false
                                showingResultAlert = true
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(12)
        }
        .alert(isSuccess ? "成功" : "错误", isPresented: $showingResultAlert) {
            Button("确定") { }
        } message: {
            Text(resultMessage)
        }
    }
}

struct DangerousOperationsSection: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var dataManager = ExternalDataManager.shared
    @StateObject private var dataService = ExternalDataService.shared
    @State private var showingClearDataAlert = false
    @State private var showingResultAlert = false
    @State private var resultMessage = ""
    @State private var isSuccess = false
    
    var body: some View {
        GroupBox("危险操作") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("数据重置")
                        .fontWeight(.medium)
                    Spacer()
                }
                
                Text("此操作将删除所有节点和标签数据，且无法撤销")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if dataManager.isDataPathSelected {
                    Text("⚠️ 同时会清除外部存储文件中的所有数据")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                }
                
                HStack(spacing: 8) {
                    Button("清除所有数据") {
                        showingClearDataAlert = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.red)
                    .disabled(store.nodes.isEmpty && store.nodes.isEmpty)
                    
                    Button("强制刷新界面") {
                        store.forceRefreshUI()
                        resultMessage = "界面已强制刷新"
                        isSuccess = true
                        showingResultAlert = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(12)
        }
        .alert("确认清除数据", isPresented: $showingClearDataAlert) {
            Button("取消", role: .cancel) { }
            Button("清除", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("此操作将删除所有节点和标签数据，且无法撤销。")
        }
        .alert(isSuccess ? "成功" : "错误", isPresented: $showingResultAlert) {
            Button("确定") { }
        } message: {
            Text(resultMessage)
        }
    }
    
    private func clearAllData() {
        // 清除内存数据
        store.clearAllData()
        
        // 如果有外部数据存储，清除所有外部文件（包括标签映射）
        if dataManager.isDataPathSelected {
            Task {
                do {
                    // 使用新的清理方法，彻底删除所有外部数据文件
                    try await dataService.clearAllExternalData()
                    await MainActor.run {
                        resultMessage = "所有数据已完全清除（包括外部存储和标签设置）"
                        isSuccess = true
                        showingResultAlert = true
                    }
                } catch {
                    await MainActor.run {
                        resultMessage = "数据已清除，但清理外部存储失败: \(error.localizedDescription)"
                        isSuccess = false
                        showingResultAlert = true
                    }
                }
            }
        } else {
            resultMessage = "所有数据已清除"
            isSuccess = true
            showingResultAlert = true
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(NodeStore.shared)
}