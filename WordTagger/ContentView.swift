import SwiftUI
import CoreLocation
import MapKit

struct ContentView: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var dataManager = ExternalDataManager.shared
    @State private var selectedNode: Node?
    @State private var showSidebar: Bool = true
    @State private var showingDataSetup = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            // 左侧：标签和搜索
            if showSidebar {
                TagSidebarView(selectedNode: $selectedNode)
                    .frame(width: 300)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            
            // 中间：单词列表
            NodeListView(selectedNode: $selectedNode)
                .frame(minWidth: showSidebar ? 350 : 400, maxWidth: showSidebar ? 400 : 450)
            
            // 右侧：详情面板 (图谱区域)
            if let node = selectedNode {
                DetailPanel(node: node)
                    .frame(minWidth: showSidebar ? 500 : 650)
            } else {
                WelcomeView()
                    .frame(minWidth: showSidebar ? 500 : 650)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showSidebar)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("requestOpenFullscreenGraph"))) { _ in
            Swift.print("📝 ContentView: 收到打开全屏图谱请求")
            openWindow(id: "fullscreenGraph")
        }
        .onKeyPress(.escape) {
            // 如果标签管理打开，按ESC键关闭它
            print("🔑 ContentView: ESC键事件接收，showSidebar=\(showSidebar)")
            if showSidebar {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showSidebar = false
                }
                print("🔑 ContentView: ESC键按下，关闭标签管理")
                return .handled
            }
            print("🔑 ContentView: ESC键忽略，标签管理未打开")
            return .ignored
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {
                    openWindow(id: "map")
                }) {
                    Image(systemName: "map")
                        .foregroundColor(.blue)
                }
                .help("打开地图视图 (⌘M)")
                
                Button(action: {
                    openWindow(id: "graph")
                }) {
                    Image(systemName: "circle.hexagonpath")
                        .foregroundColor(.purple)
                }
                .help("打开全局图谱 (⌘G)")
                
                Button(action: {
                    store.selectNode(nil)
                    selectedNode = nil
                }) {
                    Image(systemName: "clear")
                        .foregroundColor(.gray)
                }
                .help("清除选择")
            }
        }
        .onAppear {
            // 同步selectedNode状态
            DispatchQueue.main.async {
                selectedNode = store.selectedNode
            }
            
            // 注册通知监听器
            NotificationCenter.default.addObserver(
                forName: .openMapWindow,
                object: nil,
                queue: .main
            ) { _ in
                openWindow(id: "map")
            }
            
            NotificationCenter.default.addObserver(
                forName: .openGraphWindow,
                object: nil,
                queue: .main
            ) { _ in
                openWindow(id: "graph")
            }
            
            NotificationCenter.default.addObserver(
                forName: Notification.Name("openNodeManager"),
                object: nil,
                queue: .main
            ) { _ in
                openWindow(id: "nodeManager")
            }
            
            // 监听切换侧边栏的通知
            NotificationCenter.default.addObserver(
                forName: Notification.Name("toggleSidebar"),
                object: nil,
                queue: .main
            ) { _ in
                print("🔔 ContentView: 收到toggleSidebar通知，当前showSidebar=\(showSidebar)")
                withAnimation(.easeInOut(duration: 0.3)) {
                    showSidebar.toggle()
                }
                print("🔔 ContentView: 切换后showSidebar=\(showSidebar)")
            }
            
            // 检查数据路径设置
            if !dataManager.isDataPathSelected {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showingDataSetup = true
                }
            }
        }
        .onChange(of: store.selectedNode) { _, newValue in
            DispatchQueue.main.async {
                selectedNode = newValue
            }
        }
        .onChange(of: store.nodes) { _, _ in
            // 当nodes变化时，检查selectedNode是否还有效
            DispatchQueue.main.async {
                if let current = selectedNode, !store.nodes.contains(where: { $0.id == current.id }) {
                    selectedNode = nil
                }
            }
        }
        .sheet(isPresented: $showingDataSetup) {
            DataFolderSetupView(isPresented: $showingDataSetup)
        }
    }
}

// MARK: - 欢迎视图

struct WelcomeView: View {
    @EnvironmentObject private var store: NodeStore
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "book.closed")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("欢迎使用节点标签管理器")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("使用智能标签系统来组织和记忆节点")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                    Text("按 ⌘N 添加新节点")
                }
                
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.blue)
                    Text("按 ⌘F 搜索节点")
                }
                
                HStack {
                    Image(systemName: "command")
                        .foregroundColor(.purple)
                    Text("按 ⌘K 打开命令面板")
                }
            }
            .font(.body)
            .foregroundColor(.secondary)
            
            Spacer()
            
            VStack(spacing: 8) {
                Text("当前统计")
                    .font(.headline)
                
                HStack(spacing: 30) {
                    StatCard(title: "节点总数", value: "\(store.nodes.count)", color: .blue)
                    StatCard(title: "标签总数", value: "\(store.allTags.count)", color: .green)
                    StatCard(title: "地点标签", value: "\(store.allTags.filter { $0.hasCoordinates }.count)", color: .red)
                }
            }
            
            Spacer()
        }
        .padding(40)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(NodeStore.shared)
}