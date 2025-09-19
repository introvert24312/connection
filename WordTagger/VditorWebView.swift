import SwiftUI
import WebKit
import AppKit

/// Vditor(IR) 单一渲染管线封装：由 Native 控制主题，并通过 JS 的 __applyNativeTheme(dark) 统一切换
struct VditorWebView: NSViewRepresentable {
    // 输入参数
    var markdown: String
    var nodeId: String
    var onChange: (String) -> Void
    
    // 可选的节点对象，用于节点文件夹功能
    var node: Node?

    // 允许外部持有 Coordinator（例如 DetailPanel 里通过 @State 传引用）
    @Binding var coordinatorBinding: Coordinator?

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - NSViewRepresentable
    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, node: node)
    }

    func makeNSView(context: Context) -> WKWebView {
        // 增强安全配置
        let config = WKWebViewConfiguration()
        let uc = WKUserContentController()
        uc.add(context.coordinator, name: "bridge")
        config.userContentController = uc
        config.suppressesIncrementalRendering = false
        config.preferences.setValue(true, forKey: "developerExtrasEnabled") // 方便调试
        
        // 🔒 安全性增强配置
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        
        // 🚨 防止各种导航问题的安全设置
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.mediaTypesRequiringUserActionForPlayback = []
        
        // 🔒 额外的安全设置
        if #available(macOS 13.0, *) {
            config.preferences.isElementFullscreenEnabled = false  // 禁用元素全屏
        }
        
        // 🛡️ 防止意外的导航和弹窗
        if #available(macOS 11.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        
        // 🔐 iframe安全配置
        config.preferences.setValue(false, forKey: "javaScriptCanAccessClipboard")
        
        print("🔒 WebView安全配置完成")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator // 添加UI委托
        
        // 🚨 WebView级别的媒体安全设置
        webView.allowsBackForwardNavigationGestures = false
        if #available(macOS 11.0, *) {
            webView.allowsMagnification = true
        }

        // macOS: 彻底透明
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.setValue(false, forKey: "opaque")

        // 让 WebView 的 NSAppearance 与当前系统主题一致（首帧避免闪烁）
        let isDark = (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        webView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        // 强制使用外部数据管理器的路径，不提供后备选项
        guard let dataPath = ExternalDataManager.shared.currentDataPath else {
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
        
        // 🎯 尝试在节点文件夹中创建HTML，让相对路径能正常工作
        var tempURL = dataPath.appendingPathComponent("temp.html")
        var allowedPath = dataPath
        
        // 如果有关联的节点，尝试在节点文件夹中创建HTML
        if let node = node,
           let nodeFolderPath = NodeFolderManager.shared.getFolderPath(for: node),
           FileManager.default.fileExists(atPath: nodeFolderPath.path) {
            tempURL = nodeFolderPath.appendingPathComponent(".temp_editor.html")
            allowedPath = dataPath // 仍然允许访问整个数据目录
            print("🎯 在节点文件夹中创建HTML: \(nodeFolderPath.path)")
        }
        
        do {
            try html.write(to: tempURL, atomically: true, encoding: .utf8)
            // 使用 loadFileURL 而不是 loadHTMLString，这样可以正确加载本地资源
            webView.loadFileURL(tempURL, allowingReadAccessTo: allowedPath)
            print("🌐 WebView加载HTML: \(tempURL.path)")
            print("🎯 WebView允许访问路径: \(allowedPath.path)")
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
            // 🚧 临时禁用内容保护机制 - 调试换行符丢失问题
            let currentContent = context.coordinator.latestMarkdown
            let newContent = markdown
            
            print("🔍 内容更新（保护机制已禁用）：")
            print("🔍 当前内容：'\(currentContent)'")
            print("🔍 新内容：'\(newContent)'")
            print("🔍 当前内容长度：\(currentContent.count)，新内容长度：\(newContent.count)")
            
            // 只保留最基本的相同内容检查
            if currentContent == newContent {
                print("🔄 内容相同，跳过更新")
                return
            }
            
            print("✅ 直接更新编辑器内容（无保护）")
            print("🔄 内容更新详情：当前\(currentContent.count)字符 → 新\(newContent.count)字符")
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
        
        // 节点对象，用于节点文件夹功能
        var node: Node?

        // 主题缓存，避免重复注入
        private var lastDarkValue: Bool?

        init(onChange: @escaping (String) -> Void, node: Node? = nil) {
            self.onChange = onChange
            self.node = node
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
                    let loadingId = body["loadingId"] as? String
                    let directMode = body["directMode"] as? Bool ?? false
                    print("🖼️ 收到saveImage请求: fileName=\(fileName), directMode=\(directMode)")
                    saveImageToFile(fileName: fileName, data: imageData, loadingId: loadingId, directMode: directMode)
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
                
            case "commandK":
                // 转发 Command+K 给原生 App - 命令面板
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("showCommandPalette"), object: nil)
                }
                break
                
            case "commandI":
                // 转发 Command+I 给原生 App - 快速添加节点
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("addNewNode"), object: nil)
                }
                break
                
            case "commandD":
                // 转发 Command+D 给原生 App - 在图谱和详情标签间切换
                print("🎯 VditorWebView: 收到 Command+D，发送标签切换通知")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("toggleDetailPanelTab"), object: nil)
                    print("✅ VditorWebView: toggleDetailPanelTab 通知已发送")
                }
                break
                
            case "openURL":
                // 处理超链接点击：在默认浏览器中打开URL
                print("🔗 收到openURL请求，body: \(body)")
                if let urlString = body["url"] as? String {
                    print("🔗 原始URL字符串: '\(urlString)'")
                    
                    // 清理URL字符串
                    let cleanedString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if let url = URL(string: cleanedString) {
                        print("🔗 成功创建URL对象: \(url)")
                        print("🔗 URL方案: \(url.scheme ?? "无"), 主机: \(url.host ?? "无")")
                        
                        DispatchQueue.main.async {
                            print("🔗 准备在主线程中打开URL...")
                            let success = NSWorkspace.shared.open(url)
                            if success {
                                print("✅ 已在默认浏览器中打开链接: \(cleanedString)")
                                // 通过JavaScript确认成功
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    self.evaluateJS("console.log('✅ 链接已成功在浏览器中打开: \(cleanedString)');")
                                }
                            } else {
                                print("❌ NSWorkspace.shared.open 失败: \(cleanedString)")
                                // 尝试其他方式
                                if let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
                                    print("🔗 尝试使用Safari直接打开...")
                                    let configuration = NSWorkspace.OpenConfiguration()
                                    NSWorkspace.shared.open([url], withApplicationAt: safariURL, configuration: configuration, completionHandler: { app, error in
                                        if let error = error {
                                            print("🔗 Safari打开失败: \(error)")
                                        } else {
                                            print("🔗 Safari打开成功: \(String(describing: app))")
                                        }
                                    })
                                } else {
                                    print("❌ 无法找到Safari浏览器")
                                }
                            }
                        }
                    } else {
                        print("❌ 无法从字符串创建URL对象: '\(cleanedString)'")
                        // 尝试编码URL
                        if let encodedString = cleanedString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let encodedURL = URL(string: encodedString) {
                            print("🔗 尝试使用编码后的URL: \(encodedString)")
                            DispatchQueue.main.async {
                                let success = NSWorkspace.shared.open(encodedURL)
                                print("🔗 编码URL打开结果: \(success)")
                            }
                        } else {
                            print("❌ 编码URL也失败")
                        }
                    }
                } else {
                    print("❌ 无效的URL格式，body: \(body)")
                    print("❌ URL字段不是字符串类型或不存在")
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
        
        // 原生图片保存功能 - 优先保存到节点文件夹
        private func saveImageToFile(fileName: String, data: Data, loadingId: String? = nil, directMode: Bool = true) {
            var relativePath: String = ""
            var saveSuccessful = false
            
            // 🎯 优先尝试使用节点文件夹功能
            if let node = self.node {
                print("🖼️ 尝试保存图片到节点文件夹: \(node.text)")
                
                do {
                    // 使用NodeFolderManager保存图片到节点的Images子文件夹
                    let nodeRelativePath = try NodeFolderManager.shared.saveImageToNodeFolder(node, fileName: fileName, data: data)
                    relativePath = nodeRelativePath
                    saveSuccessful = true
                    print("✅ 图片已保存到节点文件夹: \(nodeRelativePath)")
                } catch {
                    print("⚠️ 节点文件夹保存失败，回退到全局Images文件夹: \(error)")
                    // 如果节点文件夹保存失败，回退到全局文件夹
                }
            } else {
                print("ℹ️ 没有关联的节点信息，使用全局Images文件夹")
            }
            
            // 如果节点文件夹保存失败，直接报错，不再使用全局Images文件夹作为后备
            if !saveSuccessful {
                print("❌ 节点文件夹保存失败，且没有关联的节点信息")
                showImageSaveError(fileName: fileName, error: "请先创建节点或检查节点文件夹权限", loadingId: loadingId)
                return
            }
            
            // 插入图片链接
            if saveSuccessful {
                if directMode {
                    print("🚀 使用直接插入模式")
                    nativeInsertImageLink(fileName: fileName, relativePath: relativePath, loadingId: loadingId)
                } else {
                    print("🔄 使用传统回调模式")
                    // 传统模式：通过JavaScript回调更新
                    let jsCallback = "window.__onImageSaved('\(fileName)', '\(relativePath)', '\(loadingId ?? "")');"
                    evaluateJS(jsCallback)
                }
            }
        }
        
        // 🚀 简化版图片链接插入 - 直接插入最终链接，无占位符
        private func nativeInsertImageLink(fileName: String, relativePath: String, loadingId: String?) {
            print("🚀 使用简化机制直接插入图片链接: \(fileName)")
            print("   - 相对路径: \(relativePath)")
            
            guard let webView = webView else {
                print("❌ WebView为nil，无法插入图片链接")
                return
            }
            
            // 生成最终的markdown图片链接
            let imageMarkdown = "![\(fileName)](\(relativePath))"
            print("📝 生成的图片链接: \(imageMarkdown)")
            
            // 🎯 简化策略：直接插入最终图片链接，无需处理占位符
            let escapedImageMarkdown = Self.escapeForJavaScript(imageMarkdown)
            
            let directInsertJS = """
            try {
                // 首先检查Vditor是否可用
                if (!window.vditor) {
                    console.error('❌ window.vditor不存在');
                    return { success: false, error: 'VDITOR_NOT_FOUND' };
                }
                
                if (typeof window.vditor.getValue !== 'function') {
                    console.error('❌ vditor.getValue函数不可用');
                    return { success: false, error: 'GET_VALUE_UNAVAILABLE' };
                }
                
                if (typeof window.vditor.setValue !== 'function') {
                    console.error('❌ vditor.setValue函数不可用');
                    return { success: false, error: 'SET_VALUE_UNAVAILABLE' };
                }
                
                // 清理任何现有的loading占位符
                const imageMarkdown = `\(escapedImageMarkdown)`;
                let currentContent = window.vditor.getValue() || '';
                console.log('🎯 直接插入模式 - 当前内容长度: ' + currentContent.length);
                
                // 移除所有loading占位符
                const loadingPattern = /!\\[加载中\\.\\.\\.\\]\\([^)]+\\)/g;
                const cleanedContent = currentContent.replace(loadingPattern, '');
                console.log('🧹 清理loading占位符: ' + (currentContent.length - cleanedContent.length) + ' 字符被移除');
                
                // 检查是否已经存在相同的图片链接，避免重复插入
                if (cleanedContent.includes(imageMarkdown)) {
                    console.log('⚠️ 图片链接已存在，跳过重复插入');
                    return {
                        success: true,
                        content: cleanedContent,
                        operation: 'DUPLICATE_SKIP'
                    };
                }
                
                // 添加图片链接
                const separator = cleanedContent.endsWith('\\n') ? '' : '\\n';
                const finalContent = cleanedContent + separator + imageMarkdown;
                
                console.log('📎 直接插入图片链接: ' + imageMarkdown);
                
                // 使用setValue更新内容
                window.vditor.setValue(finalContent);
                console.log('✅ 直接插入完成，最终内容长度: ' + finalContent.length);
                
                return {
                    success: true,
                    content: finalContent,
                    operation: 'DIRECT_INSERT'
                };
            } catch(e) {
                console.error('❌ 直接插入异常: ' + e.message);
                console.error('❌ 异常堆栈: ' + e.stack);
                return { success: false, error: e.message, stack: e.stack };
            }
            """
            
            // 执行直接插入操作并立即同步状态
            webView.evaluateJavaScript(directInsertJS) { [weak self] result, error in
                guard let self = self else { 
                    print("❌ self已被释放，无法处理图片插入结果")
                    return 
                }
                
                if let error = error {
                    print("❌ 直接图片插入JavaScript执行失败:")
                    print("   - 错误信息: \(error.localizedDescription)")
                    print("   - 错误代码: \((error as NSError).code)")
                    print("   - 错误域: \((error as NSError).domain)")
                    print("🔄 启动备用插入方案...")
                    self.fallbackImageInsert(imageMarkdown: imageMarkdown, loadingId: loadingId)
                    return
                }
                
                // 解析JavaScript返回的结果
                if let resultDict = result as? [String: Any] {
                    print("📊 JavaScript返回结果: \(resultDict)")
                    
                    if let success = resultDict["success"] as? Bool {
                        if success {
                            let operation = resultDict["operation"] as? String ?? "UNKNOWN"
                            print("🎉 直接插入成功完成: \(operation)")
                            
                            if let finalContent = resultDict["content"] as? String {
                                print("📄 最终内容长度: \(finalContent.count)字符")
                                print("🔍 内容预览: \(String(finalContent.suffix(200)))")
                                
                                // 🚀 关键：立即同步latestMarkdown状态，阻止后续覆盖
                                self.latestMarkdown = finalContent
                                print("🔄 latestMarkdown已同步，长度: \(self.latestMarkdown.count)")
                            }
                            
                            // 发送成功通知
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("imageInsertSuccess"),
                                    object: nil,
                                    userInfo: [
                                        "fileName": fileName,
                                        "relativePath": relativePath,
                                        "operation": operation
                                    ]
                                )
                            }
                        } else {
                            let errorMsg = resultDict["error"] as? String ?? "未知错误"
                            let stack = resultDict["stack"] as? String
                            print("⚠️ 直接插入报告错误: \(errorMsg)")
                            if let stack = stack {
                                print("🔍 错误堆栈: \(stack)")
                            }
                            print("🔄 启动备用插入方案...")
                            self.fallbackImageInsert(imageMarkdown: imageMarkdown, loadingId: loadingId)
                        }
                    } else {
                        print("⚠️ JavaScript结果缺少success字段")
                        print("🔄 启动备用插入方案...")
                        self.fallbackImageInsert(imageMarkdown: imageMarkdown, loadingId: loadingId)
                    }
                } else {
                    print("⚠️ 无法解析直接插入结果为字典:")
                    print("   - 结果类型: \(type(of: result))")
                    print("   - 结果内容: \(String(describing: result))")
                    print("🔄 启动备用插入方案...")
                    self.fallbackImageInsert(imageMarkdown: imageMarkdown, loadingId: loadingId)
                }
            }
        }
        
        // 📋 备用图片插入方案 - 当主要方案失败时使用
        private func fallbackImageInsert(imageMarkdown: String, loadingId: String?) {
            print("🔄 执行备用图片插入方案...")
            
            guard let webView = webView else {
                print("❌ 备用方案失败: WebView为nil")
                return
            }
            
            // 更简单的备用插入方法
            let fallbackJS = """
            try {
                // 尝试多种方式插入内容
                if (window.vditor) {
                    // 方法1: 直接插入值到编辑器
                    if (typeof window.vditor.insertValue === 'function') {
                        window.vditor.insertValue('\(imageMarkdown)');
                        console.log('✅ 备用方案1成功: insertValue');
                        'FALLBACK_INSERT_SUCCESS';
                    }
                    // 方法2: 获取当前内容并追加
                    else if (typeof window.vditor.getValue === 'function' && typeof window.vditor.setValue === 'function') {
                        const current = window.vditor.getValue() || '';
                        const separator = current.endsWith('\\n') ? '' : '\\n';
                        window.vditor.setValue(current + separator + '\(imageMarkdown)');
                        console.log('✅ 备用方案2成功: getValue+setValue');
                        'FALLBACK_APPEND_SUCCESS';
                    } else {
                        console.error('❌ 所有备用方案都失败');
                        'FALLBACK_FAILED';
                    }
                } else {
                    console.error('❌ window.vditor不存在');
                    'FALLBACK_NO_VDITOR';
                }
            } catch(e) {
                console.error('❌ 备用方案异常: ' + e.message);
                'FALLBACK_ERROR: ' + e.message;
            }
            """
            
            webView.evaluateJavaScript(fallbackJS) { result, error in
                if let error = error {
                    print("❌ 备用图片插入方案也失败: \(error.localizedDescription)")
                    print("💥 所有图片插入方案均失败，需要用户手动刷新或检查WebView状态")
                } else {
                    let resultString = result as? String ?? "nil"
                    print("🔄 备用方案执行结果: \(resultString)")
                    
                    if resultString.contains("SUCCESS") {
                        print("✅ 备用方案成功挽救了图片插入！")
                    } else {
                        print("💥 备用方案最终失败: \(resultString)")
                    }
                }
            }
        }
        
        // 显示图片保存错误
        private func showImageSaveError(fileName: String, error: String, loadingId: String?) {
            // 尝试通过JavaScript显示错误
            let loadingIdParam = loadingId != nil ? "'\(loadingId!)'" : "null"
            evaluateJS("window.__onImageSaveError && window.__onImageSaveError('\(fileName)', '\(error)', \(loadingIdParam));")
            
            // 同时通过原生方式显示错误（备用）
            DispatchQueue.main.async {
                // 可以在这里添加原生错误提示，比如通知或弹窗
                NotificationCenter.default.post(
                    name: NSNotification.Name("imageInsertError"),
                    object: nil,
                    userInfo: [
                        "fileName": fileName,
                        "error": error
                    ]
                )
            }
        }
        
        // 在 Finder 中显示图片
        private func showImageInFinder(filename: String) {
            print("🔍 showImageInFinder 调试信息:")
            print("   - 收到的filename: '\(filename)'")
            
            // 只在节点文件夹中查找图片
            guard let node = self.node else {
                print("❌ 没有关联的节点，无法查找图片")
                return
            }
            
            guard let nodeFolderPath = NodeFolderManager.shared.getFolderPath(for: node) else {
                print("❌ 无法获取节点文件夹路径")
                return
            }
            
            print("   - 节点文件夹路径: \(nodeFolderPath.path)")
            
            // 清理文件名（移除可能的旧格式前缀和URL编码）
            var cleanFilename = filename.replacingOccurrences(of: "Images/", with: "")
            cleanFilename = cleanFilename.removingPercentEncoding ?? cleanFilename
            
            print("   - 清理后的文件名: '\(cleanFilename)'")
            
            let imageURL = nodeFolderPath.appendingPathComponent(cleanFilename)
            print("   - 完整图片路径: \(imageURL.path)")
            
            // 列出节点文件夹中的所有文件，帮助调试
            do {
                let folderContents = try FileManager.default.contentsOfDirectory(atPath: nodeFolderPath.path)
                print("   - 节点文件夹内容: \(folderContents)")
            } catch {
                print("   - 无法列出文件夹内容: \(error)")
            }
            
            if FileManager.default.fileExists(atPath: imageURL.path) {
                NSWorkspace.shared.selectFile(imageURL.path, inFileViewerRootedAtPath: imageURL.deletingLastPathComponent().path)
                print("✅ 在Finder中显示图片: \(imageURL.path)")
            } else {
                print("❌ 图片文件不存在: \(imageURL.path)")
                print("   - 节点: \(node.text)")
                print("   - 节点文件夹: \(nodeFolderPath.path)")
                
                // 尝试模糊匹配文件名（忽略扩展名）
                let baseName = (cleanFilename as NSString).deletingPathExtension
                print("   - 尝试模糊匹配，基础名称: '\(baseName)'")
                
                do {
                    let folderContents = try FileManager.default.contentsOfDirectory(atPath: nodeFolderPath.path)
                    let matchingFiles = folderContents.filter { file in
                        let fileBaseName = (file as NSString).deletingPathExtension
                        return fileBaseName.contains(baseName) || baseName.contains(fileBaseName)
                    }
                    
                    if let matchedFile = matchingFiles.first {
                        let matchedURL = nodeFolderPath.appendingPathComponent(matchedFile)
                        NSWorkspace.shared.selectFile(matchedURL.path, inFileViewerRootedAtPath: matchedURL.deletingLastPathComponent().path)
                        print("✅ 模糊匹配成功，在Finder中显示: \(matchedURL.path)")
                    } else {
                        print("❌ 模糊匹配也未找到相关文件")
                    }
                } catch {
                    print("❌ 模糊匹配时读取文件夹失败: \(error)")
                }
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
        
        // MARK: - 🔗 增强型链接导航拦截系统
        
        /// 完整的导航决策处理，100%拦截外部链接并防止各种导航问题
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            
            // 获取目标URL和框架信息
            guard let url = navigationAction.request.url else {
                print("🔗 [NAV] 导航拦截: 无效的URL")
                decisionHandler(.allow)
                return
            }
            
            let urlString = url.absoluteString
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
            let navigationType = navigationAction.navigationType
            let sourceFrame = navigationAction.sourceFrame
            
            // 详细日志记录
            print("🔗 [NAV] ==================== 导航请求分析 ====================")
            print("🔗 [NAV] URL: \(urlString)")
            print("🔗 [NAV] 导航类型: \(navigationType.rawValue) (\(navigationTypeDescription(navigationType)))")
            print("🔗 [NAV] 是否为主框架: \(isMainFrame)")
            print("🔗 [NAV] 目标框架: \(navigationAction.targetFrame?.description ?? "nil")")
            print("🔗 [NAV] 源框架: \(sourceFrame.description)")
            print("🔗 [NAV] 请求方法: \(navigationAction.request.httpMethod ?? "nil")")
            print("🔗 [NAV] 请求头: \(navigationAction.request.allHTTPHeaderFields ?? [:])")
            
            // 1. 允许编辑器本身的页面加载
            if isEditorPageLoad(urlString) {
                print("🔗 [NAV] ✅ 允许: 编辑器页面加载")
                decisionHandler(.allow)
                return
            }
            
            // 2. 🚨 特别处理子框架导航 - 防止SOAuthorizationCoordinator错误
            if !isMainFrame {
                print("🔗 [NAV] ⚠️ 检测到子框架导航，分析处理策略...")
                
                // 优先检查OAuth授权URL - 这是最常见的SOAuthorizationCoordinator错误源
                if isOAuthOrAuthorizationURL(url) {
                    print("🔗 [NAV] 🚨 子框架中检测到OAuth URL，强制阻止防止SOAuthorizationCoordinator错误")
                    decisionHandler(.cancel)
                    
                    // 发送特殊通知
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("subframeOAuthBlocked"),
                            object: nil,
                            userInfo: [
                                "url": urlString,
                                "reason": "Subframe OAuth navigation blocked to prevent SOAuthorizationCoordinator error"
                            ]
                        )
                    }
                    
                    // 在外部浏览器中打开
                    openInExternalBrowser(url: url, context: "子框架OAuth阻止")
                    return
                }
                
                // 检查是否为Vditor内部iframe
                if isVditorInternalFrame(urlString) {
                    print("🔗 [NAV] ✅ 允许: Vditor内部iframe导航")
                    decisionHandler(.allow)
                    return
                }
                
                // 检查是否为外部链接的子框架导航
                if isExternalURL(urlString) {
                    print("🔗 [NAV] 🚨 阻止: 子框架中的外部链接导航 (防止SOAuthorizationCoordinator错误)")
                    decisionHandler(.cancel)
                    
                    // 在外部浏览器中打开
                    openInExternalBrowser(url: url, context: "子框架外部链接")
                    return
                }
                
                // 其他子框架导航（如about:blank等）
                print("🔗 [NAV] ✅ 允许: 子框架内部导航")
                decisionHandler(.allow)
                return
            }
            
            // 3. 🚨 主框架中也检查OAuth URL
            if isOAuthOrAuthorizationURL(url) {
                print("🔗 [NAV] 🚨 主框架中检测到OAuth URL，阻止以防止授权流程干扰")
                decisionHandler(.cancel)
                
                // 发送通知
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("mainframeOAuthBlocked"),
                        object: nil,
                        userInfo: [
                            "url": urlString,
                            "navigationType": navigationType.rawValue,
                            "reason": "Mainframe OAuth navigation blocked to prevent authorization flow interference"
                        ]
                    )
                }
                
                openInExternalBrowser(url: url, context: "主框架OAuth阻止")
                return
            }
            
            // 4. 🎯 主框架导航处理
            switch navigationType {
            case .linkActivated:
                print("🔗 [NAV] 🎯 链接激活导航")
                handleLinkActivatedNavigation(url: url, urlString: urlString, decisionHandler: decisionHandler)
                
            case .formSubmitted:
                print("🔗 [NAV] 📝 表单提交导航")
                handleFormSubmittedNavigation(url: url, urlString: urlString, decisionHandler: decisionHandler)
                
            case .backForward:
                print("🔗 [NAV] ⬅️➡️ 前进后退导航")
                decisionHandler(.cancel) // 阻止前进后退，保持在编辑器中
                
            case .reload:
                print("🔗 [NAV] 🔄 页面重载")
                if isEditorPageLoad(urlString) {
                    decisionHandler(.allow)
                } else {
                    decisionHandler(.cancel)
                }
                
            case .formResubmitted:
                print("🔗 [NAV] 📝 表单重新提交")
                decisionHandler(.cancel) // 阻止表单重新提交
                
            case .other:
                print("🔗 [NAV] 🔧 其他类型导航")
                handleOtherNavigation(url: url, urlString: urlString, decisionHandler: decisionHandler)
                
            @unknown default:
                print("🔗 [NAV] ❓ 未知导航类型")
                // 对于未知类型，采用保守策略
                if isExternalURL(urlString) {
                    decisionHandler(.cancel)
                    openInExternalBrowser(url: url, context: "未知导航类型")
                } else {
                    decisionHandler(.allow)
                }
            }
        }
        
        // MARK: - 导航类型处理方法
        
        /// 处理链接激活导航
        private func handleLinkActivatedNavigation(url: URL, urlString: String, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if isExternalURL(urlString) {
                print("🔗 [NAV] 🚨 阻止: 外部链接激活")
                decisionHandler(.cancel)
                openInExternalBrowser(url: url, context: "链接激活")
            } else {
                print("🔗 [NAV] ✅ 允许: 内部链接激活")
                decisionHandler(.allow)
            }
        }
        
        /// 处理表单提交导航
        private func handleFormSubmittedNavigation(url: URL, urlString: String, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if isExternalURL(urlString) {
                print("🔗 [NAV] 🚨 阻止: 外部表单提交")
                decisionHandler(.cancel)
                openInExternalBrowser(url: url, context: "表单提交")
            } else {
                print("🔗 [NAV] ✅ 允许: 内部表单提交")
                decisionHandler(.allow)
            }
        }
        
        /// 处理其他类型导航
        private func handleOtherNavigation(url: URL, urlString: String, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // 检查是否为JavaScript重定向等
            if isExternalURL(urlString) {
                print("🔗 [NAV] 🚨 阻止: 其他类型的外部导航")
                decisionHandler(.cancel)
                openInExternalBrowser(url: url, context: "其他导航")
            } else if urlString.contains("javascript:") {
                print("🔗 [NAV] 🚨 阻止: JavaScript URL")
                decisionHandler(.cancel)
            } else {
                print("🔗 [NAV] ✅ 允许: 其他内部导航")
                decisionHandler(.allow)
            }
        }
        
        // MARK: - URL判断辅助方法
        
        /// 判断是否为编辑器页面加载
        private func isEditorPageLoad(_ urlString: String) -> Bool {
            return urlString.contains("temp.html") || 
                   urlString.contains(".temp_editor.html") ||
                   urlString.hasPrefix("file://") && urlString.contains("html")
        }
        
        /// 判断是否为外部URL
        private func isExternalURL(_ urlString: String) -> Bool {
            return urlString.hasPrefix("http://") ||
                   urlString.hasPrefix("https://") ||
                   urlString.hasPrefix("mailto:") ||
                   urlString.hasPrefix("tel:") ||
                   urlString.hasPrefix("sms:") ||
                   urlString.hasPrefix("facetime:") ||
                   urlString.hasPrefix("skype:") ||
                   urlString.hasPrefix("zoom:") ||
                   urlString.hasPrefix("slack:") ||
                   urlString.hasPrefix("discord:") ||
                   urlString.hasPrefix("spotify:") ||
                   urlString.hasPrefix("music:")
        }
        
        /// 判断是否为Vditor内部框架（白名单机制）
        private func isVditorInternalFrame(_ urlString: String) -> Bool {
            let allowedFramePatterns = [
                "about:blank",
                "data:text/html",
                "blob:",
                "javascript:void(0)",
                ""
            ]
            
            // 🎯 允许PlantUML图表渲染服务
            if urlString.contains("plantuml.com") && urlString.contains("/svg/") {
                return true
            }
            
            // 严格的白名单检查
            for pattern in allowedFramePatterns {
                if urlString == pattern || (pattern.isEmpty && urlString.isEmpty) {
                    return true
                }
            }
            
            // 特别检查Vditor相关的安全iframe
            if urlString.contains("vditor") && (
                urlString.contains("localhost") ||
                urlString.contains("127.0.0.1") ||
                urlString.hasPrefix("file://")
            ) {
                return true
            }
            
            return false
        }
        
        /// 检测OAuth授权相关URL（防止SOAuthorizationCoordinator错误）
        private func isOAuthOrAuthorizationURL(_ url: URL) -> Bool {
            let urlString = url.absoluteString.lowercased()
            let host = url.host?.lowercased() ?? ""
            
            // OAuth关键词检测
            let oauthKeywords = [
                "oauth", "authorize", "authorization", "auth", "login", "signin", 
                "sso", "openid", "connect", "callback", "redirect"
            ]
            
            // OAuth相关参数检测
            let oauthParams = [
                "client_id=", "response_type=", "redirect_uri=", "scope=",
                "state=", "code_challenge=", "access_token=", "id_token="
            ]
            
            // 知名OAuth提供商域名
            let oauthDomains = [
                "accounts.google.com", "login.microsoftonline.com", "github.com",
                "oauth.twitter.com", "facebook.com", "apple.com", "linkedin.com",
                "discord.com", "slack.com", "dropbox.com", "spotify.com"
            ]
            
            // 检查URL路径中的OAuth关键词
            let pathAndQuery = url.path + (url.query ?? "")
            for keyword in oauthKeywords {
                if pathAndQuery.contains(keyword) {
                    print("🔗 [OAUTH] 检测到OAuth关键词: \(keyword)")
                    return true
                }
            }
            
            // 检查URL参数中的OAuth标识
            for param in oauthParams {
                if urlString.contains(param) {
                    print("🔗 [OAUTH] 检测到OAuth参数: \(param)")
                    return true
                }
            }
            
            // 检查已知OAuth域名
            for domain in oauthDomains {
                if host.contains(domain) {
                    print("🔗 [OAUTH] 检测到OAuth域名: \(domain)")
                    return true
                }
            }
            
            return false
        }
        
        /// 在外部浏览器中打开URL
        private func openInExternalBrowser(url: URL, context: String) {
            DispatchQueue.main.async { [weak self] in
                print("🔗 [NAV] 🌐 在外部浏览器打开链接: \(url.absoluteString) (上下文: \(context))")
                
                let success = NSWorkspace.shared.open(url)
                if success {
                    print("🔗 [NAV] ✅ 成功在默认浏览器打开: \(url.absoluteString)")
                    
                    // 发送成功通知
                    NotificationCenter.default.post(
                        name: NSNotification.Name("externalLinkOpened"),
                        object: nil,
                        userInfo: [
                            "url": url.absoluteString,
                            "context": context,
                            "success": true
                        ]
                    )
                } else {
                    print("🔗 [NAV] ❌ 默认浏览器打开失败，尝试Safari...")
                    self?.openInSafari(url: url, context: context)
                }
            }
        }
        
        /// 使用Safari打开URL（备用方案）
        private func openInSafari(url: URL, context: String) {
            if let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
                let configuration = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open([url], withApplicationAt: safariURL, configuration: configuration) { app, error in
                    if let error = error {
                        print("🔗 [NAV] ❌ Safari打开失败: \(error.localizedDescription)")
                        
                        // 发送失败通知
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("externalLinkOpened"),
                                object: nil,
                                userInfo: [
                                    "url": url.absoluteString,
                                    "context": context,
                                    "success": false,
                                    "error": error.localizedDescription
                                ]
                            )
                        }
                    } else {
                        print("🔗 [NAV] ✅ Safari打开成功: \(url.absoluteString)")
                        
                        // 发送成功通知
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("externalLinkOpened"),
                                object: nil,
                                userInfo: [
                                    "url": url.absoluteString,
                                    "context": context,
                                    "success": true,
                                    "method": "Safari"
                                ]
                            )
                        }
                    }
                }
            } else {
                print("🔗 [NAV] ❌ 无法找到Safari浏览器")
                
                // 最后的备用方案：尝试系统默认方式
                DispatchQueue.main.async {
                    if NSWorkspace.shared.open(url) {
                        print("🔗 [NAV] ✅ 系统默认方式打开成功")
                    } else {
                        print("🔗 [NAV] ❌ 所有打开方式均失败")
                    }
                }
            }
        }
        
        /// 获取导航类型描述
        private func navigationTypeDescription(_ type: WKNavigationType) -> String {
            switch type {
            case .linkActivated: return "链接激活"
            case .formSubmitted: return "表单提交"
            case .backForward: return "前进后退"
            case .reload: return "页面重载"
            case .formResubmitted: return "表单重新提交"
            case .other: return "其他类型"
            @unknown default: return "未知类型"
            }
        }
        
        // MARK: - 🚨 iframe和子框架特殊处理
        
        /// 处理子框架的导航策略决策 - 防止SOAuthorizationCoordinator错误
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            
            print("🔗 [IFRAME] ==================== 子框架导航策略分析 ====================")
            
            guard let url = navigationAction.request.url else {
                print("🔗 [IFRAME] 无效URL，允许导航")
                decisionHandler(.allow, preferences)
                return
            }
            
            let urlString = url.absoluteString
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
            
            print("🔗 [IFRAME] URL: \(urlString)")
            print("🔗 [IFRAME] 是否主框架: \(isMainFrame)")
            print("🔗 [IFRAME] 导航类型: \(navigationTypeDescription(navigationAction.navigationType))")
            
            // 主框架导航使用标准处理流程
            if isMainFrame {
                print("🔗 [IFRAME] 主框架导航，转向标准处理")
                // 调用标准的decidePolicyFor方法
                self.webView(webView, decidePolicyFor: navigationAction) { policy in
                    decisionHandler(policy, preferences)
                }
                return
            }
            
            // 🚨 子框架导航特殊处理
            print("🔗 [IFRAME] ⚠️ 子框架导航检测")
            
            // 检查是否为Vditor编辑器内部的合法iframe
            if isVditorInternalFrame(urlString) {
                print("🔗 [IFRAME] ✅ 允许Vditor内部iframe导航")
                
                // 为Vditor内部iframe设置适当的偏好设置
                preferences.allowsContentJavaScript = true
                preferences.preferredContentMode = .recommended
                
                decisionHandler(.allow, preferences)
                return
            }
            
            // 🚨 检查是否为外部链接在子框架中的导航 - 这是SOAuthorizationCoordinator错误的常见原因
            if isExternalURL(urlString) {
                print("🔗 [IFRAME] 🚨 检测到子框架中的外部链接导航")
                print("🔗 [IFRAME] 🚨 这可能导致SOAuthorizationCoordinator错误，强制阻止")
                
                // 强制取消子框架中的外部导航
                decisionHandler(.cancel, preferences)
                
                // 在主线程中通过外部浏览器打开
                DispatchQueue.main.async { [weak self] in
                    self?.openInExternalBrowser(url: url, context: "子框架外部链接拦截")
                }
                
                return
            }
            
            // 🎯 检查潜在的授权流程URL - 特别防护SOAuthorizationCoordinator
            if isPotentialOAuthURL(urlString) {
                print("🔗 [IFRAME] 🚨 检测到潜在OAuth授权URL在子框架中")
                print("🔗 [IFRAME] 🚨 为防止SOAuthorizationCoordinator错误，阻止此导航")
                
                decisionHandler(.cancel, preferences)
                
                // 记录OAuth拦截事件
                NotificationCenter.default.post(
                    name: NSNotification.Name("oauthNavigationBlocked"),
                    object: nil,
                    userInfo: [
                        "url": urlString,
                        "reason": "子框架OAuth导航防护",
                        "timestamp": Date().timeIntervalSince1970
                    ]
                )
                
                return
            }
            
            // 🎯 其他子框架导航（如about:blank, data URL等）
            if urlString.isEmpty || 
               urlString == "about:blank" || 
               urlString.starts(with: "data:") ||
               urlString.starts(with: "javascript:") {
                print("🔗 [IFRAME] ✅ 允许内部子框架导航: \(urlString)")
                
                // 为内部导航设置安全的偏好设置
                preferences.allowsContentJavaScript = urlString.starts(with: "javascript:") || urlString.isEmpty
                preferences.preferredContentMode = .recommended
                
                decisionHandler(.allow, preferences)
                return
            }
            
            // 🚨 未知类型的子框架导航 - 采用保守策略
            print("🔗 [IFRAME] ⚠️ 未知类型的子框架导航，采用保守策略")
            print("🔗 [IFRAME] URL模式分析:")
            print("🔗 [IFRAME] - 是否包含域名: \(urlString.contains("."))")
            print("🔗 [IFRAME] - 是否本地文件: \(urlString.starts(with: "file://"))")
            
            // 本地文件或相对路径允许
            if urlString.starts(with: "file://") || !urlString.contains("://") {
                print("🔗 [IFRAME] ✅ 允许本地或相对路径导航")
                decisionHandler(.allow, preferences)
            } else {
                print("🔗 [IFRAME] 🚨 阻止可疑的子框架导航")
                decisionHandler(.cancel, preferences)
            }
        }
        
        /// 检查是否为潜在的OAuth授权URL
        private func isPotentialOAuthURL(_ urlString: String) -> Bool {
            let oauthKeywords = [
                "oauth", "auth", "login", "signin", "sso", "authorize", "authorization",
                "connect", "callback", "redirect", "token", "access_token",
                "google.com/oauth", "facebook.com/dialog", "github.com/login",
                "microsoft.com/oauth", "apple.com/auth", "twitter.com/oauth",
                "linkedin.com/oauth", "discord.com/oauth", "slack.com/oauth"
            ]
            
            let lowercaseURL = urlString.lowercased()
            return oauthKeywords.contains { lowercaseURL.contains($0) }
        }
        
        // MARK: - 🔗 WebView其他导航相关代理方法
        
        /// 处理导航响应策略 - 额外的安全检查
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            
            guard let url = navigationResponse.response.url else {
                decisionHandler(.allow)
                return
            }
            
            let urlString = url.absoluteString
            print("🔗 [RESPONSE] 导航响应策略检查: \(urlString)")
            
            // 检查HTTP状态码
            if let httpResponse = navigationResponse.response as? HTTPURLResponse {
                print("🔗 [RESPONSE] HTTP状态码: \(httpResponse.statusCode)")
                
                // 检查是否为重定向到外部URL
                if httpResponse.statusCode >= 300 && httpResponse.statusCode < 400 {
                    if let location = httpResponse.allHeaderFields["Location"] as? String {
                        print("🔗 [RESPONSE] 检测到重定向: \(location)")
                        
                        if isExternalURL(location) {
                            print("🔗 [RESPONSE] 🚨 阻止重定向到外部URL")
                            decisionHandler(.cancel)
                            
                            if let redirectURL = URL(string: location) {
                                openInExternalBrowser(url: redirectURL, context: "HTTP重定向拦截")
                            }
                            return
                        }
                    }
                }
                
                // 检查Content-Type是否安全
                if let contentType = httpResponse.allHeaderFields["Content-Type"] as? String {
                    print("🔗 [RESPONSE] Content-Type: \(contentType)")
                    
                    // 阻止潜在的恶意内容类型
                    if contentType.contains("application/octet-stream") && isExternalURL(urlString) {
                        print("🔗 [RESPONSE] 🚨 阻止外部二进制内容下载")
                        decisionHandler(.cancel)
                        return
                    }
                }
            }
            
            // 最终检查：确保不是外部URL
            if isExternalURL(urlString) && !isEditorPageLoad(urlString) && !isVditorInternalFrame(urlString) {
                print("🔗 [RESPONSE] 🚨 最终检查：阻止外部URL响应")
                decisionHandler(.cancel)
                openInExternalBrowser(url: url, context: "响应阶段拦截")
            } else {
                print("🔗 [RESPONSE] ✅ 允许导航响应")
                decisionHandler(.allow)
            }
        }
        
        /// 处理导航错误
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("🔗 [ERROR] 导航失败: \(error.localizedDescription)")
            
            // 检查是否为链接拦截相关的错误
            if (error as NSError).code == NSURLErrorCancelled {
                print("🔗 [ERROR] 导航被取消（可能是链接拦截）")
            } else {
                print("🔗 [ERROR] 其他导航错误: \((error as NSError).code)")
            }
            
            // 发送错误通知
            NotificationCenter.default.post(
                name: NSNotification.Name("webViewNavigationError"),
                object: nil,
                userInfo: [
                    "error": error,
                    "timestamp": Date().timeIntervalSince1970
                ]
            )
        }
        
        // 简化的JavaScript执行助手（移除了图片回调失败处理）
        private func evaluateJS(_ js: String, delayMS: Int = 0) {
            guard let webView = webView else { 
                print("❌ evaluateJS: webView为nil")
                return 
            }
            
            let executeJS = { [weak webView] in
                guard let webView = webView else { 
                    print("❌ evaluateJS: webView已被释放")
                    return 
                }
                
                print("🔄 执行JavaScript: \(js.prefix(100))...")
                webView.evaluateJavaScript(js) { result, error in
                    if let error = error {
                        print("❌ JavaScript执行失败: \(error.localizedDescription)")
                        print("   JS代码: \(js)")
                    } else {
                        print("✅ JavaScript执行成功")
                        if let result = result {
                            print("   返回值: \(result)")
                        }
                    }
                }
            }
            
            if delayMS <= 0 {
                executeJS()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMS)) {
                    executeJS()
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
            :root { 
              --bg: transparent; 
              --bg-dark: #292A2B; /* Tanda暗色背景 */
              --mmd-font: 20px; 
            }
            html, body { 
              margin:0; 
              padding:0; 
              background: var(--bg); 
              transition: background-color 0.3s ease;
            }
            
            /* 暗色模式下的根背景 */
            html.vditor--dark, 
            body.vditor--dark,
            html[data-theme="dark"],
            body[data-theme="dark"] { 
              background: var(--bg-dark) !important; 
            }
            
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

            /* --- Tanda风格暗色主题优化 --- */
            .vditor--dark .vditor-reset { 
              color: #E6E6E6; /* Tanda的主文本颜色 */
            }
            
            /* 标题样式 - GitHub风格，统一颜色不同大小 */
            .vditor--dark .vditor-reset h1 { 
              color: #f0f6fc !important; /* 统一的亮白色 */
              font-weight: 600;
              font-size: 2em;
              margin-top: 24px;
              margin-bottom: 16px;
              padding-bottom: 0.3em;
              border-bottom: 1px solid #30363d;
            }
            .vditor--dark .vditor-reset h2 { 
              color: #f0f6fc !important;
              font-weight: 600;
              font-size: 1.5em;
              margin-top: 24px;
              margin-bottom: 16px;
              padding-bottom: 0.3em;
              border-bottom: 1px solid #30363d;
            }
            .vditor--dark .vditor-reset h3 { 
              color: #f0f6fc !important;
              font-weight: 600;
              font-size: 1.25em;
              margin-top: 24px;
              margin-bottom: 16px;
            }
            .vditor--dark .vditor-reset h4 { 
              color: #f0f6fc !important;
              font-weight: 600;
              font-size: 1em;
              margin-top: 24px;
              margin-bottom: 16px;
            }
            .vditor--dark .vditor-reset h5 { 
              color: #f0f6fc !important;
              font-weight: 600;
              font-size: 0.875em;
              margin-top: 24px;
              margin-bottom: 16px;
            }
            .vditor--dark .vditor-reset h6 { 
              color: #8b949e !important; /* 稍微暗一点，表示最低层级 */
              font-weight: 600;
              font-size: 0.85em;
              margin-top: 24px;
              margin-bottom: 16px;
            }
            
            /* 链接颜色 - 使用Tanda的蓝色 */
            .vditor--dark .vditor-reset a { 
              color: #6FC1FF !important; /* Tanda的链接颜色 */
            }
            .vditor--dark .vditor-reset a:hover { 
              color: #ffffff !important; /* Tanda的悬停颜色 */
            }
            
            /* 行内代码 - 使用Tanda的特殊蓝色背景 */
            .vditor--dark .vditor-reset code {
              background: #135779 !important; /* Tanda的行内代码背景色 */
              color: #E6E6E6 !important;
              padding: 0.3em;
              padding-top: 0.15em;
              padding-bottom: 0.15em;
              border: 2px solid #292A2B;
              border-radius: 0.25rem;
            }
            
            /* 代码块 - 淡色背景加边框，与主背景略有区分 */
            .vditor--dark .vditor-reset pre,
            .vditor--dark .vditor-ir__node pre,
            .vditor--dark .vditor-sv pre,
            .vditor--dark .vditor-wysiwyg pre {
              background: rgba(255, 255, 255, 0.03) !important; /* 非常淡的白色背景，与主背景形成细微差别 */
              color: #E6E6E6 !important;
              border: 2px solid #555 !important; /* 边框 */
              border-radius: 6px;
            }
            
            /* 代码文本 - 继承父容器背景和边框 */
            .vditor--dark .vditor-reset pre code,
            .vditor--dark .vditor-ir__node pre code,
            .vditor--dark .vditor-sv pre code,
            .vditor--dark .vditor-wysiwyg pre code {
              background: inherit !important; /* 继承父容器的淡色背景 */
              color: inherit;
              border: 2px solid #555 !important; /* 边框 */
              border-radius: 6px;
            }
            
            /* CodeMirror代码编辑器背景 */
            .vditor--dark .CodeMirror,
            .vditor--dark .CodeMirror-lines,
            .vditor--dark .CodeMirror-scroll,
            .vditor--dark .CodeMirror-gutter {
              background: #292A2B !important;
              color: #E6E6E6 !important;
            }
            
            /* hljs代码高亮 - 淡色背景加边框 */
            .vditor--dark .hljs {
              background: rgba(255, 255, 255, 0.03) !important; /* 与pre容器相同的淡色背景 */
              border: 2px solid #555 !important; /* 边框 */
              border-radius: 6px;
            }
            
            /* 引用块 - 使用Tanda的样式 */
            .vditor--dark .vditor-reset blockquote {
              border-left: 4px solid #6FC1FF !important; /* Tanda的蓝色边框 */
              background: #303233 !important; /* Tanda的背景色 */
              color: #a8a8a8 !important; /* 稍微暗一点的文字 */
              padding: 4px 15px;
              margin: 1em 0;
            }
            
            /* 表格样式 - 模仿Tanda */
            .vditor--dark .vditor-reset table {
              border-collapse: collapse;
              margin: 1em 0;
              background: #303233; /* Tanda的表格背景 */
            }
            .vditor--dark .vditor-reset table th {
              background: #222324 !important; /* Tanda的表头背景 */
              color: #E6E6E6 !important;
              border: 2px solid #555 !important;
              padding: 6px 13px;
            }
            .vditor--dark .vditor-reset table td {
              border: 2px solid #555 !important;
              color: #E6E6E6 !important;
              padding: 6px 13px;
            }
            .vditor--dark .vditor-reset table tr:nth-child(even) {
              background: #303233 !important;
            }
            .vditor--dark .vditor-reset table tr:nth-child(odd) {
              background: #303233 !important;
            }
            
            /* 水平分割线 */
            .vditor--dark .vditor-reset hr {
              border: 0;
              height: 2px;
              background: #E6E6E6;
              margin: 2em 0;
            }
            
            /* 列表样式优化 */
            .vditor--dark .vditor-reset ul,
            .vditor--dark .vditor-reset ol {
              padding-left: 30px;
              color: #E6E6E6;
            }
            
            /* 强调文本 */
            .vditor--dark .vditor-reset strong {
              color: #ffffff !important;
              font-weight: bold;
            }
            .vditor--dark .vditor-reset em {
              color: #ffffff !important;
              font-style: italic;
            }
            
            /* 高亮文本 */
            .vditor--dark .vditor-reset mark {
              background: #ffd93d !important; /* 使用黄色高亮 */
              color: #000000 !important;
              padding: 1px 3px;
              border-radius: 3px;
            }
            
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
            
            /* 🎯 PlantUML图表居中显示 - 适用于所有编辑模式和PlantUML格式 */
            .vditor-wysiwyg img[src*="plantuml.com"],
            .vditor-ir img[src*="plantuml.com"],
            .vditor-sv img[src*="plantuml.com"],
            .vditor-reset img[src*="plantuml.com"],
            .vditor-preview img[src*="plantuml.com"],
            /* 本地PlantUML服务器 */
            .vditor-wysiwyg img[src*="plantuml"],
            .vditor-ir img[src*="plantuml"],
            .vditor-sv img[src*="plantuml"],
            .vditor-reset img[src*="plantuml"],
            .vditor-preview img[src*="plantuml"],
            /* PlantUML文件扩展名 */
            .vditor-wysiwyg img[src$=".puml"],
            .vditor-ir img[src$=".puml"],
            .vditor-sv img[src$=".puml"],
            .vditor-reset img[src$=".puml"],
            .vditor-preview img[src$=".puml"],
            .vditor-wysiwyg img[src$=".plantuml"],
            .vditor-ir img[src$=".plantuml"],
            .vditor-sv img[src$=".plantuml"],
            .vditor-reset img[src$=".plantuml"],
            .vditor-preview img[src$=".plantuml"] {
              display: block !important;
              margin: 16px auto !important;
              max-width: 100% !important;
              height: auto !important;
              text-align: center !important;
            }
            
            /* PlantUML图表在深色模式下的优化 */
            .vditor--dark .vditor-wysiwyg img[src*="plantuml.com"],
            .vditor--dark .vditor-ir img[src*="plantuml.com"],
            .vditor--dark .vditor-sv img[src*="plantuml.com"],
            .vditor--dark .vditor-reset img[src*="plantuml.com"],
            .vditor--dark .vditor-preview img[src*="plantuml.com"],
            .vditor--dark .vditor-wysiwyg img[src*="plantuml"],
            .vditor--dark .vditor-ir img[src*="plantuml"],
            .vditor--dark .vditor-sv img[src*="plantuml"],
            .vditor--dark .vditor-reset img[src*="plantuml"],
            .vditor--dark .vditor-preview img[src*="plantuml"],
            .vditor--dark .vditor-wysiwyg img[src$=".puml"],
            .vditor--dark .vditor-ir img[src$=".puml"],
            .vditor--dark .vditor-sv img[src$=".puml"],
            .vditor--dark .vditor-reset img[src$=".puml"],
            .vditor--dark .vditor-preview img[src$=".puml"],
            .vditor--dark .vditor-wysiwyg img[src$=".plantuml"],
            .vditor--dark .vditor-ir img[src$=".plantuml"],
            .vditor--dark .vditor-sv img[src$=".plantuml"],
            .vditor--dark .vditor-reset img[src$=".plantuml"],
            .vditor--dark .vditor-preview img[src$=".plantuml"] {
              display: block !important;
              margin: 16px auto !important;
              max-width: 100% !important;
              height: auto !important;
              border-radius: 8px !important;
              box-shadow: 0 2px 8px rgba(0,0,0,0.3) !important;
              text-align: center !important;
            }
            
            /* 🎯 通用图表居中样式 - 确保所有图表都居中显示 */
            .vditor-wysiwyg p img,
            .vditor-ir p img,
            .vditor-sv p img,
            .vditor-reset p img,
            .vditor-preview p img {
              display: block !important;
              margin-left: auto !important;
              margin-right: auto !important;
            }
            
            /* 确保包含PlantUML图表的段落也居中 */
            .vditor-wysiwyg p:has(img[src*="plantuml"]),
            .vditor-ir p:has(img[src*="plantuml"]),
            .vditor-sv p:has(img[src*="plantuml"]),
            .vditor-reset p:has(img[src*="plantuml"]),
            .vditor-preview p:has(img[src*="plantuml"]) {
              text-align: center !important;
            }
            
            /* 本地图片路径处理 - 只处理节点文件夹中的图片 */
            .vditor-reset img[src$=".jpg"],
            .vditor-reset img[src$=".jpeg"],
            .vditor-reset img[src$=".png"],
            .vditor-reset img[src$=".gif"],
            .vditor-reset img[src$=".webp"],
            .vditor-reset img[src$=".bmp"],
            .vditor-reset img[src$=".tiff"],
            .vditor-reset img[src$=".tif"] {
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
            
            /* === PlantUML图表居中显示 - 全面覆盖所有模式 === */
            
            /* PlantUML外部服务图片 - plantuml.com */
            .vditor-wysiwyg img[src*="plantuml.com"],
            .vditor-ir img[src*="plantuml.com"],
            .vditor-sv img[src*="plantuml.com"],
            .vditor-reset img[src*="plantuml.com"],
            .vditor-preview img[src*="plantuml.com"] {
              display: block !important;
              margin: 16px auto !important;
              max-width: 100% !important;
              height: auto !important;
              text-align: center !important;
            }
            
            /* PlantUML本地服务器图片 */
            .vditor-wysiwyg img[src*="/plantuml/"],
            .vditor-ir img[src*="/plantuml/"],
            .vditor-sv img[src*="/plantuml/"],
            .vditor-reset img[src*="/plantuml/"],
            .vditor-preview img[src*="/plantuml/"] {
              display: block !important;
              margin: 16px auto !important;
              max-width: 100% !important;
              height: auto !important;
              text-align: center !important;
            }
            
            /* PlantUML文件格式图片 */
            .vditor-wysiwyg img[src$=".puml"],
            .vditor-ir img[src$=".puml"],
            .vditor-sv img[src$=".puml"],
            .vditor-reset img[src$=".puml"],
            .vditor-preview img[src$=".puml"],
            .vditor-wysiwyg img[src$=".plantuml"],
            .vditor-ir img[src$=".plantuml"],
            .vditor-sv img[src$=".plantuml"],
            .vditor-reset img[src$=".plantuml"],
            .vditor-preview img[src$=".plantuml"] {
              display: block !important;
              margin: 16px auto !important;
              max-width: 100% !important;
              height: auto !important;
              text-align: center !important;
            }
            
            /* PlantUML代码块渲染的图片（通过class识别） */
            .vditor-wysiwyg .language-plantuml img,
            .vditor-ir .language-plantuml img,
            .vditor-sv .language-plantuml img,
            .vditor-reset .language-plantuml img,
            .vditor-preview .language-plantuml img {
              display: block !important;
              margin: 16px auto !important;
              max-width: 100% !important;
              height: auto !important;
              text-align: center !important;
            }
            
            /* 通用图表居中 - 确保所有图表都居中显示 */
            .vditor-reset p:has(img[src*="plantuml"]),
            .vditor-reset div:has(img[src*="plantuml"]) {
              text-align: center !important;
              display: block !important;
              margin: 16px auto !important;
            }
            
            /* 暗色模式下的PlantUML图片优化 */
            .vditor--dark .vditor-reset img[src*="plantuml"],
            .vditor--dark .vditor-reset img[src*="/plantuml/"],
            .vditor--dark .vditor-reset img[src$=".puml"],
            .vditor--dark .vditor-reset img[src$=".plantuml"] {
              border-radius: 8px !important;
              box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3) !important;
              background: rgba(255, 255, 255, 0.05) !important;
              padding: 8px !important;
            }
            
            /* 确保图片容器也居中 */
            .vditor-reset .language-plantuml,
            .vditor-reset .plantuml-container,
            .vditor-reset [data-type="plantuml"] {
              text-align: center !important;
              display: block !important;
              margin: 16px auto !important;
            }
            
            /* 注意：以下旧的暗色样式已被上面的Tanda风格样式覆盖，这里保留作为后备 */
            
            /* === Vditor编辑器界面主题 - Tanda风格定制 === */
            
            /* 编辑器主体背景 */
            .vditor--dark {
              background: #292A2B !important; /* Tanda主背景色 */
              color: #E6E6E6 !important;
            }
            
            /* 编辑器内容区域 */
            .vditor--dark .vditor-content {
              background: #292A2B !important;
            }
            
            /* 工具栏背景和样式 */
            .vditor--dark .vditor-toolbar {
              background: #222324 !important; /* Tanda的工具栏背景 */
              border-bottom: 1px solid #555 !important;
              padding: 8px 12px !important;
            }
            
            /* 工具栏按钮 */
            .vditor--dark .vditor-toolbar .vditor-tooltipped {
              color: #E6E6E6 !important;
              background: transparent !important;
              border: none !important;
              padding: 6px 8px !important;
              border-radius: 4px !important;
              transition: all 0.2s ease !important;
            }
            
            /* 工具栏按钮悬停 */
            .vditor--dark .vditor-toolbar .vditor-tooltipped:hover {
              background: rgba(111, 193, 255, 0.1) !important; /* Tanda蓝色悬停 */
              color: #6FC1FF !important;
            }
            
            /* 工具栏按钮激活状态 */
            .vditor--dark .vditor-toolbar .vditor-tooltipped.vditor-tooltipped--current {
              background: #6FC1FF !important; /* Tanda蓝色 */
              color: #ffffff !important;
            }
            
            /* 工具栏分割线 */
            .vditor--dark .vditor-toolbar .vditor-toolbar__divider {
              background: #555 !important;
              height: 20px !important;
              margin: 0 8px !important;
            }
            
            /* 完全隐藏工具栏 - 保留DOM结构让Vditor正常工作 */
            .vditor-toolbar {
              height: 0 !important;          /* 高度为0 */
              width: 0 !important;           /* 宽度为0 */
              opacity: 0 !important;         /* 完全透明 */
              overflow: hidden !important;   /* 隐藏溢出内容 */
              margin: 0 !important;          /* 移除外边距 */
              padding: 0 !important;         /* 移除内边距 */
              border: none !important;       /* 移除边框 */
              pointer-events: none !important; /* 禁用鼠标交互 */
              position: absolute !important; /* 绝对定位移出视野 */
              left: -9999px !important;      /* 移到屏幕外 */
              visibility: hidden !important; /* 隐藏但保持DOM结构 */
            }
            
            /* 编辑区域样式 - 更全面的选择器 */
            .vditor--dark .vditor-ir,
            .vditor--dark .vditor-ir .vditor-reset,
            .vditor--dark .vditor-ir .vditor-ir__node,
            .vditor--dark .vditor-ir pre.vditor-ir__node {
              background: #292A2B !important; /* Tanda主背景色 */
              color: #E6E6E6 !important;
            }
            
            .vditor--dark .vditor-sv,
            .vditor--dark .vditor-sv .vditor-reset,
            .vditor--dark .vditor-sv .CodeMirror,
            .vditor--dark .vditor-sv .CodeMirror .CodeMirror-scroll {
              background: #292A2B !important; /* Tanda主背景色 */
              color: #E6E6E6 !important;
            }
            
            .vditor--dark .vditor-wysiwyg,
            .vditor--dark .vditor-wysiwyg .vditor-reset {
              background: #292A2B !important; /* Tanda主背景色 */
              color: #E6E6E6 !important;
            }
            
            /* 确保编辑器内所有可能的背景都是Tanda颜色 */
            .vditor--dark .vditor-ir__node,
            .vditor--dark .vditor-ir__preview,
            .vditor--dark .vditor-sv textarea,
            .vditor--dark .vditor-sv .CodeMirror-lines,
            .vditor--dark .vditor-wysiwyg .vditor-wysiwyg__block {
              background: #292A2B !important;
              color: #E6E6E6 !important;
            }
            
            /* 编辑器边框 */
            .vditor--dark .vditor-content .vditor-ir,
            .vditor--dark .vditor-content .vditor-sv,
            .vditor--dark .vditor-content .vditor-wysiwyg {
              border: none !important;
              outline: none !important;
            }
            
            /* 预览区域 */
            .vditor--dark .vditor-preview {
              background: #292A2B !important;
              border-left: 1px solid #555 !important;
            }
            
            /* 侧边栏 */
            .vditor--dark .vditor-outline {
              background: #222324 !important;
              border-right: 1px solid #555 !important;
            }
            
            /* 侧边栏项目 */
            .vditor--dark .vditor-outline .vditor-outline__item {
              color: #E6E6E6 !important;
              padding: 4px 12px !important;
              border-radius: 4px !important;
              margin: 2px 8px !important;
            }
            
            .vditor--dark .vditor-outline .vditor-outline__item:hover {
              background: rgba(111, 193, 255, 0.1) !important;
              color: #6FC1FF !important;
            }
            
            .vditor--dark .vditor-outline .vditor-outline__item.vditor-outline__item--current {
              background: #6FC1FF !important;
              color: #ffffff !important;
            }
            
            /* 滚动条样式 */
            .vditor--dark ::-webkit-scrollbar {
              width: 8px !important;
              height: 8px !important;
              background: transparent !important;
            }
            
            .vditor--dark ::-webkit-scrollbar-track {
              background: rgba(95, 97, 101, 0.3) !important;
              border-radius: 4px !important;
            }
            
            .vditor--dark ::-webkit-scrollbar-thumb {
              background: #6FC1FF !important; /* Tanda蓝色滚动条 */
              border-radius: 4px !important;
            }
            
            .vditor--dark ::-webkit-scrollbar-thumb:hover {
              background: #58a6ff !important;
            }
            
            /* 对话框和弹出层 */
            .vditor--dark .vditor-panel {
              background: #222324 !important;
              border: 1px solid #555 !important;
              box-shadow: 0 4px 20px rgba(0, 0, 0, 0.5) !important;
              border-radius: 6px !important;
            }
            
            .vditor--dark .vditor-panel .vditor-panel__content {
              background: #222324 !important;
              color: #E6E6E6 !important;
            }
            
            /* 输入框 */
            .vditor--dark .vditor-input {
              background: #303233 !important; /* Tanda输入框背景 */
              border: 1px solid #555 !important;
              color: #E6E6E6 !important;
              border-radius: 4px !important;
              padding: 8px 12px !important;
            }
            
            .vditor--dark .vditor-input:focus {
              border-color: #6FC1FF !important;
              box-shadow: 0 0 0 2px rgba(111, 193, 255, 0.2) !important;
              outline: none !important;
            }
            
            /* 按钮 */
            .vditor--dark .vditor-button {
              background: #303233 !important;
              border: 1px solid #555 !important;
              color: #E6E6E6 !important;
              border-radius: 4px !important;
              padding: 8px 16px !important;
              transition: all 0.2s ease !important;
            }
            
            .vditor--dark .vditor-button:hover {
              background: rgba(111, 193, 255, 0.1) !important;
              border-color: #6FC1FF !important;
              color: #6FC1FF !important;
            }
            
            .vditor--dark .vditor-button--primary {
              background: #6FC1FF !important;
              border-color: #6FC1FF !important;
              color: #ffffff !important;
            }
            
            .vditor--dark .vditor-button--primary:hover {
              background: #58a6ff !important;
              border-color: #58a6ff !important;
            }
            
            /* 选择框和下拉菜单 */
            .vditor--dark .vditor-select {
              background: #303233 !important;
              border: 1px solid #555 !important;
              color: #E6E6E6 !important;
              border-radius: 4px !important;
            }
            
            .vditor--dark .vditor-select option {
              background: #303233 !important;
              color: #E6E6E6 !important;
            }
            
            /* 状态栏 */
            .vditor--dark .vditor-counter {
              background: #222324 !important;
              border-top: 1px solid #555 !important;
              color: #E6E6E6 !important;
              padding: 8px 12px !important;
            }
            
            /* 工具提示 */
            .vditor--dark .vditor-tooltip {
              background: #161b22 !important;
              color: #E6E6E6 !important;
              border: 1px solid #555 !important;
              border-radius: 4px !important;
              box-shadow: 0 4px 20px rgba(0, 0, 0, 0.5) !important;
            }
            
            /* 表情选择器 */
            .vditor--dark .vditor-emoji {
              background: #222324 !important;
              border: 1px solid #555 !important;
              border-radius: 6px !important;
            }
            
            .vditor--dark .vditor-emoji__panel {
              background: #222324 !important;
            }
            
            .vditor--dark .vditor-emoji__item:hover {
              background: rgba(111, 193, 255, 0.1) !important;
            }
            
            /* 代码主题选择器 */
            .vditor--dark .vditor-code-theme {
              background: #222324 !important;
              border: 1px solid #555 !important;
            }
            
            /* 分割器 */
            .vditor--dark .vditor-resize {
              background: #555 !important;
            }
            
            .vditor--dark .vditor-resize:hover {
              background: #6FC1FF !important;
            }
            
            /* 特殊的输入状态样式 */
            .vditor--dark .vditor-ir .vditor-ir__marker {
              color: #6FC1FF !important; /* Tanda蓝色标记 */
            }
            
            .vditor--dark .vditor-ir .vditor-ir__marker--heading {
              color: #ff6b6b !important; /* 标题标记用红色 */
            }
            
            .vditor--dark .vditor-ir .vditor-ir__marker--bold {
              color: #ffffff !important; /* 粗体标记用白色 */
            }
            
            .vditor--dark .vditor-ir .vditor-ir__marker--italic {
              color: #ffd93d !important; /* 斜体标记用黄色 */
            }
            
            .vditor--dark .vditor-ir .vditor-ir__marker--link {
              color: #6FC1FF !important; /* 链接标记用蓝色 */
            }
          </style>
        </head>
        <body>
          <div id="vditor"></div>

          <script>
          // 🚨 增强型早期链接拦截系统 - 多层防护，确保100%拦截
          document.addEventListener('DOMContentLoaded', function() {
            console.log('🔗 [EARLY] DOM加载完成，设置增强型早期链接拦截');
            
            // 🎯 全局链接拦截状态管理
            window.__linkInterceptorState = {
              interceptCount: 0,
              lastInterceptTime: 0,
              pendingLinks: new Map(),
              debugMode: true,
              interceptedUrls: new Set()
            };
            
            // 🔧 增强型链接拦截器 - 处理所有可能的场景
            function enhancedLinkInterceptor(e) {
              const state = window.__linkInterceptorState;
              state.interceptCount++;
              
              if (state.debugMode) {
                console.log('🔗 [EARLY] 增强拦截器 #' + state.interceptCount + ':', {
                  target: e.target.tagName,
                  metaKey: e.metaKey,
                  shiftKey: e.shiftKey,
                  ctrlKey: e.ctrlKey,
                  altKey: e.altKey,
                  button: e.button,
                  eventType: e.type,
                  timestamp: Date.now()
                });
              }
              
              // 🎯 智能链接元素查找 - 多种策略确保找到链接
              let linkElement = null;
              
              // 策略1: 直接检查目标元素
              if (e.target.tagName === 'A') {
                linkElement = e.target;
              }
              
              // 策略2: 使用closest向上查找
              if (!linkElement) {
                linkElement = e.target.closest('a');
              }
              
              // 策略3: 检查父元素链 (手动遍历，防止closest失效)
              if (!linkElement) {
                let element = e.target;
                let attempts = 0;
                while (element && element.parentElement && attempts < 10) {
                  if (element.tagName === 'A') {
                    linkElement = element;
                    break;
                  }
                  element = element.parentElement;
                  attempts++;
                }
              }
              
              // 策略4: 检查子元素中是否有链接 (处理复杂嵌套)
              if (!linkElement && e.target.querySelector) {
                const childLink = e.target.querySelector('a');
                if (childLink) {
                  linkElement = childLink;
                }
              }
              
              if (linkElement) {
                const href = linkElement.href || linkElement.getAttribute('href');
                console.log('🔗 [EARLY] 找到链接元素:', {
                  href: href,
                  text: linkElement.textContent?.trim(),
                  className: linkElement.className,
                  id: linkElement.id
                });
                
                // 🎯 检查是否需要拦截 (修饰键或配置)
                const shouldIntercept = (e.metaKey || e.shiftKey || e.ctrlKey) || 
                                       window.__globalLinkInterception === true;
                
                if (shouldIntercept && href && href.trim() !== '') {
                  console.log('🔗 [EARLY] 触发链接拦截条件');
                  
                  // 🚨 强制阻止所有默认行为
                  e.preventDefault();
                  e.stopPropagation();
                  e.stopImmediatePropagation();
                  
                  // 🔄 防重复处理
                  const linkId = href + '_' + Date.now();
                  if (state.interceptedUrls.has(href) && 
                      (Date.now() - state.lastInterceptTime) < 1000) {
                    console.log('🔗 [EARLY] 防重复: 链接最近已处理');
                    return false;
                  }
                  
                  state.interceptedUrls.add(href);
                  state.lastInterceptTime = Date.now();
                  
                  // 🎯 存储待处理链接信息
                  const linkInfo = {
                    url: href,
                    text: linkElement.textContent?.trim() || '',
                    timestamp: Date.now(),
                    interceptor: 'early',
                    modifierKeys: {
                      meta: e.metaKey,
                      shift: e.shiftKey,
                      ctrl: e.ctrlKey,
                      alt: e.altKey
                    }
                  };
                  
                  state.pendingLinks.set(linkId, linkInfo);
                  
                  // 🚀 立即尝试发送到原生代码
                  const sendSuccess = attemptNativeSend(href, 'early-interceptor');
                  
                  if (sendSuccess) {
                    console.log('🔗 [EARLY] 早期发送成功，清理待处理链接');
                    state.pendingLinks.delete(linkId);
                  } else {
                    console.log('🔗 [EARLY] 早期发送失败，标记为待处理');
                    // 设置延迟重试
                    setTimeout(() => {
                      retryPendingLink(linkId);
                    }, 100);
                  }
                  
                  return false;
                }
              }
              
              // 🎯 特殊处理：检查SV预览区域的链接点击
              const isInSvPreview = e.target.closest('.vditor-sv .vditor-reset') ||
                                   e.target.closest('.vditor-preview') ||
                                   e.target.closest('[data-type="preview"]');
              
              if (isInSvPreview && linkElement) {
                console.log('🔗 [EARLY] SV预览区域链接检测');
                // 在SV预览区域，任何链接点击都应被拦截
                e.preventDefault();
                e.stopPropagation();
                e.stopImmediatePropagation();
                
                const href = linkElement.href || linkElement.getAttribute('href');
                if (href) {
                  attemptNativeSend(href, 'sv-preview');
                }
                return false;
              }
            }
            
            // 🚀 尝试发送到原生代码的通用函数
            function attemptNativeSend(url, context) {
              try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge) {
                  console.log('🔗 [SEND] 发送链接到原生:', { url, context });
                  
                  window.webkit.messageHandlers.bridge.postMessage({ 
                    type: 'openURL',
                    url: url,
                    context: context,
                    timestamp: Date.now()
                  });
                  
                  console.log('🔗 [SEND] ✅ 发送成功');
                  return true;
                } else {
                  console.log('🔗 [SEND] ❌ WebKit bridge不可用');
                  return false;
                }
              } catch(err) {
                console.error('🔗 [SEND] ❌ 发送异常:', err);
                return false;
              }
            }
            
            // 🔄 重试待处理链接
            function retryPendingLink(linkId) {
              const state = window.__linkInterceptorState;
              const linkInfo = state.pendingLinks.get(linkId);
              
              if (linkInfo) {
                console.log('🔗 [RETRY] 重试链接:', linkInfo.url);
                const success = attemptNativeSend(linkInfo.url, 'retry');
                
                if (success) {
                  state.pendingLinks.delete(linkId);
                  console.log('🔗 [RETRY] ✅ 重试成功');
                } else {
                  console.log('🔗 [RETRY] ❌ 重试失败，使用备用方案');
                  // 使用window.open作为最后备用方案
                  try {
                    window.open(linkInfo.url, '_blank');
                    state.pendingLinks.delete(linkId);
                  } catch(err) {
                    console.error('🔗 [RETRY] ❌ 备用方案也失败:', err);
                  }
                }
              }
            }
            
            // 🎯 多层事件绑定 - 确保在各种情况下都能拦截
            
            // 层级1: 文档捕获阶段 (最高优先级)
            document.addEventListener('click', enhancedLinkInterceptor, true);
            
            // 层级2: 文档冒泡阶段 (备用)
            document.addEventListener('click', enhancedLinkInterceptor, false);
            
            // 层级3: body元素 (额外保险)
            if (document.body) {
              document.body.addEventListener('click', enhancedLinkInterceptor, true);
              document.body.addEventListener('click', enhancedLinkInterceptor, false);
            }
            
            // 🎯 鼠标按下预处理 - 提前标记潜在链接点击
            document.addEventListener('mousedown', function(e) {
              if (e.button === 0) { // 左键
                const linkElement = e.target.closest('a');
                if (linkElement) {
                  linkElement.dataset.aboutToClick = 'true';
                  linkElement.dataset.clickTime = Date.now().toString();
                  
                  if (e.metaKey || e.shiftKey || e.ctrlKey) {
                    console.log('🔗 [PREPROCESS] 检测到修饰键+鼠标按下在链接上');
                    // 立即标记为需要拦截
                    linkElement.dataset.shouldIntercept = 'true';
                  }
                }
              }
            }, true);
            
            // 🎯 键盘事件监听 - 处理可能的键盘导航
            document.addEventListener('keydown', function(e) {
              // Enter键可能触发链接
              if (e.key === 'Enter' && document.activeElement && document.activeElement.tagName === 'A') {
                if (e.metaKey || e.shiftKey || e.ctrlKey) {
                  console.log('🔗 [KEYBOARD] 检测到修饰键+Enter在链接上');
                  e.preventDefault();
                  e.stopPropagation();
                  
                  const href = document.activeElement.href || document.activeElement.getAttribute('href');
                  if (href) {
                    attemptNativeSend(href, 'keyboard-enter');
                  }
                }
              }
            }, true);
            
            // 🎯 全局错误处理和调试系统初始化
            window.__linkDebugSystem = {
              enabled: true,
              logHistory: [],
              errorHistory: [],
              statisticsHistory: [],
              maxHistoryLength: 1000,
              
              // 📊 统计信息
              statistics: {
                totalInterceptions: 0,
                successfulSends: 0,
                failedSends: 0,
                svPreviewClicks: 0,
                modifierKeyClicks: 0,
                duplicateBlocks: 0,
                errorCount: 0
              },
              
              // 📝 日志记录函数
              log: function(level, category, message, data = null) {
                if (!this.enabled) return;
                
                const timestamp = new Date().toISOString();
                const logEntry = {
                  timestamp,
                  level,
                  category,
                  message,
                  data
                };
                
                this.logHistory.push(logEntry);
                if (this.logHistory.length > this.maxHistoryLength) {
                  this.logHistory.shift();
                }
                
                // 控制台输出
                const consoleMessage = `🔗 [${category.toUpperCase()}] ${message}`;
                switch (level) {
                  case 'error':
                    console.error(consoleMessage, data || '');
                    break;
                  case 'warn':
                    console.warn(consoleMessage, data || '');
                    break;
                  case 'info':
                    console.info(consoleMessage, data || '');
                    break;
                  default:
                    console.log(consoleMessage, data || '');
                }
              },
              
              // ❌ 错误记录函数
              logError: function(category, error, context = null) {
                this.statistics.errorCount++;
                
                const errorEntry = {
                  timestamp: new Date().toISOString(),
                  category,
                  error: error.message || error.toString(),
                  stack: error.stack || 'No stack trace',
                  context
                };
                
                this.errorHistory.push(errorEntry);
                if (this.errorHistory.length > this.maxHistoryLength) {
                  this.errorHistory.shift();
                }
                
                this.log('error', category, `Error: ${error.message || error}`, {
                  error: errorEntry,
                  context
                });
              },
              
              // 📊 统计更新函数
              updateStatistics: function(action, increment = 1) {
                if (this.statistics.hasOwnProperty(action)) {
                  this.statistics[action] += increment;
                }
                
                // 定期记录统计信息
                if (this.statistics.totalInterceptions % 10 === 0) {
                  this.recordStatistics();
                }
              },
              
              // 📈 记录统计快照
              recordStatistics: function() {
                const snapshot = {
                  timestamp: new Date().toISOString(),
                  ...this.statistics
                };
                
                this.statisticsHistory.push(snapshot);
                if (this.statisticsHistory.length > 100) {
                  this.statisticsHistory.shift();
                }
              },
              
              // 📋 生成调试报告
              generateReport: function() {
                return {
                  system: 'Enhanced Link Interceptor',
                  timestamp: new Date().toISOString(),
                  statistics: this.statistics,
                  recentLogs: this.logHistory.slice(-20),
                  recentErrors: this.errorHistory.slice(-10),
                  recentStatistics: this.statisticsHistory.slice(-5),
                  configuration: {
                    interceptorActive: window.__linkInterceptorState?.interceptCount || 0,
                    svInterceptorActive: window.__svLinkInterceptor?.isActive || false,
                    boundContainers: window.__svLinkInterceptor?.boundContainers?.size || 0,
                    webkitAvailable: !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge)
                  }
                };
              }
            };
            
            // 🔧 增强attemptNativeSend函数以使用调试系统
            const originalAttemptNativeSend = attemptNativeSend;
            attemptNativeSend = function(url, context) {
              const debugSystem = window.__linkDebugSystem;
              
              try {
                debugSystem.updateStatistics('totalInterceptions');
                debugSystem.log('info', 'send', `尝试发送链接`, { url, context });
                
                const result = originalAttemptNativeSend(url, context);
                
                if (result) {
                  debugSystem.updateStatistics('successfulSends');
                  debugSystem.log('info', 'send', `发送成功`, { url, context });
                } else {
                  debugSystem.updateStatistics('failedSends');
                  debugSystem.log('warn', 'send', `发送失败`, { url, context });
                }
                
                return result;
              } catch (error) {
                debugSystem.logError('send', error, { url, context });
                debugSystem.updateStatistics('failedSends');
                return false;
              }
            };
            
            // 🎯 全局异常捕获
            window.addEventListener('error', function(event) {
              window.__linkDebugSystem.logError('global', event.error, {
                filename: event.filename,
                lineno: event.lineno,
                colno: event.colno
              });
            });
            
            window.addEventListener('unhandledrejection', function(event) {
              window.__linkDebugSystem.logError('promise', event.reason, {
                type: 'unhandled promise rejection'
              });
            });
            
            // 🔧 调试工具函数
            window.__debugLinkInterceptor = function() {
              const report = window.__linkDebugSystem.generateReport();
              console.group('🔗 链接拦截器调试报告');
              console.log('📊 统计信息:', report.statistics);
              console.log('⚙️ 配置信息:', report.configuration);
              console.log('📝 最近日志:', report.recentLogs);
              console.log('❌ 最近错误:', report.recentErrors);
              console.log('📈 统计历史:', report.recentStatistics);
              console.groupEnd();
              
              return report;
            };
            
            // 🎯 手动测试链接拦截
            window.__testLinkInterception = function(url = 'https://www.google.com') {
              console.log('🧪 测试链接拦截:', url);
              const success = attemptNativeSend(url, 'manual-test');
              console.log('🧪 测试结果:', success ? '成功' : '失败');
              return success;
            };
            
            // 📊 性能监控
            window.__linkPerformanceMonitor = {
              startTime: Date.now(),
              checkpoints: [],
              
              checkpoint: function(name) {
                this.checkpoints.push({
                  name,
                  timestamp: Date.now(),
                  elapsed: Date.now() - this.startTime
                });
              },
              
              report: function() {
                console.group('⏱️ 链接拦截器性能报告');
                this.checkpoints.forEach(cp => {
                  console.log(`${cp.name}: ${cp.elapsed}ms`);
                });
                console.groupEnd();
                return this.checkpoints;
              }
            };
            
            window.__linkPerformanceMonitor.checkpoint('早期拦截器初始化完成');
            
            console.log('🔗 [EARLY] ✅ 增强型早期链接拦截系统初始化完成');
            console.log('🔧 [DEBUG] 调试工具已激活:');
            console.log('  - window.__debugLinkInterceptor() - 生成调试报告');
            console.log('  - window.__testLinkInterception(url) - 测试链接拦截');
            console.log('  - window.__linkDebugSystem - 访问调试系统');
          });
          
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

            // 🚀 精简的回调函数 - 仅用于调试和兼容性
            window.__onImageSaved = (name, path, id) => {
              console.log(`🖼️ [传统模式] __onImageSaved 被调用: name=${name}, path=${path}, id=${id}`);
              
              // 仅在传统模式下处理loading占位符替换
              if (id && id !== '') {
                const content = window.vditor ? window.vditor.getValue() : '';
                const targetMark = `![加载中...](${id})`;
                
                if (content.includes(targetMark) && window.vditor) {
                  const fileName = name.split('/').pop() || name;
                  const updated = content.replace(targetMark, `![${fileName}](${path})`);
                  window.vditor.setValue(updated);
                  console.log(`🖼️ [传统模式] 替换成功: ${targetMark} -> ![${fileName}](${path})`);
                }
              } else {
                console.log(`🖼️ [传统模式] 无loadingId，跳过占位符处理`);
              }
            };
            
            window.__onImageSaveError = (name, error, id) => {
              console.error(`🖼️ [传统模式] 图片保存失败: ${error}`);
              alert(`保存图片失败: ${error}`);
              
              // 清理loading占位符
              if (id && id !== '' && window.vditor) {
                const content = window.vditor.getValue();
                const targetMark = `![加载中...](${id})`;
                const updated = content.replace(targetMark, '');
                window.vditor.setValue(updated);
              }
            };

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
                // 🔥 Command+K 智能处理 - 不完全禁用，允许编辑器内部使用
                // 'Cmd+K': '', // 注释掉，允许编辑器在焦点内时使用
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
                
                // 🎨 初始化时根据系统主题设置背景
                const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
                if (prefersDark) {
                  document.documentElement.classList.add('vditor--dark');
                  document.body.classList.add('vditor--dark');
                  document.documentElement.setAttribute('data-theme', 'dark');
                  document.body.setAttribute('data-theme', 'dark');
                }
                
                // 🔗 立即为 Vditor 内容区域绑定链接处理器
                console.log('🔗 [INIT] Vditor初始化完成，立即绑定链接处理器');
                const vditorContent = document.querySelector('#vditor');
                if (vditorContent) {
                  vditorContent.addEventListener('click', function(e) {
                    console.log('🔗 [VDITOR] Vditor内容区域点击:', e.target.tagName, 'metaKey:', e.metaKey);
                    const linkElement = e.target.closest('a');
                    if (linkElement && (e.metaKey || e.shiftKey)) {
                      console.log('🔗 [VDITOR] Vditor内部链接点击拦截');
                      e.preventDefault();
                      e.stopPropagation();
                      e.stopImmediatePropagation();
                      handleLinkClick(e);
                      return false;
                    }
                  }, true);
                }
                
                // 🚀 强制链接处理 - 定期扫描并处理所有链接
                function forceSetupLinks() {
                  console.log('🔗 [FORCE] 强制设置链接处理器');
                  const allLinks = document.querySelectorAll('a[href]');
                  console.log('🔗 [FORCE] 找到', allLinks.length, '个链接');
                  
                  allLinks.forEach((link, index) => {
                    if (!link.dataset.customHandlerBound) {
                      console.log('🔗 [FORCE] 为链接', index, '绑定处理器:', link.href);
                      
                      // 移除所有现有的点击监听器
                      link.onclick = null;
                      
                      // 添加我们的处理器
                      link.addEventListener('click', function(e) {
                        console.log('🔗 [FORCE] 强制链接点击处理:', link.href);
                        e.preventDefault();
                        e.stopPropagation();
                        e.stopImmediatePropagation();
                        
                        // 直接发送到原生代码
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge) {
                          try {
                            window.webkit.messageHandlers.bridge.postMessage({ 
                              type: 'openURL',
                              url: link.href
                            });
                            console.log('🔗 [FORCE] 强制发送成功:', link.href);
                          } catch(err) {
                            console.error('🔗 [FORCE] 强制发送失败:', err);
                            window.open(link.href, '_blank');
                          }
                        } else {
                          window.open(link.href, '_blank');
                        }
                        return false;
                      }, true);
                      
                      link.dataset.customHandlerBound = 'true';
                    }
                  });
                }
                
                // 立即执行一次
                forceSetupLinks();
                
                // 定期重新检查和绑定
                setInterval(forceSetupLinks, 2000);
                
                // 拦截特殊快捷键
                document.addEventListener('keydown', function(e) {
                  // 调试所有按键组合
                  if (e.metaKey || e.ctrlKey || e.altKey) {
                    console.log('🎹 按键调试:', {
                      key: e.key,
                      metaKey: e.metaKey,
                      altKey: e.altKey,
                      ctrlKey: e.ctrlKey,
                      shiftKey: e.shiftKey,
                      code: e.code
                    });
                    
                    // 特别检查Command+;
                    if (e.metaKey && e.key === ';') {
                      console.log('🎯 检测到 Command+; 按键组合！');
                      e.preventDefault();
                      e.stopPropagation();
                      
                      // 手动触发大纲切换
                      try {
                        const outlineBtn = document.querySelector('[data-type="outline"]');
                        if (outlineBtn) {
                          console.log('✅ 找到大纲按钮，模拟点击');
                          outlineBtn.click();
                        } else {
                          console.error('❌ 未找到大纲按钮');
                          // 尝试其他选择器
                          const altBtn = document.querySelector('.vditor-toolbar .vditor-tooltipped[data-type="outline"]');
                          if (altBtn) {
                            console.log('✅ 找到备选大纲按钮');
                            altBtn.click();
                          }
                        }
                      } catch(err) {
                        console.error('❌ 触发大纲失败:', err);
                      }
                      return false;
                    }
                  }
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
                  
                  // Command+K: 智能处理 - 只有在编辑器未激活时转发给原生App
                  if (e.metaKey && (e.key === 'k' || e.key === 'K')) {
                    // 检查是否在编辑器内部且编辑器有焦点
                    const activeElement = document.activeElement;
                    const isInEditor = activeElement && (
                      activeElement.closest('.vditor-ir') ||
                      activeElement.closest('.vditor-sv') ||
                      activeElement.closest('.vditor-wysiwyg') ||
                      activeElement.classList.contains('vditor-reset') ||
                      activeElement.tagName === 'TEXTAREA' ||
                      (activeElement.contentEditable === 'true')
                    );
                    
                    if (isInEditor) {
                      console.log('🎯 Command+K 在编辑器内使用，自定义插入链接格式');
                      // 阻止 Vditor 的默认 Command+K 行为（避免插入 https://）
                      e.preventDefault();
                      e.stopImmediatePropagation();
                      
                      // 获取选中文字并插入到方括号内，智能光标定位
                      try {
                        // 获取当前选中的文本
                        const selection = window.getSelection();
                        const selectedText = selection.toString();
                        const hasSelectedText = selectedText && selectedText.trim().length > 0;
                        
                        if (window.vditor && window.vditor.insertValue) {
                          // 如果有选中文字，先删除选中内容
                          if (hasSelectedText) {
                            selection.deleteFromDocument();
                          }
                          
                          if (hasSelectedText) {
                            // 有选中文字：插入[selectedText]()，光标定位到()中
                            console.log('🎯 有选中文字，光标将定位到()中');
                            window.vditor.insertValue(`[${selectedText}]`);
                            
                            setTimeout(() => {
                              try {
                                const currentSel = window.getSelection();
                                if (currentSel.rangeCount > 0) {
                                  const range = currentSel.getRangeAt(0);
                                  
                                  // 插入()
                                  const textNode = document.createTextNode('()');
                                  range.insertNode(textNode);
                                  
                                  // 将光标定位到)之前
                                  range.setStart(textNode, 1);
                                  range.setEnd(textNode, 1);
                                  currentSel.removeAllRanges();
                                  currentSel.addRange(range);
                                  
                                  console.log('✅ 已插入链接格式并定位光标到()内');
                                } else {
                                  window.vditor.insertValue('()');
                                  console.log('✅ 使用简单方法插入()');
                                }
                              } catch(positionErr) {
                                console.error('❌ 光标定位失败，使用简单插入:', positionErr);
                                window.vditor.insertValue('()');
                              }
                            }, 10);
                          } else {
                            // 没有选中文字：插入[]()，光标定位到[]中
                            console.log('🎯 没有选中文字，光标将定位到[]中');
                            
                            // 先记录当前光标位置
                            const currentSel = window.getSelection();
                            if (currentSel.rangeCount > 0) {
                              const range = currentSel.getRangeAt(0);
                              
                              // 创建完整的链接格式文本节点
                              const linkText = document.createTextNode('[]()');
                              range.insertNode(linkText);
                              
                              // 将光标定位到]之前（即[]中间）
                              range.setStart(linkText, 1);
                              range.setEnd(linkText, 1);
                              currentSel.removeAllRanges();
                              currentSel.addRange(range);
                              
                              console.log('✅ 已插入空链接格式并定位光标到[]内');
                            } else {
                              // 回退方法
                              window.vditor.insertValue('[]()');
                              console.log('✅ 使用简单方法插入[]()');
                            }
                          }
                          
                        } else {
                          // 备用方法：使用原生插入
                          const linkFormat = `[${selectedText}]()`;
                          if (selectedText) {
                            selection.deleteFromDocument();
                          }
                          
                          // 创建文本节点并插入
                          const range = selection.getRangeAt(0);
                          const textNode = document.createTextNode(linkFormat);
                          range.insertNode(textNode);
                          
                          // 定位光标到)之前
                          range.setStart(textNode, linkFormat.length - 1);
                          range.setEnd(textNode, linkFormat.length - 1);
                          selection.removeAllRanges();
                          selection.addRange(range);
                          
                          console.log('✅ 使用备用方法插入并定位光标');
                        }
                      } catch(err) {
                        console.error('❌ 插入链接格式失败:', err);
                      }
                      return false;
                    } else {
                      console.log('🔥 Command+K 在编辑器外使用，转发给App处理');
                      e.preventDefault();
                      e.stopImmediatePropagation();
                      
                      try {
                        window.webkit?.messageHandlers?.bridge?.postMessage({ 
                          type: 'commandK'
                        });
                      } catch(err) {
                        console.error('无法发送 Command+K 事件:', err);
                      }
                      return false;
                    }
                  }
                  
                  // Command+I: 转发给原生App处理 - 快速添加节点
                  if (e.metaKey && (e.key === 'i' || e.key === 'I')) {
                    console.log('🔥 拦截 Command+I 快捷键，转发给App处理');
                    e.preventDefault();
                    e.stopImmediatePropagation();
                    
                    try {
                      window.webkit?.messageHandlers?.bridge?.postMessage({ 
                        type: 'commandI'
                      });
                    } catch(err) {
                      console.error('无法发送 Command+I 事件:', err);
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
                  
                  // Command+Option+8: 切换链接点击模式
                  if (e.metaKey && e.altKey && e.key === '8') {
                    console.log('🎯 检测到 Command+Option+8，切换链接点击模式');
                    e.preventDefault();
                    e.stopImmediatePropagation();
                    
                    // 切换全局链接拦截状态
                    window.__globalLinkInterception = !window.__globalLinkInterception;
                    const mode = window.__globalLinkInterception ? '强制拦截' : '正常点击';
                    console.log('🔗 链接点击模式已切换为:', mode);
                    
                    // 显示状态提示
                    try {
                      // 创建临时提示元素
                      const toast = document.createElement('div');
                      toast.style.cssText = `
                        position: fixed; top: 50px; right: 50px; z-index: 10000;
                        background: ${window.__isDarkMode ? '#2b2b2b' : '#fff'};
                        color: ${window.__isDarkMode ? '#fff' : '#333'};
                        padding: 12px 20px; border-radius: 8px;
                        box-shadow: 0 4px 12px rgba(0,0,0,0.3);
                        font-size: 14px; font-weight: 500;
                        transition: all 0.3s ease;
                      `;
                      toast.textContent = `链接点击模式: ${mode}`;
                      document.body.appendChild(toast);
                      
                      // 3秒后自动移除
                      setTimeout(() => {
                        if (toast.parentNode) {
                          toast.parentNode.removeChild(toast);
                        }
                      }, 3000);
                    } catch(err) {
                      console.error('无法显示状态提示:', err);
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
                hljs: { 
                  enable: true, 
                  lineNumber: false,
                  defaultLang: "",
                  style: 'github'  // 使用默认主题，后续通过__applyNativeTheme动态更新
                },
                math: { engine: 'KaTeX' },
                mermaid: { startOnLoad:false }     // 由我们手动控制
              },
              toolbar: [
                {
                  name: 'outline',
                  tip: '大纲 (⌘;)',
                  click() {
                    console.log('🎯 大纲按钮被点击 - 通过快捷键或鼠标');
                    // 让Vditor处理默认的outline行为
                    return true;
                  }
                }
              ], // 只保留大纲按钮，使用Command+;快捷键
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
                    
                    console.log(`🖼️ 开始处理图片上传: ${fileName}`);
                    console.log(`🖼️ 使用直接插入模式，跳过loading占位符`);
                    
                    // 🚀 直接模式：不插入loading占位符，让Swift端直接插入最终链接
                    // 读取文件
                    const reader = new FileReader();
                    reader.onload = (e) => {
                      const base64 = e.target.result.split(',')[1]; // 去掉 data:image/xxx;base64, 前缀
                      
                      console.log(`🖼️ 文件读取完成，发送到Swift处理: ${fileName}`);
                      
                      // 发送到 Swift 保存，不传递loadingId（表示使用直接插入模式）
                      window.webkit?.messageHandlers?.bridge?.postMessage({ 
                        type: 'saveImage',
                        fileName: fileName,
                        data: base64,
                        directMode: true  // 标记为直接插入模式
                      });
                      
                      console.log(`🖼️ 图片上传请求已发送到Swift，等待直接插入...`);
                    };
                    
                    reader.onerror = (error) => {
                      console.error('🖼️ 文件读取失败:', error);
                      alert('文件读取失败');
                    };
                    
                    reader.readAsDataURL(file);
                  } catch (error) {
                    console.error('🖼️ 处理图片失败:', error);
                    alert('处理图片失败: ' + error.message);
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
                if (src.match(/\.(jpg|jpeg|png|gif|webp|bmp|tiff|tif)$/i) && !src.startsWith('file://')) {
                  // 节点文件夹图片，直接使用文件名
                  const filename = src.split('/').pop();
                  e.target.src = filename;
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
              
              // 键盘快捷键 - 绑定在overlay上，只处理图片查看器的按键
              const handleKeyPress = (e) => {
                e.preventDefault();
                e.stopPropagation();
                switch(e.key) {
                  case 'Escape':
                    // ESC退出 - 立即关闭，无延迟
                    if (document.body.contains(overlay)) {
                      document.body.removeChild(overlay);
                    }
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
              
              // 绑定键盘事件到overlay上，而不是document
              overlay.addEventListener('keydown', handleKeyPress);
              
              // 点击空白区域退出
              overlay.addEventListener('click', (e) => {
                if (e.target === overlay) {
                  document.body.removeChild(overlay);
                }
              });
              
              // 确保overlay可以接收键盘事件
              overlay.setAttribute('tabindex', '0');
              overlay.focus();
              
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
            
            // 增强的超链接Command+点击处理 - 多层次拦截确保成功，特别优化SV模式
            function handleLinkClick(e) {
              console.log('🔗 [MAIN] handleLinkClick被调用');
              console.log('🔗 [MAIN] Click detected, metaKey:', e.metaKey, 'shiftKey:', e.shiftKey, 'target:', e.target, 'tagName:', e.target.tagName);
              console.log('🔗 [MAIN] 事件类型:', e.type, '时间戳:', e.timeStamp);
              
              // 支持Shift+点击或Command+点击
              if (!e.metaKey && !e.shiftKey) {
                console.log('🔗 [MAIN] 没有修饰键，退出处理');
                return;
              }
              
              console.log('🔗 [MAIN] 检测到修饰键，继续处理...');
              
              let target = e.target;
              let attempts = 0;
              const maxAttempts = 10;
              
              // 🎯 检查是否在SV预览区域 - 特殊处理
              const isInSvPreview = target.closest('.vditor-sv .vditor-reset') || 
                                   target.closest('.vditor-preview') ||
                                   target.closest('[data-type="preview"]');
              
              console.log('🔗 是否在SV预览区域:', isInSvPreview);
              
              // 向上查找链接元素
              while (target && target.tagName !== 'A' && target.parentElement && attempts < maxAttempts) {
                target = target.parentElement;
                attempts++;
                console.log('🔗 Checking parent:', target.tagName, target);
              }
              
              // 使用closest方法再次查找
              if (!target || target.tagName !== 'A') {
                target = e.target.closest('a');
                console.log('🔗 Using closest() method, found:', target);
              }
              
              if (target && target.tagName === 'A') {
                let url = target.href || target.getAttribute('href');
                console.log('🔗 [MAIN] Found link element:', target);
                console.log('🔗 [MAIN] Link href:', url);
                console.log('🔗 [MAIN] Link attributes:', {
                  href: target.getAttribute('href'),
                  target: target.getAttribute('target'),
                  className: target.className,
                  textContent: target.textContent
                });
                
                if (url && url.trim() !== '') {
                  console.log('🔗 [MAIN] 修饰键+点击链接:', url, '(metaKey:', e.metaKey, ', shiftKey:', e.shiftKey, ')');
                  
                  // 🎯 只在有修饰键时才拦截链接点击
                  if (e.metaKey || e.shiftKey || e.ctrlKey) {
                    console.log('🔗 [MAIN] 修饰键拦截链接点击');
                    e.preventDefault();
                    e.stopPropagation();
                    e.stopImmediatePropagation();
                  }
                  
                  // 清理和标准化URL
                  url = url.trim();
                  
                  // 处理相对URL和协议
                  if (!url.startsWith('http://') && !url.startsWith('https://') && !url.startsWith('mailto:') && !url.startsWith('file://')) {
                    if (url.includes('@') && !url.includes('/')) {
                      url = 'mailto:' + url;
                    } else if (url.startsWith('www.') || url.includes('.com') || url.includes('.org') || url.includes('.net')) {
                      url = 'https://' + url;
                    } else if (!url.startsWith('//')) {
                      url = 'https://' + url;
                    }
                    console.log('🔗 标准化后的URL:', url);
                  }
                  
                  // 异步发送消息，确保事件处理完成
                  setTimeout(() => {
                    try {
                      console.log('🔗 [MAIN] 准备发送消息到原生代码...', { type: 'openURL', url: url });
                      console.log('🔗 [MAIN] WebKit检查:', {
                        webkit: !!window.webkit,
                        messageHandlers: !!(window.webkit && window.webkit.messageHandlers),
                        bridge: !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge)
                      });
                      
                      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge) {
                        console.log('🔗 [MAIN] WebKit消息处理器可用，发送消息...');
                        
                        const messageData = { 
                          type: 'openURL',
                          url: url
                        };
                        console.log('🔗 [MAIN] 发送的消息数据:', messageData);
                        
                        window.webkit.messageHandlers.bridge.postMessage(messageData);
                        console.log('✅ [MAIN] 已发送openURL消息到原生代码');
                        
                        // 添加一个确认标记
                        document.body.dataset.lastLinkSent = url;
                        document.body.dataset.lastLinkTime = Date.now();
                        
                      } else {
                        console.error('❌ [MAIN] WebKit消息处理器不可用');
                        console.log('🔗 [MAIN] 尝试备选方案：window.open');
                        window.open(url, '_blank');
                        console.log('✅ [MAIN] 使用window.open打开链接');
                      }
                    } catch(err) {
                      console.error('❌ [MAIN] 发送openURL消息失败:', err);
                      console.error('❌ [MAIN] 错误详情:', err.message, err.stack);
                      try {
                        console.log('🔗 [MAIN] 备选方案：window.open');
                        window.open(url, '_blank');
                        console.log('✅ [MAIN] 备选方案：使用window.open打开链接');
                      } catch(backupErr) {
                        console.error('❌ [MAIN] 备选方案也失败:', backupErr);
                      }
                    }
                  }, 0);
                  
                  return false;
                } else {
                  console.warn('🔗 链接元素存在但没有有效的URL:', target);
                }
              } else {
                console.log('🔗 未找到链接元素');
              }
            }
            
            // 调试函数：检查当前编辑模式和环境
            window.__debugLinkClick = function() {
              console.log('🔗 [DEBUG] 链接点击调试信息:');
              console.log('  - 当前编辑模式:', currentEditMode);
              console.log('  - Vditor容器:', document.querySelector('#vditor'));
              console.log('  - IR区域:', document.querySelector('.vditor-ir'));
              console.log('  - SV区域:', document.querySelector('.vditor-sv'));
              console.log('  - 预览区域:', document.querySelector('.vditor-preview'));
              console.log('  - SV预览重置区域:', document.querySelector('.vditor-sv .vditor-reset'));
              console.log('  - 所有链接:', document.querySelectorAll('a'));
              console.log('  - WebKit可用性:', {
                webkit: !!window.webkit,
                messageHandlers: !!(window.webkit && window.webkit.messageHandlers),
                bridge: !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge)
              });
            };
            
            // 多重事件监听策略 - 确保在各种情况下都能拦截链接点击
            
            // 🎯 最高优先级：在document级别拦截所有链接点击
            document.addEventListener('click', function(e) {
              console.log('🔗 [GLOBAL] 全局点击检测:', e.target.tagName, 'metaKey:', e.metaKey, 'target:', e.target);
              
              // 检查是否是链接或包含链接
              const linkElement = e.target.closest('a') || (e.target.tagName === 'A' ? e.target : null);
              if (linkElement) {
                console.log('🔗 [GLOBAL] 检测到链接点击:', linkElement.href);
                
                // 如果有修饰键，立即阻止默认行为
                if (e.metaKey || e.shiftKey) {
                  console.log('🔗 [GLOBAL] 修饰键点击，强制阻止默认行为');
                  e.preventDefault();
                  e.stopPropagation();
                  e.stopImmediatePropagation();
                  
                  // 立即处理
                  handleLinkClick(e);
                  return false;
                }
              }
            }, true); // 使用捕获阶段，确保最早处理
            
            // 1. 在捕获阶段拦截，优先级最高
            document.addEventListener('click', function(e) {
              console.log('🔗 [CAPTURE] 捕获阶段链接检测:', e.target.tagName, 'metaKey:', e.metaKey);
              handleLinkClick(e);
            }, true);
            
            // 2. 在冒泡阶段再次拦截，以防捕获阶段被阻止
            document.addEventListener('click', handleLinkClick, false);
            
            // 3. 使用Vditor编辑器的事件系统（如果可用）
            if (window.vditor && window.vditor.element) {
              window.vditor.element.addEventListener('click', handleLinkClick, true);
            }
            
            // 4. 直接在document.body上监听，覆盖更广
            if (document.body) {
              document.body.addEventListener('click', handleLinkClick, true);
            }
            
            // 5. 全局mousedown预处理，确保准备工作完成
            document.addEventListener('mousedown', function(e) {
              if ((e.metaKey || e.shiftKey) && e.target.closest('a')) {
                console.log('🔗 Mousedown on link detected, preparing for click', '(metaKey:', e.metaKey, ', shiftKey:', e.shiftKey, ')');
                // 预处理：标记这个元素即将被点击
                e.target.closest('a').dataset.aboutToClick = 'true';
              }
            }, true);
            
            // 6. 额外的全局点击监听器用于调试和备用处理
            document.addEventListener('click', function(e) {
              console.log('🔗 [DEBUG] 全局点击检测:', e.target.tagName, e.target, 'metaKey:', e.metaKey, 'shiftKey:', e.shiftKey);
              
              if (e.target.closest('a')) {
                const link = e.target.closest('a');
                console.log('🔗 [DEBUG] 这是链接点击！href:', link.href);
                console.log('🔗 [DEBUG] defaultPrevented:', e.defaultPrevented);
                console.log('🔗 [DEBUG] 事件阶段:', e.eventPhase, '(1=捕获,2=目标,3=冒泡)');
                
                // 如果有修饰键但没有被处理，强制处理
                if ((e.metaKey || e.shiftKey) && !e.defaultPrevented) {
                  console.log('🔗 [BACKUP] 备用处理器激活');
                  handleLinkClick(e);
                } else if (e.metaKey || e.shiftKey) {
                  console.log('🔗 [DEBUG] 有修饰键但事件已被阻止，defaultPrevented:', e.defaultPrevented);
                }
              }
            }, true);
            
            // 7. 🎯 增强型SV分屏模式和多编辑模式链接拦截系统
            setTimeout(() => {
              console.log('🔗 [SV] 初始化增强型SV分屏模式链接拦截系统...');
              
              // 🎯 专门处理SV预览区域的链接拦截
              function setupSVPreviewInterception() {
                console.log('🔗 [SV] 设置SV预览区域专用拦截器');
                
                // 查找SV预览区域
                const svPreviewAreas = [
                  '.vditor-sv .vditor-reset',
                  '.vditor-preview',
                  '[data-type="preview"]',
                  '.vditor-sv .vditor-preview'
                ];
                
                svPreviewAreas.forEach(selector => {
                  const area = document.querySelector(selector);
                  if (area && !area.dataset.svInterceptorBound) {
                    console.log('🔗 [SV] 为SV区域绑定专用拦截器:', selector);
                    
                    area.addEventListener('click', function(e) {
                      const linkElement = e.target.closest('a');
                      if (linkElement) {
                        console.log('🔗 [SV] SV预览区域链接点击，强制拦截');
                        e.preventDefault();
                        e.stopPropagation();
                        e.stopImmediatePropagation();
                        
                        const url = linkElement.href || linkElement.getAttribute('href');
                        if (url && (url.startsWith('http') || url.includes('.'))) {
                          console.log('🔗 [SV] SV区域外部链接，发送到原生处理');
                          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge) {
                            window.webkit.messageHandlers.bridge.postMessage({
                              type: 'openURL',
                              url: url,
                              source: 'SV_preview_area'
                            });
                          }
                        }
                        return false;
                      }
                    }, true);
                    
                    area.dataset.svInterceptorBound = 'true';
                  }
                });
              }
              
              // 立即设置
              setupSVPreviewInterception();
              
              // 定期重新检查（处理模式切换）
              setInterval(setupSVPreviewInterception, 3000);
              
              // 🎯 SV模式专用链接拦截状态
              window.__svLinkInterceptor = {
                isActive: false,
                boundContainers: new Set(),
                lastScanTime: 0,
                interceptCount: 0
              };
              
              // 🚀 智能容器发现和绑定系统
              function discoverAndBindContainers() {
                const now = Date.now();
                if (now - window.__svLinkInterceptor.lastScanTime < 500) {
                  return; // 防止过于频繁的扫描
                }
                window.__svLinkInterceptor.lastScanTime = now;
                
                console.log('🔗 [SV] 扫描并绑定容器...');
                
                // 🎯 全面的容器选择器 - 覆盖所有可能的编辑和预览区域
                const containerSelectors = [
                  // 基础容器
                  'document', 'body', '#vditor',
                  
                  // 通用Vditor容器
                  '.vditor', '.vditor-reset', '.vditor-content',
                  
                  // IR模式容器
                  '.vditor-ir', '.vditor-ir .vditor-reset', '.vditor-ir__node',
                  
                  // SV分屏模式容器 (重点)
                  '.vditor-sv', '.vditor-sv .vditor-reset', 
                  '.vditor-sv__preview', '.vditor-sv .vditor-preview',
                  
                  // 预览区域
                  '.vditor-preview', '.vditor-preview .vditor-reset',
                  '[data-type="preview"]', '.vditor-preview__content',
                  
                  // WYSIWYG模式
                  '.vditor-wysiwyg', '.vditor-wysiwyg .vditor-reset',
                  
                  // 工具栏和其他
                  '.vditor-toolbar', '.vditor-outline'
                ];
                
                const containers = [];
                
                // 添加document和body
                containers.push(document, document.body);
                
                // 查找所有匹配的容器
                containerSelectors.forEach(selector => {
                  if (selector === 'document' || selector === 'body') return;
                  try {
                    const elements = document.querySelectorAll(selector);
                    elements.forEach(el => {
                      if (el && !containers.includes(el)) {
                        containers.push(el);
                      }
                    });
                  } catch(e) {
                    console.warn('🔗 [SV] 选择器错误:', selector, e);
                  }
                });
                
                console.log('🔗 [SV] 发现', containers.length, '个容器');
                
                // 为每个容器绑定增强型链接处理器
                containers.forEach((container, index) => {
                  const containerId = container.id || container.className || container.tagName || `container_${index}`;
                  
                  if (!window.__svLinkInterceptor.boundContainers.has(containerId)) {
                    console.log('🔗 [SV] 为容器绑定事件:', containerId);
                    
                    // 🎯 SV专用链接处理器
                    const svLinkHandler = function(e) {
                      window.__svLinkInterceptor.interceptCount++;
                      
                      console.log('🔗 [SV] SV链接处理器触发 #' + window.__svLinkInterceptor.interceptCount);
                      console.log('🔗 [SV] 事件源容器:', containerId);
                      console.log('🔗 [SV] 点击目标:', e.target.tagName, e.target.className);
                      
                      const linkElement = e.target.closest('a');
                      if (linkElement) {
                        const href = linkElement.href || linkElement.getAttribute('href');
                        console.log('🔗 [SV] 发现链接:', href);
                        
                        // 🎯 SV模式下的特殊处理逻辑
                        const isInSvPreview = container.closest('.vditor-sv') || 
                                             container.classList.contains('vditor-sv') ||
                                             e.target.closest('.vditor-sv');
                        
                        if (isInSvPreview) {
                          console.log('🔗 [SV] ⚠️ SV预览区域链接点击');
                          
                          // SV预览区域的链接应该被强制拦截
                          e.preventDefault();
                          e.stopPropagation();
                          e.stopImmediatePropagation();
                          
                          if (href && href.trim() !== '') {
                            console.log('🔗 [SV] 🚀 SV预览区域强制发送链接:', href);
                            attemptNativeSend(href, 'sv-preview-forced');
                          }
                          return false;
                        }
                        
                        // 🎯 检查修饰键
                        if (e.metaKey || e.shiftKey || e.ctrlKey) {
                          console.log('🔗 [SV] 🎯 修饰键链接拦截');
                          e.preventDefault();
                          e.stopPropagation();
                          e.stopImmediatePropagation();
                          
                          if (href && href.trim() !== '') {
                            attemptNativeSend(href, 'sv-modifier-key');
                          }
                          return false;
                        }
                      }
                    };
                    
                    // 绑定捕获和冒泡阶段
                    container.addEventListener('click', svLinkHandler, true);
                    container.addEventListener('click', svLinkHandler, false);
                    
                    window.__svLinkInterceptor.boundContainers.add(containerId);
                  }
                });
                
                window.__svLinkInterceptor.isActive = true;
              }
              
              // 🔄 MutationObserver - 监听DOM变化，特别是模式切换
              const svModeObserver = new MutationObserver((mutations) => {
                let shouldRescan = false;
                
                mutations.forEach(mutation => {
                  // 检查是否有新的Vditor相关元素
                  if (mutation.type === 'childList') {
                    mutation.addedNodes.forEach(node => {
                      if (node.nodeType === 1) { // Element node
                        const element = node;
                        if (element.classList && (
                          element.classList.contains('vditor-sv') ||
                          element.classList.contains('vditor-preview') ||
                          element.classList.contains('vditor-reset') ||
                          element.querySelector && element.querySelector('.vditor-sv, .vditor-preview')
                        )) {
                          console.log('🔗 [SV] 检测到新的SV相关元素');
                          shouldRescan = true;
                        }
                      }
                    });
                  }
                  
                  // 检查类名变化（模式切换）
                  if (mutation.type === 'attributes' && mutation.attributeName === 'class') {
                    const target = mutation.target;
                    if (target.classList && target.classList.contains('vditor')) {
                      console.log('🔗 [SV] 检测到Vditor类名变化，可能是模式切换');
                      shouldRescan = true;
                    }
                  }
                });
                
                if (shouldRescan) {
                  setTimeout(discoverAndBindContainers, 100);
                }
              });
              
              // 开始观察
              svModeObserver.observe(document.body, {
                childList: true,
                subtree: true,
                attributes: true,
                attributeFilter: ['class', 'style']
              });
              
              // 🚀 立即执行一次扫描
              discoverAndBindContainers();
              
              // 🔄 定期重新扫描（确保不遗漏）
              setInterval(() => {
                discoverAndBindContainers();
              }, 3000);
              
              // 🎯 特殊的SV预览区域强制拦截器
              const forceSvInterceptor = function(e) {
                if (e.target.closest('.vditor-sv .vditor-reset') || 
                    e.target.closest('.vditor-preview')) {
                  const link = e.target.closest('a');
                  if (link) {
                    console.log('🔗 [SV] 🚨 强制SV预览拦截器激活');
                    e.preventDefault();
                    e.stopPropagation();
                    e.stopImmediatePropagation();
                    
                    const href = link.href || link.getAttribute('href');
                    if (href) {
                      attemptNativeSend(href, 'sv-force-interceptor');
                    }
                    return false;
                  }
                }
              };
              
              // 在document级别添加最高优先级的SV拦截器
              document.addEventListener('click', forceSvInterceptor, true);
              
              console.log('🔗 [SV] ✅ 增强型SV分屏模式链接拦截系统初始化完成');
            }, 1000);
            
            // 8. 🎯 编辑模式切换监听 - 确保在模式切换后重新绑定事件
            let lastKnownMode = 'unknown';
            
            function detectModeChange() {
              let currentMode = 'unknown';
              
              if (document.querySelector('.vditor-sv')) {
                currentMode = 'sv';
              } else if (document.querySelector('.vditor-ir')) {
                currentMode = 'ir';
              } else if (document.querySelector('.vditor-wysiwyg')) {
                currentMode = 'wysiwyg';
              }
              
              if (currentMode !== lastKnownMode) {
                console.log('🔗 [MODE] 检测到编辑模式变化:', lastKnownMode, '->', currentMode);
                lastKnownMode = currentMode;
                
                // 模式切换后延迟重新绑定事件
                setTimeout(() => {
                  console.log('🔗 [MODE] 模式切换后重新绑定链接处理器');
                  // 触发重新扫描
                  if (window.__svLinkInterceptor) {
                    window.__svLinkInterceptor.boundContainers.clear();
                  }
                }, 200);
              }
            }
            
            // 定期检测模式变化
            setInterval(detectModeChange, 1000);
            
            // 图片和其他元素的点击处理
            document.addEventListener('click', function(e) {
              
              // 检查是否是本地图片（节点文件夹图片）
              if (e.target.tagName === 'IMG' && 
                  e.target.src.match(/\.(jpg|jpeg|png|gif|webp|bmp|tiff|tif)$/i)) {
                if (e.metaKey) {
                  // Command+点击：在 Finder 中显示图片
                  e.preventDefault();
                  e.stopPropagation();
                  const src = e.target.src;
                  console.log('🔍 Command+点击图片调试:');
                  console.log('   - 原始src:', src);
                  
                  // 从src中提取文件名
                  // src可能是相对路径如: "NodeFolders/nodeId_nodeName/fileName" 或绝对路径
                  let filename = src.split('/').pop();
                  
                  // 清理可能的URL参数和锚点
                  if (filename && filename.includes('?')) {
                    filename = filename.split('?')[0];
                  }
                  if (filename && filename.includes('#')) {
                    filename = filename.split('#')[0];
                  }
                  
                  // 移除可能的URL编码
                  if (filename) {
                    filename = decodeURIComponent(filename);
                  }
                  
                  console.log('   - 提取的文件名:', filename);
                  
                  try {
                    window.webkit?.messageHandlers?.bridge?.postMessage({ 
                      type: 'showImageInFinder',
                      filename: filename
                    });
                    console.log('✅ 已发送showImageInFinder请求');
                  } catch(err) {
                    console.error('❌ 无法发送showImageInFinder请求:', err);
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
                const codeTheme = dark ? 'base16/monokai' : 'github';
                const content = dark ? 'dark' : 'light';
                window.__isDarkMode = dark;
                
                console.log('🎨 应用主题:', { ui, codeTheme, content });
                
                // 正确的主题设置方法
                if (vditor.setTheme) {
                  console.log('🎨 设置编辑器UI主题:', ui);
                  vditor.setTheme(ui);
                }
                
                if (vditor.setContentTheme) {
                  console.log('🎨 设置内容主题:', content);
                  vditor.setContentTheme(content);
                }
                
                if (vditor.setCodeTheme) {
                  console.log('🎨 设置代码高亮主题:', codeTheme);
                  vditor.setCodeTheme(codeTheme);
                } else {
                  console.warn('⚠️ setCodeTheme方法不可用，尝试备选方案');
                  // 备选方案：直接更新options
                  if (vditor.options && vditor.options.preview && vditor.options.preview.hljs) {
                    vditor.options.preview.hljs.style = codeTheme;
                    console.log('✅ 通过options更新hljs样式:', codeTheme);
                  }
                }
                
                // 🎨 确保html和body也获得暗色类名，用于背景样式
                if (dark) {
                  document.documentElement.classList.add('vditor--dark');
                  document.body.classList.add('vditor--dark');
                  document.documentElement.setAttribute('data-theme', 'dark');
                  document.body.setAttribute('data-theme', 'dark');
                } else {
                  document.documentElement.classList.remove('vditor--dark');
                  document.body.classList.remove('vditor--dark');
                  document.documentElement.removeAttribute('data-theme');
                  document.body.removeAttribute('data-theme');
                }
              } catch(e) {
                console.error('Theme apply error:', e);
              }
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
          
          // 🚨 最终安全保障：全局错误捕获和链接强制拦截
          window.addEventListener('beforeunload', function(e) {
            console.log('🔗 [SAFETY] 页面即将卸载，检查是否为意外导航');
            // 在这里可以添加额外的安全检查
          });
          
          // 🔒 最终故障安全机制：监听所有可能的导航尝试
          const originalOpen = window.open;
          window.open = function(...args) {
            const url = args[0];
            console.log('🔗 [SAFETY] 拦截window.open调用:', url);
            
            if (url && typeof url === 'string') {
              // 通过我们的安全机制处理
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge) {
                try {
                  window.webkit.messageHandlers.bridge.postMessage({
                    type: 'openURL',
                    url: url,
                    source: 'window.open'
                  });
                  console.log('✅ [SAFETY] window.open重定向到原生处理器');
                  return null; // 阻止默认的window.open
                } catch(e) {
                  console.error('❌ [SAFETY] window.open重定向失败:', e);
                }
              }
            }
            
            // 如果原生处理失败，允许默认行为
            return originalOpen.apply(window, args);
          };
          
          // 🛡️ 位置改变拦截
          const originalReplace = window.location.replace;
          const originalAssign = window.location.assign;
          
          window.location.replace = function(url) {
            console.log('🔗 [SAFETY] 拦截location.replace:', url);
            if (attemptNativeSend(url, 'location.replace')) {
              return;
            }
            return originalReplace.call(window.location, url);
          };
          
          window.location.assign = function(url) {
            console.log('🔗 [SAFETY] 拦截location.assign:', url);
            if (attemptNativeSend(url, 'location.assign')) {
              return;
            }
            return originalAssign.call(window.location, url);
          };
          
          // 🚀 最终的调试和状态报告
          window.__finalSafetyReport = function() {
            return {
              interceptorsActive: {
                earlyInterceptor: !!window.__earlyLinkInterceptor,
                debugSystem: !!window.__linkDebugSystem,
                performanceMonitor: !!window.__linkPerformanceMonitor,
                windowOpenOverride: window.open !== originalOpen,
                locationReplaceOverride: window.location.replace !== originalReplace,
                locationAssignOverride: window.location.assign !== originalAssign
              },
              linkCounts: window.__linkDebugSystem ? window.__linkDebugSystem.getStatistics() : null,
              webkitAvailable: !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge),
              vditorReady: !!window.vditor,
              currentMode: window.vditor ? 'loaded' : 'loading'
            };
          };
          
          console.log('🛡️ [SAFETY] 最终安全保障机制已激活');
          console.log('🔧 [DEBUG] 使用 window.__finalSafetyReport() 查看完整状态');
          </script>
        </body>
        </html>
        """#
    }
}
