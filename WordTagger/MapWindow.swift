import SwiftUI
import CoreLocation
import MapKit
import MapKit

struct MapWindow: View {
    @EnvironmentObject private var store: NodeStore
    @State private var isLocationSelectionMode = false
    
    var body: some View {
        MapContainer(isLocationSelectionMode: $isLocationSelectionMode)
            .navigationTitle(isLocationSelectionMode ? "选择位置" : "地图窗口")
            .onAppear {
                print("MapWindow appeared, current isLocationSelectionMode: \(isLocationSelectionMode)")
                
                // 监听打开地图窗口的通知
                NotificationCenter.default.addObserver(
                    forName: .openMapWindow,
                    object: nil,
                    queue: .main
                ) { _ in
                    print("MapWindow: Received openMapWindow notification")
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
                
                // 检查是否应该直接进入位置选择模式
                // 通过延迟检查来给通知时间到达
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    print("MapWindow: Delayed check, isLocationSelectionMode: \(isLocationSelectionMode)")
                }
            }
            .onChange(of: isLocationSelectionMode) { _, newValue in
                print("MapWindow: isLocationSelectionMode changed to \(newValue)")
            }
    }
}


#Preview {
    MapWindow()
        .environmentObject(NodeStore.shared)
}