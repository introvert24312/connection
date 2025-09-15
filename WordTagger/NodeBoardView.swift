import SwiftUI
import WebKit
import Foundation

// MARK: - 节点看板 - HTML版本

/// 节点看板窗口管理器 - 支持多开
@MainActor
class NodeBoardWindowManager: ObservableObject {
    static let shared = NodeBoardWindowManager()
    
    // 不再保存窗口引用，每次都创建新窗口以支持多开
    private init() {
        print("🏗️ [节点看板窗口管理器] 初始化，支持多开模式")
    }
    
    /// 显示节点看板窗口 - 独立创建
    func showNodeBoardWindow() {
        print("🪟 [节点看板窗口管理器] 创建新的节点看板窗口（独立）")
        
        let contentView = NodeBoardView()
            .environmentObject(NodeStore.shared)
        
        let hostingView = NSHostingView(rootView: contentView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.contentView = hostingView
        newWindow.title = "节点看板"
        newWindow.setFrameAutosaveName("NodeBoardWindow")
        newWindow.isReleasedWhenClosed = false
        
        let delegate = NodeBoardWindowCloseDelegate { 
            print("🔄 [节点看板] 窗口关闭")
        }
        newWindow.delegate = delegate
        
        newWindow.makeKeyAndOrderFront(nil)
        
        print("🪟 [节点看板] 独立窗口已创建")
    }
    
    
}

// MARK: - 节点看板主视图
struct NodeBoardView: View {
    @EnvironmentObject var nodeStore: NodeStore
    @StateObject private var webViewModel: NodeBoardWebViewModel
    
    // 🆕 完全照抄NewTagIndexBoardView的初始化器逻辑
    init(associatedDataManager: NodeGraphDataManager? = nil) {
        self._webViewModel = StateObject(wrappedValue: NodeBoardWebViewModel(associatedDataManager: associatedDataManager))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // WebView
            NodeBoardWebView(viewModel: webViewModel)
        }
        .onAppear {
            webViewModel.loadNodeData(nodeStore: nodeStore)
        }
        .onChange(of: nodeStore.nodes) {
            webViewModel.loadNodeData(nodeStore: nodeStore)
        }
    }
}

// MARK: - WebView包装器
struct NodeBoardWebView: NSViewRepresentable {
    let viewModel: NodeBoardWebViewModel
    
    func makeNSView(context: Context) -> WKWebView {
        return viewModel.webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // WebView更新由ViewModel管理
    }
}

// MARK: - WebView数据管理器
class NodeBoardWebViewModel: NSObject, ObservableObject {
    let webView: WKWebView
    private var isWebViewReady = false
    private var pendingData: [NodeItem]?
    private weak var nodeStore: NodeStore?
    private let associatedDataManager: NodeGraphDataManager?  // 🆕 完全照抄NewTagIndexWebViewModel的逻辑
    private let instanceId = UUID().uuidString.prefix(8)     // 🆕 实例标识符
    
    init(associatedDataManager: NodeGraphDataManager? = nil) {
        self.associatedDataManager = associatedDataManager
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        
        setupWebView()
        print("🏗️ [节点看板WebView-\(instanceId)] 初始化，关联数据管理器: \(associatedDataManager != nil)")
    }
    
    private func setupWebView() {
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "nodeBoard")
        
        loadHTMLContent()
    }
    
    @MainActor
    func loadNodeData(nodeStore: NodeStore) {
        self.nodeStore = nodeStore
        let nodeItems = convertToNodeItems(nodeStore: nodeStore)
        
        if isWebViewReady {
            sendDataToWebView(nodeItems)
        } else {
            pendingData = nodeItems
        }
    }
    
    private func sendDataToWebView(_ nodeItems: [NodeItem]) {
        do {
            let jsonData = try JSONEncoder().encode(nodeItems)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let script = "window.updateNodeData(\(jsonString))"
                
                webView.evaluateJavaScript(script) { result, error in
                    if let error = error {
                        print("❌ [节点看板] 发送数据失败: \(error)")
                    } else {
                        print("✅ [节点看板] 数据已发送到WebView")
                    }
                }
            }
        } catch {
            print("❌ [节点看板] JSON编码失败: \(error)")
        }
    }
    
    private func loadHTMLContent() {
        let html = """
        <!doctype html>
        <html lang="zh-CN">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>节点看板</title>
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
                .node-count {
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
                <input id="layerSearch" type="text" placeholder="搜索层级名称...">
                <input id="nodeSearch" type="text" placeholder="搜索节点内容...">
                <select id="groupBy" style="font-size: 16px;">
                    <option value="layer">按层级分组</option>
                    <option value="none">不分组</option>
                </select>
                <button id="clearFilters">清除筛选</button>
                <button id="refreshData">刷新数据</button>
            </div>
            
            <div id="nodeBoard" class="grid">
                <div class="empty">正在加载数据...</div>
            </div>
            
            <script>
            console.log("🚀 节点看板 JavaScript 初始化");
            
            let DATA = [];
            let ALL_LAYERS = new Set();
            const selectedItems = new Set();
            const selectedGroupHeaders = new Set();  // 选中的组头部（层级）
            
            // 数据更新函数
            window.updateNodeData = function(nodeData) {
                try {
                    console.log("📦 [节点看板] 收到数据类型:", typeof nodeData);
                    
                    let data;
                    if (typeof nodeData === 'string') {
                        data = JSON.parse(nodeData);
                    } else {
                        data = nodeData;
                    }
                    
                    DATA = Array.isArray(data) ? data : [];
                    console.log("✅ [节点看板] 数据解析成功，项目数:", DATA.length);
                    
                    // 收集所有层级
                    ALL_LAYERS.clear();
                    DATA.forEach(item => {
                        if (item.layer && item.layer.displayName) {
                            ALL_LAYERS.add(item.layer.displayName);
                        }
                    });
                    console.log("📋 收集到层级:", Array.from(ALL_LAYERS));
                    
                    renderBoard();
                    return "success";
                } catch (e) {
                    console.error("❌ [节点看板] 数据解析错误:", e);
                    document.getElementById('nodeBoard').innerHTML = '<div class="empty">数据解析错误</div>';
                    return "error";
                }
            };
            
            // 渲染看板
            function renderBoard() {
                const board = document.getElementById('nodeBoard');
                const layerSearchTerm = document.getElementById('layerSearch').value.toLowerCase();
                const nodeSearchTerm = document.getElementById('nodeSearch').value.toLowerCase();
                const groupBy = document.getElementById('groupBy').value;
                
                // 过滤数据
                let filtered = DATA.filter(item => {
                    // 层级搜索过滤
                    const matchesLayerSearch = !layerSearchTerm || 
                        (item.layer && item.layer.displayName.toLowerCase().includes(layerSearchTerm));
                    
                    // 节点搜索过滤
                    const matchesNodeSearch = !nodeSearchTerm || 
                        item.text.toLowerCase().includes(nodeSearchTerm) || 
                        (item.meaning && item.meaning.toLowerCase().includes(nodeSearchTerm));
                    
                    return matchesLayerSearch && matchesNodeSearch;
                });
                
                if (filtered.length === 0) {
                    board.innerHTML = '<div class="empty">无匹配数据</div>';
                    return;
                }
                
                // 根据分组方式渲染
                if (groupBy === 'none') {
                    // 不分组时按层级排序
                    filtered.sort((a, b) => {
                        if (a.layer && b.layer) {
                            return a.layer.displayName.localeCompare(b.layer.displayName);
                        }
                        return 0;
                    });
                    board.innerHTML = '<div class="grid">' + filtered.map(renderChip).join('') + '</div>';
                    // 更新节点计数
                    updateNodeCount(filtered.length);
                } else if (groupBy === 'layer') {
                    renderGroupedByLayer(board, filtered);
                }
                
                // 更新选中状态显示
                updateSelectionDisplay();
            }
            
            // 渲染单个节点芯片
            function renderChip(item) {
                const itemId = item.id;
                const isSelected = selectedItems.has(itemId);
                
                return `
                    <div class="chip ${isSelected ? 'selected' : ''}" data-id="${itemId}" onclick="toggleSelection('${itemId}', event)">
                        <div class="chip-bar"></div>
                        <div class="chip-content">
                            <div class="chip-title">${escapeHtml(item.text)}</div>
                            <div class="chip-meta">
                                <span class="badge">${escapeHtml(item.layer?.displayName || '无层级')}</span>
                                <span class="badge">${item.tagCount}个标签</span>
                                ${item.isCompound ? '<span class="badge">📦复合</span>' : ''}
                                ${item.meaning ? '<span class="badge">💭含义</span>' : ''}
                            </div>
                        </div>
                    </div>
                `;
            }
            
            // 按层级分组渲染
            function renderGroupedByLayer(board, data) {
                const groups = {};
                data.forEach(item => {
                    const layerName = item.layer?.displayName || '无层级';
                    if (!groups[layerName]) groups[layerName] = [];
                    groups[layerName].push(item);
                });
                
                // 层级搜索过滤：如果有层级搜索，只显示匹配的层级
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
                    const groupId = 'group_' + groupName;
                    const isGroupSelected = selectedGroupHeaders.has(groupName);
                    html += `<div class="group-section">
                        <div class="group-header ${isGroupSelected ? 'selected' : ''}" 
                             data-group="${escapeHtml(groupName)}" 
                             onclick="toggleGroupSelection('${escapeHtml(groupName)}', event)">
                            ${escapeHtml(groupName)} (${filteredGroups[groupName].length})
                        </div>
                        <div class="group-content">
                            <div class="grid">
                                ${filteredGroups[groupName].map(renderChip).join('')}
                            </div>
                        </div>
                    </div>`;
                });
                
                board.innerHTML = html;
                
                // 更新节点计数
                updateNodeCount(data.length);
            }
            
            // 更新节点计数显示
            function updateNodeCount(count) {
                // 节点计数显示已移除，保持与标签看板一致
            }
            
            // 更新选中状态显示（已移除）
            function updateSelectionDisplay() {
                // 选中状态显示已移除
            }
            
            // 切换选择状态
            function toggleSelection(itemId, event) {
                console.log("🖱️ [节点看板] 点击节点 START:", itemId);
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
                console.log("🖱️ [节点看板] 点击节点 END");
            }
            
            // 切换组（层级）选择
            function toggleGroupSelection(groupName, event) {
                console.log("🎯 切换层级选择:", groupName);
                
                if (event.metaKey || event.ctrlKey) {
                    // Command/Ctrl+点击: 多选组
                    if (selectedGroupHeaders.has(groupName)) {
                        selectedGroupHeaders.delete(groupName);
                        // 取消选择该组下的所有节点
                        const groupItems = DATA.filter(item => 
                            item.layer?.displayName === groupName
                        );
                        groupItems.forEach(item => {
                            selectedItems.delete(item.id);
                        });
                    } else {
                        selectedGroupHeaders.add(groupName);
                        // 选择该组下的所有节点
                        const groupItems = DATA.filter(item => 
                            item.layer?.displayName === groupName
                        );
                        groupItems.forEach(item => {
                            selectedItems.add(item.id);
                        });
                    }
                } else {
                    // 普通点击: 单选组
                    selectedGroupHeaders.clear();
                    selectedItems.clear();
                    
                    selectedGroupHeaders.add(groupName);
                    // 选择该组下的所有节点
                    const groupItems = DATA.filter(item => 
                        item.layer?.displayName === groupName
                    );
                    groupItems.forEach(item => {
                        selectedItems.add(item.id);
                    });
                }
                
                renderBoard();
                notifySelectionChange();
            }
            
            // 通知选择变化
            function notifySelectionChange() {
                console.log("📤 [节点看板] 通知选择变化 START");
                console.log("   - 选中项:", Array.from(selectedItems));
                
                const selectedNodeIds = Array.from(selectedItems);
                console.log("   - 最终选择数据:", selectedNodeIds);
                
                // 检查messageHandler是否可用
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nodeBoard) {
                    console.log("   - messageHandler 可用，发送消息...");
                    try {
                        const message = {
                            type: 'selectionChanged',
                            selectedNodes: selectedNodeIds
                        };
                        console.log("   - 发送的消息:", message);
                        window.webkit.messageHandlers.nodeBoard.postMessage(message);
                        console.log("   - 消息发送成功");
                    } catch (e) {
                        console.error("❌ [节点看板] 发送消息异常:", e);
                    }
                } else {
                    console.error("❌ [节点看板] messageHandler 不可用");
                    console.log("   - window.webkit:", !!window.webkit);
                    console.log("   - messageHandlers:", !!window.webkit?.messageHandlers);
                    console.log("   - nodeBoard:", !!window.webkit?.messageHandlers?.nodeBoard);
                }
                
                console.log("📤 [节点看板] 通知选择变化 END");
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
                document.getElementById('layerSearch').value = '';
                document.getElementById('nodeSearch').value = '';
                
                // 清除选择
                selectedItems.clear();
                selectedGroupHeaders.clear();
                
                // 重新渲染
                renderBoard();
                notifySelectionChange();
            }
            
            // 刷新数据功能
            function refreshDataFromWebView() {
                console.log("🔄 从WebView触发刷新数据");
                
                // 通过消息处理器通知Swift端刷新数据
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nodeBoard) {
                    try {
                        const message = {
                            type: 'refreshData'
                        };
                        window.webkit.messageHandlers.nodeBoard.postMessage(message);
                        console.log("✅ 刷新数据消息发送成功");
                    } catch (e) {
                        console.error("❌ 发送刷新数据消息异常:", e);
                    }
                } else {
                    console.error("❌ messageHandler 不可用，无法刷新数据");
                }
            }
            
            // 事件监听
            document.getElementById('layerSearch').addEventListener('input', renderBoard);
            document.getElementById('nodeSearch').addEventListener('input', renderBoard);
            document.getElementById('groupBy').addEventListener('change', renderBoard);
            document.getElementById('clearFilters').addEventListener('click', clearAllFilters);
            document.getElementById('refreshData').addEventListener('click', refreshDataFromWebView);
            
            // 清除选择按钮事件监听已移除
            
            // 标记为就绪
            console.log("✅ [节点看板] JavaScript 初始化完成");
            window.jsReady = true;
            </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    @MainActor
    private func convertToNodeItems(nodeStore: NodeStore) -> [NodeItem] {
        let allLayers = nodeStore.layers
        
        return nodeStore.nodes.map { node in
            let layer = allLayers.first { $0.id == node.layerId }
            
            return NodeItem(
                id: node.id.uuidString,
                text: node.text,
                meaning: node.meaning,
                layerId: node.layerId.uuidString,
                layer: LayerInfo(
                    id: layer?.id.uuidString ?? "",
                    displayName: layer?.displayName ?? "未知层级",
                    color: layer?.color ?? "#666666"
                ),
                tagCount: node.tags.count,
                isCompound: node.isCompound
            )
        }
    }
    
    @MainActor
    private func updateNodeSelection(selectedNodeIds: [String]) {
        print("🔄 [节点看板] 开始处理节点选中: \(selectedNodeIds)")
        
        guard let nodeStore = nodeStore else { 
            print("❌ [节点看板] NodeStore 为空")
            return 
        }
        
        // 将字符串 ID 转换为 UUID
        let selectedUUIDs = selectedNodeIds.compactMap { UUID(uuidString: $0) }
        print("🎯 [节点看板] 转换后的 UUID: \(selectedUUIDs)")
        
        // 处理多节点选择 - 模仿标签看板的方式
        if !selectedUUIDs.isEmpty {
            let selectedNodes = nodeStore.nodes.filter { selectedUUIDs.contains($0.id) }
            print("✅ [节点看板-\(instanceId)] 找到节点: \(selectedNodes.count)个")
            selectedNodes.forEach { print("  - \($0.text)") }
            
            // 选中第一个节点作为主要节点（与主界面同步）
            if let firstNode = selectedNodes.first {
                nodeStore.selectNode(firstNode)
            }
            
            // 🆕 完全照抄NewTagIndexWebViewModel的关联数据管理器逻辑
            if let dataManager = associatedDataManager {
                print("📤 [节点看板-\(instanceId)] 更新关联数据管理器")
                print("   - 选中节点: \(selectedUUIDs.count)个")
                print("   - 选中层级: \(Set(selectedNodes.map { $0.layerId }).count)个")
                
                dataManager.updateSelectedNodes(Set(selectedUUIDs))
                dataManager.updateSelectedLayers(Set(selectedNodes.map { $0.layerId }))
                
                print("🔄 [节点看板-\(instanceId)] 数据管理器已更新（关联模式）")
            } else {
                print("📤 [节点看板-\(instanceId)] 无关联数据管理器，独立模式")
            }
        } else if selectedNodeIds.isEmpty {
            // 清除选中状态
            nodeStore.selectNode(nil)
            
            if let dataManager = associatedDataManager {
                print("🧹 [节点看板-\(instanceId)] 清除关联数据管理器选择")
                dataManager.updateSelectedNodes(Set())
                dataManager.updateSelectedLayers(Set())
            }
            print("🧹 [节点看板-\(instanceId)] 已清除节点选择")
        } else {
            print("❌ [节点看板] 未找到对应的节点")
        }
    }
}

// MARK: - 数据模型
struct NodeItem: Codable {
    let id: String
    let text: String
    let meaning: String?
    let layerId: String
    let layer: LayerInfo
    let tagCount: Int
    let isCompound: Bool
}

struct LayerInfo: Codable {
    let id: String
    let displayName: String
    let color: String
}

// MARK: - WebView委托
extension NodeBoardWebViewModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("✅ [节点看板] WebView加载完成")
        isWebViewReady = true
        
        if let pendingData = pendingData {
            sendDataToWebView(pendingData)
            self.pendingData = nil
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ [节点看板] WebView加载失败: \(error)")
    }
}

extension NodeBoardWebViewModel: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("📨 [节点看板] 收到 WebView 消息: \(message.body)")
        
        guard let messageBody = message.body as? [String: Any] else { 
            print("❌ [节点看板] 消息格式错误: \(message.body)")
            return 
        }
        
        if let type = messageBody["type"] as? String {
            print("📝 [节点看板] 消息类型: \(type)")
            switch type {
            case "selectionChanged":
                if let selectedNodeIds = messageBody["selectedNodes"] as? [String] {
                    print("🎯 [节点看板] 接收到选中变化: \(selectedNodeIds)")
                    Task { @MainActor in
                        self.updateNodeSelection(selectedNodeIds: selectedNodeIds)
                    }
                } else {
                    print("❌ [节点看板] selectedNodes 字段格式错误")
                }
            case "refreshData":
                print("🔄 [节点看板] 接收到刷新数据请求")
                Task { @MainActor in
                    self.handleRefreshData()
                }
            default:
                print("⚠️ [节点看板] 未知消息类型: \(type)")
                break
            }
        } else {
            print("❌ [节点看板] 消息缺少 type 字段")
        }
    }
    
    @MainActor
    private func handleRefreshData() {
        print("🔄 [节点看板-\(instanceId)] 处理刷新数据请求")
        
        // 通过NodeStore刷新数据
        if let nodeStore = nodeStore {
            loadNodeData(nodeStore: nodeStore)
            print("✅ [节点看板-\(instanceId)] 数据刷新完成")
        } else {
            print("❌ [节点看板-\(instanceId)] 无法获取NodeStore实例")
        }
    }
}


// MARK: - 窗口关闭委托
class NodeBoardWindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}