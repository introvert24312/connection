import SwiftUI

/// A wrapper view that integrates UniversalRelationshipGraphView with node context menu functionality
struct NodeContextGraphView<Node: UniversalGraphNode, Edge: UniversalGraphEdge>: View {
    let nodes: [Node]
    let edges: [Edge]
    let title: String
    let initialScale: Double
    let useHierarchicalLayout: Bool
    let onNodeSelected: ((Int, Bool, Bool) -> Void)?
    let onNodeDeselected: (() -> Void)?
    let onFitGraph: (() -> Void)?
    
    @EnvironmentObject private var store: NodeStore
    @State private var showingContextMenu = false
    @State private var contextMenuPosition = CGPoint.zero
    @State private var selectedNodeForContext: Node?
    @State private var showingNodeEditor = false
    @State private var nodeToEdit: Connection.Node?
    
    init(
        nodes: [Node],
        edges: [Edge],
        title: String = "节点关系图",
        initialScale: Double = 1.0,
        useHierarchicalLayout: Bool = false,
        onNodeSelected: ((Int, Bool, Bool) -> Void)? = nil,
        onNodeDeselected: (() -> Void)? = nil,
        onFitGraph: (() -> Void)? = nil
    ) {
        self.nodes = nodes
        self.edges = edges
        self.title = title
        self.initialScale = initialScale
        self.useHierarchicalLayout = useHierarchicalLayout
        self.onNodeSelected = onNodeSelected
        self.onNodeDeselected = onNodeDeselected
        self.onFitGraph = onFitGraph
    }
    
    var body: some View {
        ZStack {
            // Main graph view
            UniversalRelationshipGraphView(
                nodes: nodes,
                edges: edges,
                title: title,
                initialScale: initialScale,
                useHierarchicalLayout: useHierarchicalLayout,
                onNodeSelected: onNodeSelected,
                onNodeDeselected: onNodeDeselected,
                onFitGraph: onFitGraph,
                onNodeRightClicked: { nodeId, x, y in
                    handleNodeRightClick(nodeId: nodeId, x: x, y: y)
                }
            )
            
            // Context menu overlay
            if showingContextMenu, let contextNode = selectedNodeForContext {
                NodeContextMenuView(
                    node: extractOrCreateWordTaggerNode(from: contextNode),
                    onEditCommand: {
                        handleEditCommand()
                    },
                    onEditName: {
                        handleEditName()
                    },
                    onDelete: {
                        handleDeleteNode()
                    }
                )
                .position(x: contextMenuPosition.x, y: contextMenuPosition.y)
                .zIndex(1000)
                .onTapGesture {
                    // Dismiss context menu when tapping outside
                    dismissContextMenu()
                }
            }
        }
        .onTapGesture {
            // Dismiss context menu when tapping on the graph
            if showingContextMenu {
                dismissContextMenu()
            }
        }
        .sheet(isPresented: $showingNodeEditor) {
            if let nodeToEdit = nodeToEdit {
                NodeEditorSheet(
                    node: .constant(nodeToEdit),
                    onSave: { updatedNode in
                        handleNodeSave(updatedNode)
                    },
                    onCancel: {
                        handleNodeEditCancel()
                    }
                )
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func handleNodeRightClick(nodeId: Int, x: CGFloat, y: CGFloat) {
        // Find the node that was right-clicked
        guard let clickedNode = nodes.first(where: { $0.id == nodeId }) else {
            print("⚠️ Could not find node with ID: \(nodeId)")
            return
        }
        
        // Only show context menu for actual nodes (not tags)
        guard let wordTaggerNode = extractWordTaggerNode(from: clickedNode) else {
            print("⚠️ Right-clicked item is not a WordTagger node")
            return
        }
        
        print("🖱️ Right-click detected on node: \(wordTaggerNode.text) at (\(x), \(y))")
        
        selectedNodeForContext = clickedNode
        contextMenuPosition = CGPoint(x: x, y: y)
        showingContextMenu = true
    }
    
    private func dismissContextMenu() {
        showingContextMenu = false
        selectedNodeForContext = nil
    }
    
    private func handleEditCommand() {
        guard let contextNode = selectedNodeForContext,
              let wordTaggerNode = extractWordTaggerNode(from: contextNode) else {
            return
        }
        
        nodeToEdit = wordTaggerNode
        showingNodeEditor = true
        dismissContextMenu()
    }
    
    private func handleEditName() {
        guard let contextNode = selectedNodeForContext,
              let wordTaggerNode = extractWordTaggerNode(from: contextNode) else {
            return
        }
        
        nodeToEdit = wordTaggerNode
        showingNodeEditor = true
        dismissContextMenu()
    }
    
    private func handleDeleteNode() {
        guard let contextNode = selectedNodeForContext,
              let wordTaggerNode = extractWordTaggerNode(from: contextNode) else {
            return
        }
        
        // Show confirmation alert
        let alert = NSAlert()
        alert.messageText = "Delete Node"
        alert.informativeText = "Are you sure you want to delete the node '\(wordTaggerNode.text)'? This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Delete the node
            store.deleteNode(wordTaggerNode)
            print("🗑️ Deleted node: \(wordTaggerNode.text)")
        }
        
        dismissContextMenu()
    }
    
    private func handleNodeSave(_ updatedNode: Connection.Node) {
        // Update the node in the store
        store.updateNode(updatedNode)
        print("💾 Saved node: \(updatedNode.text)")
        
        // Clear the editing state
        nodeToEdit = nil
        showingNodeEditor = false
    }
    
    private func handleNodeEditCancel() {
        // Clear the editing state
        nodeToEdit = nil
        showingNodeEditor = false
        print("❌ Cancelled node editing")
    }
    
    /// Extracts a Connection.Node from a generic UniversalGraphNode
    private func extractWordTaggerNode(from graphNode: Node) -> Connection.Node? {
        // Check if this is a NodeGraphNode (which wraps WordTagger.Node)
        if let nodeGraphNode = graphNode as? NodeGraphNode {
            return nodeGraphNode.node
        }
        
        // If it's not a NodeGraphNode, we can't extract a WordTagger.Node
        return nil
    }
    
    /// Creates a dummy Connection.Node for context menu display when we can't extract the real one
    private func extractOrCreateWordTaggerNode(from graphNode: Node) -> Connection.Node {
        // Try to extract the real node first
        if let nodeGraphNode = graphNode as? NodeGraphNode,
           let realNode = nodeGraphNode.node {
            return realNode
        }
        
        // Create a dummy node for display purposes
        return Connection.Node(
            text: graphNode.label,
            phonetic: nil,
            meaning: graphNode.subtitle,
            layerId: UUID(), // This will need to be handled properly
            tags: [],
            isCompound: false,
            markdown: ""
        )
    }
}

// MARK: - Preview

#Preview {
    // Mock data for preview
    struct MockNode: UniversalGraphNode {
        let id: Int
        let label: String
        let subtitle: String?
    }
    
    struct MockEdge: UniversalGraphEdge {
        let fromId: Int
        let toId: Int
        let label: String?
    }
    
    let mockNodes = [
        MockNode(id: 1, label: "Node 1", subtitle: "First node"),
        MockNode(id: 2, label: "Node 2", subtitle: "Second node"),
        MockNode(id: 3, label: "Node 3", subtitle: "Third node")
    ]
    
    let mockEdges = [
        MockEdge(fromId: 1, toId: 2, label: "connects to"),
        MockEdge(fromId: 2, toId: 3, label: "links to")
    ]
    
    return NodeContextGraphView(
        nodes: mockNodes,
        edges: mockEdges,
        title: "Context Menu Graph"
    )
    .environmentObject(NodeStore.shared)
    .frame(width: 800, height: 600)
}