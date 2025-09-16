import SwiftUI
import AppKit

/// 用于检测真实的窗口点击（而不是系统的窗口激活）
struct WindowClickTracker: NSViewRepresentable {
    let windowId: UUID
    let windowType: String
    
    func makeNSView(context: Context) -> ClickDetectorView {
        return ClickDetectorView(windowId: windowId, windowType: windowType)
    }
    
    func updateNSView(_ nsView: ClickDetectorView, context: Context) {
        // 不需要更新
    }
}

/// 检测点击的NSView
@objcMembers
class ClickDetectorView: NSView {
    public let windowId: UUID
    let windowType: String
    
    init(windowId: UUID, windowType: String) {
        self.windowId = windowId
        self.windowType = windowType
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if let window = self.window {
            // 立即建立NSWindow与UUID的映射
            WindowFocusManager.shared.associateNSWindowWithUUID(window, uuid: windowId)
            print("🔗 WindowClickTracker: 建立窗口映射 - NSWindow <-> \(windowId.uuidString.prefix(8))")
            
            // 监听窗口成为key的事件
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowBecameKey),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
        }
    }
    
    @objc private func windowBecameKey(_ notification: Notification) {
        // 检查当前事件是否是鼠标点击
        if let event = NSApp.currentEvent {
            let isMouseClick = event.type == .leftMouseDown || 
                             event.type == .rightMouseDown ||
                             event.type == .leftMouseUp ||
                             event.type == .rightMouseUp
            
            if isMouseClick {
                // 这是真正的用户点击
                NotificationCenter.default.post(
                    name: NSNotification.Name("userClickedWindow"),
                    object: nil,
                    userInfo: [
                        "windowId": windowId.uuidString,
                        "windowType": windowType,
                        "isRealClick": true
                    ]
                )
                print("🖱️ 检测到真实的窗口点击 - \(windowId.uuidString.prefix(8))")
            } else {
                // 不是鼠标点击，但仍然记录用于调试
                print("⚠️ 窗口成为key但不是鼠标点击 - \(windowId.uuidString.prefix(8))")
                print("   事件类型: \(event.type.rawValue)")
            }
        } else {
            // NSApp.currentEvent为nil，尝试备用方案
            print("⚠️ NSApp.currentEvent为nil - \(windowId.uuidString.prefix(8))")
            
            // 备用方案：延迟检查
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self else { return }
                if let delayedEvent = NSApp.currentEvent {
                    let isMouseClick = delayedEvent.type == .leftMouseDown || 
                                     delayedEvent.type == .rightMouseDown ||
                                     delayedEvent.type == .leftMouseUp ||
                                     delayedEvent.type == .rightMouseUp
                    
                    if isMouseClick {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("userClickedWindow"),
                            object: nil,
                            userInfo: [
                                "windowId": self.windowId.uuidString,
                                "windowType": self.windowType,
                                "isRealClick": true
                            ]
                        )
                        print("🖱️ [延迟检测] 检测到真实的窗口点击 - \(self.windowId.uuidString.prefix(8))")
                    }
                }
            }
        }
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // 让点击穿透到下面的视图
        return nil
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension View {
    /// 添加窗口点击追踪
    func trackWindowClicks(windowId: UUID, windowType: String = "standard") -> some View {
        self.background(
            WindowClickTracker(windowId: windowId, windowType: windowType)
                .allowsHitTesting(false)
        )
    }
}