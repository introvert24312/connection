import SwiftUI
import CoreLocation
import MapKit

struct ContentView: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var dataManager = ExternalDataManager.shared
    @State private var selectedNode: Node?
    @State private var showSidebar: Bool = true
    @State private var showingDataSetup = false
    @State private var wordListWidth: CGFloat = 280 // 收窄WordList默认宽度
    @State private var isDraggingDivider = false // 是否正在拖动分割线
    @Environment(\.openWindow) private var openWindow
    
    

    var body: some View {
        HStack(spacing: 0) {
            // 左侧：标签和搜索
            if showSidebar {
                TagSidebarView(selectedNode: $selectedNode)
                    .frame(width: 220)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            
            // 中间：单词列表 - 可拖动调节宽度
            NodeListView(selectedNode: $selectedNode)
                .frame(width: wordListWidth)
            
            // 拖动分割线
            ResizableDivider(
                width: $wordListWidth,
                isDragging: $isDraggingDivider,
                minWidth: showSidebar ? 160 : 200,
                maxWidth: showSidebar ? 350 : 400
            )
            
            // 右侧：详情面板 (图谱区域)
            if let node = selectedNode {
                DetailPanel(node: node)
                    .frame(minWidth: 320, maxWidth: .infinity)
            } else {
                WelcomeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showSidebar)
        .onChange(of: showSidebar) { _, newValue in
            // 当侧边栏状态改变时，调整WordList宽度以适应新的约束
            let minWidth: CGFloat = newValue ? 160 : 200
            let maxWidth: CGFloat = newValue ? 350 : 400
            wordListWidth = max(minWidth, min(maxWidth, wordListWidth))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("requestOpenFullscreenGraph"))) { _ in
            Swift.print("📝 ContentView: 收到打开全屏图谱请求")
            openWindow(id: "fullscreenGraph")
        }
        .onKeyPress(.init("t"), phases: .down) { keyPress in
            if keyPress.modifiers == .command {
                print("🔑 ContentView: Command+T键按下")
                // 如果有选中的节点，切换到详情面板并切换编辑模式
                if let node = selectedNode {
                    print("🔑 ContentView: 有选中节点，切换详情编辑模式")
                    // 发送通知给DetailPanel切换编辑模式
                    NotificationCenter.default.post(
                        name: NSNotification.Name("toggleDetailEditMode"),
                        object: node
                    )
                    return .handled
                } else {
                    print("🔑 ContentView: 无选中节点，忽略Command+T")
                    return .ignored
                }
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if showSidebar {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showSidebar = false
                }
                return .handled
            }
            return .ignored
        }
        // 为独立窗口添加快捷键支持
        .onKeyPress(.init("e"), phases: .down) { keyPress in
            if keyPress.modifiers == .command {
                print("🔑 ContentView: Command+E键按下 - 切换侧边栏")
                withAnimation(.easeInOut(duration: 0.3)) {
                    showSidebar.toggle()
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.init("m"), phases: .down) { keyPress in
            if keyPress.modifiers == .command {
                print("🔑 ContentView: Command+M键按下 - 打开地图")
                openWindow(id: "map")
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.init("g"), phases: .down) { keyPress in
            if keyPress.modifiers == .command {
                print("🔑 ContentView: Command+G键按下 - 打开图谱")
                openWindow(id: "graph")
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.init("i"), phases: .down) { keyPress in
            if keyPress.modifiers == .command {
                print("🔑 ContentView: Command+I键按下 - 快速添加节点")
                NotificationCenter.default.post(name: NSNotification.Name("addNewNode"), object: nil)
                return .handled
            }
            return .ignored
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // GitHub同步状态指示器
                GitSyncStatusIndicator()
                
                Divider()
                
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
            
            // 注册通知监听器
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("openMapWindow"),
                object: nil,
                queue: .main
            ) { _ in
                openWindow(id: "map")
            }
            
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("openGraphWindow"),
                object: nil,
                queue: .main
            ) { _ in
                openWindow(id: "graph")
            }
            
            // 只有主窗口（共享实例）监听 openNewWindow 通知
            if store.isSharedInstance {
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("openNewWindow"),
                    object: nil,
                    queue: .main
                ) { notification in
                    if let source = notification.object as? String {
                        if source == "mainWindow" {
                            print("🔔 [DEBUG] 主窗口收到 openNewWindow 通知，打开新独立窗口")
                            openWindow(id: "layerView")
                        }
                    }
                }
                
                print("🔔 [DEBUG] 主窗口已注册 openNewWindow 通知监听")
            } else {
                print("🔔 [DEBUG] 独立窗口不监听 openNewWindow 通知")
            }
            
            NotificationCenter.default.addObserver(
                forName: Notification.Name("openMarkdownEditor"),
                object: nil,
                queue: .main
            ) { _ in
                openWindow(id: "markdownEditor")
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
            
            // 移除多余的Command+O通知监听器 - WordTaggerApp现在直接发送给DetailPanel
            
            // 移除多余的Command+L通知监听器 - WordTaggerApp现在直接发送给DetailPanel
            
            // 监听打开全屏图谱的通知
            NotificationCenter.default.addObserver(
                forName: Notification.Name("openFullscreenGraphForNode"),
                object: nil,
                queue: .main
            ) { notification in
                if let node = notification.object as? Node {
                    print("🔔 ContentView: 收到openFullscreenGraphForNode通知，节点: \(node.text)")
                    
                    // 通过DetailPanel的图谱功能触发全屏图谱
                    if node.id == selectedNode?.id {
                        // 发送通知给DetailPanel，让它打开全屏图谱
                        NotificationCenter.default.post(
                            name: NSNotification.Name("requestOpenFullscreenGraphFromDetail"),
                            object: node
                        )
                    }
                }
            }
            
            // 检查数据路径设置
            if !dataManager.isDataPathSelected {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showingDataSetup = true
                }
            }
        }
        .onChange(of: store.selectedNode) { oldValue, newValue in
            print("🔄 ContentView: store.selectedNode 发生变化: \(oldValue?.text ?? "nil") -> \(newValue?.text ?? "nil")")
            // 🔧 强制同步，确保地图选择能正确反映到主界面
            selectedNode = newValue
            print("🔄 ContentView: 强制同步本地selectedNode: \(newValue?.text ?? "nil")")
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

// MARK: - 可拖动分割线组件

struct ResizableDivider: View {
    @Binding var width: CGFloat
    @Binding var isDragging: Bool
    let minWidth: CGFloat
    let maxWidth: CGFloat
    @State private var isHovering = false
    
    var body: some View {
        ZStack {
            // 背景分割线
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 1)
            
            // 拖动区域（比可见线宽一些，便于拖动）
            Rectangle()
                .fill(Color.clear)
                .frame(width: 6)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .overlay(
                    // 悬停或拖动时显示的提示线
                    Rectangle()
                        .fill(Color.blue.opacity(0.6))
                        .frame(width: 2)
                        .opacity(isHovering || isDragging ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: isHovering || isDragging)
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            let newWidth = width + value.translation.width
                            width = max(minWidth, min(maxWidth, newWidth))
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(NodeStore.shared)
}