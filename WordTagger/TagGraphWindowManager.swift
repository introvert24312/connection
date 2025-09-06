import SwiftUI
import Combine

/// 管理标签图谱窗口状态的共享对象
/// 解决SwiftUI WindowGroup重用窗口时状态不更新的问题
@MainActor
class TagGraphWindowManager: ObservableObject {
    /// 全局共享实例
    static let shared = TagGraphWindowManager()
    
    /// 当前选中的标签类型
    @Published var currentTagType: Tag.TagType? {
        didSet {
            if let newType = currentTagType {
                print("🏷️ TagGraphWindowManager: 更新当前标签类型为 \(newType.displayName)")
                
                // 发送通知作为向后兼容的机制
                NotificationCenter.default.post(
                    name: NSNotification.Name("tagGraphWindowManagerDidUpdateTagType"),
                    object: newType
                )
            } else {
                print("🏷️ TagGraphWindowManager: 清空当前标签类型")
            }
        }
    }
    
    /// 窗口是否正在显示
    @Published var isWindowVisible: Bool = false
    
    /// 私有初始化器，确保单例模式
    private init() {
        print("🏗️ TagGraphWindowManager: 初始化共享管理器")
        
        // 🔧 修复重复窗口问题：移除重复的通知监听器
        // 因为 WordTaggerApp 已经在处理 "openTagTypeGraph" 通知
        // 不再需要在这里重复监听
    }
    
    /// 更新当前标签类型
    /// - Parameter tagType: 新的标签类型
    func updateTagType(_ tagType: Tag.TagType) {
        print("🔄 TagGraphWindowManager: 请求更新标签类型为 \(tagType.displayName)")
        
        // 如果是同一个类型且窗口已显示，不需要更新
        if currentTagType == tagType && isWindowVisible {
            print("ℹ️ TagGraphWindowManager: 标签类型相同且窗口已显示，跳过更新")
            return
        }
        
        currentTagType = tagType
        isWindowVisible = true
    }
    
    /// 清除当前状态（窗口关闭时调用）
    func clearState() {
        print("🗑️ TagGraphWindowManager: 清除状态")
        currentTagType = nil
        isWindowVisible = false
    }
    
    /// 标记窗口已显示
    func markWindowVisible() {
        if !isWindowVisible {
            print("👁️ TagGraphWindowManager: 标记窗口为可见")
            isWindowVisible = true
        }
    }
    
    /// 标记窗口已隐藏
    func markWindowHidden() {
        if isWindowVisible {
            print("🙈 TagGraphWindowManager: 标记窗口为隐藏")
            isWindowVisible = false
        }
    }
    
    // MARK: - 向后兼容性
    // 🔧 修复重复窗口问题：已移除重复的通知处理器
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - 扩展：便利方法

extension TagGraphWindowManager {
    /// 检查是否有有效的标签类型
    var hasValidTagType: Bool {
        return currentTagType != nil
    }
    
    /// 获取当前标签类型的显示名称
    var currentTagTypeDisplayName: String {
        return currentTagType?.displayName ?? "未知标签类型"
    }
}