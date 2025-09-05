import SwiftUI
import WebKit
import Foundation

// MARK: - 新版标签索引看板 - 重构版本

/// 标签索引窗口管理器 - 简化版
@MainActor
class NewTagIndexWindowManager: ObservableObject {
    static let shared = NewTagIndexWindowManager()
    
    private var window: NSWindow?
    private var windowDelegate: WindowCloseDelegate?
    
    private init() {}
    
    func showTagIndexWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        let contentView = NewTagIndexBoardView()
            .environmentObject(NodeStore.shared) // 直接使用共享实例，避免复杂性
        
        let hostingView = NSHostingView(rootView: contentView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.contentView = hostingView
        newWindow.title = "标签索引看板"
        newWindow.setFrameAutosaveName("NewTagIndexBoardWindow")
        newWindow.isReleasedWhenClosed = false
        
        // 简化窗口关闭处理
        let delegate = WindowCloseDelegate { [weak self] in
            self?.window = nil
            self?.windowDelegate = nil
        }
        self.windowDelegate = delegate
        newWindow.delegate = delegate
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        
        print("🪟 [新标签索引看板] 窗口已创建")
    }
    
    func closeWindow() {
        window?.close()
        window = nil
        windowDelegate = nil
    }
}

// MARK: - 简化的窗口关闭委托
private class WindowCloseDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

// MARK: - 新版标签索引看板主视图
struct NewTagIndexBoardView: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var webViewModel = NewTagIndexWebViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack {
                Text("标签索引看板")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // 刷新按钮
                Button("刷新数据") {
                    refreshData()
                }
                .buttonStyle(.bordered)
                
                // 数据状态显示
                Text("节点: \(store.nodes.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // 关闭按钮
                Button(action: {
                    NewTagIndexWindowManager.shared.closeWindow()
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
            NewTagIndexWebView(viewModel: webViewModel)
        }
        .onAppear {
            print("🔄 [新标签索引看板] 视图出现")
            refreshData()
        }
    }
    
    private func refreshData() {
        print("🔄 [新标签索引看板] 开始刷新数据")
        webViewModel.loadTagData(from: store)
    }
}

// MARK: - WebView包装器
struct NewTagIndexWebView: NSViewRepresentable {
    let viewModel: NewTagIndexWebViewModel
    
    func makeNSView(context: Context) -> WKWebView {
        return viewModel.webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // WebView更新由ViewModel管理
    }
}

// MARK: - WebView数据管理器 - 重构版
class NewTagIndexWebViewModel: NSObject, ObservableObject {
    let webView: WKWebView
    private var isWebViewReady = false
    private var pendingData: [GlobalTagItem] = []
    
    override init() {
        // 先创建配置
        let config = WKWebViewConfiguration()
        
        // 创建带配置的WebView
        webView = WKWebView(frame: .zero, configuration: config)
        
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        print("🔧 [新标签索引] 开始设置WebView")
        
        // 添加消息处理器到现有的配置
        webView.configuration.userContentController.add(
            WeakScriptMessageHandler(target: self),
            name: "tagIndexBoard"
        )
        
        print("🔧 [新标签索引] 已添加消息处理器: tagIndexBoard")
        
        // 设置导航委托
        webView.navigationDelegate = self
        
        // 验证配置
        print("🔧 [新标签索引] WebView配置完成，navigationDelegate已设置")
        
        loadHTMLContent()
    }
    
    @MainActor
    func loadTagData(from store: NodeStore) {
        print("📊 [新标签索引] 开始加载标签数据")
        
        // 使用全局标签管理器生成数据
        let tagItems = GlobalTagDataManager.shared.generateTagIndexData(from: store)
        
        print("📊 [新标签索引] 生成了 \(tagItems.count) 个标签项")
        
        if isWebViewReady {
            sendDataToWebView(tagItems)
        } else {
            pendingData = tagItems
        }
    }
    
    private func sendDataToWebView(_ tagItems: [GlobalTagItem]) {
        // 转换为WebView可用的格式
        let webViewData = tagItems.map { item in
            [
                "name": item.tagValue,
                "type": item.tagType,
                "layers": item.layerNames,
                "count": item.nodeCount,
                "nodes": item.nodes
            ]
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: webViewData, options: [])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
            
            let script = "window.updateData && window.updateData(\(jsonString));"
            
            DispatchQueue.main.async {
                self.webView.evaluateJavaScript(script) { result, error in
                    if let error = error {
                        print("❌ [新标签索引] JavaScript执行错误: \(error)")
                    } else {
                        print("✅ [新标签索引] 数据已发送到WebView")
                    }
                }
            }
        } catch {
            print("❌ [新标签索引] JSON序列化错误: \(error)")
        }
    }
    
    private func loadHTMLContent() {
        print("🌐 [新标签索引] 开始加载HTML内容")
        
        // 使用备份中的HTML样式，但简化逻辑
        let html = """
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
                    display: flex;
                    flex-wrap: wrap;
                    gap: 8px;
                    align-items: flex-start;
                }
                .chip {
                    display: flex;
                    gap: 8px;
                    align-items: flex-start;
                    padding: 8px 12px;
                    border-radius: 6px;
                    background: var(--card);
                    border: 1px solid var(--border);
                    cursor: pointer;
                    transition: all 0.15s ease;
                    user-select: none;
                    min-width: 120px;
                    flex-shrink: 0;
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
                    width: 3px;
                    height: 100%;
                    border-radius: 2px;
                    background: var(--accent);
                    flex-shrink: 0;
                }
                .chip-content {
                    flex: 1;
                    min-width: 0;
                }
                .chip-title {
                    font-weight: 500;
                    margin-bottom: 2px;
                    font-size: 13px;
                    line-height: 1.2;
                    overflow: hidden;
                    text-overflow: ellipsis;
                    white-space: nowrap;
                }
                .chip-meta {
                    display: flex;
                    gap: 4px;
                    flex-wrap: wrap;
                }
                .badge {
                    font-size: 10px;
                    padding: 1px 4px;
                    border-radius: 3px;
                    background: var(--border);
                    color: var(--muted);
                    white-space: nowrap;
                    flex-shrink: 0;
                }
                .empty {
                    text-align: center;
                    padding: 40px;
                    color: var(--muted);
                }
                .group-section {
                    margin-bottom: 20px;
                    border: 1px solid var(--border);
                    border-radius: 8px;
                    background: rgba(42, 42, 42, 0.3);
                    padding: 16px;
                    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
                }
                .group-header {
                    font-size: 16px;
                    font-weight: 600;
                    margin: -16px -16px 12px -16px;
                    padding: 12px 16px;
                    background: transparent;
                    color: var(--text);
                    border-radius: 7px 7px 0 0;
                    margin-bottom: 16px;
                }
                .group-content .grid {
                    margin-bottom: 0;
                }
                .type-subgroup {
                    margin-bottom: 16px;
                    padding: 8px;
                    border-radius: 6px;
                    background: rgba(60, 60, 60, 0.2);
                    border-left: 3px solid var(--accent);
                }
                .type-subgroup:last-child {
                    margin-bottom: 0;
                }
                .type-header {
                    font-weight: 500;
                    margin: 0 0 8px 0;
                    color: var(--accent);
                    font-size: 13px;
                    padding-left: 4px;
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
                <select id="groupBy">
                    <option value="layer">按层级分组</option>
                    <option value="type">按标签类型分组</option>
                    <option value="none">不分组</option>
                </select>
            </div>
            
            <div id="board" class="grid">
                <div class="empty">正在加载数据...</div>
            </div>
            
            <script>
            console.log("🚀 新版标签索引看板 JavaScript 初始化");
            
            let DATA = [];
            const selectedItems = new Set();
            
            // 数据更新函数
            window.updateData = function(jsonData) {
                try {
                    console.log("📦 [新版] 收到数据类型:", typeof jsonData);
                    
                    let data;
                    if (typeof jsonData === 'string') {
                        data = JSON.parse(jsonData);
                    } else {
                        data = jsonData;
                    }
                    
                    DATA = Array.isArray(data) ? data : [];
                    console.log("✅ [新版] 数据解析成功，项目数:", DATA.length);
                    
                    renderBoard();
                    return "success";
                } catch (e) {
                    console.error("❌ [新版] 数据解析错误:", e);
                    document.getElementById('board').innerHTML = '<div class="empty">数据解析错误</div>';
                    return "error";
                }
            };
            
            // 渲染看板
            function renderBoard() {
                const board = document.getElementById('board');
                const searchTerm = document.getElementById('search').value.toLowerCase();
                const groupBy = document.getElementById('groupBy').value;
                
                // 过滤数据
                let filtered = DATA.filter(item => 
                    !searchTerm || 
                    item.name.toLowerCase().includes(searchTerm) || 
                    item.type.toLowerCase().includes(searchTerm) ||
                    (item.layers && item.layers.some(layer => layer.toLowerCase().includes(searchTerm)))
                );
                
                if (filtered.length === 0) {
                    board.innerHTML = '<div class="empty">无匹配数据</div>';
                    return;
                }
                
                // 根据分组方式渲染
                if (groupBy === 'none') {
                    // 不分组时按使用次数排序
                    filtered.sort((a, b) => (b.count || 0) - (a.count || 0));
                    board.innerHTML = '<div class="grid">' + filtered.map(renderChip).join('') + '</div>';
                } else if (groupBy === 'layer') {
                    renderGroupedByLayer(board, filtered);
                } else if (groupBy === 'type') {
                    renderGroupedByType(board, filtered);
                }
            }
            
            // 渲染单个标签芯片
            function renderChip(item) {
                const itemId = item.type + ':' + item.name;
                const isSelected = selectedItems.has(itemId);
                
                return `
                    <div class="chip ${isSelected ? 'selected' : ''}" data-id="${itemId}" onclick="toggleSelection('${itemId}', event)">
                        <div class="chip-bar"></div>
                        <div class="chip-content">
                            <div class="chip-title">${escapeHtml(item.name)}</div>
                            <div class="chip-meta">
                                <span class="badge">${escapeHtml(item.type)}</span>
                                <span class="badge">${item.count}个节点</span>
                                ${item.layers && item.layers.length > 0 ? 
                                    item.layers.map(layer => '<span class="badge">' + escapeHtml(layer) + '</span>').join('') 
                                    : '<span class="badge">无层级</span>'
                                }
                            </div>
                        </div>
                    </div>
                `;
            }
            
            // 按层级分组渲染
            function renderGroupedByLayer(board, data) {
                const groups = {};
                data.forEach(item => {
                    if (item.layers && item.layers.length > 0) {
                        item.layers.forEach(layer => {
                            if (!groups[layer]) groups[layer] = [];
                            groups[layer].push(item);
                        });
                    } else {
                        if (!groups['无层级']) groups['无层级'] = [];
                        groups['无层级'].push(item);
                    }
                });
                
                let html = '';
                Object.keys(groups).sort().forEach(groupName => {
                    // 在每个层级内按标签类型分组
                    const typeGroups = {};
                    groups[groupName].forEach(item => {
                        if (!typeGroups[item.type]) typeGroups[item.type] = [];
                        typeGroups[item.type].push(item);
                    });
                    
                    html += `<div class="group-section">
                        <div class="group-header">${escapeHtml(groupName)} (${groups[groupName].length})</div>
                        <div class="group-content">`;
                    
                    Object.keys(typeGroups).sort().forEach(typeName => {
                        // 按使用次数排序
                        typeGroups[typeName].sort((a, b) => (b.count || 0) - (a.count || 0));
                        html += `
                            <div class="type-subgroup">
                                <div class="type-header">${escapeHtml(typeName)}</div>
                                <div class="grid">
                                    ${typeGroups[typeName].map(renderChip).join('')}
                                </div>
                            </div>
                        `;
                    });
                    
                    html += `</div></div>`;
                });
                
                board.innerHTML = html;
            }
            
            // 按标签类型分组渲染
            function renderGroupedByType(board, data) {
                const groups = {};
                data.forEach(item => {
                    if (!groups[item.type]) groups[item.type] = [];
                    groups[item.type].push(item);
                });
                
                let html = '';
                Object.keys(groups).sort().forEach(groupName => {
                    // 按使用次数排序
                    groups[groupName].sort((a, b) => (b.count || 0) - (a.count || 0));
                    html += `
                        <div class="group-section">
                            <div class="group-header">${escapeHtml(groupName)} (${groups[groupName].length})</div>
                            <div class="group-content">
                                <div class="grid">
                                    ${groups[groupName].map(renderChip).join('')}
                                </div>
                            </div>
                        </div>
                    `;
                });
                
                board.innerHTML = html;
            }
            
            // 切换选择状态
            function toggleSelection(itemId, event) {
                console.log("🖱️ [新版] 点击标签 START:", itemId);
                console.log("   - 事件类型:", event.type);
                console.log("   - metaKey:", event.metaKey, "ctrlKey:", event.ctrlKey);
                console.log("   - 当前选中项:", Array.from(selectedItems));
                
                if (event.metaKey || event.ctrlKey) {
                    // Command/Ctrl+点击: 多选
                    if (selectedItems.has(itemId)) {
                        selectedItems.delete(itemId);
                        console.log("   - 多选模式: 取消选择", itemId);
                    } else {
                        selectedItems.add(itemId);
                        console.log("   - 多选模式: 添加选择", itemId);
                    }
                } else {
                    // 普通点击: 单选
                    selectedItems.clear();
                    selectedItems.add(itemId);
                    console.log("   - 单选模式: 设置选择", itemId);
                }
                
                console.log("   - 更新后选中项:", Array.from(selectedItems));
                
                renderBoard();
                notifySelectionChange();
                console.log("🖱️ [新版] 点击标签 END");
            }
            
            // 通知选择变化 - 简化版本
            function notifySelectionChange() {
                console.log("📤 [新版] 通知选择变化 START");
                console.log("   - 原始选中项:", Array.from(selectedItems));
                
                const selections = Array.from(selectedItems).map(id => {
                    const [type, value] = id.split(':', 2);
                    const selection = {
                        type: 'tagValue',  // 简化，只支持标签值选择
                        value: value,
                        tagType: type
                    };
                    console.log("   - 转换选择项:", id, "->", selection);
                    return selection;
                });
                
                console.log("   - 最终选择数据:", selections);
                
                // 检查messageHandler是否可用
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tagIndexBoard) {
                    console.log("   - messageHandler 可用，发送消息...");
                    try {
                        const message = {
                            action: 'selectionChanged',
                            selections: selections
                        };
                        console.log("   - 发送的消息:", message);
                        window.webkit.messageHandlers.tagIndexBoard.postMessage(message);
                        console.log("   - 消息发送成功");
                    } catch (e) {
                        console.error("❌ [新版] 发送消息异常:", e);
                    }
                } else {
                    console.error("❌ [新版] messageHandler 不可用");
                    console.log("   - window.webkit:", !!window.webkit);
                    console.log("   - messageHandlers:", !!window.webkit?.messageHandlers);
                    console.log("   - tagIndexBoard:", !!window.webkit?.messageHandlers?.tagIndexBoard);
                }
                
                console.log("📤 [新版] 通知选择变化 END");
            }
            
            // 工具函数
            function escapeHtml(text) {
                const div = document.createElement('div');
                div.textContent = text;
                return div.innerHTML;
            }
            
            // 事件监听
            document.getElementById('search').addEventListener('input', renderBoard);
            document.getElementById('groupBy').addEventListener('change', renderBoard);
            
            // 标记为就绪
            console.log("✅ [新版] JavaScript 初始化完成");
            window.jsReady = true;
            </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - WebView导航委托
extension NewTagIndexWebViewModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("✅ [新标签索引] WebView加载完成")
        isWebViewReady = true
        
        // 如果有待发送的数据，现在发送
        if !pendingData.isEmpty {
            sendDataToWebView(pendingData)
            pendingData = []
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ [新标签索引] WebView加载失败: \(error)")
    }
}

// MARK: - Script消息处理
extension NewTagIndexWebViewModel: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("📨 [新标签索引] 收到消息 - name: \(message.name)")
        print("📨 [新标签索引] 消息体类型: \(type(of: message.body))")
        print("📨 [新标签索引] 消息体内容: \(message.body)")
        
        guard message.name == "tagIndexBoard" else {
            print("❌ [新标签索引] 消息名称不匹配: \(message.name)")
            return
        }
        
        guard let messageBody = message.body as? [String: Any] else {
            print("❌ [新标签索引] 消息体格式错误: \(message.body)")
            return
        }
        
        guard let action = messageBody["action"] as? String else {
            print("❌ [新标签索引] 缺少action字段: \(messageBody)")
            return
        }
        
        print("✅ [新标签索引] 处理消息动作: \(action)")
        
        switch action {
        case "selectionChanged":
            handleSelectionChanged(messageBody)
        default:
            print("⚠️ [新标签索引] 未知消息动作: \(action)")
        }
    }
    
    @MainActor
    private func handleSelectionChanged(_ messageBody: [String: Any]) {
        guard let selections = messageBody["selections"] as? [[String: Any]] else {
            print("❌ [新标签索引] 无效的选择数据")
            return
        }
        
        print("🔄 [新标签索引] 处理选择变化: \(selections.count) 项")
        
        // 转换选择数据并发送通知
        var selectedTagValues: Set<String> = []
        // 🔧 修复：当用户选择具体标签值时，不设置标签类型过滤，避免冲突
        // 让标签值过滤起主导作用，这样多选同类型标签值就能正常显示
        
        for selection in selections {
            if let value = selection["value"] as? String {
                selectedTagValues.insert(value)
            }
        }
        
        // 发送通知给全局标签管理器
        DispatchQueue.main.async {
            print("📤 [新标签索引] 发送选择变化通知")
            print("   - 选中标签值: \(selectedTagValues)")
            
            NotificationCenter.default.post(
                name: .tagIndexSelectionChanged,
                object: nil,
                userInfo: [
                    "selectedLayers": Set<String>(), // 暂时为空，后续扩展
                    "selectedTagTypes": Set<Tag.TagType>(), // 🔧 修复：清空标签类型过滤，只用标签值过滤
                    "selectedTagValues": selectedTagValues
                ]
            )
        }
    }
    
    @MainActor
    private func findTagType(by displayName: String) -> Tag.TagType? {
        // 从数据中查找实际的标签类型
        let allTags = GlobalTagDataManager.shared.cachedTagItems
        for item in allTags {
            if item.tagType == displayName {
                // 尝试从现有数据中推断标签类型
                if displayName == "地点" {
                    return .location
                } else {
                    return .custom(displayName.lowercased().replacingOccurrences(of: " ", with: "_"))
                }
            }
        }
        
        // 如果找不到，创建自定义类型
        return .custom(displayName.lowercased().replacingOccurrences(of: " ", with: "_"))
    }
}

// MARK: - 弱引用Script消息处理器
private class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    
    init(target: WKScriptMessageHandler) {
        self.target = target
        super.init()
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}