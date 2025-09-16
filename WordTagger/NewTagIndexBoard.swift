import SwiftUI
import WebKit
import Foundation

// MARK: - 新版标签看板 - 重构版本

/// 标签索引窗口管理器 - 支持多开版
@MainActor
class NewTagIndexWindowManager: ObservableObject {
    static let shared = NewTagIndexWindowManager()
    
    private var window: NSWindow?
    private var windowDelegate: WindowCloseDelegate?
    
    private init() {}
    
    func showTagIndexWindow() {
        // 🆕 支持多开：不再检查已存在窗口，直接创建新窗口
        
        let contentView = NewTagIndexBoardView()
            .environmentObject(NodeStore.shared) // 直接使用共享实例，避免复杂性
        
        let hostingView = NSHostingView(rootView: contentView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 150, y: 150, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.contentView = hostingView
        newWindow.title = "标签看板"
        newWindow.setFrameAutosaveName("NewTagIndexBoardWindow")
        newWindow.isReleasedWhenClosed = false
        
        // 窗口关闭处理（不再保存窗口引用）
        let delegate = WindowCloseDelegate { [weak self] in
            self?.window = nil
            self?.windowDelegate = nil
        }
        self.windowDelegate = delegate
        newWindow.delegate = delegate
        
        // 🆕 多开支持：不再保存窗口引用，每次都创建新窗口
        // self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        
        print("🪟 [新标签看板] 窗口已创建（支持多开）")
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

// MARK: - 新版标签看板主视图
struct NewTagIndexBoardView: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var webViewModel: NewTagIndexWebViewModel
    
    // 🆕 支持关联数据管理器的初始化器
    init(associatedDataManager: GlobalTagDataManager? = nil) {
        self._webViewModel = StateObject(wrappedValue: NewTagIndexWebViewModel(associatedDataManager: associatedDataManager))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // WebView
            NewTagIndexWebView(viewModel: webViewModel)
        }
        .onAppear {
            print("🔄 [新标签看板] 视图出现")
            refreshData()
        }
    }
    
    private func refreshData() {
        print("🔄 [新标签看板] 开始刷新数据")
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
    private let associatedDataManager: GlobalTagDataManager?  // 🆕 关联的数据管理器
    private let instanceId = UUID().uuidString.prefix(8)     // 🆕 实例标识符
    
    init(associatedDataManager: GlobalTagDataManager? = nil) {
        self.associatedDataManager = associatedDataManager
        
        // 先创建配置
        let config = WKWebViewConfiguration()
        
        // 创建带配置的WebView
        webView = WKWebView(frame: .zero, configuration: config)
        
        super.init()
        print("🏗️ [标签索引WebView-\(instanceId)] 创建新实例，关联数据管理器: \(associatedDataManager != nil)")
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
        
        // 🆕 使用临时数据管理器生成数据，避免单例依赖
        let tempDataManager = GlobalTagDataManager()
        let tagItems = tempDataManager.generateTagIndexData(from: store)
        
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
            <title>标签看板</title>
            <style>
                /* Light theme (default) */
                :root {
                    --bg: #ffffff; 
                    --card: #f8f9fa; 
                    --text: #1d1d1f; 
                    --muted: #6e6e73;
                    --accent: #007aff; 
                    --border: #e1e5e9;
                }
                
                /* Dark theme */
                @media (prefers-color-scheme: dark) {
                    :root {
                        --bg: #1e1e1e; 
                        --card: #2a2a2a; 
                        --text: #ffffff; 
                        --muted: #a0a0a0;
                        --accent: #007aff; 
                        --border: #3c3c3c;
                    }
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
                    justify-content: space-between;
                    gap: 12px;
                    margin-bottom: 16px;
                    padding-bottom: 12px;
                    border-bottom: 1px solid var(--border);
                }
                .header h1 {
                    margin: 0;
                    font-size: 18px;
                }
                .header-right {
                    display: flex;
                    align-items: center;
                    gap: 12px;
                }
                .tag-count {
                    font-size: 12px;
                    color: var(--muted);
                    font-weight: normal;
                }
                /* 已移除选中计数和清除按钮样式 */
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
                input, select, button {
                    height: 36px;
                    border: 1px solid var(--border);
                    background: var(--card);
                    color: var(--text);
                    border-radius: 6px;
                    padding: 0 12px;
                    outline: none;
                    cursor: pointer;
                    font-size: 16px;
                }
                input:focus, select:focus {
                    border-color: var(--accent);
                }
                button {
                    background: var(--accent);
                    color: white;
                    border: none;
                    font-weight: 500;
                }
                button:hover {
                    opacity: 0.9;
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
                    background: var(--card);
                    padding: 16px;
                    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
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
                    cursor: pointer;
                    transition: all 0.15s ease;
                    user-select: none;
                }
                .group-header:hover {
                    background: rgba(0, 122, 255, 0.1);
                    color: var(--accent);
                }
                .group-header.selected {
                    background: var(--accent);
                    color: white;
                }
                .group-content .grid {
                    margin-bottom: 0;
                }
                .type-subgroup {
                    margin-bottom: 16px;
                    padding: 8px;
                    border-radius: 6px;
                    background: var(--border);
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
                    cursor: pointer;
                    transition: all 0.15s ease;
                    user-select: none;
                    padding: 4px 8px;
                    border-radius: 4px;
                }
                .type-header:hover {
                    background: rgba(0, 122, 255, 0.1);
                    color: white;
                }
                .type-header.selected {
                    background: var(--accent);
                    color: white;
                }
            </style>
        </head>
        <body>
            <div class="header">
                <!-- 移除选中计数和清除选择按钮 -->
            </div>
            
            <div class="controls">
                <input id="search" type="text" placeholder="搜索标签值或类型...">
                <input id="layerSearch" type="text" placeholder="搜索层级名称...">
                <select id="groupBy" style="font-size: 16px;">
                    <option value="layer">按层级分组</option>
                    <option value="type">按标签类型分组</option>
                    <option value="none">不分组</option>
                </select>
                <button id="clearFilters">清除筛选</button>
                <button id="refreshData">刷新数据</button>
            </div>
            
            <div id="board" class="grid">
                <div class="empty">正在加载数据...</div>
            </div>
            
            <script>
            console.log("🚀 新版标签看板 JavaScript 初始化");
            
            let DATA = [];
            let ALL_LAYERS = new Set();
            const selectedItems = new Set();
            const selectedGroupHeaders = new Set();  // 新增：选中的组头部（层级）
            const selectedTypeHeaders = new Set();   // 新增：选中的标签类型头部
            
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
                    
                    // 收集所有层级
                    ALL_LAYERS.clear();
                    DATA.forEach(item => {
                        if (item.layers && Array.isArray(item.layers)) {
                            item.layers.forEach(layer => ALL_LAYERS.add(layer));
                        }
                    });
                    console.log("📋 收集到层级:", Array.from(ALL_LAYERS));
                    
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
                const layerSearchTerm = document.getElementById('layerSearch').value.toLowerCase();
                const groupBy = document.getElementById('groupBy').value;
                
                // 过滤数据
                let filtered = DATA.filter(item => {
                    // 标签搜索过滤
                    const matchesSearch = !searchTerm || 
                        item.name.toLowerCase().includes(searchTerm) || 
                        item.type.toLowerCase().includes(searchTerm);
                    
                    // 层级搜索过滤（新增）
                    const matchesLayerSearch = !layerSearchTerm ||
                        (item.layers && item.layers.some(layer => layer.toLowerCase().includes(layerSearchTerm)));
                    
                    return matchesSearch && matchesLayerSearch;
                });
                
                if (filtered.length === 0) {
                    board.innerHTML = '<div class="empty">无匹配数据</div>';
                    return;
                }
                
                // 根据分组方式渲染
                if (groupBy === 'none') {
                    // 不分组时按使用次数排序
                    filtered.sort((a, b) => (b.count || 0) - (a.count || 0));
                    board.innerHTML = '<div class="grid">' + filtered.map(renderChip).join('') + '</div>';
                    // 更新标签计数
                    updateTagCount(filtered.length);
                } else if (groupBy === 'layer') {
                    renderGroupedByLayer(board, filtered);
                } else if (groupBy === 'type') {
                    renderGroupedByType(board, filtered);
                }
                
                // 更新选中状态显示
                updateSelectionDisplay();
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
                
                // 🔍 层级搜索过滤：如果有层级搜索，只显示匹配的层级
                const layerSearchTerm = document.getElementById('layerSearch').value.toLowerCase();
                let filteredGroups = groups;
                if (layerSearchTerm) {
                    filteredGroups = {};
                    Object.keys(groups).forEach(groupName => {
                        if (groupName.toLowerCase().includes(layerSearchTerm)) {
                            filteredGroups[groupName] = groups[groupName];
                        }
                    });
                }
                
                let html = '';
                Object.keys(filteredGroups).sort().forEach(groupName => {
                    // 在每个层级内按标签类型分组
                    const typeGroups = {};
                    filteredGroups[groupName].forEach(item => {
                        if (!typeGroups[item.type]) typeGroups[item.type] = [];
                        typeGroups[item.type].push(item);
                    });
                    
                    const groupId = 'group_' + groupName;
                    const isGroupSelected = selectedGroupHeaders.has(groupName);
                    html += `<div class="group-section">
                        <div class="group-header ${isGroupSelected ? 'selected' : ''}" 
                             data-group="${escapeHtml(groupName)}" 
                             onclick="toggleGroupSelection('${escapeHtml(groupName)}', event)">
                            ${escapeHtml(groupName)} (${filteredGroups[groupName].length})
                        </div>
                        <div class="group-content">`;
                    
                    Object.keys(typeGroups).sort().forEach(typeName => {
                        // 按使用次数排序
                        typeGroups[typeName].sort((a, b) => (b.count || 0) - (a.count || 0));
                        const typeId = groupName + '_' + typeName;
                        const isTypeSelected = selectedTypeHeaders.has(typeId);
                        html += `
                            <div class="type-subgroup">
                                <div class="type-header ${isTypeSelected ? 'selected' : ''}" 
                                     data-type="${escapeHtml(typeId)}" 
                                     onclick="toggleTypeSelection('${escapeHtml(typeId)}', '${escapeHtml(typeName)}', event)">
                                    ${escapeHtml(typeName)}
                                </div>
                                <div class="grid">
                                    ${typeGroups[typeName].map(renderChip).join('')}
                                </div>
                            </div>
                        `;
                    });
                    
                    html += `</div></div>`;
                });
                
                board.innerHTML = html;
                
                // 更新标签计数
                updateTagCount(data.length);
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
                    const isGroupSelected = selectedGroupHeaders.has(groupName);
                    html += `
                        <div class="group-section">
                            <div class="group-header ${isGroupSelected ? 'selected' : ''}" 
                                 data-group="${escapeHtml(groupName)}" 
                                 onclick="toggleGroupSelection('${escapeHtml(groupName)}', event)">
                                ${escapeHtml(groupName)} (${groups[groupName].length})
                            </div>
                            <div class="group-content">
                                <div class="grid">
                                    ${groups[groupName].map(renderChip).join('')}
                                </div>
                            </div>
                        </div>
                    `;
                });
                
                board.innerHTML = html;
                
                // 更新标签计数
                updateTagCount(data.length);
            }
            
            // 更新标签计数显示
            function updateTagCount(count) {
                // 标签计数显示已移除
            }
            
            // 更新选中状态显示（已移除）
            function updateSelectionDisplay() {
                // 选中状态显示已移除
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
            
            // 新增：切换组（层级）选择
            function toggleGroupSelection(groupName, event) {
                console.log("🎯 切换组选择:", groupName);
                
                // 🔧 检查当前分组模式
                const groupBy = document.getElementById('groupBy').value;
                const isTagTypeGrouping = groupBy === 'type';
                
                console.log("🔧 当前分组模式:", groupBy, "是否为标签类型分组:", isTagTypeGrouping);
                
                if (isTagTypeGrouping && !event.metaKey && !event.ctrlKey) {
                    // 🆕 在标签类型分组模式下的普通点击：触发标签类型选择
                    console.log("🏷️ 标签类型分组模式：点击组头部触发标签类型选择");
                    
                    selectedGroupHeaders.clear();
                    selectedTypeHeaders.clear();
                    selectedItems.clear();
                    
                    selectedGroupHeaders.add(groupName);
                    
                    // 直接发送标签类型选择通知
                    notifySelectionChangeForTagType(groupName);
                    renderBoard();
                    return; // 提前返回，不执行原有逻辑
                }
                
                // 🔧 修复多选逻辑：分别处理标签类型分组和层级分组的多选
                if (event.metaKey || event.ctrlKey) {
                    if (isTagTypeGrouping) {
                        // 🆕 标签类型分组模式下的多选：处理标签类型多选
                        console.log("🏷️ 标签类型分组模式：Command+点击进行标签类型多选");
                        
                        if (selectedGroupHeaders.has(groupName)) {
                            selectedGroupHeaders.delete(groupName);
                            console.log("🔄 取消多选标签类型:", groupName);
                        } else {
                            selectedGroupHeaders.add(groupName);
                            console.log("✅ 添加多选标签类型:", groupName);
                        }
                        
                        // 收集所有选中的标签类型并发送
                        const selectedTypes = Array.from(selectedGroupHeaders);
                        console.log("🎯 当前选中的标签类型:", selectedTypes);
                        
                        // 发送多标签类型选择通知
                        if (selectedTypes.length > 0) {
                            notifySelectionChangeForTagType(null); // 让函数内部收集所有选中类型
                        } else {
                            // 如果没有选中任何类型，发送空选择
                            notifySelectionChange();
                        }
                        
                        renderBoard();
                        return; // 提前返回，不执行后续逻辑
                    } else {
                        // 层级分组模式下的多选：原有逻辑
                        if (selectedGroupHeaders.has(groupName)) {
                            selectedGroupHeaders.delete(groupName);
                            // 取消选择该组下的所有标签
                            const groupItems = DATA.filter(item => 
                                (item.layers && item.layers.includes(groupName))
                            );
                            groupItems.forEach(item => {
                                const itemId = item.type + ':' + item.name;
                                selectedItems.delete(itemId);
                            });
                        } else {
                            selectedGroupHeaders.add(groupName);
                            // 选择该组下的所有标签
                            const groupItems = DATA.filter(item => 
                                (item.layers && item.layers.includes(groupName))
                            );
                            groupItems.forEach(item => {
                                const itemId = item.type + ':' + item.name;
                                selectedItems.add(itemId);
                            });
                        }
                    }
                } else {
                    // 普通点击: 单选组（层级分组模式）
                    selectedGroupHeaders.clear();
                    selectedTypeHeaders.clear();
                    selectedItems.clear();
                    
                    selectedGroupHeaders.add(groupName);
                    // 选择该组下的所有标签
                    const groupItems = DATA.filter(item => 
                        isTagTypeGrouping ? 
                            item.type === groupName :
                            (item.layers && item.layers.includes(groupName))
                    );
                    groupItems.forEach(item => {
                        const itemId = item.type + ':' + item.name;
                        selectedItems.add(itemId);
                    });
                }
                
                renderBoard();
                notifySelectionChange();
            }
            
            // 新增：切换类型选择
            function toggleTypeSelection(typeId, typeName, event) {
                console.log("🎯 切换类型选择:", typeId, typeName);
                
                // 🔧 修复：从typeId解析出层级名称
                // typeId格式为: "groupName_typeName"
                const [groupName, ...typeNameParts] = typeId.split('_');
                const actualTypeName = typeNameParts.join('_'); // 重新组合，防止类型名本身包含下划线
                
                console.log("🔧 解析出层级:", groupName, "类型:", actualTypeName);
                
                if (event.metaKey || event.ctrlKey) {
                    // Command/Ctrl+点击: 多选类型
                    if (selectedTypeHeaders.has(typeId)) {
                        selectedTypeHeaders.delete(typeId);
                        // 🔧 修复：只取消选择该层级中该类型的标签
                        const typeItemsInGroup = DATA.filter(item => 
                            item.type === actualTypeName && 
                            item.layers && item.layers.includes(groupName)
                        );
                        typeItemsInGroup.forEach(item => {
                            const itemId = item.type + ':' + item.name;
                            selectedItems.delete(itemId);
                        });
                    } else {
                        selectedTypeHeaders.add(typeId);
                        // 🔧 修复：只选择该层级中该类型的标签
                        const typeItemsInGroup = DATA.filter(item => 
                            item.type === actualTypeName && 
                            item.layers && item.layers.includes(groupName)
                        );
                        typeItemsInGroup.forEach(item => {
                            const itemId = item.type + ':' + item.name;
                            selectedItems.add(itemId);
                        });
                    }
                } else {
                    // 🔧 普通点击类型头部：单选模式，但支持多次点击不同类型
                    if (selectedTypeHeaders.has(typeId)) {
                        // 如果已经选中，则取消选中
                        selectedTypeHeaders.delete(typeId);
                        console.log("🏷️ 取消选择标签类型:", actualTypeName);
                    } else {
                        // 如果当前没有选中，则进行单选（清除其他选择，只保留当前）
                        selectedGroupHeaders.clear();
                        selectedTypeHeaders.clear();
                        selectedItems.clear(); // 清空个别标签选择
                        
                        selectedTypeHeaders.add(typeId);
                        console.log("🏷️ 单选标签类型:", actualTypeName);
                    }
                }
                
                console.log("🔧 选择结果: 标签类型选择，将由Swift端处理过滤");
                
                renderBoard();
                notifySelectionChangeForTagType(actualTypeName); // 使用新的通知函数
            }
            
            // 🆕 通知标签类型选择变化 - 支持多选
            function notifySelectionChangeForTagType(typeName) {
                console.log("📤 [新版] 通知标签类型选择变化 START");
                
                // 🔧 收集所有选中的标签类型
                const selectedTypeNames = [];
                
                // 🆕 优先从selectedGroupHeaders收集（适用于组头部点击）
                if (selectedGroupHeaders.size > 0) {
                    selectedGroupHeaders.forEach(groupName => {
                        selectedTypeNames.push(groupName);
                    });
                    console.log("🎯 从组头部收集标签类型:", selectedTypeNames);
                } else {
                    // 从selectedTypeHeaders收集（适用于类型头部点击）
                    selectedTypeHeaders.forEach(typeId => {
                        // 从typeId解析出类型名称
                        const parts = typeId.split('_');
                        if (parts.length >= 2) {
                            const actualTypeName = parts.slice(1).join('_'); // 重新组合，防止类型名本身包含下划线
                            selectedTypeNames.push(actualTypeName);
                        }
                    });
                    console.log("🎯 从类型头部收集标签类型:", selectedTypeNames);
                }
                
                // 如果没有选中的类型，添加当前类型（兜底逻辑）
                if (selectedTypeNames.length === 0 && typeName) {
                    selectedTypeNames.push(typeName);
                    console.log("🔄 使用兜底类型:", typeName);
                }
                
                console.log("   - 选中标签类型列表:", selectedTypeNames);
                
                // 检查messageHandler是否可用
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tagIndexBoard) {
                    console.log("   - messageHandler 可用，发送标签类型选择消息...");
                    try {
                        const message = {
                            action: 'tagTypesSelected', // 🆕 使用复数形式表示多选
                            tagTypes: selectedTypeNames, // 🆕 发送标签类型数组
                            selectedLayers: []  // 层级信息将在Swift端计算
                        };
                        console.log("   - 发送的标签类型消息:", message);
                        window.webkit.messageHandlers.tagIndexBoard.postMessage(message);
                        console.log("   - 标签类型消息发送成功");
                    } catch (e) {
                        console.error("❌ [新版] 发送标签类型消息异常:", e);
                    }
                } else {
                    console.error("❌ [新版] messageHandler 不可用");
                }
                
                console.log("📤 [新版] 通知标签类型选择变化 END");
            }
            
            // 通知选择变化 - 支持层级过滤
            function notifySelectionChange() {
                console.log("📤 [新版] 通知选择变化 START");
                console.log("   - 原始选中项:", Array.from(selectedItems));
                console.log("   - 选中层级:", []);
                
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
                console.log("   - 层级过滤数据:", []);
                
                // 检查messageHandler是否可用
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tagIndexBoard) {
                    console.log("   - messageHandler 可用，发送消息...");
                    try {
                        const message = {
                            action: 'selectionChanged',
                            selections: selections,
                            selectedLayers: []  // 层级信息将在Swift端计算
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
            
            
            // 清除筛选功能
            function clearAllFilters() {
                console.log("🧹 清除所有筛选条件");
                
                // 清除搜索
                document.getElementById('search').value = '';
                document.getElementById('layerSearch').value = '';
                
                // 清除选择
                selectedItems.clear();
                selectedGroupHeaders.clear();  // 新增：清除组选择
                selectedTypeHeaders.clear();   // 新增：清除类型选择
                
                // 重新渲染
                renderBoard();
                notifySelectionChange();
            }
            
            // 事件监听
            document.getElementById('search').addEventListener('input', renderBoard);
            document.getElementById('layerSearch').addEventListener('input', renderBoard);  // 🆕 添加层级搜索监听
            document.getElementById('groupBy').addEventListener('change', renderBoard);
            document.getElementById('clearFilters').addEventListener('click', clearAllFilters);
            document.getElementById('refreshData').addEventListener('click', refreshDataFromWebView);
            
            // 清除选择按钮事件监听已移除
            
            // 🆕 刷新数据功能
            function refreshDataFromWebView() {
                console.log("🔄 从WebView触发刷新数据");
                
                // 通过消息处理器通知Swift端刷新数据
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tagIndexBoard) {
                    try {
                        const message = {
                            action: 'refreshData'
                        };
                        window.webkit.messageHandlers.tagIndexBoard.postMessage(message);
                        console.log("✅ 刷新数据消息发送成功");
                    } catch (e) {
                        console.error("❌ 发送刷新数据消息异常:", e);
                    }
                } else {
                    console.error("❌ messageHandler 不可用，无法刷新数据");
                }
            }
            
            
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
        case "tagTypeSelected":
            handleTagTypeSelected(messageBody)
        case "tagTypesSelected": // 🆕 支持多标签类型选择
            handleTagTypesSelected(messageBody)
        case "refreshData":
            handleRefreshData()
        default:
            print("⚠️ [新标签索引] 未知消息动作: \(action)")
        }
    }
    
    @MainActor
    private func handleRefreshData() {
        print("🔄 [标签索引-\(instanceId)] 处理刷新数据请求")
        
        // 通过NodeStore刷新数据
        if let nodeStore = NodeStore.shared as NodeStore? {
            loadTagData(from: nodeStore)
            print("✅ [标签索引-\(instanceId)] 数据刷新完成")
        } else {
            print("❌ [标签索引-\(instanceId)] 无法获取NodeStore实例")
        }
    }
    
    @MainActor
    private func handleSelectionChanged(_ messageBody: [String: Any]) {
        guard let selections = messageBody["selections"] as? [[String: Any]] else {
            print("❌ [标签索引-\(instanceId)] 无效的选择数据")
            return
        }
        
        // 获取选中的层级（新增功能）
        let selectedLayerNames = messageBody["selectedLayers"] as? [String] ?? []
        var selectedLayersSet = Set(selectedLayerNames)
        
        print("🔄 [标签索引-\(instanceId)] 处理选择变化: \(selections.count) 项标签值, \(selectedLayersSet.count) 个层级")
        
        // 转换选择数据
        var selectedTagValues: Set<String> = []
        var selectedTagTypes: Set<String> = []
        
        for selection in selections {
            if let value = selection["value"] as? String {
                selectedTagValues.insert(value)
            }
            if let tagType = selection["tagType"] as? String {
                selectedTagTypes.insert(tagType)
            }
        }
        
        // 🆕 自动计算标签值对应的节点所在层级
        if selectedLayersSet.isEmpty && !selectedTagValues.isEmpty {
            print("🔍 [标签索引-\(instanceId)] 自动计算标签值对应的层级")
            selectedLayersSet = calculateLayersForTagValues(selectedTagValues, selectedTagTypes)
            print("   - 计算得到的层级: \(selectedLayersSet)")
        }
        
        // 🆕 如果有关联的数据管理器，直接更新它；否则发送全局通知
        if let dataManager = associatedDataManager {
            print("📤 [标签索引-\(instanceId)] 更新关联数据管理器")
            print("   - 选中标签值: \(selectedTagValues)")
            print("   - 选中层级: \(selectedLayersSet)")
            
            dataManager.filteredLayers = selectedLayersSet
            dataManager.filteredTagTypes = Set<Tag.TagType>()  // 清空标签类型过滤
            dataManager.filteredTagValues = selectedTagValues
            
            // 🚨 移除自动保存逻辑：只实时更新过滤，不自动保存到文件
            print("🔄 [标签索引-\(instanceId)] 实时更新过滤条件（不自动保存）")
        } else {
            print("📤 [标签索引-\(instanceId)] 发送全局选择变化通知")
            
            NotificationCenter.default.post(
                name: .tagIndexSelectionChanged,
                object: nil,
                userInfo: [
                    "selectedLayers": selectedLayersSet,
                    "selectedTagTypes": Set<Tag.TagType>(),
                    "selectedTagValues": selectedTagValues
                ]
            )
        }
    }
    
    @MainActor
    private func handleTagTypeSelected(_ messageBody: [String: Any]) {
        guard let tagTypeName = messageBody["tagType"] as? String else {
            print("❌ [标签索引-\(instanceId)] 无效的标签类型数据")
            return
        }
        
        // 获取选中的层级（可选）
        let selectedLayerNames = messageBody["selectedLayers"] as? [String] ?? []
        var selectedLayersSet = Set(selectedLayerNames)
        
        print("🏷️ [标签索引-\(instanceId)] 处理标签类型选择: \(tagTypeName)")
        print("   - 关联层级: \(selectedLayersSet)")
        
        // 将标签类型名称转换为Tag.TagType enum
        let tagType = convertToTagType(tagTypeName)
        print("   - 转换后的枚举: \(tagType.displayName)")
        
        // 🆕 自动计算标签类型对应的节点所在层级
        if selectedLayersSet.isEmpty {
            print("🔍 [标签索引-\(instanceId)] 自动计算标签类型对应的层级")
            selectedLayersSet = calculateLayersForTagTypes(Set([tagType]))
            print("   - 计算得到的层级: \(selectedLayersSet)")
        }
        
        // 🆕 如果有关联的数据管理器，直接更新它；否则发送全局通知
        if let dataManager = associatedDataManager {
            print("📤 [标签索引-\(instanceId)] 更新关联数据管理器（标签类型选择）")
            
            dataManager.filteredLayers = selectedLayersSet
            dataManager.filteredTagTypes = Set([tagType])  // 设置标签类型过滤
            dataManager.filteredTagValues = Set<String>()  // 清空标签值过滤
            
            print("🔄 [标签索引-\(instanceId)] 标签类型过滤已更新（不自动保存）")
        } else {
            print("📤 [标签索引-\(instanceId)] 发送全局标签类型选择通知")
            
            NotificationCenter.default.post(
                name: .tagIndexSelectionChanged,
                object: nil,
                userInfo: [
                    "selectedLayers": selectedLayersSet,
                    "selectedTagTypes": Set([tagType]),     // 发送标签类型
                    "selectedTagValues": Set<String>()      // 清空标签值
                ]
            )
        }
    }
    
    @MainActor
    private func handleTagTypesSelected(_ messageBody: [String: Any]) {
        guard let tagTypeNames = messageBody["tagTypes"] as? [String] else {
            print("❌ [标签索引-\(instanceId)] 无效的多标签类型数据")
            return
        }
        
        // 获取选中的层级（可选）
        let selectedLayerNames = messageBody["selectedLayers"] as? [String] ?? []
        var selectedLayersSet = Set(selectedLayerNames)
        
        print("🏷️ [标签索引-\(instanceId)] 处理多标签类型选择: \(tagTypeNames)")
        print("   - 关联层级: \(selectedLayersSet)")
        
        // 将标签类型名称转换为Tag.TagType enum集合
        let tagTypes = Set(tagTypeNames.map { convertToTagType($0) })
        print("   - 转换后的枚举: \(tagTypes.map { $0.displayName })")
        
        // 🆕 自动计算标签类型对应的节点所在层级
        if selectedLayersSet.isEmpty && !tagTypes.isEmpty {
            print("🔍 [标签索引-\(instanceId)] 自动计算标签类型对应的层级")
            selectedLayersSet = calculateLayersForTagTypes(tagTypes)
            print("   - 计算得到的层级: \(selectedLayersSet)")
        }
        
        // 🆕 如果有关联的数据管理器，直接更新它；否则发送全局通知
        if let dataManager = associatedDataManager {
            print("📤 [标签索引-\(instanceId)] 更新关联数据管理器（多标签类型选择）")
            
            dataManager.filteredLayers = selectedLayersSet
            dataManager.filteredTagTypes = tagTypes  // 🔧 设置多个标签类型过滤
            dataManager.filteredTagValues = Set<String>()  // 清空标签值过滤
            
            print("🔄 [标签索引-\(instanceId)] 多标签类型过滤已更新（不自动保存）")
        } else {
            print("📤 [标签索引-\(instanceId)] 发送全局多标签类型选择通知")
            
            NotificationCenter.default.post(
                name: .tagIndexSelectionChanged,
                object: nil,
                userInfo: [
                    "selectedLayers": selectedLayersSet,
                    "selectedTagTypes": tagTypes,     // 🔧 发送多个标签类型
                    "selectedTagValues": Set<String>()      // 清空标签值
                ]
            )
        }
    }
    
    // MARK: - 层级计算辅助方法
    
    /// 计算包含指定标签值的节点所在的层级
    @MainActor
    private func calculateLayersForTagValues(_ tagValues: Set<String>, _ tagTypes: Set<String>) -> Set<String> {
        guard let nodeStore = NodeStore.shared as NodeStore? else {
            return []
        }
        
        var layers = Set<String>()
        
        // 遍历所有节点，找出包含这些标签值的节点
        for node in nodeStore.nodes {
            for tag in node.tags {
                // 检查标签值是否匹配
                if tagValues.contains(tag.value) {
                    // 同时检查标签类型是否匹配（如果有指定）
                    if tagTypes.isEmpty || tagTypes.contains(tag.type.displayName) {
                        // 找到节点所在的层级
                        if let layer = nodeStore.layers.first(where: { $0.id == node.layerId }) {
                            layers.insert(layer.displayName)
                        }
                        break
                    }
                }
            }
        }
        
        print("🔍 计算标签值对应层级: 标签值=\(tagValues), 找到层级=\(layers)")
        return layers
    }
    
    /// 计算包含指定标签类型的节点所在的层级
    @MainActor
    private func calculateLayersForTagTypes(_ tagTypes: Set<Tag.TagType>) -> Set<String> {
        guard let nodeStore = NodeStore.shared as NodeStore? else {
            return []
        }
        
        var layers = Set<String>()
        
        // 遍历所有节点，找出包含这些标签类型的节点
        for node in nodeStore.nodes {
            for tag in node.tags {
                // 检查标签类型是否匹配
                if tagTypes.contains(tag.type) {
                    // 找到节点所在的层级
                    if let layer = nodeStore.layers.first(where: { $0.id == node.layerId }) {
                        layers.insert(layer.displayName)
                    }
                    break
                }
            }
        }
        
        print("🔍 计算标签类型对应层级: 标签类型=\(tagTypes.map { $0.displayName }), 找到层级=\(layers)")
        return layers
    }
    
    @MainActor
    private func convertToTagType(_ typeName: String) -> Tag.TagType {
        // 转换标签类型名称到Tag.TagType枚举
        switch typeName {
        case "地点", "location":
            return .location
        default:
            // 对于其他类型，创建custom类型
            // 将中文标签类型名称转换为合适的key
            let customKey: String
            switch typeName {
            case "时间", "time":
                customKey = "time"
            case "人物", "person":
                customKey = "person"
            case "事件", "event":
                customKey = "event"
            case "概念", "concept":
                customKey = "concept"
            case "物品", "object":
                customKey = "object"
            default:
                customKey = typeName.lowercased().replacingOccurrences(of: " ", with: "_")
            }
            return .custom(customKey)
        }
    }
    
    @MainActor
    private func findTagType(by displayName: String) -> Tag.TagType? {
        // 简化标签类型推断，不依赖共享实例
        if displayName == "地点" {
            return .location
        } else {
            return .custom(displayName.lowercased().replacingOccurrences(of: " ", with: "_"))
        }
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