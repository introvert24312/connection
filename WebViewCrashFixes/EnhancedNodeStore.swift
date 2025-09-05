// 增强的NodeStore状态管理 - 解决WebView闪退问题
import Combine
import Foundation
import SwiftUI

@MainActor
public final class EnhancedNodeStore: ObservableObject {
    // MARK: - 原子性更新保护
    private let nodeUpdateSemaphore = DispatchSemaphore(value: 1)
    private var isUpdatingNodes = false
    
    @Published public private(set) var nodes: [Node] = []
    @Published public private(set) var selectedNode: Node?
    
    // MARK: - WebView状态同步机制
    private var pendingNodeUpdates: [UUID: Node] = [:]
    private var lastSignificantUpdate: Date = Date()
    
    /// 原子性节点更新 - 防止状态竞争
    public func updateNodeSafely(_ nodeId: UUID, markdown: String) async {
        await withCheckedContinuation { continuation in
            nodeUpdateSemaphore.wait()
            defer { nodeUpdateSemaphore.signal() }
            
            guard !isUpdatingNodes else {
                print("⚠️ NodeStore: 跳过重复更新操作")
                continuation.resume()
                return
            }
            
            isUpdatingNodes = true
            defer { isUpdatingNodes = false }
            
            if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
                var updatedNode = nodes[index]
                updatedNode.markdown = markdown
                updatedNode.updatedAt = Date()
                
                // 检测是否为实质性变化
                let hasSignificantChange = isSignificantChange(
                    from: nodes[index].markdown, 
                    to: markdown
                )
                
                nodes[index] = updatedNode
                
                if hasSignificantChange {
                    lastSignificantUpdate = Date()
                    print("✅ NodeStore: 实质性更新完成 - \(nodeId)")
                }
                
                // 更新选中节点引用
                if selectedNode?.id == nodeId {
                    selectedNode = updatedNode
                }
            }
            
            continuation.resume()
        }
    }
    
    /// 检测是否为实质性变化
    private func isSignificantChange(from oldContent: String, to newContent: String) -> Bool {
        // 忽略微小的空白变化
        let oldTrimmed = oldContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTrimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 检查内容长度变化
        let lengthDifference = abs(newTrimmed.count - oldTrimmed.count)
        if lengthDifference > 10 { // 超过10个字符认为是实质性变化
            return true
        }
        
        // 检查关键词变化
        let oldWords = Set(oldTrimmed.components(separatedBy: .whitespaces))
        let newWords = Set(newTrimmed.components(separatedBy: .whitespaces))
        
        return oldWords != newWords
    }
    
    /// 获取节点的稳定哈希 - 用于WebView ID
    public func getStableNodeHash(_ node: Node) -> String {
        let contentSignature = "\(node.text)-\(node.markdown.count)-\(node.tags.count)"
        let timeSignature = String(Int(node.updatedAt.timeIntervalSince1970 / 300)) // 5分钟窗口
        return "\(contentSignature)-\(timeSignature)".hash.description
    }
    
    /// 批量更新保护
    public func batchUpdateNodes(_ updates: [(UUID, String)]) async {
        await withCheckedContinuation { continuation in
            nodeUpdateSemaphore.wait()
            defer { nodeUpdateSemaphore.signal() }
            
            isUpdatingNodes = true
            defer { isUpdatingNodes = false }
            
            var hasAnySignificantChange = false
            
            for (nodeId, markdown) in updates {
                if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
                    let hasChange = isSignificantChange(
                        from: nodes[index].markdown, 
                        to: markdown
                    )
                    
                    var updatedNode = nodes[index]
                    updatedNode.markdown = markdown
                    updatedNode.updatedAt = Date()
                    nodes[index] = updatedNode
                    
                    if hasChange {
                        hasAnySignificantChange = true
                    }
                }
            }
            
            if hasAnySignificantChange {
                lastSignificantUpdate = Date()
            }
            
            continuation.resume()
        }
    }
}

// MARK: - WebView更新频率控制器
@MainActor
public class WebViewUpdateManager: ObservableObject {
    private var lastUpdateTime: Date = Date.distantPast
    private let minimumUpdateInterval: TimeInterval = 0.5 // 500ms最小间隔
    
    private var pendingUpdate: DispatchWorkItem?
    
    /// 安全的WebView内容设置
    public func setMarkdownSafely(
        coordinator: VditorWebView.Coordinator?,
        content: String,
        forceUpdate: Bool = false
    ) {
        guard let coordinator = coordinator else { return }
        
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastUpdateTime)
        
        if !forceUpdate && timeSinceLastUpdate < minimumUpdateInterval {
            // 取消之前的待处理更新
            pendingUpdate?.cancel()
            
            // 延迟执行更新
            let delay = minimumUpdateInterval - timeSinceLastUpdate
            pendingUpdate = DispatchWorkItem { [weak self] in
                self?.executeUpdate(coordinator: coordinator, content: content)
            }
            
            DispatchQueue.main.asyncAfter(
                deadline: .now() + delay,
                execute: pendingUpdate!
            )
        } else {
            executeUpdate(coordinator: coordinator, content: content)
        }
    }
    
    private func executeUpdate(coordinator: VditorWebView.Coordinator, content: String) {
        lastUpdateTime = Date()
        coordinator.setMarkdown(content, forceUpdate: false)
        print("✅ WebViewUpdateManager: 安全更新完成")
    }
}