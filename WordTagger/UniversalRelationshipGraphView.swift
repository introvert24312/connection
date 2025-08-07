import SwiftUI
import WebKit

// MARK: - 通用数据模型协议
protocol UniversalGraphNode {
    var id: Int { get }
    var label: String { get }
    var subtitle: String? { get }
}

protocol UniversalGraphEdge {
    var fromId: Int { get }
    var toId: Int { get }
    var label: String? { get }
}

// MARK: - 数据模型适配 - 移除extension，使用专用适配器

// MARK: - 图谱协调器协议
protocol GraphCoordinator {
    func fitGraph()
}

// MARK: - 全局图谱管理器
class GraphManager: ObservableObject {
    static let shared = GraphManager()
    private var coordinators: [ObjectIdentifier: GraphCoordinator] = [:]
    
    func registerCoordinator(_ coordinator: GraphCoordinator, for view: ObjectIdentifier) {
        coordinators[view] = coordinator
    }
    
    func getCoordinator(for view: ObjectIdentifier) -> GraphCoordinator? {
        return coordinators[view]
    }
    
    func fitAllGraphs() {
        for (_, coordinator) in coordinators {
            coordinator.fitGraph()
        }
    }
}

// MARK: - 自动颜色管理器
class AutoColorManager {
    static let shared = AutoColorManager()
    
    // 预定义颜色池 - 使用视觉上区分度高的颜色
    private let colorPool = [
        "#FF69B4", // 粉色
        "#FF4444", // 红色  
        "#4169E1", // 蓝色
        "#32CD32", // 绿色
        "#FF8C00", // 橙色
        "#9370DB", // 紫色
        "#20B2AA", // 青色
        "#DC143C", // 深红
        "#4682B4", // 钢蓝
        "#228B22", // 森林绿
        "#FF1493", // 深粉
        "#8A2BE2", // 蓝紫
        "#00CED1", // 深蓝绿
        "#FF6347", // 番茄红
        "#4169E1", // 皇家蓝
        "#32CD32", // 酸橙绿
        "#FF69B4", // 热粉
        "#8B4513", // 鞍褐色
        "#2E8B57", // 海绿
        "#B22222"  // 火砖红
    ]
    
    private var assignedColors: [String: String] = [:]
    private var usedColorIndices: Set<Int> = []
    
    private init() {
        // 初始化预定义标签颜色
        assignedColors["memory"] = "#FF69B4"    // 粉色
        assignedColors["location"] = "#FF4444"   // 红色
        assignedColors["root"] = "#4169E1"       // 蓝色
        assignedColors["shape"] = "#32CD32"      // 绿色
        assignedColors["sound"] = "#FF8C00"      // 橙色
        
        // 标记已使用的颜色索引
        usedColorIndices.insert(0) // 粉色
        usedColorIndices.insert(1) // 红色
        usedColorIndices.insert(2) // 蓝色
        usedColorIndices.insert(3) // 绿色
        usedColorIndices.insert(4) // 橙色
    }
    
    func getColor(for tagKey: String) -> String {
        // 如果已经分配过颜色，直接返回
        if let existingColor = assignedColors[tagKey] {
            return existingColor
        }
        
        // 寻找下一个未使用的颜色
        for (index, color) in colorPool.enumerated() {
            if !usedColorIndices.contains(index) {
                assignedColors[tagKey] = color
                usedColorIndices.insert(index)
                return color
            }
        }
        
        // 如果所有预定义颜色都用完了，生成随机颜色
        let randomColor = generateRandomColor()
        assignedColors[tagKey] = randomColor
        return randomColor
    }
    
    private func generateRandomColor() -> String {
        // 生成饱和度和亮度较高的随机颜色，确保可视性
        let hue = Int.random(in: 0...360)
        let saturation = Int.random(in: 60...90)
        let lightness = Int.random(in: 45...65)
        return hslToHex(h: hue, s: saturation, l: lightness)
    }
    
    private func hslToHex(h: Int, s: Int, l: Int) -> String {
        let h = Double(h) / 360.0
        let s = Double(s) / 100.0  
        let l = Double(l) / 100.0
        
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        
        var r: Double = 0, g: Double = 0, b: Double = 0
        
        if h < 1/6 {
            r = c; g = x; b = 0
        } else if h < 2/6 {
            r = x; g = c; b = 0
        } else if h < 3/6 {
            r = 0; g = c; b = x
        } else if h < 4/6 {
            r = 0; g = x; b = c
        } else if h < 5/6 {
            r = x; g = 0; b = c
        } else {
            r = c; g = 0; b = x
        }
        
        let red = Int((r + m) * 255)
        let green = Int((g + m) * 255)
        let blue = Int((b + m) * 255)
        
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

// MARK: - 通用关系图组件
struct UniversalRelationshipGraphView<Node: UniversalGraphNode, Edge: UniversalGraphEdge>: View {
    let nodes: [Node]
    let edges: [Edge]
    let title: String
    let initialScale: Double
    let onNodeSelected: ((Int) -> Void)?
    let onNodeDeselected: (() -> Void)?
    let onFitGraph: (() -> Void)?
    @State private var debugInfo = ""
    @State private var viewId = ObjectIdentifier(UUID() as AnyObject)
    
    
    init(nodes: [Node], edges: [Edge], title: String = "节点关系图", initialScale: Double = 1.0, onNodeSelected: ((Int) -> Void)? = nil, onNodeDeselected: (() -> Void)? = nil, onFitGraph: (() -> Void)? = nil) {
        self.nodes = nodes
        self.edges = edges
        self.title = title
        self.initialScale = initialScale
        self.onNodeSelected = onNodeSelected
        self.onNodeDeselected = onNodeDeselected
        self.onFitGraph = onFitGraph
    }
    
    var body: some View {
        VStack {
            if nodes.isEmpty {
                emptyStateView
            } else {
                UniversalGraphWebView(
                    nodes: nodes, 
                    edges: edges,
                    initialScale: initialScale,
                    onDebugInfo: { info in
                        DispatchQueue.main.async {
                            debugInfo = info
                        }
                    },
                    onNodeSelected: onNodeSelected,
                    onNodeDeselected: onNodeDeselected,
                    onFitGraph: onFitGraph
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("fitGraph"))) { _ in
                    // 调用fit功能
                    GraphManager.shared.fitAllGraphs()
                }
            }
        }
        .navigationTitle(title)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "network")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("暂无数据")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var debugInfoView: some View {
        Text("调试: \(debugInfo)")
            .font(.caption)
            .foregroundColor(.blue)
            .padding(4)
    }
}

// MARK: - WebView组件
struct UniversalGraphWebView<Node: UniversalGraphNode, Edge: UniversalGraphEdge>: NSViewRepresentable {
    let nodes: [Node]
    let edges: [Edge]
    let initialScale: Double
    let onDebugInfo: (String) -> Void
    let onNodeSelected: ((Int) -> Void)?
    let onNodeDeselected: (() -> Void)?
    let onFitGraph: (() -> Void)?
    
    init(nodes: [Node], edges: [Edge], initialScale: Double = 1.0, onDebugInfo: @escaping (String) -> Void, onNodeSelected: ((Int) -> Void)? = nil, onNodeDeselected: (() -> Void)? = nil, onFitGraph: (() -> Void)? = nil) {
        self.nodes = nodes
        self.edges = edges
        self.initialScale = initialScale
        self.onDebugInfo = onDebugInfo
        self.onNodeSelected = onNodeSelected
        self.onNodeDeselected = onNodeDeselected
        self.onFitGraph = onFitGraph
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        // 启用开发者工具
        #if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        #endif
        
        // 添加消息处理器
        webView.configuration.userContentController.add(context.coordinator, name: "nodeSelected")
        webView.configuration.userContentController.add(context.coordinator, name: "nodeDeselected")
        
        context.coordinator.onDebugInfo = onDebugInfo
        context.coordinator.onNodeSelected = onNodeSelected
        context.coordinator.onNodeDeselected = onNodeDeselected
        context.coordinator.onFitGraph = onFitGraph
        context.coordinator.webView = webView
        
        // 立即加载初始内容并设置数据签名
        let nodeIds = nodes.map { $0.id }.sorted()
        let edgeSignature = edges.map { "\($0.fromId)-\($0.toId)" }.sorted().joined(separator:",")
        let initialDataSignature = "\(nodeIds)-\(edgeSignature)"
        context.coordinator.lastDataSignature = initialDataSignature
        
        let htmlContent = generateGraphHTML(initialScale: initialScale)
        let baseURL = URL(string: "about:blank")
        webView.loadHTMLString(htmlContent, baseURL: baseURL)
        onDebugInfo("初始加载: \(nodes.count)个节点, \(edges.count)条边")
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        @AppStorage("enableGraphDebug") var enableGraphDebug: Bool = false
        
        // 设置coordinator引用（先设置，避免重复设置）
        if context.coordinator.webView !== webView {
            context.coordinator.webView = webView
            context.coordinator.onDebugInfo = onDebugInfo
            context.coordinator.onNodeSelected = onNodeSelected
            context.coordinator.onNodeDeselected = onNodeDeselected
            context.coordinator.onFitGraph = onFitGraph
            
            // 注册coordinator到全局管理器
            let viewId = ObjectIdentifier(webView)
            GraphManager.shared.registerCoordinator(context.coordinator, for: viewId)
        }
        
        // 计算当前数据签名
        let nodeIds = nodes.map { $0.id }.sorted()
        let edgeSignature = edges.map { "\($0.fromId)-\($0.toId)" }.sorted().joined(separator:",")
        let currentDataSignature = "\(nodeIds)-\(edgeSignature)"
        
        #if DEBUG
        if enableGraphDebug {
            print("🔍 updateNSView: lastSignature='\(context.coordinator.lastDataSignature)', currentSignature='\(currentDataSignature)'")
        }
        #endif
        
        // 强化的重复加载检查：只在数据真正变化时才更新
        if context.coordinator.lastDataSignature == currentDataSignature {
            #if DEBUG
            if enableGraphDebug {
                print("⏭️ 数据签名相同，跳过WebView更新")
            }
            #endif
            return
        }
        
        // 数据确实发生了变化，进行更新
        context.coordinator.lastDataSignature = currentDataSignature
        
        #if DEBUG
        if enableGraphDebug {
            print("🔄 数据发生变化，更新WebView内容")
        }
        #endif
        
        let htmlContent = self.generateGraphHTML(initialScale: self.initialScale)
        self.onDebugInfo("更新图形: \(self.nodes.count)个节点, \(self.edges.count)条边")
        
        // 使用简单的baseURL，避免缓存问题
        let baseURL = URL(string: "about:blank")
        webView.loadHTMLString(htmlContent, baseURL: baseURL)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, GraphCoordinator {
        var onDebugInfo: ((String) -> Void)?
        var onNodeSelected: ((Int) -> Void)?
        var onNodeDeselected: (() -> Void)?
        var onFitGraph: (() -> Void)?
        weak var webView: WKWebView?
        var lastDataSignature: String = ""
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("WebView加载失败: \(error)")
            onDebugInfo?("加载失败: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WebView导航失败: \(error)")
            onDebugInfo?("导航失败: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            onDebugInfo?("WebView开始加载内容")
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onDebugInfo?("图形加载完成")
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            
            switch message.name {
            case "nodeSelected":
                if let nodeId = body["nodeId"] as? Int {
                    onNodeSelected?(nodeId)
                }
            case "nodeDeselected":
                onNodeDeselected?()
            default:
                break
            }
        }
        
        func fitGraph() {
            let script = "if (window.fitGraph) { window.fitGraph(); }"
            webView?.evaluateJavaScript(script) { result, error in
                if let error = error {
                    print("执行fitGraph失败: \(error)")
                }
            }
        }
    }
    
    // 计算内容哈希以判断是否需要重新生成HTML
    private func calculateContentHash() -> String {
        let nodeStrings = nodes.map { "\($0.id):\($0.label)" }.joined(separator: ",")
        let edgeStrings = edges.map { "\($0.fromId)->\($0.toId)" }.joined(separator: ",")
        return "\(nodeStrings)|\(edgeStrings)"
    }
    
    private func generateGraphHTML(initialScale: Double = 1.0) -> String {
        // 安全检查：确保initialScale值在合理范围内
        let safeInitialScale = max(0.1, min(10.0, initialScale.isNaN ? 1.0 : initialScale))
        // 获取调试设置
        @AppStorage("enableGraphDebug") var enableGraphDebug: Bool = false
        
        // 调试信息：确认接收到的数据
        #if DEBUG
        if enableGraphDebug {
            print("🌐 UniversalRelationshipGraphView.generateGraphHTML - 强制重新生成")
            print("🌐 Processing \(nodes.count) nodes, \(edges.count) edges")
            
            // 检查中心单词
            if let centerNode = nodes.first(where: { ($0 as? NodeGraphNode)?.isCenter == true }),
               let wordNode = centerNode as? NodeGraphNode,
               let node = wordNode.node {
                print("🎯 CENTER NODE: \(node.text)")
            }
            
            for node in nodes {
                if let wordNode = node as? NodeGraphNode {
                    if let nodeItem = wordNode.node {
                        let centerMark = wordNode.isCenter ? "⭐" : "  "
                        print("🌐 \(centerMark) Node: \(nodeItem.text) (node) - ID: \(node.id)")
                    } else if let nodeTag = wordNode.tag {
                        print("🌐    Node: \(nodeTag.value) (tag: \(nodeTag.type.displayName)) - ID: \(node.id)")
                    }
                } else {
                    print("🌐    Node: \(node.label) - ID: \(node.id)")
                }
            }
            print("🌐 ==========================================")
        }
        #endif
        
        // 安全地转义字符串
        func escapeString(_ str: String) -> String {
            return str.replacingOccurrences(of: "'", with: "\\'")
                      .replacingOccurrences(of: "\n", with: "\\n")
                      .replacingOccurrences(of: "\r", with: "\\r")
        }
        
        // 生成节点数据 - 统一使用数字ID
        let nodeStrings = nodes.map { node in
            let color = getNodeColor(for: node)
            return """
            {id: \(node.id), label: '\(escapeString(node.label))', title: '\(escapeString(node.subtitle ?? ""))', color: {background: '\(color)', border: '#2B7CE9'}}
            """
        }
        
        // 生成边数据 - 统一使用数字ID并添加边ID
        let edgeStrings = edges.enumerated().map { i, edge in
            #if DEBUG
            if enableGraphDebug {
                print("🔗 Edge \(i+1): from=\(edge.fromId) to=\(edge.toId)")
            }
            #endif
            return "{id: \(i+1), from: \(edge.fromId), to: \(edge.toId)}"
        }
        
        let nodesStr = nodeStrings.joined(separator: ",\n                        ")
        // let edgesStr = edgeStrings.joined(separator: ",\n                        ") // 移除未使用的变量
        
        
        // 添加时间戳确保内容唯一性
        let timestamp = Date().timeIntervalSince1970
        
        return """
        <!DOCTYPE html>
        <html>
        <!-- Generated at: \(timestamp) -->
        <head>
            <meta charset="UTF-8">
            <style type="text/css">
                @media (prefers-color-scheme: dark) {
                    #mynetworkid {
                        width: 100%;
                        height: 100vh;
                        border: 1px solid #444;
                        background: #1e1e1e;
                    }
                    body { 
                        margin: 0; 
                        padding: 0; 
                        font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                        background: #1e1e1e;
                        color: #fff;
                    }
                }
                @media (prefers-color-scheme: light) {
                    #mynetworkid {
                        width: 100%;
                        height: 100vh;
                        border: 1px solid lightgray;
                        background: #fafafa;
                    }
                    body { 
                        margin: 0; 
                        padding: 0; 
                        font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                        background: #fafafa;
                        color: #333;
                    }
                }
                .loading { 
                    position: absolute; 
                    top: 50%; 
                    left: 50%; 
                    transform: translate(-50%, -50%);
                    font-size: 18px;
                    color: #666;
                }
                .error {
                    background: #ffe6e6;
                    border: 1px solid #ff9999;
                    padding: 20px;
                    margin: 20px;
                    border-radius: 8px;
                }
                .debug-info {
                    position: absolute;
                    top: 10px;
                    left: 10px;
                    background: rgba(0,0,0,0.9);
                    color: white;
                    padding: 10px;
                    border-radius: 5px;
                    font-size: 11px;
                    font-family: monospace;
                    max-width: 300px;
                    z-index: 1000;
                    white-space: pre-line;
                }
                .debug-panel {
                    position: absolute;
                    top: 10px;
                    right: 10px;
                    background: rgba(255,255,255,0.95);
                    color: black;
                    padding: 15px;
                    border-radius: 8px;
                    font-size: 12px;
                    font-family: monospace;
                    max-width: 400px;
                    z-index: 1000;
                    border: 1px solid #ccc;
                    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                }
            </style>
        </head>
        <body>
            <div id="loading" class="loading">正在加载关系图...</div>
            <div id="debug-display" style="display: \(enableGraphDebug ? "block" : "none"); padding: 20px; font-family: monospace; background: white; color: black;">
                <h3>调试显示 - 数据验证</h3>
                <div style="color: red; font-weight: bold;">生成时间: \(timestamp)</div>
                <div style="color: blue; font-weight: bold;">页面ID: \(Int.random(in: 10000...99999))</div>
                <div id="node-list"></div>
                <div id="edge-list"></div>
            </div>
            <div id="mynetworkid" style="display: \(enableGraphDebug ? "none" : "block");"></div>
            <script type="text/javascript">
                // 节点和边数据
                var nodeData = [
                    \(nodesStr)
                ];
                
                var edgeData = [
                    \(edgeStrings.joined(separator: ",\n                    "))
                ];
                
                // 显示调试信息或加载图谱
                function initializeView() {
                    var debugMode = \(enableGraphDebug ? "true" : "false");
                    
                    if (debugMode === "true") {
                        // 显示调试信息
                        showDebugInfo();
                    } else {
                        // 隐藏loading，显示图谱
                        document.getElementById('loading').style.display = 'none';
                        loadVisJS();
                    }
                }
                
                // 调试信息显示函数
                function showDebugInfo() {
                    var nodeList = document.getElementById('node-list');
                    var edgeList = document.getElementById('edge-list');
                    
                    nodeList.innerHTML = '<h4>节点数据 (' + nodeData.length + '):</h4>';
                    nodeData.forEach(function(node, i) {
                        nodeList.innerHTML += '<div>Node ' + (i+1) + ': ID=' + node.id + ', Label=' + node.label + '</div>';
                    });
                    
                    edgeList.innerHTML = '<h4>边数据 (' + edgeData.length + '):</h4>';
                    edgeData.forEach(function(edge, i) {
                        edgeList.innerHTML += '<div>Edge ' + (i+1) + ': from=' + edge.from + ' to=' + edge.to + '</div>';
                    });
                    
                    document.getElementById('loading').style.display = 'none';
                }
                
                // 初始化
                setTimeout(initializeView, 100);
                
                // 尝试加载vis.js，失败则使用简单实现
                function loadVisJS() {
                    var script = document.createElement('script');
                    script.onload = function() {
                        initVisGraph();
                    };
                    script.onerror = function() {
                        initSimpleGraph();
                    };
                    script.src = 'https://unpkg.com/vis-network/standalone/umd/vis-network.min.js';
                    document.head.appendChild(script);
                }
                
                function initVisGraph() {
                    var nodes = new vis.DataSet(nodeData);
                    var edges = new vis.DataSet(edgeData);
                    var container = document.getElementById('mynetworkid');
                    var data = { nodes: nodes, edges: edges };
                    var options = {
                        physics: {
                            enabled: true,
                            stabilization: { 
                                iterations: 200,
                                updateInterval: 25
                            },
                            solver: 'forceAtlas2Based',
                            timestep: 0.5,
                            adaptiveTimestep: true
                        },
                        nodes: {
                            font: { size: 14, color: '#333' },
                            borderWidth: 2,
                            shadow: true,
                            shape: 'circle',
                            size: 25
                        },
                        edges: {
                            width: 1.5,
                            color: { 
                                color: '#666666', 
                                highlight: '#333333', 
                                hover: '#000000' 
                            },
                            shadow: false,
                            arrows: {
                                to: { 
                                    enabled: true, 
                                    scaleFactor: 0.8, 
                                    type: 'arrow' 
                                }
                            },
                            smooth: {
                                enabled: true,
                                type: 'continuous',
                                roundness: 0.2
                            },
                            dashes: false,
                            selectionWidth: 2
                        },
                        interaction: {
                            zoomView: true,
                            dragView: true,
                            zoomSpeed: 0.2,
                            zoomSensitivity: 0.15,
                            keyboard: {
                                enabled: false
                            },
                            multiselect: false,
                            selectable: true,
                            selectConnectedEdges: false,
                            hover: true,
                            hoverConnectedEdges: true,
                            tooltipDelay: 200
                        }
                    };
                    
                    var network;
                    try {
                        network = new vis.Network(container, data, options);
                        console.log('图谱网络创建成功');
                    } catch (error) {
                        console.error('图谱网络创建失败:', error);
                        // 显示错误信息而不是崩溃
                        container.innerHTML = '<div style="padding: 20px; text-align: center; color: #666;">图谱加载失败，请重试</div>';
                        return;
                    }
                    
                    
                    network.once('stabilized', function() {
                        document.getElementById('loading').style.display = 'none';
                        container.style.display = 'block';
                        
                        var initialScale = \(safeInitialScale);
                        
                        // 安全检查：确保initialScale在合理范围内
                        if (isNaN(initialScale) || initialScale <= 0 || initialScale > 10) {
                            console.warn('无效的initialScale值:', initialScale, '重置为1.0');
                            initialScale = 1.0;
                        }
                        
                        // 先fit让所有节点在视野中，然后立即应用用户缩放设置
                        try {
                            network.fit();
                            console.log('图谱fit操作完成');
                        } catch (error) {
                            console.error('图谱fit操作失败:', error);
                        }
                        
                        if (initialScale !== 1.0) {
                            try {
                                // 立即应用用户设置的缩放级别，避免视觉跳跃
                                network.moveTo({
                                    scale: initialScale,
                                    animation: false  // 禁用动画，直接跳转到目标缩放
                                });
                                console.log('成功应用初始缩放:', initialScale);
                            } catch (error) {
                                console.error('应用初始缩放失败:', error);
                            }
                        }
                    });
                    
                    
                    window.fitGraph = function() { network.fit(); };
                }
                
                function initSimpleGraph() {
                    var container = document.getElementById('mynetworkid');
                    container.innerHTML = '';
                    container.style.display = 'block';
                    document.getElementById('loading').style.display = 'none';
                    
                    // 创建SVG
                    var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
                    svg.style.width = '100%';
                    svg.style.height = '100%';
                    container.appendChild(svg);
                    
                    var width = container.clientWidth || 800;
                    var height = container.clientHeight || 600;
                    
                    // 简单布局：圆形排列
                    var centerX = width / 2;
                    var centerY = height / 2;
                    var radius = Math.min(width, height) / 3;
                    
                    nodeData.forEach(function(node, index) {
                        var angle = (index * 2 * Math.PI) / nodeData.length;
                        node.x = centerX + radius * Math.cos(angle);
                        node.y = centerY + radius * Math.sin(angle);
                    });
                    
                    // 绘制边
                    edgeData.forEach(function(edge) {
                        var fromNode = nodeData.find(n => n.id === edge.from);
                        var toNode = nodeData.find(n => n.id === edge.to);
                        if (fromNode && toNode) {
                            var line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
                            line.setAttribute('x1', fromNode.x);
                            line.setAttribute('y1', fromNode.y);
                            line.setAttribute('x2', toNode.x);
                            line.setAttribute('y2', toNode.y);
                            line.setAttribute('stroke', '#666666');
                            line.setAttribute('stroke-width', '1.5');
                            svg.appendChild(line);
                        }
                    });
                    
                    // 绘制节点
                    nodeData.forEach(function(node) {
                        var circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
                        circle.setAttribute('cx', node.x);
                        circle.setAttribute('cy', node.y);
                        circle.setAttribute('r', 20);
                        circle.setAttribute('fill', node.color.background || node.color || '#4A90E2');
                        circle.setAttribute('stroke', '#2B7CE9');
                        circle.setAttribute('stroke-width', '2');
                        svg.appendChild(circle);
                        
                        var text = document.createElementNS('http://www.w3.org/2000/svg', 'text');
                        text.setAttribute('x', node.x);
                        text.setAttribute('y', node.y + 5);
                        text.setAttribute('text-anchor', 'middle');
                        text.setAttribute('font-size', '12');
                        text.setAttribute('font-weight', 'bold');
                        text.setAttribute('fill', '#333');
                        text.textContent = node.label;
                        svg.appendChild(text);
                    });
                    
                }
                
                // 开始加载
                setTimeout(loadVisJS, 100);
            </script>
        </body>
        </html>
        """
    }
    
    private func getNodeColor<T: UniversalGraphNode>(for node: T) -> String {
        // 检查是否是NodeGraphNode，如果是的话根据节点类型分配颜色
        if let wordNode = node as? NodeGraphNode {
            switch wordNode.nodeType {
            case .node:
                if wordNode.isCenter {
                    return "#FFD700" // 金色表示中心节点
                } else if let actualNode = wordNode.node, actualNode.isCompound {
                    // 根据复合节点的嵌套深度返回不同颜色
                    let depth = actualNode.getCompoundDepth(allNodes: NodeStore.shared.nodes)
                    switch depth {
                    case 1: return "#8B4A9C" // 1级复合节点 - 深紫色
                    case 2: return "#FF8C00" // 2级复合节点 - 橙色
                    case 3: return "#32CD32" // 3级复合节点 - 绿色  
                    case 4: return "#DC143C" // 4级复合节点 - 深红色
                    default: return "#4B0082" // 5级及以上 - 靛蓝色
                    }
                } else {
                    return "#4A90E2" // 蓝色表示普通节点
                }
            case .tag(let tagType):
                // 使用自动颜色管理器为标签分配颜色
                let tagKey: String
                switch tagType {
                case .location:
                    tagKey = "location"
                case .root:
                    tagKey = "root"
                case .custom(let customName):
                    // 自定义标签使用自定义名称作为key
                    tagKey = "custom_\(customName)"
                }
                return AutoColorManager.shared.getColor(for: tagKey)
            }
        }
        // 默认颜色
        return "#888888"
    }
}

// MARK: - 适配器，将现有数据转换为通用格式
struct GraphNodeAdapter: UniversalGraphNode {
    let id: Int
    let label: String
    let subtitle: String?
    let clusterId: String?
    let clusterColor: String?
}

struct GraphEdgeAdapter: UniversalGraphEdge {
    let fromId: Int
    let toId: Int
    let label: String?
}


// MARK: - 使用示例和预览
#Preview {
    // 模拟数据
    struct ExampleNode: UniversalGraphNode {
        let id: Int
        let label: String
        let subtitle: String?
    }
    
    struct ExampleEdge: UniversalGraphEdge {
        let fromId: Int
        let toId: Int
        let label: String?
    }
    
    let nodes = [
        ExampleNode(id: 1, label: "节点1", subtitle: "描述1"),
        ExampleNode(id: 2, label: "节点2", subtitle: "描述2"),
        ExampleNode(id: 3, label: "节点3", subtitle: "描述3")
    ]
    
    let edges = [
        ExampleEdge(fromId: 1, toId: 2, label: "连接1"),
        ExampleEdge(fromId: 2, toId: 3, label: "连接2")
    ]
    
    return UniversalRelationshipGraphView(
        nodes: nodes,
        edges: edges,
        title: "示例关系图"
    )
}