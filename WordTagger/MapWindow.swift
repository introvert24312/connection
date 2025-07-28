import SwiftUI
import CoreLocation
import MapKit
import MapKit

struct MapWindow: View {
    @EnvironmentObject private var store: WordStore
    
    var body: some View {
        MapContainer()
            .navigationTitle("地图窗口")
            .onAppear {
                // 监听打开地图窗口的通知
                NotificationCenter.default.addObserver(
                    forName: .openMapWindow,
                    object: nil,
                    queue: .main
                ) { _ in
                    // 窗口已经打开，可以在这里做一些操作
                }
            }
    }
}


#Preview {
    MapWindow()
        .environmentObject(WordStore.shared)
}