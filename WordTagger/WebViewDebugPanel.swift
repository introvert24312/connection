import SwiftUI
import WebKit

/// WebView调试面板 - 用于监控和调试WebView状态
/// 帮助诊断权限问题和生命周期问题
struct WebViewDebugPanel: View {
    @StateObject private var updateManager = WebViewUpdateManager.shared
    @StateObject private var errorHandler = WebViewErrorHandler.shared
    @StateObject private var healthMonitor = WebViewHealthMonitor.shared
    @State private var isExpanded = false
    @State private var showErrorDetails = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 状态指示栏
            HStack {
                // 健康状态指示器
                HStack(spacing: 4) {
                    Circle()
                        .fill(healthStatusColor)
                        .frame(width: 8, height: 8)
                    Text("WebView")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(healthStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 统计信息
                HStack(spacing: 12) {
                    Label("\(updateManager.statistics.active)", systemImage: "globe")
                        .font(.caption)
                        .foregroundColor(.primary)
                    
                    if !errorHandler.recentErrors.isEmpty {
                        Label("\(errorHandler.recentErrors.count)", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.red)
                            .onTapGesture {
                                showErrorDetails.toggle()
                            }
                    }
                    
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            // 详细信息面板
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // 统计信息
                    HStack {
                        VStack(alignment: .leading) {
                            Text("活跃WebView")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(updateManager.statistics.active)")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .leading) {
                            Text("待处理更新")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(updateManager.statistics.pending)")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .leading) {
                            Text("错误数量")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(errorHandler.recentErrors.count)")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(errorHandler.recentErrors.isEmpty ? .primary : .red)
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    // 操作按钮
                    HStack {
                        Button("清理缓存") {
                            clearWebViewCaches()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("重置错误") {
                            errorHandler.clearErrors()
                            healthMonitor.resetErrorCount()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(errorHandler.recentErrors.isEmpty)
                        
                        Spacer()
                        
                        Button("查看错误") {
                            showErrorDetails = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(errorHandler.recentErrors.isEmpty)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
        }
        .sheet(isPresented: $showErrorDetails) {
            WebViewErrorDetailView()
                .frame(minWidth: 500, minHeight: 300)
        }
    }
    
    private var healthStatusColor: Color {
        switch healthMonitor.healthStatus {
        case .healthy:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        case .unknown:
            return .gray
        }
    }
    
    private var healthStatusText: String {
        switch healthMonitor.healthStatus {
        case .healthy:
            return "正常"
        case .warning:
            return "警告"
        case .critical:
            return "严重"
        case .unknown:
            return "未知"
        }
    }
    
    private func clearWebViewCaches() {
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        
        dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date(timeIntervalSince1970: 0)) {
            print("🧹 WebView缓存已清理")
        }
    }
}

/// WebView错误详情视图
struct WebViewErrorDetailView: View {
    @StateObject private var errorHandler = WebViewErrorHandler.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 0) {
                // 错误列表
                if errorHandler.recentErrors.isEmpty {
                    VStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 48))
                                .foregroundColor(.green)
                            Text("暂无错误")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                } else {
                    List(errorHandler.recentErrors) { error in
                        WebViewErrorRow(error: error)
                    }
                }
                
                // 底部工具栏
                HStack {
                    Text("共 \(errorHandler.recentErrors.count) 个错误")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("清除所有") {
                        errorHandler.clearErrors()
                    }
                    .disabled(errorHandler.recentErrors.isEmpty)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
            }
            .navigationTitle("WebView 错误日志")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// WebView错误行视图
struct WebViewErrorRow: View {
    let error: WebViewErrorHandler.WebViewError
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // 错误类型图标
                Image(systemName: errorTypeIcon)
                    .foregroundColor(errorTypeColor)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(errorTypeText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(error.message)
                        .font(.body)
                        .lineLimit(isExpanded ? nil : 2)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timeFormatter.string(from: error.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(error.webViewId)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isExpanded.toggle()
            }
        }
        .padding(.vertical, 4)
    }
    
    private var errorTypeIcon: String {
        switch error.errorType {
        case .navigationFailed, .provisionalNavigationFailed:
            return "globe.badge.chevron.backward"
        case .javaScriptError:
            return "doc.text.below.ecg"
        case .memoryWarning:
            return "memorychip"
        case .permissionDenied:
            return "lock.shield"
        }
    }
    
    private var errorTypeColor: Color {
        switch error.errorType {
        case .navigationFailed, .provisionalNavigationFailed:
            return .orange
        case .javaScriptError:
            return .blue
        case .memoryWarning:
            return .red
        case .permissionDenied:
            return .purple
        }
    }
    
    private var errorTypeText: String {
        switch error.errorType {
        case .navigationFailed:
            return "导航失败"
        case .provisionalNavigationFailed:
            return "临时导航失败"
        case .javaScriptError:
            return "JavaScript错误"
        case .memoryWarning:
            return "内存警告"
        case .permissionDenied:
            return "权限被拒绝"
        }
    }
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

#Preview {
    VStack {
        WebViewDebugPanel()
        Spacer()
    }
    .frame(width: 400, height: 200)
}