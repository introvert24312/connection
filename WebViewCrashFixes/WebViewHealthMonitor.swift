// WebView健康监控和调试工具
import SwiftUI
import WebKit
import Combine

// MARK: - WebView健康监控器
@MainActor
public class WebViewHealthMonitor: ObservableObject {
    static let shared = WebViewHealthMonitor()
    
    @Published public var isMonitoring = false
    @Published public var healthMetrics: [WebViewHealthMetric] = []
    @Published public var alerts: [HealthAlert] = []
    
    private var cancellables = Set<AnyCancellable>()
    private var monitoringTimer: Timer?
    
    private init() {}
    
    // MARK: - 监控控制
    public func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        print("🔍 WebView健康监控已启动")
        
        // 每5秒收集一次指标
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.collectHealthMetrics()
            }
        }
        
        // 监听WebView相关通知
        setupNotificationListeners()
    }
    
    public func stopMonitoring() {
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        cancellables.removeAll()
        print("⏹️ WebView健康监控已停止")
    }
    
    // MARK: - 指标收集
    private func collectHealthMetrics() {
        let timestamp = Date()
        
        // 收集系统指标
        let memoryUsage = getMemoryUsage()
        let cpuUsage = getCPUUsage()
        
        let metric = WebViewHealthMetric(
            timestamp: timestamp,
            memoryUsage: memoryUsage,
            cpuUsage: cpuUsage,
            activeWebViews: getActiveWebViewCount(),
            crashCount: getCrashCount()
        )
        
        healthMetrics.append(metric)
        
        // 保持最近100条记录
        if healthMetrics.count > 100 {
            healthMetrics.removeFirst()
        }
        
        // 检查是否需要发出警告
        checkForAlerts(metric)
    }
    
    private func checkForAlerts(_ metric: WebViewHealthMetric) {
        // 内存使用过高警告
        if metric.memoryUsage > 500_000_000 { // 500MB
            addAlert(.highMemoryUsage(metric.memoryUsage))
        }
        
        // CPU使用过高警告
        if metric.cpuUsage > 80.0 {
            addAlert(.highCPUUsage(metric.cpuUsage))
        }
        
        // WebView过多警告
        if metric.activeWebViews > 5 {
            addAlert(.tooManyWebViews(metric.activeWebViews))
        }
        
        // 崩溃频率警告
        if metric.crashCount > 0 {
            addAlert(.crashDetected(metric.crashCount))
        }
    }
    
    private func addAlert(_ alert: HealthAlert) {
        // 避免重复警告
        if !alerts.contains(where: { $0.type == alert.type }) {
            alerts.append(alert)
            print("⚠️ WebView健康警告: \(alert.message)")
        }
    }
    
    // MARK: - 系统指标获取
    private func getMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Int(info.resident_size)
        } else {
            return 0
        }
    }
    
    private func getCPUUsage() -> Double {
        var info = proc_taskinfo()
        let result = proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
        
        if result == Int32(MemoryLayout<proc_taskinfo>.size) {
            return Double(info.pti_total_user + info.pti_total_system) / Double(CLOCKS_PER_SEC) * 100.0
        } else {
            return 0.0
        }
    }
    
    private func getActiveWebViewCount() -> Int {
        // 统计当前活跃的WebView数量
        let windows = NSApplication.shared.windows
        var count = 0
        
        for window in windows {
            count += countWebViewsInView(window.contentView)
        }
        
        return count
    }
    
    private func countWebViewsInView(_ view: NSView?) -> Int {
        guard let view = view else { return 0 }
        
        var count = 0
        if view is WKWebView {
            count += 1
        }
        
        for subview in view.subviews {
            count += countWebViewsInView(subview)
        }
        
        return count
    }
    
    private func getCrashCount() -> Int {
        // 这里可以实现崩溃计数逻辑
        // 暂时返回0
        return 0
    }
    
    // MARK: - 通知监听
    private func setupNotificationListeners() {
        // 监听WebView相关事件
        NotificationCenter.default.publisher(for: NSNotification.Name("webViewDidLoad"))
            .sink { [weak self] _ in
                self?.logEvent("WebView加载完成")
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSNotification.Name("webViewDidClose"))
            .sink { [weak self] _ in
                self?.logEvent("WebView已关闭")
            }
            .store(in: &cancellables)
    }
    
    private func logEvent(_ message: String) {
        print("📝 WebView事件: \(message)")
    }
    
    // MARK: - 诊断方法
    public func generateHealthReport() -> String {
        var report = """
        # WebView健康报告
        
        ## 监控状态
        - 监控中: \(isMonitoring ? "是" : "否")
        - 记录数量: \(healthMetrics.count)
        - 警告数量: \(alerts.count)
        
        ## 当前指标
        """
        
        if let latest = healthMetrics.last {
            report += """
            
            - 内存使用: \(formatBytes(latest.memoryUsage))
            - CPU使用: \(String(format: "%.1f", latest.cpuUsage))%
            - 活跃WebView: \(latest.activeWebViews)
            - 崩溃次数: \(latest.crashCount)
            """
        }
        
        report += """
        
        ## 近期警告
        """
        
        for alert in alerts.suffix(5) {
            report += "\n- \(alert.timestamp.formatted()): \(alert.message)"
        }
        
        return report
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.style = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - 数据结构
public struct WebViewHealthMetric {
    let timestamp: Date
    let memoryUsage: Int // 字节
    let cpuUsage: Double // 百分比
    let activeWebViews: Int
    let crashCount: Int
}

public struct HealthAlert: Identifiable {
    public let id = UUID()
    let timestamp: Date
    let type: AlertType
    let message: String
    
    init(_ type: AlertType) {
        self.timestamp = Date()
        self.type = type
        self.message = type.message
    }
    
    enum AlertType {
        case highMemoryUsage(Int)
        case highCPUUsage(Double)
        case tooManyWebViews(Int)
        case crashDetected(Int)
        
        var message: String {
            switch self {
            case .highMemoryUsage(let bytes):
                let formatter = ByteCountFormatter()
                return "内存使用过高: \(formatter.string(fromByteCount: Int64(bytes)))"
            case .highCPUUsage(let usage):
                return "CPU使用过高: \(String(format: "%.1f", usage))%"
            case .tooManyWebViews(let count):
                return "WebView过多: \(count)个"
            case .crashDetected(let count):
                return "检测到崩溃: \(count)次"
            }
        }
    }
}

extension HealthAlert.AlertType: Equatable {
    public static func == (lhs: HealthAlert.AlertType, rhs: HealthAlert.AlertType) -> Bool {
        switch (lhs, rhs) {
        case (.highMemoryUsage, .highMemoryUsage),
             (.highCPUUsage, .highCPUUsage),
             (.tooManyWebViews, .tooManyWebViews),
             (.crashDetected, .crashDetected):
            return true
        default:
            return false
        }
    }
}

// MARK: - 调试面板视图
public struct WebViewHealthPanel: View {
    @StateObject private var monitor = WebViewHealthMonitor.shared
    @State private var showingReport = false
    @State private var reportContent = ""
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题和控制
            HStack {
                Text("WebView健康监控")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(monitor.isMonitoring ? "停止监控" : "开始监控") {
                    if monitor.isMonitoring {
                        monitor.stopMonitoring()
                    } else {
                        monitor.startMonitoring()
                    }
                }
                .buttonStyle(.bordered)
            }
            
            // 当前指标
            if let latest = monitor.healthMetrics.last {
                MetricsView(metric: latest)
            }
            
            // 警告列表
            if !monitor.alerts.isEmpty {
                AlertsView(alerts: monitor.alerts)
            }
            
            // 历史图表（简化版本）
            if monitor.healthMetrics.count > 1 {
                HistoryView(metrics: monitor.healthMetrics)
            }
            
            Spacer()
            
            // 报告按钮
            HStack {
                Spacer()
                Button("生成报告") {
                    reportContent = monitor.generateHealthReport()
                    showingReport = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showingReport) {
            NavigationView {
                ScrollView {
                    Text(reportContent)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                }
                .navigationTitle("健康报告")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") {
                            showingReport = false
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 子视图
private struct MetricsView: View {
    let metric: WebViewHealthMetric
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前指标")
                .font(.headline)
            
            HStack {
                MetricCard(
                    title: "内存",
                    value: formatBytes(metric.memoryUsage),
                    color: metric.memoryUsage > 500_000_000 ? .red : .blue
                )
                
                MetricCard(
                    title: "CPU",
                    value: "\(String(format: "%.1f", metric.cpuUsage))%",
                    color: metric.cpuUsage > 80 ? .red : .green
                )
                
                MetricCard(
                    title: "WebView",
                    value: "\(metric.activeWebViews)",
                    color: metric.activeWebViews > 5 ? .orange : .blue
                )
            }
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.style = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .padding()
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .frame(maxWidth: .infinity)
    }
}

private struct AlertsView: View {
    let alerts: [HealthAlert]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("警告 (\(alerts.count))")
                .font(.headline)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(alerts.suffix(5)) { alert in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            
                            Text(alert.message)
                                .font(.caption)
                            
                            Spacer()
                            
                            Text(alert.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
            }
            .frame(maxHeight: 120)
        }
    }
}

private struct HistoryView: View {
    let metrics: [WebViewHealthMetric]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("历史趋势")
                .font(.headline)
            
            // 简化的趋势显示
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(metrics.suffix(20).indices, id: \.self) { index in
                    let metric = metrics.suffix(20)[index]
                    let normalizedHeight = max(4, min(40, Int(metric.cpuUsage / 2)))
                    
                    Rectangle()
                        .fill(metric.cpuUsage > 80 ? Color.red : Color.blue)
                        .frame(width: 8, height: CGFloat(normalizedHeight))
                }
            }
            .frame(height: 50)
        }
    }
}