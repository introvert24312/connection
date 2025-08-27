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
                    
                    if let sourceInfo = notification.object as? [String: String],
                       let sourceId = sourceInfo["sourceWindowId"] {
                        sourceWindowId = sourceId
                        // 创建窗口映射关系
                        WindowFocusManager.shared.createWindowMapping(
                            childWindowId: windowId.uuidString,
                            sourceWindowId: sourceId
                        )
                        print("✅ MapWindow: 设置sourceWindowId = \(sourceId.prefix(8))")
                        print("🗺️ 地图窗口: 记录源窗口ID并创建映射 - \(sourceId)")
                    } else {
                        print("⚠️ MapWindow: 未能从mapWindowSetupMapping通知中获取sourceWindowId")
                    }
                }
                
                // 立即检查是否有待处理的映射通知 - 解决时序问题
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    print("🔍 MapWindow: 延迟检查sourceWindowId状态...")
                    print("🔍 MapWindow: 当前sourceWindowId = \(sourceWindowId ?? "仍然是nil")")
                    if sourceWindowId == nil {
                        print("⚠️ MapWindow: 窗口映射可能存在时序问题，尝试手动请求映射...")
                        // 手动请求窗口映射
                        NotificationCenter.default.post(
                            name: NSNotification.Name("requestWindowMapping"),
                            object: ["childWindowId": windowId.uuidString, "windowType": "map"]
                        )
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
