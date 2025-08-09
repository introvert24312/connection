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
    @Environment(\.colorScheme) private var colorScheme
    var markdown: String
    var onChange: (String) -> Void
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "bridge")
        config.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        let appearanceName: NSAppearance.Name = (colorScheme == .dark ? .darkAqua : .aqua)
        if let app = NSAppearance(named: appearanceName) {
            webView.appearance = app
        }
        webView.enclosingScrollView?.drawsBackground = false
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        
        let html = generateHTML()
        webView.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
        context.coordinator.webView = webView
        context.coordinator.setMarkdown(markdown)
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        let appearanceName: NSAppearance.Name = (colorScheme == .dark ? .darkAqua : .aqua)
        if let app = NSAppearance(named: appearanceName) {
            nsView.appearance = app
        }
        let jsTheme = "window.__applyNativeTheme && window.__applyNativeTheme(\(colorScheme == .dark ? "true" : "false"));"
        nsView.evaluateJavaScript(jsTheme, completionHandler: nil)
        context.coordinator.setMarkdown(markdown)
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
                // 先把当前原生外观传给网页，强制应用主题，再同步内容，保证首帧就正确
                let isDark = (webView?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
                webView?.evaluateJavaScript("window.__applyNativeTheme(\(isDark ? "true" : "false"))", completionHandler: nil)
                // 同步当前值（即使是空字符串也要写入，以避免不同步）
                setMarkdown(lastSyncedValue)
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
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <link rel="stylesheet" href="Resources/vditor/index.css" />
          <style>
            /* Clean, responsive base styles for Vditor + Mermaid */
            :root { --bg: transparent; --fg:#1f2328; --muted:#6e7781; --code-bg:#f6f8fa; --code-fg:#1f2328; --s4:16px; }
            @media (prefers-color-scheme: dark){ :root{ --fg:#d4d4d4; --muted:#9aa0a6; --code-bg:#2d2d2d; --code-fg:#d4d4d4; } }
            html,body{ color-scheme:light dark; margin:0; padding:0; background:var(--bg); color:var(--fg); font:14px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif; }
            #vditor{ height:100vh; border:none; }
            .vditor,.vditor *{ border:none; box-shadow:none; }
            .vditor-toolbar{ background:#f6f8fa; padding:8px 16px; }
            @media (prefers-color-scheme: dark){ .vditor-toolbar{ background:#1f1f1f; } }
            .vditor-ir{ background:transparent; font-size:18px; line-height:1.7; }
            pre{ background:var(--code-bg); color:var(--code-fg); border-radius:6px; padding:var(--s4); overflow:auto; }
            code{ background:color-mix(in srgb, var(--code-bg) 90%, transparent); color:var(--code-fg); border-radius:3px; padding:.2em .4em; font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace; }
            /* Mermaid: responsive, non-obtrusive */
            #content,.mermaid,.mmd-block{ position:relative; z-index:auto; }
            .mermaid{ display:block; margin:var(--s4) 0; padding:0; background:transparent; overflow:visible; text-align:center; }
            .mermaid>svg{ display:block; width:100%; max-width:100%; height:auto; block-size:auto; }
            /* Avoid label clipping when htmlLabels=true */
            .mermaid .label foreignObject{ overflow:visible; }
            .mermaid .label foreignObject, .mermaid .label foreignObject>div{ max-width:100%; box-sizing:border-box; }
            .mermaid .label foreignObject>div{
              display:block;
              padding:2px 4px;
              white-space:normal;
              word-break:break-word;
              overflow-wrap:anywhere;
              line-height:1.4;
              font-size:16px;
            }
          </style>
        </head>
        <body>
          <div id="vditor"></div>
          <div style="position:fixed;left:8px;bottom:8px;font:11px -apple-system,BlinkMacSystemFont,'Segoe UI';background:rgba(0,0,0,.5);color:#fff;padding:2px 6px;border-radius:6px;z-index:9999;">VDITOR_WEBVIEW v2</div>
          <!-- Load Mermaid BEFORE Vditor so first render uses our config/fonts -->
          <script src="Resources/mermaid/mermaid.min.js"></script>
          <script src="Resources/vditor/index.min.js"></script>
          <script>
            // ---- Unified Mermaid config ----
            function currentMermaidConfig(){
              const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
              const shared = {
                startOnLoad: false,
                securityLevel: 'loose', // allow htmlLabels/foreignObject
                fontFamily: "-apple-system, 'SF Pro Text', 'Segoe UI', Arial, sans-serif",
                flowchart: { useMaxWidth: true, htmlLabels: true, curve: 'basis', padding: 8, nodeSpacing: 40, rankSpacing: 40 }
              };
              return isDark ? {
                ...shared,
                theme: 'dark',
                themeVariables: {
                  primaryColor: '#161b22', primaryTextColor: '#c9d1d9', primaryBorderColor: '#30363d',
                  lineColor: '#58a6ff', background:'#0d1117', mainBkg:'#161b22', secondaryColor:'#21262d',
                  fontSize:'16px', lineHeight:'1.4'
                }
              } : {
                ...shared,
                theme: 'default',
                themeVariables: {
                  primaryColor:'#ffffff', primaryTextColor:'#24292f', primaryBorderColor:'#d0d7de',
                  lineColor:'#0969da', tertiaryColor:'#f6f8fa', background:'#ffffff',
                  fontSize:'16px', lineHeight:'1.4'
                }
              }
            }

            // Only container/layout fix — never touch colors
            function mermaidContainerFix(){
              document.querySelectorAll('.mermaid,.mmd-block').forEach(div=>{
                div.style.position='relative'; div.style.zIndex='auto';
                div.style.removeProperty('transform'); div.style.removeProperty('min-width'); div.style.removeProperty('min-height');
              });
              document.querySelectorAll('.mermaid>svg').forEach(svg=>{
                svg.style.display='block'; svg.style.width='100%'; svg.style.height='auto';
                svg.style.removeProperty('min-width'); svg.style.removeProperty('min-height'); svg.style.removeProperty('transform');
              });
            }

            function installMermaid(){
              if (window.mermaid && window.mermaid.initialize) {
                window.mermaid.initialize(currentMermaidConfig());
              }
            }

            (function(){
              // 1) Ensure Mermaid is configured BEFORE Vditor constructs/first-render
              installMermaid();

              const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
              const vditor = new Vditor('vditor', {
                mode: 'ir',
                theme: isDark ? 'dark' : 'classic',
                value: '',
                width: '100%',
                height: '100vh',
                cache: { enable: false },
                after(){
                  // Bridge: ready
                  window.webkit?.messageHandlers?.bridge?.postMessage({ type: 'ready' });
                  // DO NOT initialize mermaid here again — avoid double themes on first render
                  mermaidContainerFix();
                },
                preview: {
                  theme: { current: isDark ? 'dark' : 'light' },
                  hljs: { enable: true, style: isDark ? 'github-dark' : 'github' },
                  math: { engine: 'KaTeX' },
                  // Forward our unified config to Vditor's mermaid so it renders with the same settings
                  mermaid: currentMermaidConfig()
                },
                toolbar: [ 'emoji','headings','bold','italic','strike','link','|','list','ordered-list','check','outdent','indent','|','quote','line','code','inline-code','insert-before','insert-after','|','upload','table','|','undo','redo','|','fullscreen','edit-mode','both','preview','outline','code-theme' ],
                upload: {
                  accept: 'image/*',
                  handler(files){
                    const f = files?.[0]; if(!f) return null;
                    const reader = new FileReader();
                    reader.onload = (e)=>{
                      const base64Data = String(e.target.result).split(',')[1] || '';
                      window.webkit?.messageHandlers?.bridge?.postMessage({ type:'image', filename:f.name, data: base64Data });
                    };
                    reader.readAsDataURL(f);
                    return null;
                  }
                },
                input(value){
                  clearTimeout(window.__inputDebounce);
                  window.__inputDebounce = setTimeout(()=>{
                    window.webkit?.messageHandlers?.bridge?.postMessage({ type:'change', value });
                  }, 300);
                }
              });
              window.vditor = vditor;

              // Cmd/Ctrl+S -> save
              document.addEventListener('keydown', (e)=>{
                if ((e.metaKey||e.ctrlKey) && e.key==='s') { e.preventDefault(); window.webkit?.messageHandlers?.bridge?.postMessage({ type:'save' }); }
              });

              // Theme change: re-init Mermaid BEFORE asking Vditor to re-render
              const mq = window.matchMedia('(prefers-color-scheme: dark)');
              function onThemeChange(e){
                const dark = e.matches;
                vditor.setTheme(dark ? 'dark' : 'classic');
                // 1) re-install Mermaid so first paint after theme change uses correct variables/fonts
                installMermaid();
                // 2) Force Vditor to re-render preview to apply the new mermaid theme
                try {
                  const val = vditor.getValue();
                  if (val != null) vditor.setValue(val);
                } catch(_) {}
                // 3) Layout fix after DOM updates
                setTimeout(mermaidContainerFix, 60);
              }
              if (mq.addEventListener) mq.addEventListener('change', onThemeChange); else if (mq.addListener) mq.addListener(onThemeChange);
              // Expose a native hook to force theme application without waiting for matchMedia events
              window.__applyNativeTheme = function(dark){
                try { window.vditor && window.vditor.setTheme(dark ? 'dark' : 'classic'); } catch(_) {}
                // Re-install Mermaid with the correct variables
                installMermaid();
                // Force a stable re-render so diagrams take the new config immediately
                try {
                  const val = window.vditor?.getValue();
                  if (val != null) window.vditor.setValue(val);
                } catch(_) {}
                // Layout fix after DOM updates
                setTimeout(mermaidContainerFix, 60);
              };
            })();
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
