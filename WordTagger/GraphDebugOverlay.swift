import SwiftUI
import WebKit

/// 图谱调试覆盖层 - 持久显示在图谱上方，监控图谱状态
struct GraphDebugOverlay: View {
    @State private var debugInfo: [String] = []
    @State private var isVisible = true
    @State private var webViewState = "未知"
    @State private var lastUpdate = Date()
    @State private var updateCounter = 0
    @State private var currentWindowId = "未知"
    @State private var allWindowIds: [String] = []
    @State private var storeState = "未知"
    
    let webView: WKWebView?
    let graphId: String
    let nodeText: String
    let windowId: String
    
    var body: some View {
        VStack {
            if isVisible {
                debugPanel
                    .transition(.opacity)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            startMonitoring()
        }
    }
    
    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 标题栏
            HStack {
                Text("🔍 图谱调试器")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("节点: \(nodeText)")
                    .font(.caption)
                    .foregroundColor(.yellow)
                
                Button(action: {
                    withAnimation {
                        isVisible.toggle()
                    }
                }) {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            
            // 状态信息
            VStack(alignment: .leading, spacing: 2) {
                // 多窗口信息
                statusRow("当前窗口", windowId.prefix(8).description)
                statusRow("活跃窗口", currentWindowId)
                statusRow("总窗口数", "\(allWindowIds.count)")
                statusRow("Store状态", storeState)
                
                // 分割线
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 1)
                
                // WebView信息
                statusRow("WebView状态", webViewState)
                statusRow("图谱ID", graphId.prefix(12).description)
                statusRow("更新次数", "\(updateCounter)")
                statusRow("最后更新", timeAgo(lastUpdate))
                
                if let webView = webView {
                    statusRow("WebView对象", "\(ObjectIdentifier(webView))".prefix(12).description)
                    statusRow("是否加载", webView.isLoading ? "加载中" : "已加载")
                    statusRow("URL", webView.url?.absoluteString?.prefix(20).description ?? "无")
                }
            }
            .font(.caption)
            
            // 最近的调试信息
            if !debugInfo.isEmpty {
                Divider()
                    .background(Color.white)
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(debugInfo.enumerated().reversed()), id: \.offset) { index, info in
                            Text(info)
                                .font(.caption2)
                                .foregroundColor(.white)
                                .opacity(Double(debugInfo.count - index) / Double(debugInfo.count))
                        }
                    }
                }
                .frame(maxHeight: 100)
            }
            
            // 控制按钮
            HStack {
                Button("清除日志") {
                    debugInfo.removeAll()
                }
                .font(.caption)
                .foregroundColor(.white)
                
                Spacer()
                
                Button("测试WebView") {
                    testWebView()
                }
                .font(.caption)
                .foregroundColor(.white)
                
                Button("强制刷新") {
                    forceRefresh()
                }
                .font(.caption)
                .foregroundColor(.white)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.8))
                .stroke(Color.blue, lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }
    
    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text("\(label):")
                .foregroundColor(.gray)
            Text(value)
                .foregroundColor(.white)
            Spacer()
        }
    }
    
    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 1 {
            return "刚刚"
        } else if interval < 60 {
            return "\(Int(interval))秒前"
        } else {
            return "\(Int(interval/60))分钟前"
        }
    }
    
    private func addDebugInfo(_ info: String) {
        let timestamp = DateFormatter().string(from: Date()).suffix(8)
        let logEntry = "[\(timestamp)] \(info)"
        
        DispatchQueue.main.async {
            debugInfo.append(logEntry)
            if debugInfo.count > 20 {
                debugInfo.removeFirst()
            }
            lastUpdate = Date()
            updateCounter += 1
        }
    }
    
    private func startMonitoring() {
        addDebugInfo("🟢 调试器启动 - 窗口: \(windowId.prefix(8))")
        
        // 监控多窗口状态
        updateWindowInfo()
        
        // 监控WebView状态变化
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            updateWindowInfo()
            updateStoreInfo()
            
            guard let webView = webView else {
                webViewState = "WebView为空"
                return
            }
            
            let currentState = webView.isLoading ? "加载中" : "已加载"
            if currentState != webViewState {
                webViewState = currentState
                addDebugInfo("📊 WebView状态变化: \(currentState)")
            }
            
            // 检查WebView的父视图
            checkWebViewHierarchy()
        }
        
        // 监听通知
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("windowFocusChanged"),
            object: nil,
            queue: .main
        ) { notification in
            if let windowInfo = notification.object {
                addDebugInfo("🏠 窗口焦点变化: \(windowInfo)")
            } else {
                addDebugInfo("🏠 窗口失去焦点")
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            addDebugInfo("✅ 应用变为活跃")
        }
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            addDebugInfo("❌ 应用失去活跃")
        }
        
        // 监听节点选择事件
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("selectNodeFromCommandClick"),
            object: nil,
            queue: .main
        ) { notification in
            if let node = notification.object {
                addDebugInfo("👆 收到节点选择: \(node)")
            }
        }
        
        // 监听其他可能干扰的通知
        let criticalNotifications = [
            "toggleDetailPanelTab",
            "switchToDetailTab", 
            "switchToGraphTab",
            "executeDetailTabSwitch",
            "executeGraphTabSwitch",
            "forceGraphRefresh"
        ]
        
        for notificationName in criticalNotifications {
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name(notificationName),
                object: nil,
                queue: .main
            ) { notification in
                addDebugInfo("📡 通知: \(notificationName)")
            }
        }
    }
    
    private func checkWebViewHierarchy() {
        guard let webView = webView else { return }
        
        var current: NSView? = webView
        var hierarchy: [String] = []
        
        while let view = current {
            let isHidden = view.isHidden
            let alpha = view.alphaValue
            let frame = view.frame
            
            hierarchy.append("\(type(of: view))(hidden:\(isHidden), alpha:\(alpha), frame:\(frame.width)x\(frame.height))")
            current = view.superview
            
            if hierarchy.count > 5 { break } // 防止过深
        }
        
        if hierarchy.count > 0 {
            let newHierarchy = hierarchy.joined(separator: " -> ")
            // 只在层次结构变化时记录
            // 这里可以根据需要调整记录频率
        }
    }
    
    private func testWebView() {
        guard let webView = webView else {
            addDebugInfo("❌ 测试失败: WebView为空")
            return
        }
        
        addDebugInfo("🧪 开始WebView测试")
        
        // 测试JavaScript执行
        webView.evaluateJavaScript("document.title") { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    addDebugInfo("❌ JS测试失败: \(error.localizedDescription)")
                } else {
                    addDebugInfo("✅ JS测试成功: \(result ?? "无结果")")
                }
            }
        }
        
        // 测试WebView可见性
        let isVisible = !webView.isHidden && webView.alphaValue > 0
        addDebugInfo("👁️ WebView可见性: \(isVisible)")
        
        // 测试父视图链
        var parent = webView.superview
        var level = 0
        while parent != nil && level < 3 {
            let isParentVisible = !parent!.isHidden && parent!.alphaValue > 0
            addDebugInfo("📦 父视图\(level): \(type(of: parent!)) 可见:\(isParentVisible)")
            parent = parent!.superview
            level += 1
        }
    }
    
    private func updateWindowInfo() {
        // 获取WindowFocusManager的状态
        let activeWindowId = WindowFocusManager.shared.getActiveWindowId()?.uuidString ?? "无"
        if activeWindowId != currentWindowId {
            currentWindowId = activeWindowId.prefix(8).description
            addDebugInfo("🏠 活跃窗口变化: \(currentWindowId)")
        }
        
        // 获取所有注册的窗口
        let debugInfo = WindowFocusManager.shared.getDebugInfo()
        if let windowList = debugInfo["windowList"] as? [String] {
            allWindowIds = windowList
        }
    }
    
    private func updateStoreInfo() {
        // 这里可以添加Store状态监控
        // 需要通过某种方式获取Store的状态
        storeState = "监控中"
    }
    
    private func forceRefresh() {
        addDebugInfo("🔄 强制刷新请求")
        // 发送刷新通知
        NotificationCenter.default.post(
            name: NSNotification.Name("forceGraphRefresh"),
            object: graphId
        )
    }
}

#Preview {
    GraphDebugOverlay(
        webView: nil,
        graphId: "preview-graph",
        nodeText: "测试节点",
        windowId: "preview-window-id"
    )
    .frame(width: 400, height: 300)
    .background(Color.gray)
}