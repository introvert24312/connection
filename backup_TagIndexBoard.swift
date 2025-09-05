import SwiftUI
import WebKit
import Foundation

// MARK: - 标签索引看板数据模型
struct TagIndexItem: Codable, Identifiable {
    var id = UUID()
    let name: String        // 标签值
    let type: String        // 标签类型显示名
    let layers: [String]    // 所属层级
    let count: Int          // 出现次数
    
    init(name: String, type: String, layers: [String], count: Int) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.layers = layers
        self.count = count
    }
}

// MARK: - 标签索引看板窗口管理器
class TagIndexWindowManager: ObservableObject {
    static let shared = TagIndexWindowManager()
    
    private var window: NSWindow?
    private var windowDelegate: WindowDelegate?
    
    private init() {}
    
    // 显示标签索引看板窗口
    @MainActor
    func showTagIndexWindow(with nodeStore: NodeStore) {
        print("🪟 [标签索引看板] 准备创建窗口...")
        print("   - 接收到的NodeStore: \(type(of: nodeStore))")
        print("   - 是否为共享实例: \(nodeStore.isSharedInstance)")
        print("   - 节点数量: \(nodeStore.nodes.count)")
        print("   - 层级数量: \(nodeStore.layers.count)")
        
        if let existingWindow = window {
            print("🪟 [标签索引看板] 窗口已存在，激活窗口")
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        // 验证NodeStore是否有有效数据
        if nodeStore.nodes.isEmpty && nodeStore.layers.isEmpty {
            print("⚠️ [标签索引看板] 警告: NodeStore为空，将尝试使用共享实例")
            // 如果传入的NodeStore为空，尝试使用共享实例
            let sharedStore = NodeStore.shared
            print("   - 共享实例节点数: \(sharedStore.nodes.count)")
            print("   - 共享实例层级数: \(sharedStore.layers.count)")
            
            // 创建窗口内容
            let contentView = TagIndexBoardView()
                .environmentObject(sharedStore) // 使用共享实例
            
            // 创建窗口
            let hostingView = NSHostingView(rootView: contentView)
            
            let newWindow = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            
            newWindow.contentView = hostingView
            newWindow.title = "标签索引看板"
            newWindow.setFrameAutosaveName("TagIndexBoardWindow")
            newWindow.isReleasedWhenClosed = false
            
            // 设置窗口关闭处理
            self.windowDelegate = WindowDelegate { [weak self] in
                self?.window = nil
                self?.windowDelegate = nil
            }
            newWindow.delegate = self.windowDelegate
            
            self.window = newWindow
            newWindow.makeKeyAndOrderFront(nil)
            
            print("🪟 [标签索引看板] 窗口已创建 (使用共享NodeStore实例)")
        } else {
            // 创建窗口内容
            let contentView = TagIndexBoardView()
                .environmentObject(nodeStore)
            
            // 创建窗口
            let hostingView = NSHostingView(rootView: contentView)
            
            let newWindow = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            
            newWindow.contentView = hostingView
            newWindow.title = "标签索引看板"
            newWindow.setFrameAutosaveName("TagIndexBoardWindow")
            newWindow.isReleasedWhenClosed = false
            
            // 设置窗口关闭处理
            self.windowDelegate = WindowDelegate { [weak self] in
                self?.window = nil
                self?.windowDelegate = nil
            }
            newWindow.delegate = self.windowDelegate
            
            self.window = newWindow
            newWindow.makeKeyAndOrderFront(nil)
            
            print("🪟 [标签索引看板] 窗口已创建 (使用传入的NodeStore)")
        }
    }
    
    // 关闭窗口
    func closeWindow() {
        window?.close()
        window = nil
    }
}

// MARK: - 标签索引看板主视图
struct TagIndexBoardView: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var webViewModel = TagIndexWebViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("标签索引看板")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // 同步按钮
                Button("刷新数据") {
                    webViewModel.loadData(from: store)
                }
                .buttonStyle(.bordered)
                
                // 数据状态显示
                Text("节点: \(store.nodes.count), 层级: \(store.layers.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // 关闭按钮
                Button(action: {
                    TagIndexWindowManager.shared.closeWindow()
                }) {
                    Image(systemName: "xmark.circle")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // WebView
            TagIndexWebView(viewModel: webViewModel)
        }
        .onAppear {
            print("🔄 [标签索引看板视图] onAppear 被调用")
            print("   - 视图Store实例: \(type(of: store))")
            print("   - 是否为共享实例: \(store.isSharedInstance)")
            print("   - 节点数量: \(store.nodes.count)")
            webViewModel.loadData(from: store)
            webViewModel.setupSelectionHandler { selectedItems in
                handleSelection(selectedItems)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            print("🔄 [标签索引看板视图] 应用激活，刷新数据")
            webViewModel.loadData(from: store)
        }
    }
    
    // 处理选择事件
    private func handleSelection(_ selectedItems: [TagIndexSelection]) {
        var selectedLayers: Set<String> = []
        var selectedTagTypes: Set<Tag.TagType> = []
        var selectedTagValues: Set<String> = []
        
        for selection in selectedItems {
            switch selection.type {
            case "layer":
                selectedLayers.insert(selection.value)
            case "tagType":
                // 需要根据显示名找到对应的TagType
                if let tagType = findTagType(by: selection.value) {
                    selectedTagTypes.insert(tagType)
                }
            case "tagValue":
                selectedTagValues.insert(selection.value)
            default:
                break
            }
        }
        
        // 通知全局标签图谱
        NotificationCenter.default.post(
            name: .tagIndexSelectionChanged,
            object: nil,
            userInfo: [
                "selectedLayers": selectedLayers,
                "selectedTagTypes": selectedTagTypes,
                "selectedTagValues": selectedTagValues
            ]
        )
        
        print("🔄 [标签索引看板] 选择已更新并通知全局图谱")
    }
    
    // 根据显示名查找TagType
    private func findTagType(by displayName: String) -> Tag.TagType? {
        // 先检查预定义类型
        if displayName == "地点" {
            return .location
        }
        
        // 检查自定义类型
        let allTags = store.nodes.flatMap { $0.tags }
        for tag in allTags {
            if tag.type.displayName == displayName {
                return tag.type
            }
        }
        
        return nil
    }
}

// MARK: - WebView包装器
struct TagIndexWebView: NSViewRepresentable {
    let viewModel: TagIndexWebViewModel
    
    func makeNSView(context: Context) -> WKWebView {
        return viewModel.webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // WebView更新由ViewModel管理
    }
}

// MARK: - WebView数据管理
class TagIndexWebViewModel: NSObject, ObservableObject {
    let webView = WKWebView()
    private var selectionHandler: (([TagIndexSelection]) -> Void)?
    
    override init() {
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        // 配置WebView
        webView.configuration.userContentController.add(
            WeakScriptMessageHandler(target: self),
            name: "tagIndexBoard"
        )
        
        // 设置导航代理以监听加载完成
        webView.navigationDelegate = self
        
        // 加载HTML内容
        loadHTMLContent()
    }
    
    func setupSelectionHandler(_ handler: @escaping ([TagIndexSelection]) -> Void) {
        selectionHandler = handler
    }
    
    private var pendingDataLoad: (() -> Task<Void, Never>)?
    
    func loadData(from store: NodeStore) {
        Task { @MainActor in
            print("🔍 [标签索引看板] 开始加载数据...")
            print("   - NodeStore类型: \(type(of: store))")
            print("   - 是否为共享实例: \(store.isSharedInstance)")
            print("   - 节点数量: \(store.nodes.count)")
            print("   - 层级数量: \(store.layers.count)")
            
            // 添加详细的节点调试信息
            if !store.nodes.isEmpty {
                print("   - 前3个节点:")
                for (index, node) in store.nodes.prefix(3).enumerated() {
                    print("     [\(index)] '\(node.text)' (层: \(node.layerId), 标签: \(node.tags.count))")
                    for (tagIndex, tag) in node.tags.enumerated() {
                        print("       Tag[\(tagIndex)]: \(tag.type.displayName) = '\(tag.value)'")
                    }
                }
            } else {
                print("   ⚠️ NodeStore中没有节点数据!")
            }
            
            if !store.layers.isEmpty {
                print("   - 层级信息:")
                for layer in store.layers {
                    print("     - \(layer.displayName) (ID: \(layer.id.uuidString.prefix(8)))")
                }
            } else {
                print("   ⚠️ NodeStore中没有层级数据!")
            }
            
            let tagIndexItems = convertToTagIndexItems(from: store)
            let jsonData = encodeToJSON(tagIndexItems)
            
            print("   - 转换后的标签项数量: \(tagIndexItems.count)")
            print("   - JSON数据长度: \(jsonData.count)")
            if tagIndexItems.count > 0 {
                print("   - 示例项目: \(tagIndexItems.prefix(3))")
            } else {
                print("   ❌ 转换后没有标签项! 检查数据转换逻辑...")
            }
            
            // 创建数据更新闭包
            let updateData = {
                Task { @MainActor in
                    do {
                        // 使用更安全的方式构造JavaScript调用，直接传递JSON字符串
                        let script = "window.updateData(`\(jsonData)`);"
                        let result = try await self.webView.evaluateJavaScript(script)
                        print("✅ [标签索引看板] 数据已更新到WebView: \(String(describing: result))")
                    } catch {
                        print("❌ [标签索引看板] JavaScript执行错误: \(error)")
                        // 如果模板字符串失败，尝试转义方法
                        do {
                            let escapedJsonData = jsonData.replacingOccurrences(of: "\\", with: "\\\\")
                                                          .replacingOccurrences(of: "\"", with: "\\\"")
                                                          .replacingOccurrences(of: "\n", with: "\\n")
                                                          .replacingOccurrences(of: "\r", with: "\\r")
                                                          .replacingOccurrences(of: "\t", with: "\\t")
                            
                            let script = "window.updateData(\"\(escapedJsonData)\");"
                            let _ = try await self.webView.evaluateJavaScript(script)
                            print("✅ [标签索引看板] 数据已更新到WebView (使用转义方法)")
                        } catch {
                            print("❌ [标签索引看板] 转义方法也失败: \(error)")
                            // 最后尝试重新加载HTML并重试
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                                guard let self = self else { return }
                                Task { @MainActor in
                                    do {
                                        // 先检查函数是否存在
                                        let functionType = try await self.webView.evaluateJavaScript("typeof window.updateData") as? String ?? "undefined"
                                        print("🔍 [重试检查] window.updateData类型: \(functionType)")
                                        
                                        if functionType == "function" {
                                            // 再次尝试基本方法
                                            let script = "window.updateData(`\(jsonData)`);"
                                            let _ = try await self.webView.evaluateJavaScript(script)
                                            print("✅ [标签索引看板] 数据已更新到WebView (重试成功)")
                                        } else {
                                            print("❌ [标签索引看板] 重试后 updateData 函数仍不存在")
                                            // 尝试重新加载 HTML
                                            self.loadHTMLContent()
                                        }
                                    } catch {
                                        print("❌ [标签索引看板] 重试后仍然失败: \(error)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // 检查WebView是否已经加载完成
            do {
                let _ = try await webView.evaluateJavaScript("typeof window.updateData")
                // 如果能执行JavaScript，说明页面已加载
                let _ = updateData()
            } catch {
                // 如果不能执行JavaScript，保存数据加载闭包，等待页面加载完成
                print("⏳ [标签索引看板] WebView未准备好，等待页面加载完成...")
                self.pendingDataLoad = updateData
            }
        }
    }
    
    // 数据转换逻辑
    @MainActor
    private func convertToTagIndexItems(from store: NodeStore) -> [TagIndexItem] {
        var items: [TagIndexItem] = []
        var tagValueCounts: [String: (type: String, layers: Set<String>, count: Int)] = [:]
        
        print("🔄 [数据转换] 开始处理节点...")
        print("   - 总节点数: \(store.nodes.count)")
        print("   - 总层级数: \(store.layers.count)")
        
        if store.nodes.isEmpty {
            print("❌ [数据转换] NodeStore中没有节点，无法转换数据")
            return []
        }
        
        if store.layers.isEmpty {
            print("❌ [数据转换] NodeStore中没有层级，无法转换数据")
            return []
        }
        
        // 统计所有标签值的信息
        for (nodeIndex, node) in store.nodes.enumerated() {
            guard let layer = store.layers.first(where: { $0.id == node.layerId }) else { 
                print("⚠️ [数据转换] 节点 \(nodeIndex) '\(node.text)' 找不到对应的层级 \(node.layerId.uuidString.prefix(8))")
                // 列出所有可用的层级ID
                print("   - 可用层级:")
                for availableLayer in store.layers {
                    print("     - \(availableLayer.displayName): \(availableLayer.id.uuidString.prefix(8))")
                }
                continue 
            }
            let layerName = layer.displayName
            
            if nodeIndex < 3 { // 只打印前3个节点的详细信息
                print("📄 [数据转换] 节点 \(nodeIndex): '\(node.text)' 在层级 '\(layerName)'，有 \(node.tags.count) 个标签")
                for (tagIndex, tag) in node.tags.enumerated() {
                    print("     - 标签 \(tagIndex): \(tag.type.displayName) = '\(tag.value)'")
                }
            }
            
            if node.tags.isEmpty {
                print("⚠️ [数据转换] 节点 '\(node.text)' 没有标签")
                continue
            }
            
            for tag in node.tags {
                let key = "\(tag.type.displayName)|\(tag.value)"
                
                if var existing = tagValueCounts[key] {
                    existing.layers.insert(layerName)
                    existing.count += 1
                    tagValueCounts[key] = existing
                } else {
                    tagValueCounts[key] = (
                        type: tag.type.displayName,
                        layers: Set([layerName]),
                        count: 1
                    )
                }
            }
        }
        
        print("🏷️ [数据转换] 统计结果: 发现 \(tagValueCounts.count) 个不同的标签值")
        
        if tagValueCounts.isEmpty {
            print("❌ [数据转换] 没有找到任何标签值！")
            return []
        }
        
        // 转换为TagIndexItem
        for (key, info) in tagValueCounts {
            let components = key.components(separatedBy: "|")
            guard components.count == 2 else { 
                print("⚠️ [数据转换] 跳过无效的key格式: \(key)")
                continue 
            }
            
            let tagValue = components[1]
            let item = TagIndexItem(
                name: tagValue,
                type: info.type,
                layers: Array(info.layers).sorted(),
                count: info.count
            )
            items.append(item)
            
            if items.count <= 3 {
                print("   - 创建项目: \(item.name) (\(item.type), \(item.count)次, 层级: \(item.layers))")
            }
        }
        
        let sortedItems = items.sorted { $0.name < $1.name }
        print("✅ [数据转换] 成功转换 \(sortedItems.count) 个标签项")
        
        return sortedItems
    }
    
    private func encodeToJSON(_ items: [TagIndexItem]) -> String {
        do {
            let jsonData = try JSONEncoder().encode(items)
            return String(data: jsonData, encoding: .utf8) ?? "[]"
        } catch {
            print("❌ [标签索引看板] JSON编码错误: \(error)")
            return "[]"
        }
    }
    
    private func loadHTMLContent() {
        print("🌐 [标签索引看板] 开始加载HTML内容")
        
        // 使用简化的测试版本来解决WebView加载问题
        let simpleHTML = """
        <!doctype html>
        <html lang="zh-CN">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>标签索引看板</title>
            <style>
                :root {
                    --bg: #1e1e1e; 
                    --card: #2a2a2a; 
                    --text: #ffffff; 
                    --muted: #a0a0a0;
                    --accent: #007aff; 
                    --border: #3c3c3c;
                }
                * { box-sizing: border-box; }
                body {
                    margin: 0;
                    background: var(--bg);
                    color: var(--text);
                    font: 14px/1.5 -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
                    padding: 20px;
                }
                .header {
                    display: flex;
                    align-items: center;
                    gap: 12px;
                    margin-bottom: 16px;
                    padding-bottom: 12px;
                    border-bottom: 1px solid var(--border);
                }
                .header h1 {
                    margin: 0;
                    font-size: 18px;
                }
                .hint {
                    color: var(--muted);
                    font-size: 12px;
                }
                .controls {
                    display: flex;
                    gap: 10px;
                    align-items: center;
                    margin-bottom: 16px;
                }
                input, select {
                    height: 32px;
                    border: 1px solid var(--border);
                    background: var(--card);
                    color: var(--text);
                    border-radius: 6px;
                    padding: 0 10px;
                    outline: none;
                }
                input:focus, select:focus {
                    border-color: var(--accent);
                }
                .grid {
                    display: grid;
                    grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
                    gap: 12px;
                }
                .chip {
                    display: flex;
                    gap: 10px;
                    align-items: flex-start;
                    padding: 12px;
                    border-radius: 8px;
                    background: var(--card);
                    border: 1px solid var(--border);
                    cursor: pointer;
                    transition: all 0.15s ease;
                    user-select: none;
                }
                .chip:hover {
                    transform: translateY(-1px);
                    border-color: var(--accent);
                }
                .chip.selected {
                    border-color: var(--accent);
                    box-shadow: 0 0 0 2px rgba(0, 122, 255, 0.3);
                }
                .chip-bar {
                    width: 4px;
                    height: 100%;
                    border-radius: 2px;
                    background: var(--accent);
                }
                .chip-content {
                    flex: 1;
                }
                .chip-title {
                    font-weight: 500;
                    margin-bottom: 4px;
                }
                .chip-meta {
                    display: flex;
                    gap: 6px;
                    flex-wrap: wrap;
                }
                .badge {
                    font-size: 11px;
                    padding: 2px 6px;
                    border-radius: 4px;
                    background: var(--border);
                    color: var(--muted);
                }
                .empty {
                    text-align: center;
                    padding: 40px;
                    color: var(--muted);
                }
            </style>
        </head>
        <body>
            <div class="header">
                <h1>标签索引看板</h1>
                <span class="hint">Command+点击多选</span>
            </div>
            
            <div class="controls">
                <input id="search" type="text" placeholder="搜索标签值或类型...">
                <select id="sort">
                    <option value="count">按使用次数</option>
                    <option value="name">按名称</option>
                </select>
            </div>
            
            <div id="board" class="grid">
                <div class="empty">正在加载数据...</div>
            </div>
            
            <script>
            console.log("🚀 标签索引看板 JavaScript 初始化");
            
            let DATA = [];
            const selectedChips = new Set();
            
            // 数据更新函数
            window.updateData = function(jsonData) {
                try {
                    console.log("📦 收到数据类型:", typeof jsonData);
                    
                    let data;
                    if (typeof jsonData === 'string') {
                        console.log("📦 收到字符串数据:", jsonData.substring(0, 100) + "...");
                        data = JSON.parse(jsonData);
                    } else if (Array.isArray(jsonData)) {
                        console.log("📦 收到数组数据，长度:", jsonData.length);
                        data = jsonData;
                    } else if (typeof jsonData === 'object') {
                        console.log("📦 收到对象数据:", jsonData);
                        data = jsonData;
                    } else {
                        throw new Error("不支持的数据类型: " + typeof jsonData);
                    }
                    
                    DATA = data;
                    console.log("✅ 数据解析成功，项目数:", DATA.length);
                    if (DATA.length > 0) {
                        console.log("📋 示例数据:", DATA[0]);
                    }
                    render();
                    return "success";
                } catch (e) {
                    console.error("❌ 数据解析错误:", e);
                    console.error("原始数据:", jsonData);
                    document.getElementById('board').innerHTML = '<div class="empty">数据解析错误: ' + e.message + '</div>';
                    return "error";
                }
            };
            
            // 渲染函数
            function render() {
                const board = document.getElementById('board');
                const searchTerm = document.getElementById('search').value.toLowerCase();
                const sortBy = document.getElementById('sort').value;
                
                let filtered = DATA.filter(item => 
                    !searchTerm || 
                    item.name.toLowerCase().includes(searchTerm) || 
                    item.type.toLowerCase().includes(searchTerm)
                );
                
                // 排序
                if (sortBy === 'count') {
                    filtered.sort((a, b) => (b.count || 0) - (a.count || 0));
                } else {
                    filtered.sort((a, b) => a.name.localeCompare(b.name));
                }
                
                if (filtered.length === 0) {
                    board.innerHTML = '<div class="empty">没有匹配的数据</div>';
                    return;
                }
                
                const html = filtered.map(item => {
                    const chipId = `${item.type}|${item.name}`;
                    const isSelected = selectedChips.has(chipId);
                    
                    return `
                        <div class="chip ${isSelected ? 'selected' : ''}" onclick="handleChipClick(event, '${chipId}')">
                            <div class="chip-bar"></div>
                            <div class="chip-content">
                                <div class="chip-title">${escapeHtml(item.name)}</div>
                                <div class="chip-meta">
                                    <span class="badge">${escapeHtml(item.type)}</span>
                                    <span class="badge">${item.count}次</span>
                                    ${item.layers.map(layer => `<span class="badge">${escapeHtml(layer)}</span>`).join('')}
                                </div>
                            </div>
                        </div>
                    `;
                }).join('');
                
                board.innerHTML = html;
                console.log("🎨 渲染完成，显示", filtered.length, "个项目");
            }
            
            // 处理点击事件
            function handleChipClick(event, chipId) {
                if (event.metaKey || event.ctrlKey) {
                    // Command/Ctrl+点击多选
                    if (selectedChips.has(chipId)) {
                        selectedChips.delete(chipId);
                    } else {
                        selectedChips.add(chipId);
                    }
                } else {
                    // 普通点击单选
                    selectedChips.clear();
                    selectedChips.add(chipId);
                }
                
                render();
                notifySelection();
            }
            
            // 发送选择通知
            function notifySelection() {
                const selections = [];
                
                for (const chipId of selectedChips) {
                    const [type, value] = chipId.split('|');
                    selections.push({type: 'tagValue', value: value});
                    selections.push({type: 'tagType', value: type});
                    
                    // 找到对应的item并添加layers
                    const item = DATA.find(d => d.type === type && d.name === value);
                    if (item) {
                        item.layers.forEach(layer => {
                            selections.push({type: 'layer', value: layer});
                        });
                    }
                }
                
                // 去重
                const uniqueSelections = Array.from(
                    new Map(selections.map(s => [`${s.type}|${s.value}`, s])).values()
                );
                
                console.log("📤 发送选择通知:", uniqueSelections);
                
                // 发送到Swift
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tagIndexBoard) {
                    window.webkit.messageHandlers.tagIndexBoard.postMessage({
                        action: 'selectionChanged',
                        selections: uniqueSelections
                    });
                }
            }
            
            // 工具函数
            function escapeHtml(str) {
                const div = document.createElement('div');
                div.textContent = str;
                return div.innerHTML;
            }
            
            // 事件监听
            document.getElementById('search').addEventListener('input', render);
            document.getElementById('sort').addEventListener('change', render);
            
            console.log("✅ updateData 函数已定义，等待数据...");
            </script>
        </body>
        </html>
        """
        
        print("🌐 [标签索引看板] 加载简化HTML内容，长度: \(simpleHTML.count)")
        webView.loadHTMLString(simpleHTML, baseURL: nil)
    }
}

// MARK: - 选择数据模型
struct TagIndexSelection: Codable {
    let type: String    // "layer", "tagType", "tagValue"
    let value: String   // 对应的值
}

// MARK: - WebKit导航代理
extension TagIndexWebViewModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("🌐 [标签索引看板] WebView页面加载完成")
        
        // 检查页面内容是否正确加载
        Task { @MainActor in
            do {
                let title = try await webView.evaluateJavaScript("document.title") as? String ?? ""
                let bodyHTML = try await webView.evaluateJavaScript("document.body.innerHTML") as? String ?? ""
                print("📄 [WebView调试] 页面标题: \(title)")
                print("📄 [WebView调试] Body内容长度: \(bodyHTML.count)")
                let functionTypeResult = try await webView.evaluateJavaScript("typeof window.updateData")
                print("📄 [WebView调试] updateData函数存在: \(String(describing: functionTypeResult))")
                
                // 检查DOM结构
                let boardElement = try await webView.evaluateJavaScript("document.getElementById('board')") as? String ?? "null"
                print("📄 [WebView调试] board元素存在: \(boardElement != "null")")
                
            } catch {
                print("❌ [WebView调试] 无法检查页面状态: \(error)")
            }
        }
        
        // 如果有待处理的数据加载，现在执行它
        if let pendingLoad = pendingDataLoad {
            print("📦 [标签索引看板] 执行待处理的数据加载")
            let _ = pendingLoad()
            pendingDataLoad = nil
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ [标签索引看板] WebView导航失败: \(error)")
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("❌ [标签索引看板] WebView临时导航失败: \(error)")
    }
}

// MARK: - WebKit消息处理
extension TagIndexWebViewModel: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "tagIndexBoard",
              let body = message.body as? [String: Any] else { return }
        
        if let action = body["action"] as? String {
            switch action {
            case "selectionChanged":
                if let selectionsData = body["selections"] as? [[String: String]] {
                    let selections = selectionsData.compactMap { dict -> TagIndexSelection? in
                        guard let type = dict["type"], let value = dict["value"] else { return nil }
                        return TagIndexSelection(type: type, value: value)
                    }
                    selectionHandler?(selections)
                }
            default:
                break
            }
        }
    }
}

// MARK: - 弱引用消息处理包装器
class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    
    init(target: WKScriptMessageHandler) {
        self.target = target
        super.init()
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - 窗口代理
private class WindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

// MARK: - 通知扩展
extension Notification.Name {
    static let tagIndexSelectionChanged = Notification.Name("TagIndexSelectionChanged")
}