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
    let onNodeSelected: ((Int) -> Void)?
    let onNodeDeselected: (() -> Void)?
    let onFitGraph: (() -> Void)?
    @State private var debugInfo = ""
    @State private var viewId = ObjectIdentifier(UUID() as AnyObject)
    
    init(nodes: [Node], edges: [Edge], title: String = "节点关系图", onNodeSelected: ((Int) -> Void)? = nil, onNodeDeselected: (() -> Void)? = nil, onFitGraph: (() -> Void)? = nil) {
        self.nodes = nodes
        self.edges = edges
        self.title = title
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
    let onDebugInfo: (String) -> Void
    let onNodeSelected: ((Int) -> Void)?
    let onNodeDeselected: (() -> Void)?
    let onFitGraph: (() -> Void)?
    
    init(nodes: [Node], edges: [Edge], onDebugInfo: @escaping (String) -> Void, onNodeSelected: ((Int) -> Void)? = nil, onNodeDeselected: (() -> Void)? = nil, onFitGraph: (() -> Void)? = nil) {
        self.nodes = nodes
        self.edges = edges
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
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        let htmlContent = generateGraphHTML()
        onDebugInfo("生成图形: \(nodes.count)个节点, \(edges.count)条边")
        
        // 使用更安全的baseURL以避免安全问题
        let baseURL = URL(string: "https://unpkg.com")
        webView.loadHTMLString(htmlContent, baseURL: baseURL)
        
        // 设置coordinator引用
        context.coordinator.webView = webView
        context.coordinator.onDebugInfo = onDebugInfo
        context.coordinator.onNodeSelected = onNodeSelected
        context.coordinator.onNodeDeselected = onNodeDeselected
        context.coordinator.onFitGraph = onFitGraph
        
        // 注册coordinator到全局管理器
        let viewId = ObjectIdentifier(webView)
        GraphManager.shared.registerCoordinator(context.coordinator, for: viewId)
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
    
    private func generateGraphHTML() -> String {
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
            return "{id: \(i+1), from: \(edge.fromId), to: \(edge.toId)}"
        }
        
        let nodesStr = nodeStrings.joined(separator: ",\n                        ")
        let edgesStr = edgeStrings.joined(separator: ",\n                        ")
        
        
        return """
        <!DOCTYPE html>
        <html>
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
            <div class="debug-info">节点: \(nodes.count) | 连接: \(edges.count)</div>
            <div class="debug-panel" id="debugPanel">调试信息加载中...</div>
            <div id="mynetworkid" style="display: none;"></div>
            <script type="text/javascript">
                console.log('初始化简单图谱 - 节点:', \(nodes.count), '边:', \(edges.count));
                
                // 节点和边数据
                var nodeData = [
                    \(nodesStr)
                ];
                
                var edgeData = [
                    \(edgeStrings.joined(separator: ",\n                    "))
                ];
                
                console.log('节点数据:', nodeData);
                console.log('边数据:', edgeData);
                console.log('节点ID类型:', typeof nodeData[0]?.id);
                console.log('边from类型:', typeof edgeData[0]?.from);
                console.log('节点数量:', nodeData.length, '边数量:', edgeData.length);
                
                // 显示调试信息到页面
                function updateDebugPanel(message) {
                    var panel = document.getElementById('debugPanel');
                    if (panel) {
                        panel.innerHTML += message + '<br>';
                    }
                }
                
                updateDebugPanel('节点数量: ' + nodeData.length);
                updateDebugPanel('边数量: ' + edgeData.length);
                if (nodeData.length > 0) {
                    updateDebugPanel('节点ID类型: ' + typeof nodeData[0].id);
                    updateDebugPanel('=== 实际节点ID ===');
                    var nodeIds = [];
                    nodeData.forEach((node, index) => {
                        nodeIds.push(node.id);
                        updateDebugPanel('节点' + (index+1) + ' ID: ' + node.id + ' (' + node.label + ')');
                    });
                    updateDebugPanel('节点ID集合: [' + nodeIds.join(', ') + ']');
                }
                if (edgeData.length > 0) {
                    updateDebugPanel('边from类型: ' + typeof edgeData[0].from);
                    updateDebugPanel('边to类型: ' + typeof edgeData[0].to);
                }
                
                // 尝试加载vis.js，失败则使用简单实现
                function loadVisJS() {
                    var script = document.createElement('script');
                    script.onload = function() {
                        console.log('vis.js加载成功');
                        initVisGraph();
                    };
                    script.onerror = function() {
                        console.log('vis.js加载失败，使用简单实现');
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
                            solver: 'forceAtlas2Based'
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
                        }
                    };
                    
                    var network = new vis.Network(container, data, options);
                    
                    // 调试DataSet信息
                    console.log('DataSet nodes:', nodes.length);
                    console.log('DataSet edges:', edges.length);
                    console.log('edges in dataset:', edges.get());
                    
                    // ID类型检查脚本
                    updateDebugPanel('=== 边连接检查 ===');
                    edges.get().forEach((e, index) => {
                        var fromNode = nodes.get(e.from);
                        var toNode = nodes.get(e.to);
                        updateDebugPanel('边' + (index+1) + ': from=' + e.from + '(' + typeof e.from + ') to=' + e.to + '(' + typeof e.to + ')');
                        updateDebugPanel('  找到from节点: ' + (fromNode ? '✓' : '✗'));
                        updateDebugPanel('  找到to节点: ' + (toNode ? '✓' : '✗'));
                        
                        console.log(
                            'Edge ID:', e.id,
                            'from:', e.from, typeof e.from,
                            'to:', e.to, typeof e.to,
                            'from node:', fromNode,
                            'to node:', toNode
                        );
                    });
                    
                    network.once('stabilized', function() {
                        document.getElementById('loading').style.display = 'none';
                        container.style.display = 'block';
                        network.fit();
                        console.log('网络已稳定，节点:', nodes.length, '边:', edges.length);
                        updateDebugPanel('=== 网络已稳定 ===');
                        updateDebugPanel('渲染完成，边应该可见');
                        
                        // 强制测试边的显示
                        setTimeout(function() {
                            updateDebugPanel('=== 强制边样式测试 ===');
                            network.setOptions({
                                edges: {
                                    width: 3,
                                    color: { color: '#ff0000' },
                                    dashes: false,
                                    shadow: false
                                }
                            });
                            updateDebugPanel('已应用红色测试边样式');
                        }, 1000);
                    });
                    
                    // 网络事件监听
                    network.on('afterDrawing', function() {
                        updateDebugPanel('图谱已重绘，边数: ' + edges.length);
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
                    
                    console.log('简单图谱渲染完成');
                }
                
                // 开始加载
                setTimeout(loadVisJS, 100);
            </script>
        </body>
        </html>
        """
    }
    
    private func getNodeColor<T: UniversalGraphNode>(for node: T) -> String {
        // 检查是否是WordGraphNode，如果是的话根据节点类型分配颜色
        if let wordNode = node as? WordGraphNode {
            switch wordNode.nodeType {
            case .word:
                if wordNode.isCenter {
                    return "#FFD700" // 金色表示中心单词
                } else {
                    return "#4A90E2" // 蓝色表示普通单词
                }
            case .tag(let tagType):
                // 使用自动颜色管理器为标签分配颜色
                let tagKey: String
                switch tagType {
                case .memory:
                    tagKey = "memory"
                case .location:
                    tagKey = "location"
                case .root:
                    tagKey = "root"
                case .shape:
                    tagKey = "shape"
                case .sound:
                    tagKey = "sound"
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