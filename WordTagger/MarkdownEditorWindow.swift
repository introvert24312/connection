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
                
                /* === Stop full-page overlay from Mermaid SVG === */
                #content, .mermaid, .mmd-block { position: relative !important; z-index: auto !important; }

                .mermaid > svg {
                  position: relative !important;
                  left: auto !important; right: auto !important; top: auto !important; bottom: auto !important;
                  display: block !important;
                  width: 100% !important;
                  height: auto !important;
                  max-width: none !important;
                  min-width: 800px !important;
                  min-height: 600px !important;
                }
                
                #vditor {
                    height: 100vh;
                    border: none !important;
                }
                
                /* 全局移除所有Vditor相关边框 */
                .vditor, .vditor * {
                    border: none !important;
                    outline: none !important;
                    box-shadow: none !important;
                }
                
                /* Github官方浅色主题 */
                .vditor {
                    --panel-background-color: transparent;
                    --textarea-background-color: transparent;
                    --toolbar-background-color: #f6f8fa;
                    --border-color: transparent;
                    --text-color: #24292f !important;
                    --second-color: #24292f !important;
                    --count-color: #24292f !important;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Helvetica Neue', Arial, sans-serif;
                    border: none !important;
                }
                
                /* 浅色模式强制设置 */
                @media (prefers-color-scheme: light) {
                    .vditor .vditor-ir {
                        color: #24292f !important;
                    }
                    
                    .vditor .vditor-ir * {
                        color: #24292f !important;
                    }
                }
                
                /* Github官方工具栏 - 移除边框 */
                .vditor-toolbar {
                    border: none !important;
                    background-color: #f6f8fa !important;
                    padding: 8px 16px !important;
                }
                
                /* Github官方编辑区域 - 透明背景 */
                .vditor-ir {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Helvetica Neue', Arial, sans-serif !important;
                    font-size: 18px !important;
                    line-height: 1.7 !important;
                    color: #24292f !important;
                    background-color: transparent !important;
                }
                
                /* 浅色主题字体大小设置 */
                @media (prefers-color-scheme: light) {
                    .vditor-ir *, .vditor-ir p, .vditor-ir div, .vditor-ir span {
                        font-size: 18px !important;
                        color: #24292f !important;
                    }
                    
                    /* 浅色主题标题字体大小 */
                    .vditor-ir h1 {
                        font-size: 32px !important;
                        font-weight: 700 !important;
                        color: #24292f !important;
                    }
                    
                    .vditor-ir h2 {
                        font-size: 28px !important;
                        font-weight: 600 !important;
                        color: #24292f !important;
                    }
                    
                    .vditor-ir h3 {
                        font-size: 24px !important;
                        font-weight: 600 !important;
                        color: #24292f !important;
                    }
                    
                    .vditor-ir h4, .vditor-ir h5, .vditor-ir h6 {
                        font-size: 20px !important;
                        font-weight: 600 !important;
                        color: #24292f !important;
                    }
                    
                    /* 浅色主题 - Mermaid节点强制放大 - 超高优先级 */
                    html body div .vditor-ir .mermaid svg rect,
                    html body div .vditor-ir .mermaid svg circle,
                    html body div .vditor-ir .mermaid svg ellipse,
                    html body div .vditor-ir .mermaid svg polygon,
                    html body div .vditor-ir .mermaid rect,
                    html body div .vditor-ir .mermaid circle,
                    html body div .vditor-ir .mermaid ellipse,
                    html body div .vditor-ir .mermaid polygon,
                    html body div .mermaid svg rect,
                    html body div .mermaid svg circle,
                    html body div .mermaid svg ellipse,
                    html body div .mermaid svg polygon,
                    html body div .mermaid rect,
                    html body div .mermaid circle,
                    html body div .mermaid ellipse,
                    html body div .mermaid polygon,
                    html body .mermaid svg rect,
                    html body .mermaid svg circle,
                    html body .mermaid svg ellipse,
                    html body .mermaid svg polygon,
                    html body .mermaid rect,
                    html body .mermaid circle,
                    html body .mermaid ellipse,
                    html body .mermaid polygon {
                        transform: scale(1.4) !important;
                        transform-origin: center !important;
                        stroke-width: 4px !important;
                        stroke: #333 !important;
                    }
                    
                    html body div .vditor-ir .mermaid,
                    html body div .mermaid,
                    html body .mermaid {
                        transform: scale(1.5) !important;
                        transform-origin: center !important;
                        min-width: 800px !important;
                        min-height: 600px !important;
                        margin: 40px auto !important;
                        padding: 50px !important;
                    }
                }
                
                /* Blackout暗色主题 - 使用指定CSS */
                @media (prefers-color-scheme: dark) {
                    /* 根CSS变量 */
                    :root {
                        --of-theme-color: #ff9100;
                        --of-theme-color-dark: #4b4b46;
                        --of-darkest-color: #2d2d2d;
                        --of-darker-color: #1e1e1e;
                        --of-dark-color: #292929;
                        --of-dark-color2: #202020;
                        --of-dark-color3: #404040;
                        --of-dark-color4: #232323;
                        --of-dark-color5: #222222;
                        --of-dark-color6: #1b1b1b;
                        --of-strong: white;
                        --of-strong-code: #00ffa6;
                        --of-font-size: 15px;
                        --of-selection: #4a89dc;
                        --of-selection-text: white;
                        --of-text-color: #c6c5b8;
                        --bg-color: var(--of-darker-color);
                        --text-color: var(--of-text-color);
                        --text-color-main: var(--of-text-color);
                    }
                    
                    .vditor {
                        --panel-background-color: var(--of-darker-color);
                        --textarea-background-color: var(--of-darker-color);
                        --toolbar-background-color: var(--of-darkest-color);
                        --border-color: transparent;
                        --text-color: var(--of-text-color);
                        --second-color: var(--of-text-color);
                        --count-color: var(--of-text-color);
                        border: none !important;
                        color: var(--of-text-color);
                        background: var(--of-darker-color);
                    }
                    
                    .vditor-toolbar {
                        border: none !important;
                        background-color: var(--of-darkest-color) !important;
                        color: var(--of-text-color);
                    }
                    
                    .vditor-ir {
                        color: var(--of-text-color) !important;
                        background-color: transparent !important;
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Helvetica Neue', Arial, sans-serif;
                        line-height: 1.7;
                    }
                    
                    /* 暗色主题文字样式 */
                    .vditor-ir *,
                    .vditor-ir p,
                    .vditor-ir div:not(.mermaid):not([class*="mermaid"]), 
                    .vditor-ir span:not(.mermaid *),
                    .vditor-ir li,
                    .vditor-ir blockquote,
                    .vditor-ir code:not(.mermaid *),
                    .vditor-ir pre,
                    .vditor-ir table,
                    .vditor-ir td,
                    .vditor-ir th {
                        color: var(--of-text-color) !important;
                    }
                    
                    /* 标题样式 */
                    .vditor-ir h1,
                    .vditor-ir h2,
                    .vditor-ir h3,
                    .vditor-ir h4,
                    .vditor-ir h5,
                    .vditor-ir h6 {
                        color: var(--of-strong) !important;
                        font-weight: bold;
                    }
                    
                    .vditor-ir h1 {
                        font-size: 2.5rem !important;
                        border-bottom: 1px solid #383838;
                    }
                    
                    .vditor-ir h2 {
                        font-size: 1.63rem !important;
                    }
                    
                    .vditor-ir h3 {
                        font-size: 1.6rem !important;
                    }
                    
                    .vditor-ir h4 {
                        font-size: 1.12rem !important;
                    }
                    
                    .vditor-ir h5 {
                        font-size: 0.97rem !important;
                    }
                    
                    .vditor-ir h6 {
                        font-size: 0.93rem !important;
                        color: #d3d3d3 !important;
                    }
                    
                    /* 强调文字 */
                    .vditor-ir strong,
                    .vditor-ir b {
                        color: var(--of-strong) !important;
                    }
                    
                    /* 代码样式 */
                    .vditor-ir code {
                        background: rgba(255, 255, 255, 0.05) !important;
                        color: var(--of-strong-code) !important;
                        border-radius: 0.2rem;
                    }
                    
                    /* 引用样式 */
                    .vditor-ir blockquote {
                        border: 1px solid var(--of-theme-color);
                        background-color: var(--of-dark-color);
                        border-radius: 8px;
                        padding: 20px;
                        color: white !important;
                    }
                    
                    /* 链接样式 */
                    .vditor-ir a {
                        color: var(--of-theme-color) !important;
                        text-decoration: underline;
                    }
                    
                    .vditor-ir a:hover {
                        color: white !important;
                    }
                    
                    /* Mermaid图表暗色主题强制覆盖 - 使用最高优先级 */
                    
                    /* 1. Mermaid容器整体背景和尺寸 - 超级强制 */
                    .vditor-ir .mermaid,
                    .vditor-ir .mermaid > svg,
                    .vditor-ir div[data-processed-by="mermaid"],
                    div.mermaid,
                    .mermaid {
                        background: var(--of-darker-color) !important;
                        background-color: var(--of-darker-color) !important;
                        border-radius: 12px !important;
                        padding: 50px !important;
                        margin: 40px 0 !important;
                        width: 100% !important;
                        min-width: 800px !important;
                        min-height: 600px !important;
                        height: auto !important;
                        max-width: none !important;
                        display: block !important;
                        overflow: visible !important;
                        transform: scale(1.5) !important;
                        transform-origin: center !important;
                    }
                    
                    /* 1.1 SVG内部容器尺寸强制放大 */
                    .vditor-ir .mermaid svg,
                    .mermaid svg {
                        width: 100% !important;
                        height: auto !important;
                        min-width: 800px !important;
                        min-height: 600px !important;
                        background: var(--of-darker-color) !important;
                        background-color: var(--of-darker-color) !important;
                        transform: scale(1.2) !important;
                    }
                }
                
                /* === 终极强制覆盖规则 - 最高优先级 === */
                
                /* 浅色模式：超高优先级强制放大 */
                html body div.vditor div.vditor-ir div.mermaid svg rect,
                html body div.vditor div.vditor-ir div.mermaid svg circle,
                html body div.vditor div.vditor-ir div.mermaid svg ellipse,
                html body div.vditor div.vditor-ir div.mermaid svg polygon,
                html body div.vditor div.vditor-ir div.mermaid rect[style],
                html body div.vditor div.vditor-ir div.mermaid circle[style],
                html body div.vditor div.vditor-ir div.mermaid ellipse[style],
                html body div.vditor div.vditor-ir div.mermaid polygon[style] {
                    transform: scale(1.6) !important;
                    transform-origin: center !important;
                    stroke-width: 4px !important;
                    stroke: #333333 !important;
                }
                
                /* 浅色模式：整体容器强制放大 */
                html body div.vditor div.vditor-ir div.mermaid {
                    transform: scale(1.8) !important;
                    transform-origin: center !important;
                    min-width: 900px !important;
                    min-height: 700px !important;
                    padding: 60px !important;
                    margin: 50px auto !important;
                }
                
                /* 暗色模式：超高优先级强制颜色 */
                @media (prefers-color-scheme: dark) {
                    html body div.vditor div.vditor-ir div.mermaid svg rect[style],
                    html body div.vditor div.vditor-ir div.mermaid svg circle[style],
                    html body div.vditor div.vditor-ir div.mermaid svg ellipse[style],
                    html body div.vditor div.vditor-ir div.mermaid svg polygon[style],
                    html body div.vditor div.vditor-ir div.mermaid rect,
                    html body div.vditor div.vditor-ir div.mermaid circle,
                    html body div.vditor div.vditor-ir div.mermaid ellipse,
                    html body div.vditor div.vditor-ir div.mermaid polygon {
                        fill: #292929 !important;
                        stroke: #ff9100 !important;
                        stroke-width: 3px !important;
                        transform: scale(1.4) !important;
                        transform-origin: center !important;
                    }
                    
                    html body div.vditor div.vditor-ir div.mermaid svg text[style],
                    html body div.vditor div.vditor-ir div.mermaid text {
                        fill: #c6c5b8 !important;
                        color: #c6c5b8 !important;
                        font-size: 16px !important;
                        font-weight: 600 !important;
                    }
                }
                
                /* SVG容器最高优先级覆盖 */
                html body div.vditor div.vditor-ir div.mermaid > svg {
                    width: 100% !important;
                    height: auto !important;
                    max-width: none !important;
                    min-width: 800px !important;
                    min-height: 600px !important;
                    transform: scale(1.2) !important;
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
                    // 添加Mermaid渲染完成回调
                    after() {
                        // 编辑器初始化完成
                        window.webkit?.messageHandlers?.bridge?.postMessage({
                            type: 'ready'
                        });
                        
                        // 立即强制应用Mermaid样式
                        setTimeout(bruteForceMermaidFix, 100);
                        setTimeout(bruteForceMermaidFix, 500);
                        setTimeout(bruteForceMermaidFix, 1000);
                        
                        // 初始化mermaid主题配置
                        if (window.mermaid && window.mermaid.initialize) {
                            const currentTheme = window.matchMedia('(prefers-color-scheme: dark)').matches;
                            console.log('🎨 初始化mermaid主题配置，当前主题:', currentTheme ? '深色' : '浅色');
                            
                            window.mermaid.initialize({
                                startOnLoad: false,
                                theme: currentTheme ? 'dark' : 'default',
                                securityLevel: 'strict',
                                themeVariables: currentTheme ? {
                                    primaryColor: '#292929',
                                    primaryTextColor: '#c6c5b8',
                                    primaryBorderColor: '#ff9100',
                                    lineColor: '#ff9100'
                                } : {
                                    primaryColor: '#ffffff',
                                    primaryTextColor: '#333333',
                                    primaryBorderColor: '#333333'
                                }
                            });
                        }
                        
                        // 监听所有可能的Mermaid渲染事件
                        const observer = new MutationObserver((mutations) => {
                            let hasMermaid = false;
                            mutations.forEach((mutation) => {
                                if (mutation.addedNodes) {
                                    mutation.addedNodes.forEach((node) => {
                                        if (node.nodeType === 1) {
                                            if (node.classList?.contains('mermaid') || 
                                                node.querySelector?.('.mermaid') ||
                                                node.tagName === 'svg') {
                                                hasMermaid = true;
                                            }
                                        }
                                    });
                                }
                            });
                            if (hasMermaid) {
                                setTimeout(bruteForceMermaidFix, 10);
                            }
                        });
                        observer.observe(document.body, { childList: true, subtree: true });
                        
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
                            flowchart: { 
                                useMaxWidth: false,
                                htmlLabels: true,
                                curve: 'basis'
                            },
                            // 强制应用blackout主题色彩
                            themeVariables: isDark ? {
                                primaryColor: '#292929',
                                primaryTextColor: '#c6c5b8', 
                                primaryBorderColor: '#ff9100',
                                lineColor: '#ff9100',
                                secondaryColor: '#1e1e1e',
                                tertiaryColor: '#404040',
                                background: '#1e1e1e',
                                mainBkg: '#292929',
                                secondBkg: '#202020',
                                tertiaryBkg: '#404040'
                            } : {
                                primaryColor: '#ffffff',
                                primaryTextColor: '#333333',
                                primaryBorderColor: '#333333',
                                lineColor: '#333333',
                                secondaryColor: '#f0f0f0',
                                tertiaryColor: '#e0e0e0'
                            }
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
                
                // 暴露修复函数到全局，便于手动调试
                window.fixMermaid = bruteForceMermaidFix;
                
                // 暴力修复Mermaid样式函数 - 直接操作DOM - 优化版
                function bruteForceMermaidFix() {
                    const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
                    console.log('🔨🔨🔨 开始暴力修复Mermaid样式 - 优化版');
                    console.log('当前主题模式 - 暗色模式:', isDark);
                    console.log('当前时间:', new Date().toLocaleTimeString());
                    
                    // 清理旧的修复标记，确保重新应用
                    const oldStyledElements = document.querySelectorAll('[data-theme-fixed]');
                    oldStyledElements.forEach(el => el.removeAttribute('data-theme-fixed'));
                    
                    // 更精准地找到Mermaid相关元素
                    const allSvgs = document.querySelectorAll('svg');
                    const mermaidDivs = document.querySelectorAll('.mermaid, [class*="mermaid"], div:has(svg)');
                    const vditorContent = document.querySelectorAll('.vditor-ir, .vditor-content');
                    
                    console.log('找到', allSvgs.length, '个SVG元素,', mermaidDivs.length, '个mermaid容器,', vditorContent.length, '个编辑器内容区');
                    
                    // 1. 强制修复所有SVG容器尺寸
                    allSvgs.forEach((svg, index) => {
                        // 检查是否是Mermaid SVG（通过父元素或内容判断）
                        const parent = svg.closest('.mermaid') || svg.parentElement;
                        const isMermaidSvg = parent && (
                            parent.classList.contains('mermaid') ||
                            svg.querySelector('g[class*="node"]') ||
                            svg.querySelector('rect[class*="rect"]') ||
                            svg.querySelector('text[class*="label"]')
                        );
                        
                        if (isMermaidSvg) {
                            console.log('修复SVG #' + index);
                            // 强制设置SVG尺寸
                            svg.style.setProperty('width', '100%', 'important');
                            svg.style.setProperty('height', 'auto', 'important');
                            svg.style.setProperty('max-width', 'none', 'important');
                            svg.style.setProperty('min-width', '800px', 'important');
                            svg.style.setProperty('min-height', '600px', 'important');
                            svg.style.setProperty('transform', 'scale(1.2)', 'important');
                            svg.style.setProperty('transform-origin', 'center', 'important');
                            svg.setAttribute('data-fixed', 'true');
                        }
                    });
                    
                    // 2. 强制修复所有节点元素 - 改进检测逻辑
                    const allShapes = document.querySelectorAll('rect, circle, ellipse, polygon');
                    console.log('找到', allShapes.length, '个图形元素');
                    
                    allShapes.forEach((shape, index) => {
                        const svg = shape.closest('svg');
                        const isMermaidShape = svg && (
                            // 检查是否在.mermaid容器内
                            shape.closest('.mermaid') ||
                            // 检查SVG是否有Mermaid特征
                            svg.querySelector('g[class*="node"]') ||
                            svg.querySelector('g[class*="cluster"]') ||
                            svg.querySelector('text[class*="label"]') ||
                            svg.querySelector('path[class*="edge"]') ||
                            // 检查shape本身的属性
                            shape.getAttribute('class')?.includes('node') ||
                            shape.getAttribute('class')?.includes('rect') ||
                            shape.getAttribute('class')?.includes('cluster') ||
                            // 检查父元素
                            shape.parentElement?.getAttribute('class')?.includes('node')
                        );
                        
                        if (isMermaidShape) {
                            console.log('发现Mermaid节点 #' + index, '当前fill:', shape.getAttribute('fill'));
                            
                            if (isDark) {
                                // 暗色模式 - 强制设置暗色背景
                                console.log('应用暗色样式到节点 #' + index);
                                shape.style.setProperty('fill', '#292929', 'important');
                                shape.style.setProperty('stroke', '#ff9100', 'important');
                                shape.style.setProperty('stroke-width', '3px', 'important');
                                // 直接修改属性
                                shape.setAttribute('fill', '#292929');
                                shape.setAttribute('stroke', '#ff9100');
                                shape.setAttribute('stroke-width', '3');
                                // 移除可能的内联样式
                                const currentStyle = shape.getAttribute('style') || '';
                                const newStyle = currentStyle
                                    .replace(/fill:[^;]*;?/g, '')
                                    .replace(/stroke:[^;]*;?/g, '') +
                                    ';fill: #292929 !important; stroke: #ff9100 !important; stroke-width: 3px !important;';
                                shape.setAttribute('style', newStyle);
                            } else {
                                // 浅色模式 - 保持原有外观，只加粗边框
                                console.log('应用浅色样式到节点 #' + index);
                                shape.style.setProperty('stroke', '#333333', 'important');
                                shape.style.setProperty('stroke-width', '2px', 'important');
                                shape.setAttribute('stroke', '#333333');
                                shape.setAttribute('stroke-width', '2');
                                // 移除可能的固定尺寸
                                shape.style.removeProperty('width');
                                shape.style.removeProperty('height');
                                shape.removeAttribute('width');
                                shape.removeAttribute('height');
                            }
                            
                            // 节点适度放大，深色模式稍小避免遮挡文字
                            shape.style.setProperty('transform', isDark ? 'scale(1.05)' : 'scale(1.1)', 'important');
                            shape.style.setProperty('transform-origin', 'center', 'important');
                        }
                    });
                    
                    // 3. 强制修复所有文字 - 确保可见且大小合适
                    const allTexts = document.querySelectorAll('text');
                    console.log('找到', allTexts.length, '个文字元素');
                    
                    allTexts.forEach((text, index) => {
                        const svg = text.closest('svg');
                        const isMermaidText = svg && (
                            text.closest('.mermaid') ||
                            svg.querySelector('g[class*="node"]') ||
                            text.getAttribute('class')?.includes('label') ||
                            text.getAttribute('class')?.includes('nodeLabel') ||
                            text.parentElement?.getAttribute('class')?.includes('label')
                        );
                        
                        if (isMermaidText) {
                            console.log('发现Mermaid文字 #' + index, '内容:', text.textContent?.substring(0, 20));
                            
                            if (isDark) {
                                // 暗色模式文字颜色
                                console.log('应用暗色文字样式 #' + index);
                                text.style.setProperty('fill', '#c6c5b8', 'important');
                                text.style.setProperty('color', '#c6c5b8', 'important');
                                text.setAttribute('fill', '#c6c5b8');
                                // 移除可能的内联样式
                                const currentStyle = text.getAttribute('style') || '';
                                const newStyle = currentStyle
                                    .replace(/fill:[^;]*;?/g, '')
                                    .replace(/color:[^;]*;?/g, '') +
                                    ';fill: #c6c5b8 !important; color: #c6c5b8 !important;';
                                text.setAttribute('style', newStyle);
                            }
                            
                            // 确保文字大小合适，不会被节点遮挡
                            text.style.setProperty('font-size', '18px', 'important');
                            text.style.setProperty('font-weight', '600', 'important');
                            text.style.setProperty('font-family', '-apple-system, sans-serif', 'important');
                            // 确保文字在节点上方
                            text.style.setProperty('z-index', '100', 'important');
                            text.style.setProperty('pointer-events', 'none', 'important');
                        }
                    });
                    
                    // 4. 强制修复容器 - 自适应大小
                    mermaidDivs.forEach((div, index) => {
                        console.log('修复容器 #' + index);
                        if (isDark) {
                            div.style.setProperty('background', '#1e1e1e', 'important');
                            div.style.setProperty('background-color', '#1e1e1e', 'important');
                            // 暗色模式适度放大
                            div.style.setProperty('transform', 'scale(1.2)', 'important');
                        } else {
                            // 浅色模式保持自然大小，只加边距
                            div.style.setProperty('transform', 'scale(1.1)', 'important');
                        }
                        div.style.setProperty('transform-origin', 'center', 'important');
                        
                        // 移除固定尺寸，改为自适应
                        div.style.removeProperty('min-width');
                        div.style.removeProperty('min-height');
                        div.style.removeProperty('width');
                        div.style.removeProperty('height');
                        
                        // 只设置合理的padding和margin
                        div.style.setProperty('padding', '20px', 'important');
                        div.style.setProperty('margin', '20px auto', 'important');
                        div.style.setProperty('border-radius', '8px', 'important');
                        div.style.setProperty('overflow', 'visible', 'important');
                        div.style.setProperty('display', 'block', 'important');
                    });
                    
                    // 5. 超级暴力修复 - 如果是深色模式，强制修改所有符合条件的元素
                    if (isDark) {
                        console.log('🌙 启动深色模式超级暴力修复');
                        
                        // 强制修改所有rect元素
                        const allRects = document.querySelectorAll('rect');
                        console.log('找到所有rect:', allRects.length);
                        allRects.forEach((rect, i) => {
                            if (rect.closest('svg')) {
                                console.log('强制修复rect #' + i, '原fill:', rect.getAttribute('fill'));
                                rect.setAttribute('fill', '#292929');
                                rect.setAttribute('stroke', '#ff9100');
                                rect.style.fill = '#292929';
                                rect.style.stroke = '#ff9100';
                                rect.style.setProperty('fill', '#292929', 'important');
                                rect.style.setProperty('stroke', '#ff9100', 'important');
                            }
                        });
                        
                        // 强制修改所有circle元素
                        const allCircles = document.querySelectorAll('circle');
                        console.log('找到所有circle:', allCircles.length);
                        allCircles.forEach((circle, i) => {
                            if (circle.closest('svg')) {
                                console.log('强制修复circle #' + i);
                                circle.setAttribute('fill', '#292929');
                                circle.setAttribute('stroke', '#ff9100');
                                circle.style.fill = '#292929';
                                circle.style.stroke = '#ff9100';
                                circle.style.setProperty('fill', '#292929', 'important');
                                circle.style.setProperty('stroke', '#ff9100', 'important');
                            }
                        });
                        
                        // 强制修改所有polygon元素
                        const allPolygons = document.querySelectorAll('polygon');
                        console.log('找到所有polygon:', allPolygons.length);
                        allPolygons.forEach((polygon, i) => {
                            if (polygon.closest('svg')) {
                                console.log('强制修复polygon #' + i);
                                polygon.setAttribute('fill', '#292929');
                                polygon.setAttribute('stroke', '#ff9100');
                                polygon.style.fill = '#292929';
                                polygon.style.stroke = '#ff9100';
                                polygon.style.setProperty('fill', '#292929', 'important');
                                polygon.style.setProperty('stroke', '#ff9100', 'important');
                            }
                        });
                        
                        // 强制修改所有text元素为浅色
                        const allTextElements = document.querySelectorAll('text');
                        console.log('找到所有text:', allTextElements.length);
                        allTextElements.forEach((textEl, i) => {
                            if (textEl.closest('svg')) {
                                console.log('强制修复text #' + i, '内容:', textEl.textContent?.substring(0, 10));
                                textEl.setAttribute('fill', '#c6c5b8');
                                textEl.style.fill = '#c6c5b8';
                                textEl.style.color = '#c6c5b8';
                                textEl.style.setProperty('fill', '#c6c5b8', 'important');
                                textEl.style.setProperty('color', '#c6c5b8', 'important');
                                // 标记已修复
                                textEl.setAttribute('data-theme-fixed', isDark ? 'dark' : 'light');
                            }
                        });
                        
                        console.log('🌙 深色模式超级暴力修复完成');
                    }
                    
                    // 标记所有修复过的元素
                    const allMermaidElements = document.querySelectorAll('.mermaid');
                    allMermaidElements.forEach(elem => {
                        elem.setAttribute('data-theme-fixed', isDark ? 'dark' : 'light');
                    });
                    
                    console.log('🔨 暴力修复完成 - 当前主题标记:', isDark ? 'dark' : 'light');
                }
                
                // 主题切换监听 - 使用现代API修复版
                const themeMediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
                
                function handleThemeChange(e) {
                    const isDark = e.matches;
                    console.log('🎨 主题切换检测:', isDark ? '切换到深色模式' : '切换到浅色模式');
                    console.log('🕐 切换时间:', new Date().toLocaleTimeString());
                    
                    if (vditor) {
                        // 1. 立即切换编辑器主题
                        console.log('🔄 切换vditor主题到:', isDark ? 'dark' : 'classic');
                        vditor.setTheme(isDark ? 'dark' : 'classic');
                        
                        // 2. 完全重新初始化mermaid配置
                        if (window.mermaid) {
                            console.log('🔄 完全重新初始化mermaid配置');
                            
                            // 先清除旧配置
                            window.mermaid.initialize({
                                startOnLoad: false,
                                theme: isDark ? 'dark' : 'default',
                                securityLevel: 'strict',
                                fontFamily: '-apple-system, sans-serif',
                                themeVariables: isDark ? {
                                    primaryColor: '#292929',
                                    primaryTextColor: '#c6c5b8',
                                    primaryBorderColor: '#ff9100',
                                    lineColor: '#ff9100',
                                    background: '#1e1e1e',
                                    mainBkg: '#292929',
                                    secondBkg: '#202020',
                                    tertiaryBkg: '#404040'
                                } : {
                                    primaryColor: '#ffffff',
                                    primaryTextColor: '#333333',
                                    primaryBorderColor: '#333333',
                                    lineColor: '#333333',
                                    background: '#ffffff',
                                    mainBkg: '#ffffff',
                                    secondBkg: '#f0f0f0'
                                }
                            });
                        }
                        
                        // 3. 强制清除所有现有的Mermaid渲染状态
                        setTimeout(() => {
                            console.log('🧹 清除所有Mermaid渲染状态');
                            const mermaidElements = document.querySelectorAll('.mermaid, [data-processed-by="mermaid"]');
                            console.log('找到', mermaidElements.length, '个需要重置的mermaid元素');
                            
                            mermaidElements.forEach((element, index) => {
                                console.log('重置元素 #' + index);
                                
                                // 获取或保存原始Mermaid代码
                                let originalContent = element.getAttribute('data-original-mermaid') || 
                                                    element.textContent ||
                                    element.innerHTML.replace(/<[^>]*>/g, '').trim();
                                
                                // 如果没有保存过原始内容，现在保存
                                if (!element.getAttribute('data-original-mermaid') && originalContent) {
                                    element.setAttribute('data-original-mermaid', originalContent);
                                    console.log('保存原始内容 #' + index + ':', originalContent.substring(0, 50));
                                }
                                
                                // 完全重置元素状态
                                element.innerHTML = originalContent;
                                element.removeAttribute('data-processed');
                                element.removeAttribute('data-processed-by');
                                element.classList.remove('mermaid');
                                element.classList.remove('rendered');
                                
                                // 重新添加mermaid类
                                setTimeout(() => {
                                    element.classList.add('mermaid');
                                    console.log('重新添加mermaid类到元素 #' + index);
                                }, 10);
                            });
                        }, 50);
                        
                        // 4. 延迟触发完全重新渲染
                        setTimeout(() => {
                            console.log('🔄 触发vditor完全重新渲染');
                            
                            // 强制vditor重新解析和渲染所有内容
                            if (vditor && vditor.preview) {
                                try {
                                    // 方法1：重新设置内容触发渲染
                                    const currentValue = vditor.getValue();
                                    if (currentValue) {
                                        // 触发完全重新渲染
                                        vditor.setValue(currentValue);
                                    }
                                    
                                    // 方法2：手动触发预览渲染
                                    if (vditor.preview.render) {
                                        vditor.preview.render();
                                    }
                                } catch (err) {
                                    console.log('vditor重新渲染出错:', err);
                                }
                            }
                            
                            // 额外的手动mermaid初始化
                            if (window.mermaid && window.mermaid.init) {
                                setTimeout(() => {
                                    console.log('🔄 手动初始化mermaid图表');
                                    try {
                                        const mermaidElems = document.querySelectorAll('.mermaid:not([data-processed])');
                                        console.log('找到未处理的mermaid元素:', mermaidElems.length);
                                        if (mermaidElems.length > 0) {
                                            window.mermaid.init(undefined, mermaidElems);
                                        }
                                    } catch (err) {
                                        console.log('手动mermaid初始化失败:', err);
                                    }
                                }, 200);
                            }
                        }, 150);
                        
                        // 5. 多轮暴力样式修复
                        const fixTimings = [100, 300, 600, 1000, 1500, 2500];
                        fixTimings.forEach((delay, index) => {
                            setTimeout(() => {
                                console.log('第' + (index + 1) + '轮暴力修复');
                                bruteForceMermaidFix();
                            }, delay);
                        });
                        
                        // 6. 最终验证和修复
                        setTimeout(() => {
                            console.log('🏁 最终验证主题切换结果');
                            const mermaidElements = document.querySelectorAll('.mermaid');
                            console.log('最终检查：找到', mermaidElements.length, '个mermaid元素');
                            
                            let needsFix = false;
                            if (isDark) {
                                // 检查深色模式是否正确应用
                                const darkNodes = document.querySelectorAll('.mermaid rect[fill="#292929"], .mermaid circle[fill="#292929"]');
                                const lightNodes = document.querySelectorAll('.mermaid rect[fill="#ffffff"], .mermaid rect[fill="white"], .mermaid circle[fill="#ffffff"], .mermaid circle[fill="white"]');
                                console.log('深色节点数:', darkNodes.length, '浅色节点数:', lightNodes.length);
                                if (lightNodes.length > 0) needsFix = true;
                            } else {
                                // 检查浅色模式
                                const scaledElements = document.querySelectorAll('.mermaid[style*="scale(1.8)"]');
                                console.log('已放大的浅色元素数:', scaledElements.length);
                                if (scaledElements.length !== mermaidElements.length) needsFix = true;
                            }
                            
                            if (needsFix) {
                                console.log('⚠️ 检测到主题未完全切换，执行最终修复');
                                bruteForceMermaidFix();
                            } else {
                                console.log('✅ 主题切换验证通过');
                            }
                        }, 3000);
                    }
                }
                
                // 使用现代API添加监听器
                themeMediaQuery.addEventListener('change', handleThemeChange);
                
                // 强制Mermaid主题函数
                function forceMermaidTheme() {
                    const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
                    
                    // 查找所有Mermaid图表
                    const mermaids = document.querySelectorAll('.mermaid');
                    mermaids.forEach(mermaid => {
                        // 添加样式覆盖class
                        mermaid.classList.add('mermaid-override-styles');
                        
                        if (isDark) {
                            // 暗色模式 - 强制所有节点使用暗色背景
                            const shapes = mermaid.querySelectorAll('rect, circle, ellipse, polygon');
                            shapes.forEach(shape => {
                                shape.setAttribute('fill', '#292929');
                                shape.setAttribute('stroke', '#ff9100');
                                shape.setAttribute('stroke-width', '3');
                                shape.style.transform = 'scale(1.4)';
                                shape.style.transformOrigin = 'center';
                            });
                            
                            // 强制文字颜色
                            const texts = mermaid.querySelectorAll('text');
                            texts.forEach(text => {
                                text.setAttribute('fill', '#c6c5b8');
                                text.style.color = '#c6c5b8';
                                text.style.fontSize = '16px';
                                text.style.fontWeight = '600';
                            });
                        } else {
                            // 浅色模式 - 强制节点放大
                            const shapes = mermaid.querySelectorAll('rect, circle, ellipse, polygon');
                            shapes.forEach(shape => {
                                shape.style.transform = 'scale(1.6)';
                                shape.style.transformOrigin = 'center';
                                shape.setAttribute('stroke-width', '4');
                                shape.setAttribute('stroke', '#333');
                            });
                            
                            // 整体放大
                            mermaid.style.transform = 'scale(1.8)';
                            mermaid.style.transformOrigin = 'center';
                            mermaid.style.minWidth = '900px';
                            mermaid.style.minHeight = '700px';
                        }
                    });
                }
                
                // 智能Mermaid样式监视器 - 根据主题变化调整检查频率
                let mermaidStyleTimer;
                let lastTheme = window.matchMedia('(prefers-color-scheme: dark)').matches;
                
                function startMermaidStyleWatcher() {
                    if (mermaidStyleTimer) clearInterval(mermaidStyleTimer);
                    
                    mermaidStyleTimer = setInterval(() => {
                        const currentTheme = window.matchMedia('(prefers-color-scheme: dark)').matches;
                        
                        // 检测主题是否发生变化
                        if (currentTheme !== lastTheme) {
                            console.log('🎨 主题监视器检测到变化:', currentTheme ? '切换到深色' : '切换到浅色');
                            lastTheme = currentTheme;
                            // 主题变化时立即修复
                            setTimeout(bruteForceMermaidFix, 10);
                        }
                        
                        // 检查是否有未修复或主题不匹配的元素
                        const currentThemeKey = currentTheme ? 'dark' : 'light';
                        const wrongThemeElements = document.querySelectorAll('.mermaid:not([data-theme-fixed="' + currentThemeKey + '"])');
                        
                        if (wrongThemeElements.length > 0) {
                            console.log('🔧 监视器发现', wrongThemeElements.length, '个需要修复的Mermaid元素');
                            bruteForceMermaidFix();
                        }
                        
                        // 应用强制主题
                        forceMermaidTheme();
                    }, 2000); // 降低检查频率避免性能问题
                }
                
                // 启动样式监视器
                startMermaidStyleWatcher();
                
                // 疯狂的暴力修复 - 多次尝试确保生效
                setTimeout(bruteForceMermaidFix, 100);
                setTimeout(bruteForceMermaidFix, 300);
                setTimeout(bruteForceMermaidFix, 500);
                setTimeout(bruteForceMermaidFix, 1000);
                setTimeout(bruteForceMermaidFix, 2000);
                setTimeout(bruteForceMermaidFix, 3000);
                
                // 每3秒强制修复一次
                setInterval(bruteForceMermaidFix, 3000);
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