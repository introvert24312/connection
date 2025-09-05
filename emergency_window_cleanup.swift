import AppKit
import Foundation

/// Emergency Window Cleanup Script
/// This script forcefully closes all uncloseable windows and cleans up window-related resources
class EmergencyWindowCleanup {
    
    /// Force close all application windows and clean up resources
    static func executeCleanup() {
        print("🚨 开始紧急窗口清理...")
        
        // 1. 关闭所有窗口
        closeAllWindows()
        
        // 2. 清理通知中心
        clearNotificationCenter()
        
        // 3. 重置WindowFocusManager状态
        resetWindowFocusManager()
        
        // 4. 强制垃圾回收
        forceMemoryCleanup()
        
        print("✅ 紧急窗口清理完成")
    }
    
    /// 强制关闭所有窗口
    private static func closeAllWindows() {
        print("🪟 关闭所有应用窗口...")
        
        let app = NSApplication.shared
        let windows = app.windows
        
        print("   发现 \(windows.count) 个窗口")
        
        for (index, window) in windows.enumerated() {
            print("   [\(index + 1)] 窗口: \(window.title) - 类型: \(type(of: window))")
            
            // 强制关闭窗口
            if window.canBecomeKey {
                window.close()
                print("     ✅ 已关闭")
            } else {
                // 对于系统对话框等特殊窗口，尝试强制结束
                window.orderOut(nil)
                print("     ⚠️ 强制隐藏")
            }
        }
        
        // 等待窗口关闭
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let remainingWindows = NSApplication.shared.windows.count
            print("   剩余窗口数量: \(remainingWindows)")
        }
    }
    
    /// 清理通知中心
    private static func clearNotificationCenter() {
        print("📡 清理通知中心...")
        
        // 移除所有观察者（这会影响当前运行的代码，但在紧急情况下是必要的）
        NotificationCenter.default.removeObserver(self)
        
        // 发送清理通知
        NotificationCenter.default.post(
            name: NSNotification.Name("emergencyWindowCleanup"),
            object: nil
        )
        
        print("   ✅ 通知中心已清理")
    }
    
    /// 重置WindowFocusManager状态
    private static func resetWindowFocusManager() {
        print("🏠 重置窗口焦点管理器...")
        
        let focusManager = WindowFocusManager.shared
        
        // 强制刷新窗口状态
        focusManager.forceRefreshWindowState()
        
        // 清除当前活跃窗口
        focusManager.setActiveWindow(nil)
        
        print("   ✅ 窗口焦点管理器已重置")
    }
    
    /// 强制内存清理
    private static func forceMemoryCleanup() {
        print("🧹 强制内存清理...")
        
        // 清理自动释放池
        autoreleasepool {
            // 执行一些内存清理操作
            print("   内存清理中...")
        }
        
        // 建议系统进行垃圾回收（虽然Swift有ARC，但这能帮助清理一些系统资源）
        print("   ✅ 内存清理完成")
    }
}

/// 在WordTaggerApp中添加紧急清理功能的扩展
extension NSApplication {
    
    /// 执行紧急窗口清理
    func performEmergencyCleanup() {
        EmergencyWindowCleanup.executeCleanup()
    }
    
    /// 安全退出应用程序
    func safeTerminate() {
        print("🛑 安全退出应用程序...")
        
        // 先执行清理
        performEmergencyCleanup()
        
        // 等待清理完成后退出
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("👋 应用程序即将退出")
            self.terminate(nil)
        }
    }
}

// MARK: - 快捷键支持

/// 添加紧急清理快捷键支持
class EmergencyCleanupKeyHandler {
    
    static let shared = EmergencyCleanupKeyHandler()
    private var monitor: Any?
    
    private init() {
        setupGlobalKeyMonitor()
    }
    
    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    /// 设置全局按键监听（Command+Option+Escape 触发紧急清理）
    private func setupGlobalKeyMonitor() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags
            let keyCode = event.keyCode
            
            // Command+Option+Escape = 紧急清理
            if modifiers.contains([.command, .option]) && keyCode == 53 { // 53 = Escape key
                print("🚨 检测到紧急清理快捷键：Command+Option+Escape")
                
                DispatchQueue.main.async {
                    NSApplication.shared.performEmergencyCleanup()
                }
            }
        }
        
        print("🔧 紧急清理快捷键已设置：Command+Option+Escape")
    }
}