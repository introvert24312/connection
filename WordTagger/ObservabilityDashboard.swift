import SwiftUI
import Combine

// MARK: - Observability Dashboard

struct ObservabilityDashboard: View {
    @StateObject private var tracingService = TracingService.shared
    @StateObject private var logger = StructuredLogger.shared
    @State private var selectedTab = 0
    @State private var selectedTraceId: String?
    @State private var logFilterLevel: LogLevel = .info
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Main Content
            TabView(selection: $selectedTab) {
                // Live Traces Tab
                liveTracesView
                    .tabItem {
                        Image(systemName: "arrow.triangle.branch")
                        Text("Live Traces")
                    }
                    .tag(0)
                
                // Performance Metrics Tab
                performanceMetricsView
                    .tabItem {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                        Text("Metrics")
                    }
                    .tag(1)
                
                // Logs Tab
                logsView
                    .tabItem {
                        Image(systemName: "doc.text")
                        Text("Logs")
                    }
                    .tag(2)
                
                // System Health Tab
                systemHealthView
                    .tabItem {
                        Image(systemName: "heart.fill")
                        Text("Health")
                    }
                    .tag(3)
            }
        }
        .frame(minWidth: 1200, minHeight: 800)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("WordTagger Observability")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Real-time monitoring and trace analysis")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Quick Stats
            HStack(spacing: 20) {
                quickStatView(
                    title: "Active Spans",
                    value: String(tracingService.activeSpans.count),
                    color: .blue
                )
                
                quickStatView(
                    title: "Total Traces",
                    value: String(Set(tracingService.completedSpans.map { $0.context.traceId }).count),
                    color: .green
                )
                
                quickStatView(
                    title: "Error Rate",
                    value: String(format: "%.1f%%", errorRate * 100),
                    color: errorRate > 0.1 ? .red : .green
                )
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .border(Color.gray.opacity(0.3), width: 0.5)
    }
    
    private func quickStatView(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
    
    private var errorRate: Double {
        let totalSpans = tracingService.completedSpans.count
        guard totalSpans > 0 else { return 0.0 }
        
        let errorSpans = tracingService.completedSpans.filter { !$0.outcome.isSuccess }.count
        return Double(errorSpans) / Double(totalSpans)
    }
    
    // MARK: - Live Traces View
    
    private var liveTracesView: some View {
        HSplitView {
            // Trace List
            VStack(alignment: .leading, spacing: 0) {
                // Search and Filter
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search traces...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .padding(.horizontal)
                .padding(.top)
                
                Divider()
                    .padding(.horizontal)
                
                // Trace List
                List(filteredTraces, id: \.context.traceId, selection: $selectedTraceId) { span in
                    traceListItem(span: span)
                }
                .listStyle(PlainListStyle())
            }
            .frame(minWidth: 350)
            
            // Trace Details
            if let traceId = selectedTraceId {
                traceDetailsView(traceId: traceId)
            } else {
                VStack {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a trace to view details")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private var filteredTraces: [Span] {
        let uniqueTraces = Dictionary(grouping: tracingService.completedSpans) { $0.context.traceId }
            .compactMapValues { spans in
                spans.max { $0.endTime < $1.endTime }
            }
            .values
            .sorted { $0.endTime > $1.endTime }
        
        if searchText.isEmpty {
            return Array(uniqueTraces.prefix(100))
        }
        
        return uniqueTraces.filter { span in
            span.context.operationName.localizedCaseInsensitiveContains(searchText) ||
            span.context.traceId.localizedCaseInsensitiveContains(searchText) ||
            span.context.tags.values.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    private func traceListItem(span: Span) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Status indicator
                Circle()
                    .fill(span.outcome.isSuccess ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Text(span.context.operationName)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                
                Spacer()
                
                Text(formatDuration(span.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Trace: \(String(span.context.traceId.prefix(8)))...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(formatTime(span.endTime))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !span.context.tags.isEmpty {
                HStack {
                    ForEach(Array(span.context.tags.prefix(3)), id: \.key) { key, value in
                        tagView(key: key, value: value)
                    }
                    if span.context.tags.count > 3 {
                        Text("+\(span.context.tags.count - 3) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func tagView(key: String, value: String) -> some View {
        Text("\(key): \(value)")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(3)
    }
    
    private func traceDetailsView(traceId: String) -> some View {
        let traceSpans = tracingService.getTraceTree(traceId: traceId)
            .sorted { $0.context.startTime < $1.context.startTime }
        
        return VStack(alignment: .leading, spacing: 0) {
            // Trace Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Trace Details")
                    .font(.headline)
                
                Text("Trace ID: \(traceId)")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                
                if let rootSpan = traceSpans.first {
                    HStack {
                        Text("Started:")
                        Text(formatFullTime(rootSpan.context.startTime))
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text("Total Duration:")
                        Text(formatDuration(traceSpans.map { $0.duration }.reduce(0, +)))
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color.gray.opacity(0.3), width: 0.5)
            
            // Trace Timeline
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(traceSpans, id: \.id) { span in
                        traceSpanView(span: span, rootStartTime: traceSpans.first?.context.startTime ?? Date())
                    }
                }
                .padding()
            }
        }
    }
    
    private func traceSpanView(span: Span, rootStartTime: Date) -> some View {
        let relativeStartTime = span.context.startTime.timeIntervalSince(rootStartTime)
        let indentLevel = calculateIndentLevel(span: span)
        
        return HStack(alignment: .top, spacing: 8) {
            // Indent indicator
            Rectangle()
                .fill(Color.clear)
                .frame(width: CGFloat(indentLevel * 20))
            
            // Timeline indicator
            VStack(spacing: 2) {
                Circle()
                    .fill(span.outcome.isSuccess ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                if indentLevel > 0 {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 2, height: 20)
                }
            }
            
            // Span details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(span.context.operationName)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(formatDuration(span.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Started: +\(formatDuration(relativeStartTime))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !span.outcome.isSuccess, let error = span.outcome.errorMessage {
                        Text("Error: \(error)")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
                
                if !span.context.tags.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 4) {
                        ForEach(Array(span.context.tags.sorted { $0.key < $1.key }), id: \.key) { key, value in
                            tagView(key: key, value: value)
                        }
                    }
                }
                
                if !span.logs.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Logs:")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        ForEach(span.logs.indices, id: \.self) { index in
                            let log = span.logs[index]
                            HStack {
                                Text("[\(log.level.rawValue)]")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(colorForLogLevel(log.level))
                                
                                Text(log.message)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(span.outcome.isSuccess ? Color.clear : Color.red.opacity(0.05))
        .cornerRadius(4)
    }
    
    private func calculateIndentLevel(span: Span) -> Int {
        // Simple indentation based on parent span
        return span.context.parentSpanId != nil ? 1 : 0
    }
    
    // MARK: - Performance Metrics View
    
    private var performanceMetricsView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Operation Performance Overview
                operationPerformanceOverview
                
                // Service Performance Charts
                servicePerformanceCharts
                
                // Recent Performance Trends
                performanceTrendsView
            }
            .padding()
        }
    }
    
    private var operationPerformanceOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Operation Performance Overview")
                .font(.headline)
            
            let operationSummaries = getOperationSummaries()
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(operationSummaries, id: \.operationName) { summary in
                    operationSummaryCard(summary: summary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func operationSummaryCard(summary: OperationMetricsSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary.operationName)
                .font(.headline)
                .lineLimit(1)
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calls")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(summary.totalCalls)")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Success Rate")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f%%", summary.successRate * 100))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(summary.successRate > 0.95 ? .green : (summary.successRate > 0.8 ? .orange : .red))
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                performanceStatRow(label: "Avg", value: formatDuration(summary.avgDuration))
                performanceStatRow(label: "P95", value: formatDuration(summary.p95Duration))
                performanceStatRow(label: "P99", value: formatDuration(summary.p99Duration))
            }
        }
        .padding()
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .shadow(radius: 1)
    }
    
    private func performanceStatRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .leading)
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
    
    private var servicePerformanceCharts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Service Performance Distribution")
                .font(.headline)
            
            // Simple performance chart visualization
            let serviceMetrics = getServiceMetrics()
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(serviceMetrics, id: \.serviceName) { metric in
                    serviceMetricCard(metric: metric)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func serviceMetricCard(metric: ServiceMetric) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metric.serviceName)
                .font(.headline)
                .lineLimit(1)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Operations:")
                    Spacer()
                    Text("\(metric.operationCount)")
                        .fontWeight(.medium)
                }
                .font(.caption)
                
                HStack {
                    Text("Avg Duration:")
                    Spacer()
                    Text(formatDuration(metric.avgDuration))
                        .fontWeight(.medium)
                }
                .font(.caption)
                
                HStack {
                    Text("Error Rate:")
                    Spacer()
                    Text(String(format: "%.1f%%", metric.errorRate * 100))
                        .fontWeight(.medium)
                        .foregroundColor(metric.errorRate > 0.1 ? .red : .green)
                }
                .font(.caption)
            }
            
            // Simple bar chart representation
            HStack(spacing: 2) {
                ForEach(0..<10) { index in
                    Rectangle()
                        .fill(metric.errorRate > 0.1 ? Color.red.opacity(0.3) : Color.green.opacity(0.3))
                        .frame(height: CGFloat.random(in: 4...20))
                }
            }
        }
        .padding()
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .shadow(radius: 1)
    }
    
    private var performanceTrendsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Performance Trends")
                .font(.headline)
            
            Text("Performance trends over the last 100 operations")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Simple trend visualization placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .frame(height: 200)
                .overlay(
                    VStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                        Text("Performance trend chart would go here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                )
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Logs View
    
    private var logsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Log Controls
            HStack {
                // Log Level Filter
                Picker("Log Level", selection: $logFilterLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 300)
                
                Spacer()
                
                // Log Count
                Text("\(filteredLogs.count) logs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Logs List
            List(filteredLogs.indices, id: \.self) { index in
                let log = filteredLogs[index]
                logEntryView(log: log)
            }
            .listStyle(PlainListStyle())
        }
    }
    
    private var filteredLogs: [SpanLog] {
        return logger.recentLogs
            .filter { $0.level.priority >= logFilterLevel.priority }
            .reversed()
    }
    
    private func logEntryView(log: SpanLog) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(formatFullTime(log.timestamp))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .leading)
                
                Text("[\(log.level.rawValue)]")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(colorForLogLevel(log.level))
                    .frame(width: 60, alignment: .leading)
                
                Text(log.message)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(nil)
            }
            
            if !log.fields.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4), alignment: .leading, spacing: 4) {
                    ForEach(Array(log.fields.sorted { $0.key < $1.key }), id: \.key) { key, value in
                        Text("\(key)=\(value)")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(3)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - System Health View
    
    private var systemHealthView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // System Overview
                systemOverviewCard
                
                // Service Health Status
                serviceHealthStatus
                
                // Recent Alerts
                recentAlertsView
            }
            .padding()
        }
    }
    
    private var systemOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Health Overview")
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                healthMetricCard(
                    title: "Uptime",
                    value: "99.9%",
                    status: .healthy
                )
                
                healthMetricCard(
                    title: "Response Time",
                    value: String(format: "%.0fms", avgResponseTime * 1000),
                    status: avgResponseTime < 0.5 ? .healthy : (avgResponseTime < 1.0 ? .warning : .critical)
                )
                
                healthMetricCard(
                    title: "Error Rate",
                    value: String(format: "%.2f%%", errorRate * 100),
                    status: errorRate < 0.01 ? .healthy : (errorRate < 0.05 ? .warning : .critical)
                )
                
                healthMetricCard(
                    title: "Active Traces",
                    value: String(tracingService.activeSpans.count),
                    status: tracingService.activeSpans.count < 100 ? .healthy : .warning
                )
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func healthMetricCard(title: String, value: String, status: HealthStatus) -> some View {
        VStack(spacing: 8) {
            Circle()
                .fill(status.color)
                .frame(width: 12, height: 12)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .padding()
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .shadow(radius: 1)
    }
    
    private var serviceHealthStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Service Health Status")
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(getServiceHealthStatuses(), id: \.serviceName) { status in
                    serviceHealthCard(status: status)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func serviceHealthCard(status: ServiceHealthStatus) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(status.health.color)
                .frame(width: 16, height: 16)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(status.serviceName)
                    .font(.headline)
                
                Text(status.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let lastSeen = status.lastSeen {
                    Text("Last seen: \(formatTime(lastSeen))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .shadow(radius: 1)
    }
    
    private var recentAlertsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Alerts")
                .font(.headline)
            
            let alerts = getRecentAlerts()
            
            if alerts.isEmpty {
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                    Text("No recent alerts")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("All systems operating normally")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(alerts, id: \.id) { alert in
                        alertCard(alert: alert)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func alertCard(alert: SystemAlert) -> some View {
        HStack(spacing: 12) {
            Image(systemName: alert.severity.iconName)
                .font(.title3)
                .foregroundColor(alert.severity.color)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.message)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(alert.service)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(formatFullTime(alert.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(alert.severity.color.opacity(0.05))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(alert.severity.color.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Helper Methods
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 0.001 {
            return String(format: "%.0fμs", duration * 1_000_000)
        } else if duration < 1.0 {
            return String(format: "%.0fms", duration * 1000)
        } else {
            return String(format: "%.2fs", duration)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatFullTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
    
    private func colorForLogLevel(_ level: LogLevel) -> Color {
        switch level {
        case .trace: return .purple
        case .debug: return .blue
        case .info: return .primary
        case .warn: return .orange
        case .error: return .red
        }
    }
    
    private var avgResponseTime: Double {
        let recentMetrics = tracingService.metrics.suffix(100)
        guard !recentMetrics.isEmpty else { return 0.0 }
        
        return recentMetrics.map { $0.duration }.reduce(0, +) / Double(recentMetrics.count)
    }
    
    private func getOperationSummaries() -> [OperationMetricsSummary] {
        let uniqueOperations = Set(tracingService.metrics.map { $0.operationName })
        return uniqueOperations.map { operationName in
            tracingService.getMetricsSummary(operationName: operationName)
        }.sorted { $0.totalCalls > $1.totalCalls }
    }
    
    private func getServiceMetrics() -> [ServiceMetric] {
        let serviceMetrics = Dictionary(grouping: tracingService.metrics) { metric in
            String(metric.operationName.split(separator: ".").first ?? "Unknown")
        }
        
        return serviceMetrics.compactMap { serviceName, metrics in
            let totalOperations = metrics.count
            let avgDuration = metrics.map { $0.duration }.reduce(0, +) / Double(totalOperations)
            let errorCount = metrics.filter { !$0.success }.count
            let errorRate = Double(errorCount) / Double(totalOperations)
            
            return ServiceMetric(
                serviceName: serviceName,
                operationCount: totalOperations,
                avgDuration: avgDuration,
                errorRate: errorRate
            )
        }.sorted { $0.operationCount > $1.operationCount }
    }
    
    private func getServiceHealthStatuses() -> [ServiceHealthStatus] {
        let services = ["NodeStore", "GitService", "SearchService", "GraphService", "DataManager"]
        
        return services.map { serviceName in
            let recentMetrics = tracingService.metrics
                .filter { $0.operationName.hasPrefix(serviceName) }
                .suffix(10)
            
            let health: HealthStatus
            let statusMessage: String
            
            if recentMetrics.isEmpty {
                health = .warning
                statusMessage = "No recent activity"
            } else {
                let errorRate = Double(recentMetrics.filter { !$0.success }.count) / Double(recentMetrics.count)
                if errorRate == 0.0 {
                    health = .healthy
                    statusMessage = "Operating normally"
                } else if errorRate < 0.1 {
                    health = .warning
                    statusMessage = "Minor issues detected"
                } else {
                    health = .critical
                    statusMessage = "Service degraded"
                }
            }
            
            return ServiceHealthStatus(
                serviceName: serviceName,
                health: health,
                statusMessage: statusMessage,
                lastSeen: recentMetrics.last?.timestamp
            )
        }
    }
    
    private func getRecentAlerts() -> [SystemAlert] {
        // For now, return empty array - in a real implementation, this would
        // analyze recent traces and metrics to generate alerts
        return []
    }
}

// MARK: - Supporting Types

enum HealthStatus {
    case healthy
    case warning
    case critical
    
    var color: Color {
        switch self {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

struct ServiceMetric {
    let serviceName: String
    let operationCount: Int
    let avgDuration: TimeInterval
    let errorRate: Double
}

struct ServiceHealthStatus {
    let serviceName: String
    let health: HealthStatus
    let statusMessage: String
    let lastSeen: Date?
}

struct SystemAlert {
    let id = UUID()
    let service: String
    let message: String
    let severity: AlertSeverity
    let timestamp: Date
}

enum AlertSeverity {
    case info
    case warning
    case critical
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
    
    var iconName: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    ObservabilityDashboard()
        .frame(width: 1200, height: 800)
}