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

// MARK: - 通用关系图组件
struct UniversalRelationshipGraphView<Node: UniversalGraphNode, Edge: UniversalGraphEdge>: View {
    let nodes: [Node]
    let edges: [Edge]
    let title: String
    @State private var debugInfo = ""
    
    init(nodes: [Node], edges: [Edge], title: String = "节点关系图") {
        self.nodes = nodes
        self.edges = edges
        self.title = title
    }
    
    var body: some View {
        VStack {
            if nodes.isEmpty {
                emptyStateView
            } else {
                UniversalGraphWebView(nodes: nodes, edges: edges) { info in
                    DispatchQueue.main.async {
                        debugInfo = info
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        context.coordinator.onDebugInfo = onDebugInfo
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        let htmlContent = generateGraphHTML()
        onDebugInfo("生成图形: \(nodes.count)个节点, \(edges.count)条边")
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var onDebugInfo: ((String) -> Void)?
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("WebView加载失败: \(error)")
            onDebugInfo?("加载失败: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onDebugInfo?("图形加载完成")
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
                #mynetworkid {
                    width: 100%;
                    height: 100vh;
                    border: 1px solid lightgray;
                    background: #fafafa;
                }
                body { margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
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
                                selectConnectedEdges: false,
                                multiselect: true,
                                navigationButtons: true,
                                keyboard: {
                                    enabled: true
                                }
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
                        
                        // 事件监听
                        network.on('selectNode', function(params) {
                            console.log('选中节点:', params.nodes);
                        });
                        
                        network.on('stabilizationIterationsDone', function() {
                            console.log('图形稳定化完成');
                            document.getElementById('loading').style.display = 'none';
                            container.style.display = 'block';
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
        // 不再设置自定义颜色，让 vis.js 使用默认配色
        // 返回空字符串让 vis.js 自动分配颜色
        return ""
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