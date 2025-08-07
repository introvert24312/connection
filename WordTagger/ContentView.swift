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
                    .frame(minWidth: showSidebar ? 400 : 500, maxWidth: .infinity)
            } else {
                WelcomeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showSidebar)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("requestOpenFullscreenGraph"))) { _ in
            Swift.print("📝 ContentView: 收到打开全屏图谱请求")
            openWindow(id: "fullscreenGraph")
        }
        .onKeyPress(.init("l"), phases: .down) { keyPress in
            if keyPress.modifiers == .command {
                // 检查是否有全屏图谱窗口打开
                let windowManager = FullscreenGraphWindowManager.shared
                if windowManager.isWindowActive() {
                    Swift.print("📝 ContentView: Command+L - 关闭全屏图谱窗口")
                    windowManager.hideFullscreenGraph()
                    return .handled
                }
            }
            return .ignored
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
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)
                
                VStack(spacing: 16) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    Text("欢迎使用节点标签管理器")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("使用智能标签系统来组织和记忆节点")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                        Text("按 ⌘N 添加新节点")
                            .font(.callout)
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.blue)
                        Text("按 ⌘F 搜索节点")
                            .font(.callout)
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "command")
                            .foregroundColor(.purple)
                        Text("按 ⌘K 打开命令面板")
                            .font(.callout)
                    }
                }
                .foregroundColor(.secondary)
                
                VStack(spacing: 8) {
                    Text("当前统计")
                        .font(.headline)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                        StatCard(title: "节点总数", value: "\(store.nodes.count)", color: .blue)
                        StatCard(title: "标签总数", value: "\(store.allTags.count)", color: .green)
                        StatCard(title: "地点标签", value: "\(store.allTags.filter { $0.hasCoordinates }.count)", color: .red)
                    }
                }
                
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(NodeStore.shared)
}