import SwiftUI
import CoreLocation
import MapKit
import MapKit

struct MapWindow: View {
    @EnvironmentObject private var store: WordStore
    @State private var isLocationSelectionMode = false
    
    var body: some View {
        MapContainer(isLocationSelectionMode: $isLocationSelectionMode)
            .navigationTitle(isLocationSelectionMode ? "选择位置" : "地图窗口")
            .onAppear {
                // 监听打开地图窗口的通知
                NotificationCenter.default.addObserver(
                    forName: .openMapWindow,
                    object: nil,
                    queue: .main
                ) { _ in
                    isLocationSelectionMode = false
                }
                
                // 监听打开地图进行位置选择的通知
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("openMapForLocationSelection"),
                    object: nil,
                    queue: .main
                ) { _ in
                    print("MapWindow: Received openMapForLocationSelection notification")
                    isLocationSelectionMode = true
                }
            }
    }
}


#Preview {
    MapWindow()
        .environmentObject(WordStore.shared)
}