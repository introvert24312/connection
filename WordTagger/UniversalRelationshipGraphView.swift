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
        webView.loadHTMLString(htmlContent, baseURL: nil)
        
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
        
        // 生成节点数据
        let nodeStrings = nodes.map { node in
            let color = getNodeColor(for: node)
            return """
            {id: \(node.id), label: '\(escapeString(node.label))', title: '\(escapeString(node.subtitle ?? ""))', color: {background: '\(color)', border: '#2B7CE9'}}
            """
        }
        
        // 生成边数据（移除标签）
        let edgeStrings = edges.map { edge in
            return "{from: \(edge.fromId), to: \(edge.toId)}"
        }
        
        let nodesStr = nodeStrings.joined(separator: ",\n                        ")
        let edgesStr = edgeStrings.joined(separator: ",\n                        ")
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <script type="text/javascript" src="https://unpkg.com/vis-network/standalone/umd/vis-network.min.js"></script>
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
            </style>
        </head>
        <body>
            <div id="loading" class="loading">正在加载关系图...</div>
            <div id="mynetworkid" style="display: none;"></div>
            <script type="text/javascript">
                console.log('初始化关系图 - 节点:', \(nodes.count), '边:', \(edges.count));
                
                setTimeout(function() {
                    try {
                        if (typeof vis === 'undefined') {
                            throw new Error('vis.js 库未加载');
                        }
                        
                        var nodes = new vis.DataSet([
                        \(nodesStr)
                        ]);
                        
                        var edges = new vis.DataSet([
                        \(edgesStr)
                        ]);
                        
                        var container = document.getElementById('mynetworkid');
                        var data = { nodes: nodes, edges: edges };
                        var options = {
                            physics: {
                                enabled: true,
                                stabilization: { iterations: 150 },
                                barnesHut: {
                                    gravitationalConstant: -8000,
                                    springConstant: 0.001,
                                    springLength: 300,
                                    damping: 0.1
                                },
                                repulsion: {
                                    centralGravity: 0.1,
                                    springLength: 400,
                                    springConstant: 0.01,
                                    damping: 0.09
                                }
                            },
                            nodes: {
                                font: { 
                                    size: 20, 
                                    color: '#333',
                                    face: 'Arial, -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif',
                                    align: 'center',
                                    vadjust: 0,
                                    bold: true
                                },
                                borderWidth: 2,
                                shadow: true,
                                shape: 'circle',
                                size: 45,
                                labelHighlightBold: false,
                                scaling: {
                                    min: 35,
                                    max: 70,
                                    label: {
                                        enabled: true,
                                        min: 18,
                                        max: 24
                                    }
                                }
                            },
                            edges: {
                                width: 2,
                                color: { color: '#848484' },
                                shadow: true,
                                smooth: { type: 'continuous' }
                            },
                            interaction: {
                                dragNodes: true,
                                dragView: true,
                                zoomView: true,
                                zoomSpeed: 1,
                                selectConnectedEdges: false,
                                multiselect: true,
                                navigationButtons: true,
                                keyboard: {
                                    enabled: true
                                },
                                tooltipDelay: 100,
                                hideEdgesOnDrag: false,
                                hideNodesOnDrag: false
                            },
                            manipulation: {
                                enabled: false
                            },
                            layout: {
                                improvedLayout: true,
                                clusterThreshold: 150,
                                hierarchical: {
                                    enabled: false
                                }
                            },
                            groups: {}
                        };
                        
                        var network = new vis.Network(container, data, options);
                        
                        // 等待稳定后居中显示
                        network.once('stabilized', function() {
                            setTimeout(function() {
                                network.fit({
                                    animation: {
                                        duration: 1000,
                                        easingFunction: "easeInOutQuad"
                                    }
                                });
                            }, 100);
                        });
                        
                        // 事件监听
                        network.on('selectNode', function(params) {
                            console.log('选中节点:', params.nodes);
                            if (params.nodes && params.nodes.length > 0) {
                                var nodeId = params.nodes[0];
                                // 通知Swift代码处理节点聚焦
                                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nodeSelected) {
                                    window.webkit.messageHandlers.nodeSelected.postMessage({
                                        type: 'nodeSelected',
                                        nodeId: nodeId
                                    });
                                }
                            }
                        });
                        
                        network.on('deselectNode', function(params) {
                            // 当取消选择时，退出聚焦模式
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nodeDeselected) {
                                window.webkit.messageHandlers.nodeDeselected.postMessage({
                                    type: 'nodeDeselected'
                                });
                            }
                        });
                        
                        network.on('stabilizationIterationsDone', function() {
                            console.log('图形稳定化完成');
                            document.getElementById('loading').style.display = 'none';
                            container.style.display = 'block';
                        });
                        
                        // 禁用双击缩放，只允许捏合手势缩放
                        container.addEventListener('dblclick', function(e) {
                            e.preventDefault();
                            e.stopPropagation();
                        });
                        
                        // 添加更流畅的缩放动画
                        network.on('zoom', function(params) {
                            var scale = network.getScale();
                            console.log('缩放比例:', scale);
                        });
                        
                        // 添加回到中心的函数
                        window.fitGraph = function() {
                            network.fit({
                                animation: {
                                    duration: 300,
                                    easingFunction: 'easeInOutQuart'
                                }
                            });
                        };
                        
                        // 监听来自Swift的消息
                        window.addEventListener('message', function(event) {
                            if (event.data && event.data.type === 'fitGraph') {
                                window.fitGraph();
                            }
                        });
                        
                        // 3秒后强制显示
                        setTimeout(function() {
                            document.getElementById('loading').style.display = 'none';
                            container.style.display = 'block';
                        }, 3000);
                        
                    } catch (error) {
                        console.error('图形初始化失败:', error);
                        document.body.innerHTML = '<div class="error"><h3>关系图加载失败</h3><p>' + error.message + '</p></div>';
                    }
                }, 500);
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
                // 根据标签类型分配颜色
                switch tagType {
                case .memory:
                    return "#FF69B4" // 粉色表示记忆标签
                case .location:
                    return "#FF4444" // 红色表示地点标签
                case .root:
                    return "#4169E1" // 蓝色表示词根标签
                case .shape:
                    return "#32CD32" // 绿色表示形近标签
                case .sound:
                    return "#FF8C00" // 橙色表示音近标签
                case .custom(_):
                    return "#9370DB" // 紫色表示自定义标签
                }
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