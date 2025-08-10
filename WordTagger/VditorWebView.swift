import SwiftUI
import WebKit

/// Vditor(IR) 单一渲染管线封装：由 Native 控制主题，并通过 JS 的 __applyNativeTheme(dark) 统一切换
struct VditorWebView: NSViewRepresentable {
    // 输入参数
    var markdown: String
    var nodeId: String
    var onChange: (String) -> Void

    // 允许外部持有 Coordinator（例如 DetailPanel 里通过 @State 传引用）
    @Binding var coordinatorBinding: Coordinator?

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - NSViewRepresentable
    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        // 基础配置
        let config = WKWebViewConfiguration()
        let uc = WKUserContentController()
        uc.add(context.coordinator, name: "bridge")
        config.userContentController = uc
        config.suppressesIncrementalRendering = false
        config.preferences.setValue(true, forKey: "developerExtrasEnabled") // 方便调试

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // macOS: 彻底透明
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.setValue(false, forKey: "opaque")

        // 让 WebView 的 NSAppearance 与当前系统主题一致（首帧避免闪烁）
        let isDark = (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        webView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        // 生成 HTML 并加载
        let html = generateHTML()
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] // 支持本地图片相对路径
        webView.loadHTMLString(html, baseURL: documentsURL)

        // 绑定
        context.coordinator.webView = webView
        context.coordinator.latestMarkdown = markdown
        context.coordinator.nodeId = nodeId
        coordinatorBinding = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // 主题变化：只走 Native，一处下发
        context.coordinator.applyThemeIfNeeded(colorScheme: colorScheme)

        // 文本变化：在 ready 后才下发
        if context.coordinator.isReady {
            context.coordinator.setMarkdown(markdown, forceUpdate: false)
        } else {
            context.coordinator.latestMarkdown = markdown
        }
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var webView: WKWebView?
        var onChange: (String) -> Void

        // 状态
        var isReady = false
        var latestMarkdown: String = ""
        var nodeId: String = ""

        // 主题缓存，避免重复注入
        private var lastDarkValue: Bool?

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        // JS → Native
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "bridge" else { return }
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }

            switch type {
            case "ready":
                // 页面 JS 初始化完成
                isReady = true
                // 1) 主题下发
                applyTheme(force: true)
                // 2) 首帧文本注入
                setMarkdown(latestMarkdown, forceUpdate: true)

            case "change":
                if let value = body["value"] as? String {
                    latestMarkdown = value
                    onChange(value)
                }

            case "save":
                // 如果需要处理 ⌘S，可以在这里转发给上层
                // print("⌘S requested from Vditor")
                break

            case "image":
                // 如果你实现了上传回调，可在此接收
                // filename / data(base64)
                // print("image from web:", body)
                break

            default:
                break
            }
        }

        // 提供给外部的控制方法
        func setMarkdown(_ text: String, forceUpdate: Bool) {
            latestMarkdown = text
            let escaped = Self.escapeForJavaScript(text)
            evaluateJS("window.__setMarkdown(`\(escaped)`, \(forceUpdate ? "true" : "false"));")
        }

        func toggleMode() {
            evaluateJS("window.__toggleVditorMode && window.__toggleVditorMode();")
        }

        // 主题：只走 Native
        func applyThemeIfNeeded(colorScheme: ColorScheme) {
            let dark = (colorScheme == .dark)
            if lastDarkValue != dark {
                lastDarkValue = dark
                applyTheme(force: true)
            }
        }

        private func applyTheme(force: Bool) {
            let isDark = (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            lastDarkValue = isDark
            evaluateJS("window.__applyNativeTheme(\(isDark ? "true" : "false"));", delayMS: force ? 0 : 30)
        }

        // Helpers
        private func evaluateJS(_ js: String, delayMS: Int = 0) {
            guard let webView = webView else { return }
            if delayMS <= 0 {
                webView.evaluateJavaScript(js, completionHandler: nil)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMS)) {
                    webView.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }

        static func escapeForJavaScript(_ string: String) -> String {
            string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
    }

    // MARK: - HTML / JS （单一入口：__applyNativeTheme）
    private func generateHTML() -> String {
        // 你可以把 CDN 换成本地资源；这里只用 CDN 以便快速验证
        return #"""
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>Vditor IR</title>

          <!-- Vditor -->
          <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/vditor/dist/index.css">
          <script src="https://cdn.jsdelivr.net/npm/vditor/dist/index.min.js"></script>

          <!-- Mermaid -->
          <script src="https://cdn.jsdelivr.net/npm/mermaid@10.6.1/dist/mermaid.min.js"></script>

          <style>
            :root { --bg: transparent; --mmd-font: 20px; }
            html, body { margin:0; padding:0; background: var(--bg); }
            #vditor { height: 100vh; }

            /* --- Mermaid base scaling via container font-size --- */
            .mermaid { font-size: var(--mmd-font) !important; }

            /* --- Dark content readability for Markdown preview/content --- */
            .vditor--dark .vditor-reset { color: #c9d1d9; }
            .vditor--dark .vditor-reset h1,
            .vditor--dark .vditor-reset h2,
            .vditor--dark .vditor-reset h3,
            .vditor--dark .vditor-reset h4,
            .vditor--dark .vditor-reset h5,
            .vditor--dark .vditor-reset h6 { color: #e6edf3; }
            .vditor--dark .vditor-reset a { color: #58a6ff; }
            .vditor--dark .vditor-reset code,
            .vditor--dark .vditor-reset pre {
              background: #161b22;
              color: #c9d1d9;
              border-color: #30363d;
            }
          </style>
        </head>
        <body>
          <div id="vditor"></div>

          <script>
          (function(){
            // -------- Mermaid 主题配置（不监听系统）--------
            function currentMermaidConfig(dark){
              const shared = {
                startOnLoad: false,
                securityLevel: 'loose',
                fontFamily: "-apple-system, 'SF Pro Text', 'Segoe UI', Arial, sans-serif",
                flowchart: { useMaxWidth: true, htmlLabels: true, curve: 'basis', padding: 8, nodeSpacing: 40, rankSpacing: 40 }
              };
              return dark ? {
                ...shared,
                theme: 'dark',
                themeVariables: {
                  primaryColor:'#161b22', primaryTextColor:'#c9d1d9', primaryBorderColor:'#30363d',
                  lineColor:'#58a6ff', background:'#0d1117', mainBkg:'#161b22', secondaryColor:'#21262d',
                  fontSize:'1em', lineHeight:'1.4'
                }
              } : {
                ...shared,
                theme: 'default',
                themeVariables: {
                  primaryColor:'#ffffff', primaryTextColor:'#24292f', primaryBorderColor:'#d0d7de',
                  lineColor:'#0969da', tertiaryColor:'#f6f8fa', background:'#ffffff',
                  fontSize:'1em', lineHeight:'1.4'
                }
              };
            }

            function installMermaid(dark){
              if (!window.mermaid) return;
              window.mermaid.initialize(currentMermaidConfig(dark));
            }

            // 容器修正，避免 SVG 锁高/溢出
            function containerFix(){
              document.querySelectorAll('.mermaid>svg').forEach(svg=>{
                svg.style.display='block';
                svg.style.width='100%';
                svg.style.height='auto';
                svg.style.removeProperty('transform');
                svg.style.removeProperty('min-width');
                svg.style.removeProperty('min-height');
              });
            }

            // Vditor 初始化（固定浅色占位；真实主题由 Native 注入）
            const vditor = new Vditor('vditor', {
              mode: 'ir',
              theme: 'classic',                   // 占位
              value: '',
              width: '100%',
              height: '100vh',
              cache: { enable: false },
              after(){
                // 通知 Native：ready
                try { window.webkit?.messageHandlers?.bridge?.postMessage({ type: 'ready' }); } catch(_) {}
                setTimeout(containerFix, 30);
              },
              preview: {
                theme: { current: 'light' },      // 占位
                hljs: { enable: true, style: 'github' },
                math: { engine: 'KaTeX' },
                mermaid: { startOnLoad:false }     // 由我们手动控制
              },
              toolbar: ['emoji','headings','bold','italic','strike','link','|','list','ordered-list','check','outdent','indent','|','quote','line','code','inline-code','insert-before','insert-after','|','upload','table','|','undo','redo','|','fullscreen','edit-mode','both','preview','outline','code-theme' ],
              upload: { accept:'image/*' },
              input(value){
                clearTimeout(window.__inputDebounce);
                window.__inputDebounce = setTimeout(()=>{
                  try { window.webkit?.messageHandlers?.bridge?.postMessage({ type:'change', value }); } catch(_) {}
                }, 300);
              }
            });
            window.vditor = vditor;

            // 动态调整 Mermaid 基准字号（整体缩放）
            window.__setMermaidFont = function(px){
              try {
                document.documentElement.style.setProperty('--mmd-font', typeof px === 'number' ? px + 'px' : String(px));
                const val = vditor.getValue();
                if (val != null) vditor.setValue(val); // 触发预览重算
              } catch(_) {}
              setTimeout(containerFix, 60);
            };

            // Native 唯一入口：应用主题 + 触发重渲染
            window.__applyNativeTheme = function(dark){
              try {
                const ui = dark ? 'dark' : 'classic';
                const code = dark ? 'github-dark' : 'github';
                const content = dark ? 'dark' : 'light';
                if (vditor.setTheme) vditor.setTheme(ui, code, content);
              } catch(_) {}
              installMermaid(dark);
              try {
                const val = vditor.getValue();
                if (val != null) vditor.setValue(val); // 触发预览（含 mermaid）重算
              } catch(_) {}
              setTimeout(containerFix, 60);
            };

            // 设置/强制设置 Markdown
            window.__setMarkdown = function(text, force){
              try{
                const cur = vditor.getValue();
                if (force || cur !== text) vditor.setValue(text);
              }catch(_){}
            };

            // 切换编辑模式（IR <-> WYSIWYG）
            window.__toggleVditorMode = function(){
              try{
                const mode = vditor.getCurrentMode ? vditor.getCurrentMode() : 'ir';
                const next = mode === 'ir' ? 'wysiwyg' : 'ir';
                if (vditor.setEditMode) vditor.setEditMode(next);
              }catch(_){}
            };
          })();
          </script>
        </body>
        </html>
        """#
    }
}
