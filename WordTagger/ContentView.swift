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
        // 移除重复的快捷键定义 - 统一使用 WordTaggerApp.commands 中的 Menu 快捷键
        // 保留下列特殊的本地功能快捷键
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
            print("🚀 [DEBUG] ContentView.onAppear - 开始注册通知监听器，isSharedInstance: \(store.isSharedInstance)")
            
            // 注册通知监听器
            
            // 新的执行通知监听器
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("executeOpenMapWindow"),
                object: nil,
                queue: .main
            ) { notification in
                // executeOpenMapWindow 应该根据发送方区分处理
                let isIndependentNotification = (notification.object as? String) == "independent"
                let isMainWindow = store.isSharedInstance
                
                if isMainWindow && isIndependentNotification {
                    print("🏠 ContentView(主): 忽略独立窗口的executeOpenMapWindow通知")
                    return
                }
                if !store.isSharedInstance && !isIndependentNotification {
                    print("🏠 ContentView(独立): 忽略主窗口的executeOpenMapWindow通知")
                    return
                }
                
                // 防重复执行机制：使用静态变量记录最近一次执行时间
                struct ExecutionTracker {
                    static var lastExecutionTime: [String: Date] = [:]
                    static let cooldownPeriod: TimeInterval = 0.5 // 500ms冷却期
                }
                
                let commandKey = isIndependentNotification ? "executeOpenMapWindow_independent" : "executeOpenMapWindow_main"
                let now = Date()
                
                if let lastTime = ExecutionTracker.lastExecutionTime[commandKey] {
                    let timeSinceLastExecution = now.timeIntervalSince(lastTime)
                    if timeSinceLastExecution < ExecutionTracker.cooldownPeriod {
                        print("🏠 ContentView: 忽略executeOpenMapWindow通知 - 冷却期内 (\(String(format: "%.3f", timeSinceLastExecution))s)")
                        return
                    }
                }
                
                ExecutionTracker.lastExecutionTime[commandKey] = now
                
                print("🏠 ContentView: 处理executeOpenMapWindow通知 - 打开地图窗口")
                openWindow(id: "map")
            }
            
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("executeOpenGraphWindow"),
                object: nil,
                queue: .main
            ) { notification in
                // executeOpenGraphWindow 应该根据发送方区分处理
                let isIndependentNotification = (notification.object as? String) == "independent"
                let isMainWindow = store.isSharedInstance
                
                if isMainWindow && isIndependentNotification {
                    print("🏠 ContentView(主): 忽略独立窗口的executeOpenGraphWindow通知")
                    return
                }
                if !store.isSharedInstance && !isIndependentNotification {
                    print("🏠 ContentView(独立): 忽略主窗口的executeOpenGraphWindow通知")
                    return
                }
                
                // 防重复执行机制：使用静态变量记录最近一次执行时间
                struct ExecutionTracker {
                    static var lastExecutionTime: [String: Date] = [:]
                    static let cooldownPeriod: TimeInterval = 0.5 // 500ms冷却期
                }
                
                let commandKey = isIndependentNotification ? "executeOpenGraphWindow_independent" : "executeOpenGraphWindow_main"
                let now = Date()
                
                if let lastTime = ExecutionTracker.lastExecutionTime[commandKey] {
                    let timeSinceLastExecution = now.timeIntervalSince(lastTime)
                    if timeSinceLastExecution < ExecutionTracker.cooldownPeriod {
                        print("🏠 ContentView: 忽略executeOpenGraphWindow通知 - 冷却期内 (\(String(format: "%.3f", timeSinceLastExecution))s)")
                        return
                    }
                }
                
                ExecutionTracker.lastExecutionTime[commandKey] = now
                
                print("🏠 ContentView: 处理executeOpenGraphWindow通知 - 打开图谱窗口")
                openWindow(id: "graph")
            }
            
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("executeOpenNodeManager"),
                object: nil,
                queue: .main
            ) { notification in
                // executeOpenNodeManager 应该根据发送方区分处理
                // 主窗口发送 object: nil，独立窗口发送 object: "independent"
                // 只处理与当前窗口类型匹配的通知
                
                let isIndependentNotification = (notification.object as? String) == "independent"
                let isMainWindow = store.isSharedInstance
                
                // 如果是主窗口但收到独立窗口通知，或反之，则忽略
                if isMainWindow && isIndependentNotification {
                    print("🏠 ContentView(主): 忽略独立窗口的executeOpenNodeManager通知")
                    return
                }
                if !store.isSharedInstance && !isIndependentNotification {
                    print("🏠 ContentView(独立): 忽略主窗口的executeOpenNodeManager通知")
                    return
                }
                
                // 防重复执行机制：使用静态变量记录最近一次执行时间
                struct ExecutionTracker {
                    static var lastExecutionTime: [String: Date] = [:]
                    static let cooldownPeriod: TimeInterval = 0.5 // 500ms冷却期
                }
                
                let commandKey = isIndependentNotification ? "executeOpenNodeManager_independent" : "executeOpenNodeManager_main"
                let now = Date()
                
                if let lastTime = ExecutionTracker.lastExecutionTime[commandKey] {
                    let timeSinceLastExecution = now.timeIntervalSince(lastTime)
                    if timeSinceLastExecution < ExecutionTracker.cooldownPeriod {
                        print("🏠 ContentView: 忽略executeOpenNodeManager通知 - 冷却期内 (\(String(format: "%.3f", timeSinceLastExecution))s)")
                        return
                    }
                }
                
                ExecutionTracker.lastExecutionTime[commandKey] = now
                
                print("🏠 ContentView: 处理executeOpenNodeManager通知 - 打开节点管理器")
                openWindow(id: "nodeManager")
            }
            
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("executeToggleSidebar"),
                object: nil,
                queue: .main
            ) { notification in
                // executeToggleSidebar 应该根据发送方区分处理
                // 主窗口发送 object: nil，独立窗口发送 object: "independent"
                // 只处理与当前窗口类型匹配的通知
                
                let isIndependentNotification = (notification.object as? String) == "independent"
                let isMainWindow = store.isSharedInstance
                
                // 如果是主窗口但收到独立窗口通知，或反之，则忽略
                if isMainWindow && isIndependentNotification {
                    print("🏠 ContentView(主): 忽略独立窗口的executeToggleSidebar通知")
                    return
                }
                if !store.isSharedInstance && !isIndependentNotification {
                    print("🏠 ContentView(独立): 忽略主窗口的executeToggleSidebar通知") 
                    return
                }
                
                // 防重复执行机制：使用静态变量记录最近一次执行时间
                struct ExecutionTracker {
                    static var lastExecutionTime: [String: Date] = [:]
                    static let cooldownPeriod: TimeInterval = 0.5 // 500ms冷却期
                }
                
                let commandKey = isIndependentNotification ? "executeToggleSidebar_independent" : "executeToggleSidebar_main"
                let now = Date()
                
                if let lastTime = ExecutionTracker.lastExecutionTime[commandKey] {
                    let timeSinceLastExecution = now.timeIntervalSince(lastTime)
                    if timeSinceLastExecution < ExecutionTracker.cooldownPeriod {
                        print("🏠 ContentView: 忽略executeToggleSidebar通知 - 冷却期内 (\(String(format: "%.3f", timeSinceLastExecution))s)")
                        return
                    }
                }
                
                ExecutionTracker.lastExecutionTime[commandKey] = now
                
                print("🏠 ContentView: 处理executeToggleSidebar通知 - 当前showSidebar=\(showSidebar)")
                withAnimation(.easeInOut(duration: 0.3)) {
                    showSidebar.toggle()
                }
                print("🏠 ContentView: executeToggleSidebar执行完成 - 新showSidebar=\(showSidebar)")
            }
            
            // 只有主窗口（共享实例）监听 executeOpenWindow 通知
            if store.isSharedInstance {
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("executeOpenWindow"),
                    object: nil,
                    queue: .main
                ) { notification in
                    if let windowId = notification.object as? String {
                        print("✅ [DEBUG] 主窗口收到executeOpenWindow通知，打开窗口: \(windowId)")
                        openWindow(id: windowId)
                    } else {
                        print("⚠️ [WARNING] executeOpenWindow通知缺少windowId")
                    }
                }
                
                print("🔔 [DEBUG] 主窗口已注册executeOpenWindow通知监听")
            } else {
                print("🔔 [DEBUG] 独立窗口不监听executeOpenWindow通知")
            }
            
            // 所有窗口都监听 openNewWindow 通知以便创建新的独立窗口
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("openNewWindow"),
                object: nil,
                queue: .main
            ) { notification in
                // 使用WindowFocusManager来防重复执行
                // 注意：这里无法直接获取当前ContentView所属窗口的UUID，但可以通过isSharedInstance判断窗口类型
                print("🔔 [DEBUG] ContentView收到openNewWindow通知，窗口类型: \(store.isSharedInstance ? "主窗口" : "独立窗口")")
                
                // 防重复执行机制：使用静态变量记录最近一次执行时间
                struct ExecutionTracker {
                    static var lastExecutionTime: Date?
                    static let cooldownPeriod: TimeInterval = 0.5 // 500ms冷却期
                }
                
                let now = Date()
                
                if let lastTime = ExecutionTracker.lastExecutionTime {
                    let timeSinceLastExecution = now.timeIntervalSince(lastTime)
                    if timeSinceLastExecution < ExecutionTracker.cooldownPeriod {
                        print("🏠 ContentView: 忽略openNewWindow通知 - 冷却期内 (\(String(format: "%.3f", timeSinceLastExecution))s)")
                        return
                    }
                }
                
                ExecutionTracker.lastExecutionTime = now
                
                print("✅ ContentView: 处理openNewWindow通知 - 打开新的独立窗口")
                openWindow(id: "layerView")
            }
            
            NotificationCenter.default.addObserver(
                forName: Notification.Name("openMarkdownEditor"),
                object: nil,
                queue: .main
            ) { _ in
                openWindow(id: "markdownEditor")
            }
            
            // 旧的通用通知监听器保留用于向后兼容
            NotificationCenter.default.addObserver(
                forName: Notification.Name("openNodeManager"),
                object: nil,
                queue: .main
            ) { notification in
                // 检查窗口焦点状态，只有活跃窗口响应
                guard WindowFocusManager.shared.shouldHandleNotificationForActiveWindow(isGlobalCommand: true) else {
                    print("🏠 ContentView: 忽略openNodeManager通知 - 窗口非活跃状态")
                    return
                }
                
                // 只处理内部的执行通知
                if let source = notification.object as? String, source == "internal" {
                    openWindow(id: "nodeManager")
                } else {
                    // 默认情况下也打开窗口（向后兼容）
                    openWindow(id: "nodeManager")
                }
            }
            
            // 旧的通用通知监听器保留用于向后兼容
            NotificationCenter.default.addObserver(
                forName: Notification.Name("toggleSidebar"),
                object: nil,
                queue: .main
            ) { notification in
                // 只处理内部的执行通知
                if let source = notification.object as? String, source == "internal" {
                    print("🔔 ContentView: 收到toggleSidebar通知，当前showSidebar=\(showSidebar)")
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSidebar.toggle()
                    }
                    print("🔔 ContentView: 切换后showSidebar=\(showSidebar)")
                }
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