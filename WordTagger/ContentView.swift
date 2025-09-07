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
    
    // 窗口ID，可以从外部传入
    let windowId: UUID
    
    init(windowId: UUID? = nil) {
        self.windowId = windowId ?? UUID()
    }
    
    // 状态管理 - 用于快捷键响应
    @State private var showCommandPalette = false
    @State private var showQuickSearch = false
    @State private var showQuickAdd = false
    @State private var showTagManager = false
    
    // 集中的防重复执行机制
    @State private var commandCooldowns: [String: Date] = [:]
    private let cooldownPeriod: TimeInterval = 0.5
    
    private func shouldExecuteCommand(_ commandName: String) -> Bool {
        let now = Date()
        if let lastExecution = commandCooldowns[commandName] {
            let timeSinceLastExecution = now.timeIntervalSince(lastExecution)
            if timeSinceLastExecution < cooldownPeriod {
                print("🚫 忽略命令 '\(commandName)' - 冷却期内 (剩余: \(String(format: "%.3f", cooldownPeriod - timeSinceLastExecution))s)")
                return false
            }
        }
        commandCooldowns[commandName] = now
        print("✅ 执行命令 '\(commandName)'")
        return true
    }
    

    var body: some View {
        mainContentView
            .modifier(ContentViewModifier(
                showSidebar: $showSidebar,
                selectedNode: $selectedNode,
                showingDataSetup: $showingDataSetup,
                showCommandPalette: $showCommandPalette,
                showQuickAdd: $showQuickAdd,
                showTagManager: $showTagManager,
                showQuickSearch: $showQuickSearch,
                store: store,
                dataManager: dataManager,
                openWindow: openWindow,
                windowId: windowId
            ))
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var mainContentView: some View {
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
            print("📦 ContentView: showSidebar 变为 \(newValue)")
            // 当侧边栏状态改变时，调整WordList宽度以适应新的约束
            let minWidth: CGFloat = newValue ? 160 : 200
            let maxWidth: CGFloat = newValue ? 350 : 400
            wordListWidth = max(minWidth, min(maxWidth, wordListWidth))
        }
    }
}

// MARK: - ContentViewModifier

struct ContentViewModifier: ViewModifier {
    @Binding var showSidebar: Bool
    @Binding var selectedNode: Node?
    @Binding var showingDataSetup: Bool
    @Binding var showCommandPalette: Bool
    @Binding var showQuickAdd: Bool
    @Binding var showTagManager: Bool
    @Binding var showQuickSearch: Bool
    let store: NodeStore
    let dataManager: ExternalDataManager
    let openWindow: OpenWindowAction
    let windowId: UUID
    
    func body(content: Content) -> some View {
        content
            .modifier(ContentViewKeyboardModifier(
                showSidebar: $showSidebar,
                selectedNode: $selectedNode,
                showTagManager: $showTagManager
            ))
            .modifier(ContentViewSheetModifier(
                showingDataSetup: $showingDataSetup,
                showCommandPalette: $showCommandPalette,
                showQuickAdd: $showQuickAdd,
                showTagManager: $showTagManager,
                store: store
            ))
            .modifier(ContentViewFocusedValueModifier(
                showSidebar: $showSidebar,
                showCommandPalette: $showCommandPalette,
                showQuickAdd: $showQuickAdd,
                showTagManager: $showTagManager,
                showQuickSearch: $showQuickSearch,
                openWindow: openWindow,
                windowId: windowId
            ))
            .modifier(ContentViewLifecycleModifier(
                selectedNode: $selectedNode,
                showingDataSetup: $showingDataSetup,
                store: store,
                dataManager: dataManager
            ))
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("executeOpenWindow"))) { notification in
                // 只让主窗口处理 executeOpenWindow，避免多窗口重复打开
                guard store.isSharedInstance else {
                    print("🚫 ContentView: 非主窗口忽略executeOpenWindow通知")
                    return
                }
                if let windowId = notification.object as? String {
                    print("✅ ContentView: (主窗口) 收到executeOpenWindow通知 - windowId: \(windowId)")
                    openWindow(id: windowId)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("restorePreviousTagFilterState"))) { _ in
                print("✅ ContentView: 收到restorePreviousTagFilterState通知，调用store方法")
                store.restorePreviousTagFilterState()
            }
            .toolbar {
                toolbarContent
            }
            .overlay {
                if showQuickSearch {
                    quickSearchOverlay
                }
            }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            GitSyncStatusIndicator()
            Divider()
            
            Button(action: {
                // 🔧 修复：先打开窗口，再发送通知确保映射建立
                print("🗺️ ContentView: 地图按钮被点击")
                
                // 先打开地图窗口
                openWindow(id: "map")
                
                // 延迟发送通知，确保窗口已创建
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // 🔧 修复：直接使用传入的windowId，这就是主窗口的实际ID
                    let sourceWindowId = self.windowId.uuidString
                    print("🗺️ ContentView: 发送映射通知 - 窗口ID: \(sourceWindowId.prefix(8))")
                    let sourceInfo = ["sourceWindowId": sourceWindowId]
                    NotificationCenter.default.post(name: NSNotification.Name("setupMapWindowMapping"), object: sourceInfo)
                }
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
            .help("打开全局节点图谱 (⌘G)")
            
            Button(action: {
                GlobalTagGraphWindowManager.shared.showGlobalTagGraphWindow()
            }) {
                Image(systemName: "network")
                    .foregroundColor(.orange)
            }
            .help("全局标签图谱 (⌘⇧G)")
            
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
    
    @ViewBuilder
    private var quickSearchOverlay: some View {
        QuickSearchView(
            onDismiss: { 
                showQuickSearch = false
            },
            onNodeSelected: { node in
                if let nodeLayer = store.layers.first(where: { $0.id == node.layerId }) {
                    store.setCurrentLayer(nodeLayer)
                }
                store.selectNode(node)
                selectedNode = node
                showQuickSearch = false
            }
        )
        .environmentObject(store)
        .transition(.opacity)
        .zIndex(1000)
    }
}

// MARK: - ContentView Sub-Modifiers

struct ContentViewKeyboardModifier: ViewModifier {
    @Binding var showSidebar: Bool
    @Binding var selectedNode: Node?
    @Binding var showTagManager: Bool
    
    func body(content: Content) -> some View {
        content
            .onKeyPress(.init("t"), phases: .down) { keyPress in
                handleCommandTKey(keyPress)
            }
            .onKeyPress(.escape) {
                handleEscapeKey()
            }
    }
    
    private func handleCommandTKey(_ keyPress: KeyPress) -> KeyPress.Result {
        if keyPress.modifiers == .command {
            print("🔑 ContentView: Command+T键按下")
            if let node = selectedNode {
                print("🔑 ContentView: 有选中节点，切换详情编辑模式")
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
    
    private func handleEscapeKey() -> KeyPress.Result {
        // 首先检查是否有TagManager打开
        if showTagManager {
            showTagManager = false
            return .handled
        }
        
        // 然后检查sidebar
        if showSidebar {
            withAnimation(.easeInOut(duration: 0.3)) {
                showSidebar = false
            }
            return .handled
        }
        return .ignored
    }
}

struct ContentViewSheetModifier: ViewModifier {
    @Binding var showingDataSetup: Bool
    @Binding var showCommandPalette: Bool
    @Binding var showQuickAdd: Bool
    @Binding var showTagManager: Bool
    let store: NodeStore
    
    func body(content: Content) -> some View {
        ZStack {
            content
                .sheet(isPresented: $showingDataSetup) {
                    DataFolderSetupView(isPresented: $showingDataSetup)
                }
                .sheet(isPresented: $showCommandPalette) {
                    CommandPaletteSheetView(isPresented: $showCommandPalette)
                        .environmentObject(store)
                }
                .sheet(isPresented: $showQuickAdd) {
                    QuickAddSheetView(windowId: store.isSharedInstance ? UUID(uuidString: "00000000-0000-0000-0000-000000000001") : nil)
                        .environmentObject(store)
                }
            
            // TagManager overlay显示
            if showTagManager {
                TagManagerView {
                    showTagManager = false
                }
            }
        }
    }
}

struct ContentViewFocusedValueModifier: ViewModifier {
    @Binding var showSidebar: Bool
    @Binding var showCommandPalette: Bool
    @Binding var showQuickAdd: Bool
    @Binding var showTagManager: Bool
    @Binding var showQuickSearch: Bool
    let openWindow: OpenWindowAction
    let windowId: UUID  // 从ContentView传入的实际窗口ID
    
    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.showCommandPalette, ShowCardAction {
                showCommandPalette = true
            })
            .focusedSceneValue(\.addNewNode, ShowCardAction {
                showQuickAdd = true
            })
            .focusedSceneValue(\.openQuickSearch, ShowCardAction {
                showQuickSearch = true
            })
            .focusedSceneValue(\.openTagManager, ShowCardAction {
                showTagManager = true
            })
            .focusedSceneValue(\.openNodeManager, ShowCardAction {
                openWindow(id: "nodeManager")
            })
            .focusedSceneValue(\.openMapWindow, ShowCardAction {
                // 🔧 修复：使用实际的窗口ID而不是固定UUID
                print("🗺️ ContentView: Command+M触发地图窗口打开")
                
                // 先打开地图窗口
                openWindow(id: "map")
                
                // 延迟发送通知，确保窗口已创建
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // 🔧 修复：直接使用传入的windowId，这就是主窗口的实际ID
                    let sourceWindowId = self.windowId.uuidString
                    print("🗺️ ContentView: Command+M发送映射通知 - 窗口ID: \(sourceWindowId.prefix(8))")
                    let sourceInfo = ["sourceWindowId": sourceWindowId]
                    NotificationCenter.default.post(name: NSNotification.Name("setupMapWindowMapping"), object: sourceInfo)
                }
            })
            .focusedSceneValue(\.openGraphWindow, ShowCardAction {
                openWindow(id: "graph")
            })
            .focusedSceneValue(\.toggleSidebar, ShowCardAction {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showSidebar.toggle()
                }
            })
            .focusedSceneValue(\.openNewWindow, ShowCardAction {
                openWindow(id: "layerView")
            })
            .focusedSceneValue(\.switchToDetailTab, ShowCardAction {
                NotificationCenter.default.post(name: NSNotification.Name("switchToDetailTab"), object: nil)
            })
            .focusedSceneValue(\.switchToGraphTab, ShowCardAction {
                NotificationCenter.default.post(name: NSNotification.Name("switchToGraphTab"), object: nil)
            })
            .focusedSceneValue(\.clearTagFilter, ShowCardAction {
                NotificationCenter.default.post(name: NSNotification.Name("clearTagFilter"), object: nil)
            })
            .focusedSceneValue(\.restorePreviousTagFilterState, ShowCardAction {
                print("🔑 ContentView: Command+T 恢复标签筛选状态")
                NotificationCenter.default.post(name: NSNotification.Name("restorePreviousTagFilterState"), object: nil)
            })
            .focusedSceneValue(\.openTagSearch, ShowCardAction {
                print("🔑 ContentView: Command+F 被触发")
                // 如果侧边栏隐藏，先显示侧边栏
                if !showSidebar {
                    print("🔑 ContentView: 侧边栏隐藏，先显示侧边栏")
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSidebar = true
                    }
                    // 延迟发送通知，等待侧边栏显示完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        print("🔑 ContentView: 发送openTagSearch通知（延迟后）")
                        NotificationCenter.default.post(name: NSNotification.Name("openTagSearch"), object: nil)
                    }
                } else {
                    print("🔑 ContentView: 侧边栏已显示，直接发送openTagSearch通知")
                    // 直接发送openTagSearch通知，让TagSidebarView处理
                    NotificationCenter.default.post(name: NSNotification.Name("openTagSearch"), object: nil)
                }
            })
    }
}

struct ContentViewLifecycleModifier: ViewModifier {
    @Binding var selectedNode: Node?
    @Binding var showingDataSetup: Bool
    let store: NodeStore
    let dataManager: ExternalDataManager
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                handleOnAppear()
            }
            .onChange(of: store.selectedNode) { oldValue, newValue in
                handleSelectedNodeChange(oldValue, newValue)
            }
            .onChange(of: store.nodes) { _, _ in
                handleNodesChange()
            }
    }
    
    private func handleOnAppear() {
        if !dataManager.isDataPathSelected {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingDataSetup = true
            }
        }
    }
    
    private func handleSelectedNodeChange(_ oldValue: Node?, _ newValue: Node?) {
        print("🔄 ContentView: store.selectedNode 发生变化: \(oldValue?.text ?? "nil") -> \(newValue?.text ?? "nil")")
        // 使用异步更新避免状态同步时序问题
        DispatchQueue.main.async {
            if selectedNode?.id != newValue?.id {
                selectedNode = newValue
                print("🔄 ContentView: 异步同步本地selectedNode: \(newValue?.text ?? "nil")")
            } else {
                print("🔄 ContentView: 节点ID相同，跳过同步")
            }
        }
    }
    
    private func handleNodesChange() {
        DispatchQueue.main.async {
            if let current = selectedNode, !store.nodes.contains(where: { $0.id == current.id }) {
                selectedNode = nil
            }
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

// MARK: - Command Palette Sheet View

struct CommandPaletteSheetView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var store: NodeStore
    
    var body: some View {
        CommandPaletteView(isPresented: $isPresented)
            .frame(minWidth: 750, minHeight: 450)
            .frame(idealWidth: 800, idealHeight: 500)
    }
}

// MARK: - Tag Manager Sheet View

struct TagManagerSheetView: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        TagManagerView {
            isPresented = false
        }
        .frame(width: 700, height: 600)
        .presentationBackground(.clear)
        .presentationCornerRadius(0)
    }
}

#Preview {
    ContentView()
        .environmentObject(NodeStore.shared)
}