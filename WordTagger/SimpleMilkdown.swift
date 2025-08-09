import WebKit
import SwiftUI

struct SimpleMilkdownWebView: NSViewRepresentable {
    var markdown: String
    var onChange: (String) -> Void
    
    func makeCoordinator() -> Coordinator { 
        Coordinator(onChange: onChange) 
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let uc = WKUserContentController()
        uc.add(context.coordinator, name: "bridge")
        config.userContentController = uc
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        
        let html = generateHTML()
        webView.loadHTMLString(html, baseURL: nil)
        context.coordinator.webView = webView
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.setMarkdown(markdown)
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        private let onChange: (String) -> Void
        
        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let dict = message.body as? [String: Any],
               let type = dict["type"] as? String,
               type == "markdown",
               let value = dict["value"] as? String {
                onChange(value)
            }
        }
        
        func setMarkdown(_ markdown: String) {
            let escaped = markdown.replacingOccurrences(of: "\\", with: "\\\\")
                                 .replacingOccurrences(of: "\"", with: "\\\"")
                                 .replacingOccurrences(of: "\n", with: "\\n")
            let js = "setMarkdown(\"\(escaped)\");"
            webView?.evaluateJavaScript(js)
        }
    }
    
    private func generateHTML() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body { 
                    font-family: -apple-system, system-ui; 
                    margin: 16px; 
                    background: transparent;
                    color: #333;
                }
                @media (prefers-color-scheme: dark) {
                    body { color: #d4d4d4; }
                }
                textarea {
                    width: 100%;
                    min-height: 400px;
                    border: 1px solid #ccc;
                    border-radius: 8px;
                    padding: 12px;
                    font-family: ui-monospace, monospace;
                    font-size: 14px;
                    resize: vertical;
                    background: transparent;
                    color: inherit;
                }
                @media (prefers-color-scheme: dark) {
                    textarea { 
                        border-color: #555; 
                        color: #d4d4d4;
                    }
                }
            </style>
        </head>
        <body>
            <textarea id="editor" placeholder="输入Markdown内容..."></textarea>
            <script>
                const editor = document.getElementById('editor');
                
                editor.addEventListener('input', () => {
                    window.webkit?.messageHandlers?.bridge?.postMessage({
                        type: 'markdown',
                        value: editor.value
                    });
                });
                
                function setMarkdown(content) {
                    editor.value = content;
                }
            </script>
        </body>
        </html>
        """
    }
}