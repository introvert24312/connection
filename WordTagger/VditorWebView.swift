import SwiftUI
import WebKit
import AppKit

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
        
        // 允许访问本地文件
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator // 添加UI委托

        // macOS: 彻底透明
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.setValue(false, forKey: "opaque")

        // 让 WebView 的 NSAppearance 与当前系统主题一致（首帧避免闪烁）
        let isDark = (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        webView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        // 强制使用外部数据管理器的路径，不提供后备选项
        guard let baseURL = ExternalDataManager.shared.currentDataPath else {
            // 如果没有设置外部路径，加载一个提示页面
            let errorHTML = Self.generateErrorHTML()
            webView.loadHTMLString(errorHTML, baseURL: nil)
            return webView
        }
        
        // 确保有访问权限
        guard ExternalDataManager.shared.ensureAccess() else {
            let errorHTML = Self.generateAccessErrorHTML()
            webView.loadHTMLString(errorHTML, baseURL: nil)
            return webView
        }
        
        // 生成 HTML 并加载
        let html = Self.generateHTML()
        
        // 创建临时 HTML 文件以支持本地图片加载
        let tempURL = baseURL.appendingPathComponent("temp.html")
        do {
            try html.write(to: tempURL, atomically: true, encoding: .utf8)
            // 使用 loadFileURL 而不是 loadHTMLString，这样可以正确加载本地资源
            webView.loadFileURL(tempURL, allowingReadAccessTo: baseURL)
        } catch {
            print("创建临时HTML文件失败: \(error)")
            let errorHTML = Self.generateWriteErrorHTML()
            webView.loadHTMLString(errorHTML, baseURL: nil)
        }

        // 绑定
        context.coordinator.webView = webView
        context.coordinator.latestMarkdown = markdown
        context.coordinator.nodeId = nodeId
        
        // 异步设置 coordinator binding 避免在视图更新时修改状态
        DispatchQueue.main.async {
            coordinatorBinding = context.coordinator
        }
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
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
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
                
            case "saveImage":
                // 处理图片保存
                if let fileName = body["fileName"] as? String,
                   let base64Data = body["data"] as? String,
                   let imageData = Data(base64Encoded: base64Data) {
                    saveImageToFile(fileName: fileName, data: imageData)
                }
                break

            case "image":
                // 如果你实现了上传回调，可在此接收
                // filename / data(base64)
                // print("image from web:", body)
                break
                
            case "showImageInFinder":
                // 在 Finder 中显示图片
                if let filename = body["filename"] as? String {
                    showImageInFinder(filename: filename)
                }
                break
                
            case "commandE":
                // 通过通知机制转发 Command+E 给原生 App
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("toggleSidebar"), object: nil)
                }
                break
                
            case "commandO":
                // 转发 Command+O 给原生 App - 切换到详情标签
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("switchToDetailTab"), object: nil)
                }
                break
                
            case "commandL":
                // 转发 Command+L 给原生 App - 切换到图谱标签  
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("switchToGraphTab"), object: nil)
                }
                break
                
            case "commandD":
                // 转发 Command+D 给原生 App - 全屏详情面板
                DispatchQueue.main.async {
                    // Command+D应该触发全屏详情面板，不是切换到图谱
                    // 这里暂时不做任何操作，让DetailPanel自己的按键处理来处理Command+D
                }
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
            evaluateJS("window.__applyNativeTheme(\(isDark ? "true" : "false"));", delayMS: 0) // 立即执行，无延迟
        }
        
        // 图片保存功能
        private func saveImageToFile(fileName: String, data: Data) {
            // 强制使用外部数据管理器获取图片路径，不提供后备选项
            guard let imagesURL = ExternalDataManager.shared.getImagesURL() else {
                print("错误：必须先设置外部数据存储路径才能保存图片")
                evaluateJS("window.__onImageSaveError && window.__onImageSaveError('\(fileName)', '请先在设置中选择数据存储文件夹');")
                return
            }
            
            // 确保外部数据管理器有访问权限
            guard ExternalDataManager.shared.ensureAccess() else {
                print("错误：无法访问外部数据存储路径")
                evaluateJS("window.__onImageSaveError && window.__onImageSaveError('\(fileName)', '无法访问数据存储文件夹，请重新选择');")
                return
            }
            
            // 确保目录存在
            try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true, attributes: nil)
            
            // 保存文件
            let fileURL = imagesURL.appendingPathComponent(fileName)
            
            do {
                // 直接保存原始图片，不压缩
                try data.write(to: fileURL)
                print("图片已保存到: \(fileURL.path)")
                
                // 通知前端保存成功
                let relativePath = "Images/\(fileName)"
                evaluateJS("window.__onImageSaved && window.__onImageSaved('\(fileName)', '\(relativePath)');")
            } catch {
                print("保存图片失败: \(error)")
                evaluateJS("window.__onImageSaveError && window.__onImageSaveError('\(fileName)', '\(error.localizedDescription)');")
            }
        }
        
        // 在 Finder 中显示图片
        private func showImageInFinder(filename: String) {
            guard let imagesURL = ExternalDataManager.shared.getImagesURL() else { 
                print("错误：必须先设置外部数据存储路径")
                return 
            }
            
            // 确保外部数据管理器有访问权限
            guard ExternalDataManager.shared.ensureAccess() else {
                print("错误：无法访问外部数据存储路径")
                return
            }
            
            let fileURL = imagesURL.appendingPathComponent(filename.replacingOccurrences(of: "Images/", with: ""))
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
            } else {
                print("图片文件不存在: \(fileURL.path)")
            }
        }

        // MARK: - WKUIDelegate
        func webViewDidClose(_ webView: WKWebView) {
            print("🌐 VditorWebView: WebView关闭")
            // 通知焦点管理器WebView已关闭
            NotificationCenter.default.post(name: NSNotification.Name("webViewDidClose"), object: nil)
        }
        
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            // 处理JS的prompt调用
            completionHandler(defaultText)
        }
        
        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("🌐 VditorWebView: 页面加载完成")
            // WebView加载完成时，发送通知
            NotificationCenter.default.post(name: NSNotification.Name("webViewDidLoad"), object: nil)
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

    // MARK: - 错误页面生成
    private static func generateErrorHTML() -> String {
        return """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8" />
    <title>WordTagger - 需要设置数据存储路径</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: #f5f5f5;
            color: #333;
        }
        .error-container {
            text-align: center;
            padding: 40px;
            background: white;
            border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
            max-width: 500px;
        }
        h1 { color: #e74c3c; margin-bottom: 20px; }
        p { margin: 15px 0; line-height: 1.6; }
        .instruction { background: #ecf0f1; padding: 15px; border-radius: 6px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="error-container">
        <h1>📁 需要设置数据存储路径</h1>
        <p>请在设置中选择一个外部文件夹来存储您的数据和图片。</p>
        <div class="instruction">
            <strong>操作步骤：</strong><br>
            1. 点击左上角的设置按钮<br>
            2. 选择“数据存储文件夹”<br>
            3. 选择一个安全的位置（如 Documents 或 Desktop）
        </div>
        <p>设置完成后，您的数据和图片都将保存在所选文件夹中。</p>
    </div>
</body>
</html>
"""
    }
    
    private static func generateAccessErrorHTML() -> String {
        return """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8" />
    <title>WordTagger - 访问权限错误</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: #f5f5f5;
            color: #333;
        }
        .error-container {
            text-align: center;
            padding: 40px;
            background: white;
            border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
            max-width: 500px;
        }
        h1 { color: #e74c3c; margin-bottom: 20px; }
        p { margin: 15px 0; line-height: 1.6; }
        .instruction { background: #ecf0f1; padding: 15px; border-radius: 6px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="error-container">
        <h1>🔒 访问权限错误</h1>
        <p>无法访问数据存储文件夹，请重新选择。</p>
        <div class="instruction">
            <strong>解决方法：</strong><br>
            1. 转到设置页面<br>
            2. 点击“重新选择数据文件夹”<br>
            3. 选择一个您有写入权限的文件夹
        </div>
        <p>建议选择 Documents、Desktop 或其他用户目录。</p>
    </div>
</body>
</html>
"""
    }
    
    private static func generateWriteErrorHTML() -> String {
        return """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8" />
    <title>WordTagger - 写入错误</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: #f5f5f5;
            color: #333;
        }
        .error-container {
            text-align: center;
            padding: 40px;
            background: white;
            border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
            max-width: 500px;
        }
        h1 { color: #e74c3c; margin-bottom: 20px; }
        p { margin: 15px 0; line-height: 1.6; }
    </style>
</head>
<body>
    <div class="error-container">
        <h1>⚠️ 写入错误</h1>
        <p>无法在数据存储文件夹中创建文件。</p>
        <p>请检查文件夹是否存在且有写入权限。</p>
    </div>
</body>
</html>
"""
    }
    
    // MARK: - HTML / JS （单一入口：__applyNativeTheme）
    private static func generateHTML() -> String {
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
            .mermaid { 
              font-size: 20px !important;
              zoom: 1.3;  /* 整体放大 1.3 倍 */
              transform-origin: top left;
            }
            .mermaid svg text { 
              font-size: 20px !important;
              font-family: -apple-system, 'SF Pro Text', sans-serif !important;
            }

            /* --- Dark content readability for Markdown preview/content --- */
            .vditor--dark .vditor-reset { color: #c9d1d9; }
            
            /* --- 图片性能优化 --- */
            .vditor-reset img {
              max-width: 100%;
              height: auto;
              image-rendering: -webkit-optimize-contrast;
              will-change: transform;
            }
            
            /* 大图片加载时显示占位符 */
            .vditor-reset img[src^="data:"] {
              background: #f0f0f0;
              min-height: 100px;
            }
            
            .vditor--dark .vditor-reset img[src^="data:"] {
              background: #2b2b2b;
            }
            
            /* 本地图片路径处理 */
            .vditor-reset img[src^="Images/"],
            .vditor-reset img[src^="./Images/"],
            .vditor-reset img[src*="/Images/"] {
              max-width: 100%;
              height: auto;
              cursor: default;
              display: block;
            }
            
            /* 图片加载失败时的样式 */
            .vditor-reset img:not([src=""]) {
              min-width: 100px;
              min-height: 100px;
              background: #f0f0f0 url('data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100"><text x="50%" y="50%" text-anchor="middle" dy=".3em" fill="%23999">图片加载中...</text></svg>') center no-repeat;
            }
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
                  fontSize:'20px', lineHeight:'1.4'
                }
              } : {
                ...shared,
                theme: 'default',
                themeVariables: {
                  primaryColor:'#ffffff', primaryTextColor:'#24292f', primaryBorderColor:'#d0d7de',
                  lineColor:'#0969da', tertiaryColor:'#f6f8fa', background:'#ffffff',
                  fontSize:'20px', lineHeight:'1.4'
                }
              };
            }

            function installMermaid(dark){
              if (!window.mermaid) return;
              window.mermaid.initialize(currentMermaidConfig(dark));
            }

            // 容器修正，避免 SVG 锁高/溢出 + viewBox 缩放
            function containerFix(){
              document.querySelectorAll('.mermaid>svg').forEach(svg=>{
                svg.style.display='block';
                svg.style.width='100%';
                svg.style.height='auto';
                svg.style.removeProperty('transform');
                svg.style.removeProperty('min-width');
                svg.style.removeProperty('min-height');
                
                // viewBox 缩放：放大内容
                const viewBox = svg.getAttribute('viewBox');
                if (viewBox) {
                  const [x, y, width, height] = viewBox.split(' ').map(Number);
                  const scaleFactor = 0.7; // 缩小 viewBox 使内容看起来更大
                  svg.setAttribute('viewBox', `${x} ${y} ${width * scaleFactor} ${height * scaleFactor}`);
                }
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
              hotkey: {
                // 禁用 Command+E 快捷键，让 App 使用
                'edit-mode': '',
                // 彻底禁用所有可能的 Command+E 相关快捷键
                'Ctrl+Alt+E': '',
                'Shift+Ctrl+E': '',
                'Ctrl+E': '',
                // 🔥 禁用 Command+O、Command+L 和 Command+D，让应用层接管
                'Cmd+O': '',
                'Ctrl+O': '',
                'Cmd+D': '',
                'Ctrl+D': '',
                'Cmd+L': '',
                'Ctrl+L': '',
                // 禁用可能的组合键
                'Cmd+Shift+O': '',
                'Cmd+Shift+L': '',
                'Ctrl+Shift+O': '',
                'Ctrl+Shift+L': ''
              },
              after(){
                // 通知 Native：ready
                try { window.webkit?.messageHandlers?.bridge?.postMessage({ type: 'ready' }); } catch(_) {}
                setTimeout(containerFix, 30);
                
                // 拦截特殊快捷键
                document.addEventListener('keydown', function(e) {
                  // Command+E: 转发给原生 App
                  if (e.metaKey && (e.key === 'e' || e.key === 'E')) {
                    console.log('拦截 Command+E 快捷键，转发给 App 处理');
                    e.preventDefault();
                    e.stopImmediatePropagation();
                    
                    try {
                      window.webkit?.messageHandlers?.bridge?.postMessage({ 
                        type: 'commandE'
                      });
                    } catch(err) {
                      console.error('无法发送 Command+E 事件:', err);
                    }
                    return false;
                  }
                  
                  // Command+O: 转发给原生App处理
                  if (e.metaKey && (e.key === 'o' || e.key === 'O')) {
                    console.log('🔥 拦截 Command+O 快捷键，转发给App处理');
                    e.preventDefault();
                    e.stopImmediatePropagation();
                    
                    try {
                      window.webkit?.messageHandlers?.bridge?.postMessage({ 
                        type: 'commandO'
                      });
                    } catch(err) {
                      console.error('无法发送 Command+O 事件:', err);
                    }
                    return false;
                  }
                  
                  // Command+L: 转发给原生App处理
                  if (e.metaKey && (e.key === 'l' || e.key === 'L')) {
                    console.log('🔥 拦截 Command+L 快捷键，转发给App处理');
                    e.preventDefault();
                    e.stopImmediatePropagation();
                    
                    try {
                      window.webkit?.messageHandlers?.bridge?.postMessage({ 
                        type: 'commandL'
                      });
                    } catch(err) {
                      console.error('无法发送 Command+L 事件:', err);
                    }
                    return false;
                  }
                  
                  // Command+D: 转发给原生App处理 (全屏详情面板)
                  if (e.metaKey && (e.key === 'd' || e.key === 'D')) {
                    console.log('🔥 拦截 Command+D 快捷键，转发给App处理');
                    e.preventDefault();
                    e.stopImmediatePropagation();
                    
                    try {
                      window.webkit?.messageHandlers?.bridge?.postMessage({ 
                        type: 'commandD'
                      });
                    } catch(err) {
                      console.error('无法发送 Command+D 事件:', err);
                    }
                    return false;
                  }
                  
                  // Command+/: 切换编辑模式
                  if (e.metaKey && e.key === '/') {
                    console.log('🎯 拦截 Command+/ 快捷键，准备切换编辑模式');
                    console.log('按键信息:', { key: e.key, metaKey: e.metaKey, ctrlKey: e.ctrlKey, altKey: e.altKey });
                    e.preventDefault();
                    e.stopImmediatePropagation();
                    
                    try {
                      if (window.__toggleVditorMode) {
                        console.log('🔄 调用 __toggleVditorMode 函数');
                        window.__toggleVditorMode();
                      } else {
                        console.error('❌ __toggleVditorMode 函数不存在');
                      }
                    } catch(err) {
                      console.error('❌ 无法切换编辑模式:', err);
                    }
                    return false;
                  }
                }, true);
              },
              preview: {
                theme: { current: 'light' },      // 占位
                hljs: { enable: true, style: 'github' },
                math: { engine: 'KaTeX' },
                mermaid: { startOnLoad:false }     // 由我们手动控制
              },
              toolbar: ['emoji','headings','bold','italic','strike','link','|','list','ordered-list','check','outdent','indent','|','quote','line','code','inline-code','insert-before','insert-after','|','upload','table','|','undo','redo','|','fullscreen','edit-mode','both','preview','outline','code-theme' ],
              upload: { 
                accept:'image/*',
                async handler(files) {
                  // 自定义上传处理
                  const file = files[0];
                  if (!file) return;
                  
                  try {
                    // 生成唯一文件名
                    const timestamp = Date.now();
                    const ext = file.name.split('.').pop() || 'jpg';
                    const fileName = `img_${timestamp}.${ext}`;
                    
                    // 显示加载提示
                    vditor.insertValue(`![加载中...]()`);
                    
                    // 读取文件
                    const reader = new FileReader();
                    reader.onload = (e) => {
                      const base64 = e.target.result.split(',')[1]; // 去掉 data:image/xxx;base64, 前缀
                      
                      // 发送到 Swift 保存
                      window.webkit?.messageHandlers?.bridge?.postMessage({ 
                        type: 'saveImage',
                        fileName: fileName,
                        data: base64
                      });
                      
                      // 设置回调处理
                      window.__onImageSaved = (name, path) => {
                        // 替换加载提示为实际图片路径（使用相对路径）
                        const content = vditor.getValue();
                        const updated = content.replace('![加载中...]()', `![${file.name}](${path})`);
                        vditor.setValue(updated);
                      };
                      
                      window.__onImageSaveError = (name, error) => {
                        alert(`保存图片失败: ${error}`);
                        const content = vditor.getValue();
                        const updated = content.replace('![加载中...]()', '');
                        vditor.setValue(updated);
                      };
                    };
                    
                    reader.readAsDataURL(file);
                  } catch (error) {
                    console.error('处理图片失败:', error);
                    alert('处理图片失败');
                  }
                  
                  return null; // 阻止默认处理
                }
              },
              input(value){
                clearTimeout(window.__inputDebounce);
                window.__inputDebounce = setTimeout(()=>{
                  // 获取原始 Markdown 内容（getValue 已经处理了还原）
                  const originalValue = vditor.getValue();
                  console.log('Input event - sending value:', originalValue.substring(0, 100) + '...');
                  try { 
                    window.webkit?.messageHandlers?.bridge?.postMessage({ 
                      type:'change', 
                      value: originalValue 
                    }); 
                  } catch(e) {
                    console.error('Failed to send change message:', e);
                  }
                }, 50); // 缩短防抖时间到50ms，提高响应速度
              },
              // 添加 blur 事件处理，确保失焦时立即保存
              blur() {
                clearTimeout(window.__inputDebounce);
                const originalValue = vditor.getValue();
                console.log('Blur event - immediately sending value');
                try { 
                  window.webkit?.messageHandlers?.bridge?.postMessage({ 
                    type:'change', 
                    value: originalValue 
                  }); 
                } catch(e) {
                  console.error('Failed to send change message on blur:', e);
                }
              }
            });
            window.vditor = vditor;
            
            // 实现自定义图片缩放语法
            // 支持格式：
            // ![alt|50](src)      - 缩放到 50%
            // ![alt|75.5](src)    - 缩放到 75.5%
            // ![alt|300px](src)   - 固定宽度 300 像素
            const processImageScale = (markdown) => {
              return markdown.replace(/!\[([^\]]*?)\|([0-9.]+)(px)?\]\(([^)]+)\)/g, (match, alt, size, unit, src) => {
                // 如果有 px 单位，使用像素；否则使用百分比
                const style = unit === 'px' 
                  ? `width: ${size}px; height: auto; max-width: 100%;`
                  : `width: ${size}%; height: auto; max-width: 100%;`;
                // 保留原始 alt 文本（去掉缩放参数）
                return `<img src="${src}" alt="${alt}" style="${style}" title="${alt}" />`;
              });
            };
            
            // 保存原始 Markdown 用于编辑
            let originalMarkdown = { current: '' };
            
            // 重写 setValue 以支持缩放语法
            const originalSetValue = vditor.setValue.bind(vditor);
            vditor.setValue = function(value) {
              // 保存原始内容
              originalMarkdown.current = value;
              // 处理缩放语法仅用于显示
              const processed = processImageScale(value);
              originalSetValue(processed);
            };
            
            // 确保 input 事件也处理缩放
            const originalInsertValue = vditor.insertValue.bind(vditor);
            vditor.insertValue = function(value) {
              const processed = processImageScale(value);
              originalInsertValue(processed);
            };
            
            // 重写 getValue 返回原始内容
            const originalGetValue = vditor.getValue.bind(vditor);
            vditor.getValue = function() {
              // 获取当前编辑器内容
              const currentValue = originalGetValue();
              // 如果内容包含我们的 HTML img 标签，尝试还原
              if (currentValue.includes('<img')) {
                // 还原 img 标签为 Markdown 格式
                return currentValue.replace(/<img src="([^"]+)" alt="([^"]*)" style="width: (\d+(?:\.\d+)?)(px|%);[^"]*"[^>]*>/g, 
                  (match, src, alt, size, unit) => {
                    const suffix = unit === 'px' ? 'px' : '';
                    return `![${alt}|${size}${suffix}](${src})`;
                  });
              }
              return currentValue;
            };
            
            // 监听图片加载事件进行调试
            document.addEventListener('error', function(e) {
              if (e.target.tagName === 'IMG') {
                console.error('图片加载失败:', e.target.src);
                // 尝试修复路径
                const src = e.target.src;
                if (src.includes('Images/') && !src.startsWith('file://')) {
                  // 如果不是 file:// 开头，尝试转换
                  const filename = src.split('Images/').pop();
                  e.target.src = 'Images/' + filename;
                }
              }
            }, true);
            
            // 图片交互处理：支持双击放大、Command+点击在Finder中显示、在文档内缩放拖动
            let imageClickTimeout = null;
            let imageClickCount = 0;
            
            // 添加图片缩放状态管理
            let scaledImages = new Map(); // 存储每个图片的缩放状态
            
            // 创建全屏覆盖层（用于退出缩放模式）
            function createImageOverlay(img) {
              const overlay = document.createElement('div');
              overlay.style.cssText = `
                position: fixed;
                top: 0;
                left: 0;
                width: 100vw;
                height: 100vh;
                background: rgba(0, 0, 0, 0.8);
                z-index: 10000;
                cursor: zoom-out;
                display: flex;
                align-items: center;
                justify-content: center;
              `;
              
              const clonedImg = img.cloneNode(true);
              clonedImg.style.cssText = `
                max-width: 90vw;
                max-height: 90vh;
                width: auto;
                height: auto;
                object-fit: contain;
                transform-origin: center;
                transition: none;  // 移除默认过渡，减少延迟
                cursor: grab;
              `;
              
              let scale = 1;
              let translateX = 0;
              let translateY = 0;
              let isDragging = false;
              let startX = 0;
              let startY = 0;
              
              // 更新变换
              function updateTransform() {
                clonedImg.style.transform = `scale(${scale}) translate(${translateX}px, ${translateY}px)`;
              }
              
              // 真正的捏合缩放支持
              let initialDistance = 0;
              let initialScale = 1;
              let isGesturing = false;
              
              // Gesture事件支持（Safari/WebKit）
              overlay.addEventListener('gesturestart', (e) => {
                e.preventDefault();
                isGesturing = true;
                initialScale = scale;
                clonedImg.style.transition = 'none';
              });
              
              overlay.addEventListener('gesturechange', (e) => {
                e.preventDefault();
                if (isGesturing) {
                  const newScale = initialScale * e.scale;
                  scale = Math.max(0.5, Math.min(5, newScale));
                  updateTransform();
                }
              });
              
              overlay.addEventListener('gestureend', (e) => {
                e.preventDefault();
                isGesturing = false;
                // 移除过渡动画，减少释放延迟
              });
              
              // 双指触摸捏合缩放（通用支持）
              let touches = {};
              
              overlay.addEventListener('touchstart', (e) => {
                e.preventDefault();
                if (e.touches.length === 2) {
                  // 双指捏合开始
                  const touch1 = e.touches[0];
                  const touch2 = e.touches[1];
                  initialDistance = Math.sqrt(
                    Math.pow(touch2.clientX - touch1.clientX, 2) + 
                    Math.pow(touch2.clientY - touch1.clientY, 2)
                  );
                  initialScale = scale;
                  clonedImg.style.transition = 'none';
                  isGesturing = true;
                } else if (e.touches.length === 1 && !isGesturing) {
                  // 单指拖拽
                  const touch = e.touches[0];
                  lastTouchX = touch.clientX;
                  lastTouchY = touch.clientY;
                  isTouchDragging = true;
                  clonedImg.style.transition = 'none';
                }
              });
              
              overlay.addEventListener('touchmove', (e) => {
                e.preventDefault();
                
                if (e.touches.length === 2 && isGesturing) {
                  // 双指捏合缩放
                  const touch1 = e.touches[0];
                  const touch2 = e.touches[1];
                  const currentDistance = Math.sqrt(
                    Math.pow(touch2.clientX - touch1.clientX, 2) + 
                    Math.pow(touch2.clientY - touch1.clientY, 2)
                  );
                  
                  if (initialDistance > 0) {
                    const scaleRatio = currentDistance / initialDistance;
                    const newScale = initialScale * scaleRatio;
                    scale = Math.max(0.5, Math.min(5, newScale));
                    updateTransform();
                  }
                } else if (e.touches.length === 1 && isTouchDragging && !isGesturing) {
                  // 单指拖拽 - 进一步降低灵敏度
                  const touch = e.touches[0];
                  const deltaX = (touch.clientX - lastTouchX) * 0.4;  // 降低到40%灵敏度
                  const deltaY = (touch.clientY - lastTouchY) * 0.4;  // 降低到40%灵敏度
                  
                  translateX += deltaX;
                  translateY += deltaY;
                  
                  lastTouchX = touch.clientX;
                  lastTouchY = touch.clientY;
                  updateTransform();
                }
              });
              
              overlay.addEventListener('touchend', (e) => {
                e.preventDefault();
                if (e.touches.length < 2) {
                  isGesturing = false;
                  initialDistance = 0;
                }
                if (e.touches.length === 0) {
                  isTouchDragging = false;
                }
                // 移除过渡动画，减少释放延迟
              });
              
              // 鼠标滚轮缩放（支持触控板捏合）
              overlay.addEventListener('wheel', (e) => {
                e.preventDefault();
                
                // 检测是否是触控板捏合手势（ctrlKey为true表示捏合）
                if (e.ctrlKey) {
                  // 触控板捏合缩放，更精细的控制
                  const delta = -e.deltaY * 0.01;
                  scale = Math.max(0.5, Math.min(5, scale * (1 + delta)));
                } else {
                  // 普通滚轮缩放
                  const delta = e.deltaY > 0 ? 0.9 : 1.1;
                  scale = Math.max(0.5, Math.min(5, scale * delta));
                }
                updateTransform();
              });
              
              // 触摸变量声明（用于上面的触摸事件）
              let lastTouchX = 0;
              let lastTouchY = 0;
              let isTouchDragging = false;
              
              // 拖拽功能
              clonedImg.addEventListener('mousedown', (e) => {
                if (e.button === 0) {
                  e.preventDefault();
                  isDragging = true;
                  startX = e.clientX - translateX;
                  startY = e.clientY - translateY;
                  clonedImg.style.cursor = 'grabbing';
                  clonedImg.style.transition = 'none';
                }
              });
              
              overlay.addEventListener('mousemove', (e) => {
                if (isDragging) {
                  translateX = e.clientX - startX;
                  translateY = e.clientY - startY;
                  updateTransform();
                }
              });
              
              overlay.addEventListener('mouseup', () => {
                if (isDragging) {
                  isDragging = false;
                  clonedImg.style.cursor = 'grab';
                  // 移除过渡动画，减少鼠标释放延迟
                }
              });
              
              // 双击重置
              clonedImg.addEventListener('dblclick', (e) => {
                e.stopPropagation();
                scale = 1;
                translateX = 0;
                translateY = 0;
                updateTransform();
              });
              
              // 点击空白区域或ESC退出
              overlay.addEventListener('click', (e) => {
                if (e.target === overlay) {
                  document.body.removeChild(overlay);
                }
              });
              
              // 键盘快捷键
              const handleKeyPress = (e) => {
                e.preventDefault();
                switch(e.key) {
                  case 'Escape':
                    // ESC退出 - 立即关闭，无延迟
                    if (document.body.contains(overlay)) {
                      document.body.removeChild(overlay);
                    }
                    document.removeEventListener('keydown', handleKeyPress);
                    break;
                  case '0':
                    // 数字0重置缩放
                    scale = 1;
                    translateX = 0;
                    translateY = 0;
                    updateTransform();
                    break;
                  case '=':
                  case '+':
                    // 放大
                    scale = Math.min(5, scale * 1.2);
                    updateTransform();
                    break;
                  case '-':
                    // 缩小
                    scale = Math.max(0.5, scale * 0.8);
                    updateTransform();
                    break;
                  case '1':
                    // 实际大小
                    scale = 1;
                    updateTransform();
                    break;
                }
              };
              document.addEventListener('keydown', handleKeyPress);
              
              overlay.appendChild(clonedImg);
              return overlay;
            }
            
            // 阻止所有图片的默认双击行为（包括vditor内置的）
            document.addEventListener('dblclick', function(e) {
              if (e.target.tagName === 'IMG') {
                e.preventDefault();
                e.stopImmediatePropagation();
                e.stopPropagation();
              }
            }, true);
            
            document.addEventListener('click', function(e) {
              if (e.target.tagName === 'IMG' && e.target.src.includes('Images/')) {
                if (e.metaKey) {
                  // Command+点击：在 Finder 中显示图片
                  e.preventDefault();
                  e.stopPropagation();
                  const src = e.target.src;
                  const filename = src.split('Images/').pop();
                  try {
                    window.webkit?.messageHandlers?.bridge?.postMessage({ 
                      type: 'showImageInFinder',
                      filename: 'Images/' + filename
                    });
                  } catch(err) {
                    console.error('无法打开图片:', err);
                  }
                } else {
                  // 普通点击：处理双击检测
                  e.preventDefault();
                  e.stopPropagation();
                  
                  imageClickCount++;
                  const currentImg = e.target;
                  
                  if (imageClickCount === 1) {
                    imageClickTimeout = setTimeout(() => {
                      // 单击：不做任何操作
                      console.log('单击图片');
                      imageClickCount = 0;
                    }, 300);
                  } else if (imageClickCount === 2) {
                    // 双击：进入缩放模式
                    clearTimeout(imageClickTimeout);
                    imageClickCount = 0;
                    
                    console.log('双击图片，进入缩放模式');
                    const overlay = createImageOverlay(currentImg);
                    document.body.appendChild(overlay);
                    
                    // 立即显示，无淡入动画
                    overlay.style.opacity = '1';
                  }
                }
              }
            });

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

            // 切换编辑模式（IR <-> SV 分屏预览）
            let currentEditMode = 'ir'; // 跟踪当前模式，默认为即时渲染(8)
            
            window.__toggleVditorMode = function(){
              try{
                console.log('🔄 开始切换编辑模式...');
                console.log('当前模式:', currentEditMode);
                
                // 首先点击编辑模式按钮打开下拉菜单
                const editModeBtn = document.querySelector('[data-type="edit-mode"]');
                if (editModeBtn) {
                  console.log('找到编辑模式按钮');
                  editModeBtn.click();
                  
                  // 等待下拉菜单出现，然后选择对应的模式
                  setTimeout(() => {
                    if (currentEditMode === 'ir') {
                      // 从 IR(8) 切换到 SV(9) 分屏预览
                      const svBtn = document.querySelector('[data-mode="sv"]');
                      if (svBtn) {
                        console.log('切换到 SV 分屏预览模式');
                        svBtn.click();
                        currentEditMode = 'sv';
                      } else {
                        console.error('❌ 找不到 SV 按钮');
                        // 如果找不到SV按钮，尝试查找所有可用的模式按钮
                        const allModeButtons = document.querySelectorAll('[data-mode]');
                        console.log('可用的模式按钮:', Array.from(allModeButtons).map(btn => btn.getAttribute('data-mode')));
                      }
                    } else {
                      // 从 SV(9) 切换回 IR(8)
                      const irBtn = document.querySelector('[data-mode="ir"]');
                      if (irBtn) {
                        console.log('切换到 IR 即时渲染模式');
                        irBtn.click();
                        currentEditMode = 'ir';
                      } else {
                        console.error('❌ 找不到 IR 按钮');
                      }
                    }
                    
                    console.log('✅ 模式切换完成，当前模式:', currentEditMode);
                  }, 100); // 给下拉菜单一点时间显示
                } else {
                  console.error('❌ 找不到编辑模式切换按钮');
                }
              }catch(e){
                console.error('❌ 切换模式失败:', e);
              }
            };
          })();
          </script>
        </body>
        </html>
        """#
    }
}
