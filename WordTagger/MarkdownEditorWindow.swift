import SwiftUI
import WebKit

// MARK: - Markdown编辑器窗口
struct MarkdownEditorWindow: View {
    @StateObject private var documentState = DocumentState()
    @State private var showingOpenDialog = false
    @State private var showingSaveDialog = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Group {
                    Button("新建") {
                        documentState.newDocument()
                    }
                    .keyboardShortcut("n", modifiers: [.command])
                    
                    Button("打开...") {
                        documentState.openDocument()
                    }
                    .keyboardShortcut("o", modifiers: [.command])
                    
                    Divider()
                    
                    Button("保存") {
                        documentState.saveDocument()
                    }
                    .keyboardShortcut("s", modifiers: [.command])
                    .disabled(!documentState.isModified && documentState.hasFile)
                    
                    Button("另存为...") {
                        documentState.saveDocumentAs()
                    }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
                
                // 文档状态指示
                HStack {
                    if documentState.isModified {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                    }
                    Text(documentState.documentTitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Vditor编辑器
            MarkdownVditorWebView(
                markdown: documentState.content,
                onChange: { newContent in
                    documentState.updateContent(newContent)
                }
            )
        }
        .navigationTitle(documentState.documentTitle)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("VditorSaveRequested"))) { _ in
            documentState.saveDocument()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("VditorExportRequested"))) { notification in
            handleExportRequest(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("VditorImageUpload"))) { notification in
            handleImageUpload(notification)
        }
        .onAppear {
            // 设置窗口关闭时的处理
            setupWindowCloseHandler()
        }
    }
    
    private func handleExportRequest(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let format = userInfo["format"] as? String,
              let _ = userInfo["content"] as? String else { return }
        
        let savePanel = NSSavePanel()
        
        switch format {
        case "html":
            savePanel.allowedContentTypes = [.html]
            savePanel.nameFieldStringValue = "导出.html"
        case "pdf":
            savePanel.allowedContentTypes = [.pdf]
            savePanel.nameFieldStringValue = "导出.pdf"
        default:
            return
        }
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            // TODO: 实现具体的导出逻辑
            print("📄 导出\(format)到: \(url)")
        }
    }
    
    private func handleImageUpload(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let imageData = userInfo["data"] as? Data,
              let filename = userInfo["filename"] as? String else { return }
        
        if let relativePath = documentState.handleImageDrop(imageData: imageData, filename: filename) {
            // 在编辑器中插入图片链接
            let imageMarkdown = "![\(filename)](\(relativePath))"
            
            // 通过JavaScript插入图片链接
            NotificationCenter.default.post(
                name: NSNotification.Name("InsertImageMarkdown"),
                object: nil,
                userInfo: ["markdown": imageMarkdown]
            )
            
            print("🖼️ 图片已保存并插入: \(relativePath)")
        } else {
            print("❌ 图片上传失败，请先保存文档")
        }
    }
    
    private func setupWindowCloseHandler() {
        // 监听窗口关闭事件
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow,
               window.contentViewController?.view.superview != nil {
                // 检查未保存的更改
                if !documentState.checkForUnsavedChanges() {
                    // 用户取消关闭
                    // TODO: 阻止窗口关闭（需要在windowShouldClose中处理）
                }
            }
        }
    }
}

// MARK: - Vditor WebView (更新增强版本)
struct MarkdownVditorWebView: NSViewRepresentable {
    var markdown: String
    var onChange: (String) -> Void
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "bridge")
        config.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        
        let html = generateHTML()
        webView.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
        context.coordinator.webView = webView
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        if !markdown.isEmpty {
            context.coordinator.setMarkdown(markdown)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        private let onChange: (String) -> Void
        private var lastSyncedValue: String = ""
        private var isUpdatingFromSwift = false
        
        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
            super.init()
            
            // 监听插入图片链接的通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(insertImageMarkdown(_:)),
                name: NSNotification.Name("InsertImageMarkdown"),
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc private func insertImageMarkdown(_ notification: Notification) {
            guard let userInfo = notification.userInfo,
                  let markdown = userInfo["markdown"] as? String else { return }
            
            let escaped = markdown
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            
            let js = "window.vditor?.insertValue('\(escaped)');"
            webView?.evaluateJavaScript(js)
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let type = dict["type"] as? String else { return }
            
            switch type {
            case "change":
                if !isUpdatingFromSwift,
                   let value = dict["value"] as? String,
                   value != lastSyncedValue {
                    lastSyncedValue = value
                    onChange(value)
                }
            case "ready":
                print("✅ Vditor ready")
                // 编辑器准备好后，同步当前值
                if !lastSyncedValue.isEmpty {
                    setMarkdown(lastSyncedValue)
                }
            case "save":
                // 支持 Cmd+S 保存
                NotificationCenter.default.post(name: NSNotification.Name("VditorSaveRequested"), object: nil)
            case "export":
                // 支持导出请求
                if let format = dict["format"] as? String,
                   let content = dict["content"] as? String {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("VditorExportRequested"), 
                        object: nil,
                        userInfo: ["format": format, "content": content]
                    )
                }
            case "image":
                // 处理图片上传
                if let filename = dict["filename"] as? String,
                   let dataString = dict["data"] as? String,
                   let data = Data(base64Encoded: dataString) {
                    handleImageUpload(data: data, filename: filename)
                }
            default:
                break
            }
        }
        
        func setMarkdown(_ markdown: String) {
            guard markdown != lastSyncedValue else { return }
            
            isUpdatingFromSwift = true
            lastSyncedValue = markdown
            
            let escaped = markdown
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            let js = "window.vditor?.setValue(\"\(escaped)\");"
            webView?.evaluateJavaScript(js) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.isUpdatingFromSwift = false
                }
            }
        }
        
        private func handleImageUpload(data: Data, filename: String) {
            // TODO: 通过NotificationCenter通知主窗口处理图片上传
            NotificationCenter.default.post(
                name: NSNotification.Name("VditorImageUpload"),
                object: nil,
                userInfo: ["data": data, "filename": filename]
            )
        }
    }
    
    private func generateHTML() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <link rel="stylesheet" href="Resources/vditor/index.css">
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    background: transparent;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif;
                }
                #vditor {
                    height: 100vh;
                }
                /* 适配系统主题 */
                @media (prefers-color-scheme: dark) {
                    .vditor {
                        --panel-background-color: #1e1e1e;
                        --textarea-background-color: #1e1e1e;
                        --toolbar-background-color: #2d2d2d;
                        --border-color: #444;
                        --text-color: #d4d4d4;
                    }
                }
            </style>
        </head>
        <body>
            <div id="vditor"></div>
            
            <script src="Resources/vditor/index.min.js"></script>
            <script>
                let vditor;
                
                // 检测主题
                const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
                
                // 初始化 Vditor (IR 模式 = 即时渲染)
                vditor = new Vditor('vditor', {
                    mode: 'ir', // 关键：即时渲染模式，类似 Typora
                    theme: isDark ? 'dark' : 'classic',
                    value: '',
                    width: '100%',
                    height: '100vh',
                    cache: { enable: false },
                    preview: {
                        theme: {
                            current: isDark ? 'dark' : 'light'
                        },
                        // 安全配置：启用内容清理
                        hljs: { enable: true, style: isDark ? 'github-dark' : 'github' },
                        math: { engine: 'KaTeX' },
                        mermaid: { 
                            theme: isDark ? 'dark' : 'default',
                            securityLevel: 'strict',
                            startOnLoad: false,
                            maxTextSize: 50000,
                            // 渲染节流配置
                            flowchart: { useMaxWidth: false }
                        }
                    },
                    // HTML 安全清理
                    options: {
                        sanitize: true
                    },
                    upload: {
                        accept: 'image/*',
                        handler(files) {
                            // 处理图片上传
                            const file = files[0];
                            if (!file) return;
                            
                            const reader = new FileReader();
                            reader.onload = (e) => {
                                const base64Data = e.target.result.split(',')[1];
                                window.webkit?.messageHandlers?.bridge?.postMessage({
                                    type: 'image',
                                    filename: file.name,
                                    data: base64Data
                                });
                            };
                            reader.readAsDataURL(file);
                            return null; // 阻止默认上传
                        }
                    },
                    toolbar: [
                        'emoji', 'headings', 'bold', 'italic', 'strike', 'link', '|',
                        'list', 'ordered-list', 'check', 'outdent', 'indent', '|',
                        'quote', 'line', 'code', 'inline-code', 'insert-before', 'insert-after', '|',
                        'upload', 'table', '|',
                        'undo', 'redo', '|',
                        'fullscreen', 'edit-mode', 'both', 'preview', 'outline', 'code-theme'
                    ],
                    after() {
                        // 编辑器初始化完成
                        window.webkit?.messageHandlers?.bridge?.postMessage({
                            type: 'ready'
                        });
                        
                        // 添加键盘快捷键
                        document.addEventListener('keydown', (e) => {
                            if (e.metaKey || e.ctrlKey) {
                                switch(e.key) {
                                    case 's':
                                        e.preventDefault();
                                        window.webkit?.messageHandlers?.bridge?.postMessage({
                                            type: 'save'
                                        });
                                        break;
                                }
                            }
                        });
                    },
                    input(value) {
                        // 内容变化回调 - 添加防抖以提高性能
                        clearTimeout(window.inputTimeout);
                        window.inputTimeout = setTimeout(() => {
                            window.webkit?.messageHandlers?.bridge?.postMessage({
                                type: 'change',
                                value: value
                            });
                        }, 300); // 300ms 防抖
                    }
                });
                
                // 暴露到全局，供 Swift 调用
                window.vditor = vditor;
                
                // 主题切换监听
                window.matchMedia('(prefers-color-scheme: dark)').addListener((e) => {
                    if (vditor) {
                        vditor.setTheme(e.matches ? 'dark' : 'classic');
                    }
                });
            </script>
        </body>
        </html>
        """
    }
}

#Preview {
    MarkdownEditorWindow()
        .frame(width: 1000, height: 700)
}