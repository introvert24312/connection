// 增强的VditorWebView - 解决闪退问题
import SwiftUI
import WebKit
import AppKit

struct EnhancedVditorWebView: NSViewRepresentable {
    var markdown: String
    var nodeId: String
    var onChange: (String) -> Void
    
    @Binding var coordinatorBinding: Coordinator?
    @Environment(\.colorScheme) private var colorScheme
    
    // 稳定性控制
    @State private var isInitialized = false
    @State private var pendingContent: String?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, nodeId: nodeId)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let uc = WKUserContentController()
        uc.add(context.coordinator, name: "bridge")
        config.userContentController = uc
        config.suppressesIncrementalRendering = false
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        // 允许访问本地文件
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        // macOS透明设置
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.setValue(false, forKey: "opaque")
        
        // 设置外观
        let isDark = (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        webView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        
        // 加载HTML
        loadHTMLContent(webView: webView, context: context)
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // 增强的内容更新逻辑
        guard context.coordinator.isReady else {
            // WebView未准备好时，暂存内容
            context.coordinator.pendingMarkdown = markdown
            print("⏳ VditorWebView: WebView未准备好，暂存内容")
            return
        }
        
        // 智能内容保护
        let shouldUpdate = shouldUpdateContent(
            currentContent: context.coordinator.latestMarkdown,
            newContent: markdown,
            coordinator: context.coordinator
        )
        
        if shouldUpdate {
            context.coordinator.setMarkdownSafely(markdown)
            print("✅ VditorWebView: 内容已安全更新")
        } else {
            print("🛡️ VditorWebView: 内容保护 - 跳过更新")
        }
        
        // 主题更新
        context.coordinator.applyThemeIfNeeded(colorScheme: colorScheme)
    }
    
    // MARK: - 私有方法
    
    private func loadHTMLContent(webView: WKWebView, context: Context) {
        guard let baseURL = ExternalDataManager.shared.currentDataPath else {
            let errorHTML = generateErrorHTML()
            webView.loadHTMLString(errorHTML, baseURL: nil)
            return
        }
        
        guard ExternalDataManager.shared.ensureAccess() else {
            let errorHTML = generateAccessErrorHTML()
            webView.loadHTMLString(errorHTML, baseURL: nil)
            return
        }
        
        let html = generateHTML()
        
        // 创建临时HTML文件
        let tempURL = baseURL.appendingPathComponent("temp_enhanced.html")
        do {
            try html.write(to: tempURL, atomically: true, encoding: .utf8)
            webView.loadFileURL(tempURL, allowingReadAccessTo: baseURL)
            
            // 绑定coordinator
            context.coordinator.webView = webView
            context.coordinator.latestMarkdown = markdown
            context.coordinator.nodeId = nodeId
            
            DispatchQueue.main.async {
                coordinatorBinding = context.coordinator
            }
            
        } catch {
            print("❌ 创建HTML文件失败: \(error)")
            let errorHTML = generateWriteErrorHTML()
            webView.loadHTMLString(errorHTML, baseURL: nil)
        }
    }
    
    /// 智能内容更新判断
    private func shouldUpdateContent(
        currentContent: String,
        newContent: String,
        coordinator: Coordinator
    ) -> Bool {
        // 基础检查
        if currentContent == newContent {
            return false
        }
        
        // 检查更新频率限制
        let now = Date()
        if now.timeIntervalSince(coordinator.lastUpdateTime) < 0.2 {
            return false
        }
        
        // 内容长度检查 - 更智能的保护
        let currentLength = currentContent.trimmingCharacters(in: .whitespacesAndNewlines).count
        let newLength = newContent.trimmingCharacters(in: .whitespacesAndNewlines).count
        
        // 防止空内容覆盖有效内容
        if currentLength > 50 && newLength < 10 {
            print("🛡️ 保护: 防止空内容覆盖有效内容")
            return false
        }
        
        // 防止内容大幅缩减（可能是异常）
        if currentLength > 100 && newLength < currentLength * 0.5 {
            print("🛡️ 保护: 防止内容大幅缩减")
            return false
        }
        
        return true
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        var webView: WKWebView?
        var onChange: (String) -> Void
        var nodeId: String
        
        // 状态管理
        var isReady = false
        var latestMarkdown: String = ""
        var pendingMarkdown: String?
        var lastUpdateTime: Date = Date.distantPast
        
        // 主题缓存
        private var lastDarkValue: Bool?
        
        // 稳定性控制
        private let updateQueue = DispatchQueue(label: "vditor.update", qos: .userInitiated)
        private var updateTimer: Timer?
        
        init(onChange: @escaping (String) -> Void, nodeId: String) {
            self.onChange = onChange
            self.nodeId = nodeId
        }
        
        // MARK: - 安全的内容设置
        func setMarkdownSafely(_ text: String) {
            // 取消之前的更新
            updateTimer?.invalidate()
            
            updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                self?.executeMarkdownUpdate(text)
            }
        }
        
        private func executeMarkdownUpdate(_ text: String) {
            lastUpdateTime = Date()
            latestMarkdown = text
            
            let escaped = Self.escapeForJavaScript(text)
            let js = "window.__setMarkdown(`\(escaped)`, false);"
            
            evaluateJS(js) { [weak self] result, error in
                if let error = error {
                    print("❌ Markdown更新失败: \(error)")
                } else {
                    print("✅ Markdown更新成功")
                }
            }
        }
        
        // MARK: - WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "bridge" else { return }
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            
            switch type {
            case "ready":
                handleReady()
            case "change":
                if let value = body["value"] as? String {
                    handleContentChange(value)
                }
            case "save":
                handleSave()
            default:
                break
            }
        }
        
        private func handleReady() {
            print("✅ VditorWebView: 已准备就绪")
            isReady = true
            
            // 应用主题
            applyTheme(force: true)
            
            // 如果有待处理的内容，现在设置
            if let pending = pendingMarkdown {
                setMarkdownSafely(pending)
                pendingMarkdown = nil
            } else {
                setMarkdownSafely(latestMarkdown)
            }
        }
        
        private func handleContentChange(_ value: String) {
            // 防抖处理
            guard Date().timeIntervalSince(lastUpdateTime) > 0.1 else {
                return
            }
            
            latestMarkdown = value
            
            // 异步调用onChange避免状态竞争
            DispatchQueue.main.async { [weak self] in
                self?.onChange(value)
            }
        }
        
        private func handleSave() {
            // 处理保存事件
            print("💾 VditorWebView: 收到保存请求")
        }
        
        // MARK: - 主题管理
        func applyThemeIfNeeded(colorScheme: ColorScheme) {
            let dark = (colorScheme == .dark)
            if lastDarkValue != dark {
                lastDarkValue = dark
                applyTheme(force: true)
            }
        }
        
        private func applyTheme(force: Bool) {
            guard isReady else { return }
            
            let isDark = (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            lastDarkValue = isDark
            
            let js = "window.__applyNativeTheme(\(isDark ? "true" : "false"));"
            evaluateJS(js)
        }
        
        // MARK: - JavaScript执行
        private func evaluateJS(_ js: String, completion: ((Any?, Error?) -> Void)? = nil) {
            guard let webView = webView else {
                completion?(nil, NSError(domain: "WebView", code: -1, userInfo: [NSLocalizedDescriptionKey: "WebView不可用"]))
                return
            }
            
            webView.evaluateJavaScript(js) { result, error in
                if let error = error {
                    print("❌ JavaScript执行失败: \(error)")
                }
                completion?(result, error)
            }
        }
        
        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("✅ VditorWebView: 页面加载完成")
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ VditorWebView: 页面加载失败 - \(error)")
            isReady = false
        }
        
        static func escapeForJavaScript(_ string: String) -> String {
            return string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
    }
    
    // MARK: - HTML生成
    private func generateHTML() -> String {
        // 这里使用与原版相同的HTML模板，但添加了稳定性增强
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <title>Enhanced Vditor</title>
            
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/vditor/dist/index.css">
            <script src="https://cdn.jsdelivr.net/npm/vditor/dist/index.min.js"></script>
            
            <style>
                :root { --bg: transparent; }
                html, body { margin:0; padding:0; background: var(--bg); }
                #vditor { height: 100vh; }
                
                /* 稳定性增强样式 */
                .loading-overlay {
                    position: fixed;
                    top: 0; left: 0; right: 0; bottom: 0;
                    background: rgba(0,0,0,0.1);
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    z-index: 9999;
                    transition: opacity 0.3s ease;
                }
            </style>
        </head>
        <body>
            <div id="vditor"></div>
            
            <script>
            (function(){
                let vditor;
                let isInitializing = false;
                let contentUpdateQueue = [];
                
                // 初始化Vditor
                function initializeVditor() {
                    if (isInitializing) return;
                    isInitializing = true;
                    
                    try {
                        vditor = new Vditor('vditor', {
                            mode: 'ir',
                            theme: 'classic',
                            value: '',
                            width: '100%',
                            height: '100vh',
                            cache: { enable: false },
                            after() {
                                console.log('✅ Enhanced Vditor初始化完成');
                                window.vditor = vditor;
                                
                                // 通知Native已准备就绪
                                try {
                                    window.webkit?.messageHandlers?.bridge?.postMessage({
                                        type: 'ready'
                                    });
                                } catch(e) {
                                    console.error('通知Native失败:', e);
                                }
                                
                                isInitializing = false;
                                
                                // 处理队列中的内容更新
                                processContentQueue();
                            },
                            input(value) {
                                // 防抖处理
                                clearTimeout(window.__inputDebounce);
                                window.__inputDebounce = setTimeout(() => {
                                    try {
                                        window.webkit?.messageHandlers?.bridge?.postMessage({
                                            type: 'change',
                                            value: vditor.getValue()
                                        });
                                    } catch(e) {
                                        console.error('发送内容变化失败:', e);
                                    }
                                }, 100);
                            }
                        });
                    } catch(error) {
                        console.error('Vditor初始化失败:', error);
                        isInitializing = false;
                    }
                }
                
                // 处理内容更新队列
                function processContentQueue() {
                    while (contentUpdateQueue.length > 0) {
                        const update = contentUpdateQueue.shift();
                        setMarkdownInternal(update.text, update.force);
                    }
                }
                
                // 安全的Markdown设置
                function setMarkdownInternal(text, force) {
                    if (!vditor || isInitializing) {
                        contentUpdateQueue.push({ text, force });
                        return;
                    }
                    
                    try {
                        const currentValue = vditor.getValue() || '';
                        if (force || currentValue !== text) {
                            vditor.setValue(text);
                            console.log('✅ Markdown内容已更新');
                        }
                    } catch(error) {
                        console.error('设置Markdown失败:', error);
                    }
                }
                
                // 全局方法
                window.__setMarkdown = function(text, force) {
                    setMarkdownInternal(text, force);
                };
                
                window.__applyNativeTheme = function(dark) {
                    if (!vditor) return;
                    
                    try {
                        const ui = dark ? 'dark' : 'classic';
                        const code = dark ? 'github-dark' : 'github';
                        const content = dark ? 'dark' : 'light';
                        
                        if (vditor.setTheme) {
                            vditor.setTheme(ui, code, content);
                        }
                        
                        console.log('✅ 主题已应用:', dark ? '深色' : '浅色');
                    } catch(error) {
                        console.error('应用主题失败:', error);
                    }
                };
                
                // 启动初始化
                initializeVditor();
                
            })();
            </script>
        </body>
        </html>
        """
    }
    
    private func generateErrorHTML() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8" />
            <title>Enhanced Vditor - 错误</title>
            <style>
                body { font-family: -apple-system, sans-serif; text-align: center; padding: 50px; }
                .error { color: #e74c3c; }
            </style>
        </head>
        <body>
            <h1 class="error">需要设置数据存储路径</h1>
            <p>请在设置中选择数据存储文件夹</p>
        </body>
        </html>
        """
    }
    
    private func generateAccessErrorHTML() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8" />
            <title>Enhanced Vditor - 访问错误</title>
            <style>
                body { font-family: -apple-system, sans-serif; text-align: center; padding: 50px; }
                .error { color: #e74c3c; }
            </style>
        </head>
        <body>
            <h1 class="error">访问权限错误</h1>
            <p>无法访问数据存储文件夹，请重新选择</p>
        </body>
        </html>
        """
    }
    
    private func generateWriteErrorHTML() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8" />
            <title>Enhanced Vditor - 写入错误</title>
            <style>
                body { font-family: -apple-system, sans-serif; text-align: center; padding: 50px; }
                .error { color: #e74c3c; }
            </style>
        </head>
        <body>
            <h1 class="error">写入错误</h1>
            <p>无法创建HTML文件</p>
        </body>
        </html>
        """
    }
}