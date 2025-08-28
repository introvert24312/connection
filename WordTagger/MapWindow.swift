import SwiftUI
import CoreLocation
import MapKit

struct MapWindow: View {
    @EnvironmentObject private var store: NodeStore
    @State private var isLocationSelectionMode = false
    @State private var windowId = UUID()
    @State private var sourceWindowId: String? = nil
    
    var body: some View {
        MapContainer(isLocationSelectionMode: $isLocationSelectionMode, sourceWindowId: sourceWindowId)
            .navigationTitle(isLocationSelectionMode ? "选择位置" : "地图窗口")
            .registerWindow(windowId, type: .map, displayName: "地图视图")
            .onAppear {
                print("MapWindow appeared, current isLocationSelectionMode: \(isLocationSelectionMode)")
                
                // 监听打开地图窗口的通知
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("openMapWindow"),
                    object: nil,
                    queue: .main
                ) { notification in
                    print("MapWindow: Received openMapWindow notification")
                    
                    // 🔧 修复：如果通知包含源窗口信息，立即设置映射
                    if let sourceInfo = notification.object as? [String: String],
                       let sourceId = sourceInfo["sourceWindowId"] {
                        print("🎯 MapWindow: 直接从openMapWindow通知获取源窗口ID - \(sourceId.prefix(8))")
                        sourceWindowId = sourceId
                        // 创建窗口映射关系
                        WindowFocusManager.shared.createWindowMapping(
                            childWindowId: windowId.uuidString,
                            sourceWindowId: sourceId
                        )
                        print("✅ MapWindow: 立即设置窗口映射 - 源窗口: \(sourceId.prefix(8))")
                    }
                    
                    // 不改变 isLocationSelectionMode，让 openMapForLocationSelection 通知来控制
                }
                
                // 监听打开地图进行位置选择的通知
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("openMapForLocationSelection"),
                    object: nil,
                    queue: .main
                ) { _ in
                    print("MapWindow: ✅ Received openMapForLocationSelection notification!")
                    print("MapWindow: Setting isLocationSelectionMode = true")
                    isLocationSelectionMode = true
                    print("MapWindow: isLocationSelectionMode is now: \(isLocationSelectionMode)")
                }
                
                // 监听清除标签筛选通知
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("clearTagFilter"),
                    object: nil,
                    queue: .main
                ) { _ in
                    // clearTagFilter是全局命令，应该在任何活跃窗口中可用
                    if !WindowFocusManager.shared.shouldHandleNotification(for: windowId, isGlobalCommand: true, commandName: "clearTagFilter") {
                        print("🚫 地图窗口: 忽略clearTagFilter通知 - 应用无活跃窗口")
                        return
                    }
                    print("✅ 地图窗口: 处理clearTagFilter通知，清除标签筛选")
                    store.clearTagFilter()
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
                        WindowFocusManager.shared.createWindowMapping(
                            childWindowId: windowId.uuidString,
                            sourceWindowId: sourceId
                        )
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
                WindowFocusManager.shared.removeWindowMapping(for: windowId.uuidString)
            }
    }
}


#Preview {
    MapWindow()
        .environmentObject(NodeStore.shared)
}
