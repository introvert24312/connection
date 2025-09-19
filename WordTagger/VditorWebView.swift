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
            
            /* 标题颜色 - 模仿Tanda的彩色标题层次 */
            .vditor--dark .vditor-reset h1 { 
              color: #ff6b6b !important; /* 红色 - 类似Tanda的H1 */
              font-weight: normal;
              padding-top: 0.25em;
              padding-bottom: 0.25em;
            }
            .vditor--dark .vditor-reset h2 { 
              color: #ff69b4 !important; /* 粉色 - 类似Tanda的H2 */
              font-weight: normal;
              padding-top: 0.6em;
              padding-bottom: 0.6em;
            }
            .vditor--dark .vditor-reset h3 { 
              color: #ffd93d !important; /* 黄色 - 类似Tanda的H3 */
              font-weight: normal;
              padding-top: 0.25em;
              padding-bottom: 0.25em;
            }
            .vditor--dark .vditor-reset h4 { 
              color: #6bcf7f !important; /* 绿色 - 类似Tanda的H4 */
              font-weight: normal;
              padding-top: 0.25em;
              padding-bottom: 0.25em;
            }
            .vditor--dark .vditor-reset h5 { 
              color: #74c0fc !important; /* 蓝色 */
              font-weight: normal;
            }
            .vditor--dark .vditor-reset h6 { 
              color: #d0bfff !important; /* 紫色 */
              font-weight: normal;
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
            
            /* 代码块 - 使用Tanda的深色背景 */
            .vditor--dark .vditor-reset pre,
            .vditor--dark .vditor-reset pre code,
            .vditor--dark .vditor-ir__node pre,
            .vditor--dark .vditor-ir__node pre code,
            .vditor--dark .vditor-sv pre,
            .vditor--dark .vditor-sv pre code,
            .vditor--dark .vditor-wysiwyg pre,
            .vditor--dark .vditor-wysiwyg pre code {
              background: #303233 !important; /* Tanda的代码块背景色 */
              color: #E6E6E6 !important;
              border: 2px solid #292A2B;
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
            
            /* base16/pop主题代码块 - 确保背景适配Tanda风格 */
            .vditor--dark .hljs {
              background: #303233 !important; /* 保持Tanda的代码块背景 */
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
            
            // 增强的超链接Command+点击处理 - 多层次拦截确保成功
            function handleLinkClick(e) {
              console.log('🔗 Click detected, metaKey:', e.metaKey, 'shiftKey:', e.shiftKey, 'target:', e.target, 'tagName:', e.target.tagName);
              
              // 支持Shift+点击或Command+点击
              if (!e.metaKey && !e.shiftKey) return;
              
              let target = e.target;
              let attempts = 0;
              const maxAttempts = 10;
              
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
                console.log('🔗 Found link element:', target);
                console.log('🔗 Link href:', url);
                
                if (url && url.trim() !== '') {
                  console.log('🔗 修饰键+点击链接:', url, '(metaKey:', e.metaKey, ', shiftKey:', e.shiftKey, ')');
                  
                  // 强制阻止所有默认行为和事件传播
                  e.preventDefault();
                  e.stopPropagation();
                  e.stopImmediatePropagation();
                  
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
                      console.log('🔗 准备发送消息到原生代码...', { type: 'openURL', url: url });
                      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge) {
                        console.log('🔗 WebKit消息处理器可用，发送消息...');
                        window.webkit.messageHandlers.bridge.postMessage({ 
                          type: 'openURL',
                          url: url
                        });
                        console.log('✅ 已发送openURL消息到原生代码');
                      } else {
                        console.error('❌ WebKit消息处理器不可用');
                        console.log('🔗 尝试备选方案：window.open');
                        window.open(url, '_blank');
                        console.log('✅ 使用window.open打开链接');
                      }
                    } catch(err) {
                      console.error('❌ 发送openURL消息失败:', err);
                      try {
                        console.log('🔗 备选方案：window.open');
                        window.open(url, '_blank');
                        console.log('✅ 备选方案：使用window.open打开链接');
                      } catch(backupErr) {
                        console.error('❌ 备选方案也失败:', backupErr);
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
            
            // 多重事件监听策略 - 确保在各种情况下都能拦截链接点击
            
            // 1. 在捕获阶段拦截，优先级最高
            document.addEventListener('click', handleLinkClick, true);
            
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
                
                // 如果有修饰键但没有被处理，强制处理
                if ((e.metaKey || e.shiftKey) && !e.defaultPrevented) {
                  console.log('🔗 [BACKUP] 备用处理器激活');
                  handleLinkClick(e);
                }
              }
            }, true);
            
            // 7. 定时器方式的深度拦截 - 在Vditor加载完成后重新绑定事件
            setTimeout(() => {
              console.log('🔗 延迟绑定链接处理器...');
              // 查找所有可能的容器并绑定事件
              const containers = [
                document,
                document.body,
                document.querySelector('.vditor'),
                document.querySelector('.vditor-reset'),
                document.querySelector('#vditor')
              ].filter(Boolean);
              
              containers.forEach(container => {
                console.log('🔗 在容器上绑定事件:', container);
                container.addEventListener('click', function(e) {
                  if ((e.metaKey || e.shiftKey) && e.target.closest('a')) {
                    console.log('🔗 [DEEP] 深度拦截器触发');
                    handleLinkClick(e);
                  }
                }, true);
              });
            }, 1000);
            
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
                
                // 只使用setTheme方法，不干扰内容
                if (vditor.setTheme) {
                  vditor.setTheme(ui, content, codeTheme);
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
          </script>
        </body>
        </html>
        """#
    }
}
