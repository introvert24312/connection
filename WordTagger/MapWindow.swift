import SwiftUI
import CoreLocation
import MapKit

struct MapWindow: View {
    @EnvironmentObject private var store: NodeStore
    @State private var isLocationSelectionMode = false
    @State private var windowId = UUID()
    @State private var sourceWindowId: String? = nil
    @State private var windowCreationTime = Date()
    @State private var openedForBrowsingOnly = false
    
    var body: some View {
        MapContainer(isLocationSelectionMode: $isLocationSelectionMode, sourceWindowId: sourceWindowId)
            .navigationTitle(isLocationSelectionMode ? "选择位置" : "地图窗口")
            .registerWindow(windowId, type: .map, displayName: "地图视图")
            .onAppear {
                print("MapWindow appeared, current isLocationSelectionMode: \(isLocationSelectionMode)")
                
                // 监听设置地图窗口映射的通知
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("setupMapWindowMapping"),
                    object: nil,
                    queue: .main
                ) { notification in
                    print("MapWindow: Received setupMapWindowMapping notification")
                    
                    // 🔧 关键修复：标记此窗口为浏览模式，永远不响应位置选择通知
                    openedForBrowsingOnly = true
                    isLocationSelectionMode = false  // 确保重置位置选择模式
                    print("🔧 MapWindow: 已标记为浏览模式窗口，重置位置选择模式，将忽略所有位置选择请求")
                    
                    // 🔧 修复：如果通知包含源窗口信息，立即设置映射
                    if let sourceInfo = notification.object as? [String: String],
                       let sourceId = sourceInfo["sourceWindowId"] {
                        print("🎯 MapWindow: 从setupMapWindowMapping通知获取源窗口ID - \(sourceId.prefix(8))")
                        print("🎯 MapWindow: 完整源窗口ID = \(sourceId)")
                        sourceWindowId = sourceId
                        // 创建窗口映射关系
                        Task { @MainActor in
                            WindowFocusManager.shared.createWindowMapping(
                                childWindowId: windowId.uuidString,
                                sourceWindowId: sourceId
                            )
                        }
                        print("✅ MapWindow: 立即设置窗口映射 - 源窗口: \(sourceId.prefix(8))")
                        print("✅ MapWindow: 地图窗口ID = \(windowId.uuidString.prefix(8))")
                    } else {
                        print("⚠️ MapWindow: setupMapWindowMapping通知中没有sourceWindowId！")
                    }
                }
                
                // 监听打开地图进行位置选择的通知
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("openMapForLocationSelection"),
                    object: nil,
                    queue: .main
                ) { notification in
                    print("MapWindow: ✅ Received openMapForLocationSelection notification!")
                    
                    // 🔧 关键修复：如果此窗口是专门为浏览模式打开的，直接忽略
                    if openedForBrowsingOnly {
                        print("🚫 MapWindow: 忽略位置选择通知 - 此窗口是浏览模式窗口")
                        return
                    }
                    
                    // 🔧 修复：只有在这个地图窗口是新创建的时才响应位置选择通知
                    let shouldRespond: Bool
                    let windowAge = Date().timeIntervalSince(windowCreationTime)
                    
                    if let targetData = notification.object as? [String: Any] {
                        if let targetWindowId = targetData["targetWindowId"] as? String,
                           targetWindowId == windowId.uuidString {
                            // 明确指定了目标窗口ID
                            shouldRespond = true
                            print("MapWindow: 通知指定了目标窗口，匹配当前窗口")
                        } else if let requestTime = targetData["requestTime"] as? Date {
                            // 🔧 修复：更严格的时间验证 - 只有在窗口创建后0.8秒内发出的请求才被接受
                            let timeDiff = abs(requestTime.timeIntervalSince(windowCreationTime))
                            shouldRespond = timeDiff <= 0.8 && windowAge <= 2.0
                            print("MapWindow: 带时间戳的请求(时间差: \(String(format: "%.1f", timeDiff))s, 窗口年龄: \(String(format: "%.1f", windowAge))s) -> 响应: \(shouldRespond)")
                        } else {
                            shouldRespond = false
                            print("MapWindow: 通知有数据但不包含时间戳或目标窗口")
                        }
                    } else if notification.object == nil {
                        // 向后兼容：没有任何数据的通知，只有非常新的窗口才响应
                        shouldRespond = windowAge <= 1.0
                        print("MapWindow: 空通知，窗口年龄: \(String(format: "%.1f", windowAge))s -> 响应: \(shouldRespond)")
                    } else {
                        shouldRespond = false
                        print("MapWindow: 忽略位置选择通知 - 不是针对此窗口的")
                    }
                    
                    if shouldRespond {
                        print("MapWindow: 设置位置选择模式")
                        isLocationSelectionMode = true
                    } else {
                        print("MapWindow: 忽略位置选择通知 - 这是已存在的地图窗口")
                    }
                    
                    print("MapWindow: isLocationSelectionMode is now: \(isLocationSelectionMode)")
                }
                
                // 监听清除标签筛选通知
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("clearTagFilter"),
                    object: nil,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        // clearTagFilter是全局命令，应该在任何活跃窗口中可用
                        if !WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true, commandName: "clearTagFilter") {
                            print("🚫 地图窗口: 忽略clearTagFilter通知 - 应用无活跃窗口")
                            return
                        }
                        print("✅ 地图窗口: 处理clearTagFilter通知，清除标签筛选")
                        store.clearTagFilter()
                    }
                }
                
                // 监听 restorePreviousTagFilterState 通知
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("restorePreviousTagFilterState"),
                    object: nil,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        // restorePreviousTagFilterState是全局命令，应该在任何活跃窗口中可用
                        if !WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true, commandName: "restorePreviousTagFilterState") {
                            print("🚫 地图窗口: 忽略restorePreviousTagFilterState通知 - 应用无活跃窗口")
                            return
                        }
                        print("✅ 地图窗口: 处理restorePreviousTagFilterState通知，恢复标签筛选")
                        store.restorePreviousTagFilterState()
                    }
                }
                
                // 监听 mapWindowSetupMapping 通知，获取源窗口信息并创建映射
                print("🔗 MapWindow: 开始监听mapWindowSetupMapping通知...")
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("mapWindowSetupMapping"),
                    object: nil,
                    queue: .main
                ) { notification in
                    print("🔗 MapWindow: 收到mapWindowSetupMapping通知")
                    print("🔗 MapWindow: notification.object = \(notification.object ?? "nil")")
                    print("🔗 MapWindow: 当前windowId = \(windowId.uuidString.prefix(8))")
                    print("🔗 MapWindow: 更新前sourceWindowId = \(sourceWindowId?.prefix(8) ?? "nil")")
                    
                    if let sourceInfo = notification.object as? [String: String],
                       let sourceId = sourceInfo["sourceWindowId"] {
                        
                        // 🔧 检查是否是针对这个特定地图窗口的通知
                        if let targetMapWindowId = sourceInfo["targetMapWindowId"] {
                            if targetMapWindowId != windowId.uuidString {
                                print("🚫 MapWindow: 忽略mapWindowSetupMapping通知 - 目标窗口不匹配")
                                print("   - 目标ID: \(targetMapWindowId.prefix(8))")
                                print("   - 当前ID: \(windowId.uuidString.prefix(8))")
                                return
                            }
                            print("🎯 MapWindow: 通知匹配当前地图窗口 - \(targetMapWindowId.prefix(8))")
                        } else {
                            // 向后兼容：如果没有指定目标，则使用全局处理方式
                            print("⚠️ MapWindow: mapWindowSetupMapping通知未指定目标，使用全局处理模式")
                        }
                        
                        let oldSourceId = sourceWindowId
                        sourceWindowId = sourceId
                        // 创建窗口映射关系
                        Task { @MainActor in
                            WindowFocusManager.shared.createWindowMapping(
                                childWindowId: windowId.uuidString,
                                sourceWindowId: sourceId
                            )
                        }
                        print("✅ MapWindow: 设置sourceWindowId = \(sourceId.prefix(8))")
                        print("🔄 MapWindow: sourceWindowId 变更: \(oldSourceId?.prefix(8) ?? "nil") → \(sourceId.prefix(8))")
                        print("🗺️ 地图窗口: 记录源窗口ID并创建映射 - \(sourceId)")
                    } else {
                        print("⚠️ MapWindow: 未能从mapWindowSetupMapping通知中获取sourceWindowId")
                    }
                }
                
                // 🔧 主动请求窗口映射信息，解决多窗口冲突问题
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    print("🔍 MapWindow: 主动请求窗口映射信息...")
                    print("🔍 MapWindow: 当前sourceWindowId = \(sourceWindowId?.prefix(8) ?? "仍然是nil")")
                    
                    if sourceWindowId == nil {
                        print("🔄 MapWindow: sourceWindowId为nil，主动请求映射...")
                        // 🎯 发送带有地图窗口ID的请求，让源窗口直接回复给这个地图窗口
                        NotificationCenter.default.post(
                            name: NSNotification.Name("requestWindowMappingForMap"),
                            object: [
                                "mapWindowId": windowId.uuidString,
                                "requestedBy": "MapWindow-\(windowId.uuidString.prefix(8))"
                            ]
                        )
                        print("📤 MapWindow: 已发送requestWindowMappingForMap请求 - mapWindowId: \(windowId.uuidString.prefix(8))")
                    } else {
                        print("✅ MapWindow: sourceWindowId已设置，无需请求")
                    }
                }
                
                // 检查是否应该直接进入位置选择模式
                // 通过延迟检查来给通知时间到达
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    print("MapWindow: Delayed check, isLocationSelectionMode: \(isLocationSelectionMode)")
                }
            }
            .onChange(of: isLocationSelectionMode) { _, newValue in
                print("MapWindow: isLocationSelectionMode changed to \(newValue)")
            }
            .onDisappear {
                // 清理窗口映射
                Task { @MainActor in
                    WindowFocusManager.shared.removeWindowMapping(for: windowId.uuidString)
                }
            }
    }
}


#Preview {
    MapWindow()
        .environmentObject(NodeStore.shared)
}
