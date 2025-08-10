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
        
        // 允许访问本地文件
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

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
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let wordTaggerURL = documentsURL.appendingPathComponent("WordTagger") // 设置为 WordTagger 目录，支持相对路径 Images/xxx
        
        // 创建临时 HTML 文件以支持本地图片加载
        let tempURL = wordTaggerURL.appendingPathComponent("temp.html")
        try? html.write(to: tempURL, atomically: true, encoding: .utf8)
        
        // 使用 loadFileURL 而不是 loadHTMLString，这样可以正确加载本地资源
        webView.loadFileURL(tempURL, allowingReadAccessTo: wordTaggerURL)

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
                // 转发 Command+E 给原生 App
                DispatchQueue.main.async {
                    // 模拟原生按键事件
                    let event = NSEvent.keyEvent(with: .keyDown,
                                               location: NSPoint.zero,
                                               modifierFlags: .command,
                                               timestamp: 0,
                                               windowNumber: 0,
                                               context: nil,
                                               characters: "e",
                                               charactersIgnoringModifiers: "e",
                                               isARepeat: false,
                                               keyCode: 14) // E 键的 keyCode
                    
                    if let event = event {
                        NSApp.sendEvent(event)
                    }
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
            // 获取文档目录
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            
            // 创建 Images 子目录
            let imagesURL = documentsURL.appendingPathComponent("WordTagger/Images")
            
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
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let fileURL = documentsURL.appendingPathComponent("WordTagger").appendingPathComponent(filename)
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
            } else {
                print("图片文件不存在: \(fileURL.path)")
            }
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
                'Ctrl+E': ''
              },
              after(){
                // 通知 Native：ready
                try { window.webkit?.messageHandlers?.bridge?.postMessage({ type: 'ready' }); } catch(_) {}
                setTimeout(containerFix, 30);
                
                // 拦截 Command+E 并转发给原生 App
                document.addEventListener('keydown', function(e) {
                  if (e.metaKey && (e.key === 'e' || e.key === 'E')) {
                    console.log('拦截 Command+E 快捷键，转发给 App 处理');
                    e.preventDefault();
                    e.stopImmediatePropagation();
                    
                    // 发送消息给原生 App 处理
                    try {
                      window.webkit?.messageHandlers?.bridge?.postMessage({ 
                        type: 'commandE'
                      });
                    } catch(err) {
                      console.error('无法发送 Command+E 事件:', err);
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
            
            // 图片点击处理：只有 Command+点击 才在 Finder 中显示，普通点击不做任何操作
            document.addEventListener('click', function(e) {
              if (e.target.tagName === 'IMG' && e.target.src.includes('Images/')) {
                if (e.metaKey) {
                  // Command+点击：在 Finder 中显示图片
                  e.preventDefault();
                  e.stopPropagation();
                  // 提取文件名
                  const src = e.target.src;
                  const filename = src.split('Images/').pop();
                  // 发送消息给 Swift
                  try {
                    window.webkit?.messageHandlers?.bridge?.postMessage({ 
                      type: 'showImageInFinder',
                      filename: 'Images/' + filename
                    });
                  } catch(err) {
                    console.error('无法打开图片:', err);
                  }
                } else {
                  // 普通点击：阻止默认行为，避免误触
                  e.preventDefault();
                  console.log('普通点击图片，已阻止默认行为。使用 Command+点击 可在 Finder 中显示图片');
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
