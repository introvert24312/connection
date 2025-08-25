import SwiftUI
import Charts

// MARK: - Service Health Dashboard

struct ServiceHealthDashboard: View {
    @StateObject private var serviceRegistry = ServiceRegistry.shared
    @State private var selectedService: ServiceDescriptor?
    @State private var showingServiceDetails = false
    @State private var refreshTimer: Timer?
    @State private var selectedServiceType: ServiceType? = nil
    @State private var searchText = ""
    
    private var filteredServices: [ServiceDescriptor] {
        var services = serviceRegistry.getAllServices()
        
        // Filter by service type
        if let selectedType = selectedServiceType {
            services = services.filter { $0.type == selectedType }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            services = services.filter { service in
                service.name.localizedCaseInsensitiveContains(searchText) ||
                service.purpose.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return services
    }
    
    private var healthSummary: (healthy: Int, warning: Int, critical: Int, unknown: Int) {
        let services = filteredServices
        var healthy = 0, warning = 0, critical = 0, unknown = 0
        
        for service in services {
            switch serviceRegistry.health(for: service.name).status {
            case .healthy: healthy += 1
            case .warning: warning += 1
            case .critical: critical += 1
            case .unknown: unknown += 1
            }
        }
        
        return (healthy, warning, critical, unknown)
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                // Header
                HeaderView(
                    searchText: $searchText,
                    selectedServiceType: $selectedServiceType,
                    healthSummary: healthSummary
                )
                
                // Service List
                List(filteredServices, selection: $selectedService) { service in
                    ServiceRowView(
                        service: service,
                        health: serviceRegistry.health(for: service.name)
                    )
                    .tag(service)
                }
                .listStyle(SidebarListStyle())
            }
            .navigationTitle("Services")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: refreshServices) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh all services")
                }
            }
        } detail: {
            // Detail View
            if let selectedService = selectedService {
                ServiceDetailView(
                    service: selectedService,
                    health: serviceRegistry.health(for: selectedService.name),
                    serviceRegistry: serviceRegistry
                )
            } else {
                ServiceOverviewView(
                    serviceRegistry: serviceRegistry,
                    healthSummary: healthSummary
                )
            }
        }
        .onAppear {
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }
    
    private func refreshServices() {
        serviceRegistry.forceHealthCheck()
    }
    
    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            serviceRegistry.forceHealthCheck()
        }
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Header View

private struct HeaderView: View {
    @Binding var searchText: String
    @Binding var selectedServiceType: ServiceType?
    let healthSummary: (healthy: Int, warning: Int, critical: Int, unknown: Int)
    
    var body: some View {
        VStack(spacing: 12) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search services...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal)
            
            // Service Type Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ServiceTypeChip(
                        title: "All",
                        isSelected: selectedServiceType == nil,
                        color: .blue
                    ) {
                        selectedServiceType = nil
                    }
                    
                    ForEach(ServiceType.allCases, id: \.self) { type in
                        ServiceTypeChip(
                            title: type.displayName,
                            isSelected: selectedServiceType == type,
                            color: type.color
                        ) {
                            selectedServiceType = type
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Health Summary
            HealthSummaryView(summary: healthSummary)
                .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Service Type Chip

private struct ServiceTypeChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSelected ? color : color.opacity(0.1))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Health Summary View

private struct HealthSummaryView: View {
    let summary: (healthy: Int, warning: Int, critical: Int, unknown: Int)
    
    var body: some View {
        HStack(spacing: 16) {
            HealthIndicator(
                status: .healthy,
                count: summary.healthy,
                icon: "checkmark.circle.fill"
            )
            HealthIndicator(
                status: .warning,
                count: summary.warning,
                icon: "exclamationmark.triangle.fill"
            )
            HealthIndicator(
                status: .critical,
                count: summary.critical,
                icon: "xmark.circle.fill"
            )
            HealthIndicator(
                status: .unknown,
                count: summary.unknown,
                icon: "questionmark.circle.fill"
            )
        }
    }
}

private struct HealthIndicator: View {
    let status: ServiceHealthStatus
    let count: Int
    let icon: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(status.color)
                .font(.caption)
            Text("\(count)")
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Service Row View

private struct ServiceRowView: View {
    let service: ServiceDescriptor
    let health: ServiceHealth
    
    var body: some View {
        HStack {
            // Health Status Indicator
            Image(systemName: health.status.icon)
                .foregroundColor(health.status.color)
                .font(.system(size: 12))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(service.purpose)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    Text(service.type.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(service.type.color.opacity(0.2))
                        .foregroundColor(service.type.color)
                        .cornerRadius(4)
                    
                    Spacer()
                    
                    Text(service.version)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Service Overview

private struct ServiceOverviewView: View {
    @ObservedObject var serviceRegistry: ServiceRegistry
    let healthSummary: (healthy: Int, warning: Int, critical: Int, unknown: Int)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Overall Health Chart
                HealthChartView(healthSummary: healthSummary)
                    .frame(height: 200)
                
                // Service Type Distribution
                ServiceTypeDistributionView(serviceRegistry: serviceRegistry)
                
                // Recent Health Changes
                RecentHealthChangesView(serviceRegistry: serviceRegistry)
            }
            .padding()
        }
        .navigationTitle("Service Overview")
    }
}

// MARK: - Health Chart View

private struct HealthChartView: View {
    let healthSummary: (healthy: Int, warning: Int, critical: Int, unknown: Int)
    
    private var chartData: [HealthChartData] {
        [
            HealthChartData(status: "Healthy", count: healthSummary.healthy, color: .green),
            HealthChartData(status: "Warning", count: healthSummary.warning, color: .orange),
            HealthChartData(status: "Critical", count: healthSummary.critical, color: .red),
            HealthChartData(status: "Unknown", count: healthSummary.unknown, color: .gray)
        ].filter { $0.count > 0 }
    }
    
    var body: some View {
        VStack {
            Text("Service Health Distribution")
                .font(.headline)
                .padding(.bottom)
            
            if #available(macOS 13.0, *) {
                Chart(chartData, id: \.status) { item in
                    SectorMark(
                        angle: .value("Count", item.count),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(item.color)
                    .opacity(0.8)
                }
                .chartLegend(position: .bottom, alignment: .center)
            } else {
                // Fallback for older macOS versions
                HStack(spacing: 20) {
                    ForEach(chartData, id: \.status) { item in
                        VStack {
                            Text("\(item.count)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(item.color)
                            Text(item.status)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

private struct HealthChartData {
    let status: String
    let count: Int
    let color: Color
}

// MARK: - Service Type Distribution

private struct ServiceTypeDistributionView: View {
    @ObservedObject var serviceRegistry: ServiceRegistry
    
    private var serviceTypeData: [ServiceTypeData] {
        ServiceType.allCases.map { type in
            let services = serviceRegistry.getServicesByType(type)
            return ServiceTypeData(
                type: type,
                count: services.count,
                services: services
            )
        }.filter { $0.count > 0 }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Service Distribution by Type")
                .font(.headline)
                .padding(.bottom)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(serviceTypeData, id: \.type) { data in
                    ServiceTypeCard(data: data)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

private struct ServiceTypeData {
    let type: ServiceType
    let count: Int
    let services: [ServiceDescriptor]
}

private struct ServiceTypeCard: View {
    let data: ServiceTypeData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(data.type.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(data.count)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(data.type.color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                ForEach(data.services.prefix(3), id: \.name) { service in
                    Text("• \(service.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if data.services.count > 3 {
                    Text("• and \(data.services.count - 3) more...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .padding()
        .background(data.type.color.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(data.type.color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Recent Health Changes

private struct RecentHealthChangesView: View {
    @ObservedObject var serviceRegistry: ServiceRegistry
    
    private var recentChanges: [HealthChangeData] {
        // For demonstration - in real app, you'd track health changes over time
        serviceRegistry.getAllServices().compactMap { service in
            let health = serviceRegistry.health(for: service.name)
            if health.status != .healthy {
                return HealthChangeData(
                    serviceName: service.name,
                    status: health.status,
                    message: health.message,
                    timestamp: health.timestamp
                )
            }
            return nil
        }.sorted { $0.timestamp > $1.timestamp }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Recent Health Issues")
                .font(.headline)
                .padding(.bottom)
            
            if recentChanges.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("All services are healthy!")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(recentChanges.prefix(5), id: \.serviceName) { change in
                        HealthChangeRow(change: change)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

private struct HealthChangeData {
    let serviceName: String
    let status: ServiceHealthStatus
    let message: String?
    let timestamp: Date
}

private struct HealthChangeRow: View {
    let change: HealthChangeData
    
    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: change.timestamp, relativeTo: Date())
    }
    
    var body: some View {
        HStack {
            Image(systemName: change.status.icon)
                .foregroundColor(change.status.color)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(change.serviceName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(timeAgo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let message = change.message {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(8)
        .background(change.status.color.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - Service Detail View

private struct ServiceDetailView: View {
    let service: ServiceDescriptor
    let health: ServiceHealth
    @ObservedObject var serviceRegistry: ServiceRegistry
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                ServiceDetailHeader(service: service, health: health)
                
                // APIs
                if let apis = service.apis {
                    ServiceAPIsView(apis: apis)
                }
                
                // Performance Metrics
                if let performance = service.performance {
                    ServicePerformanceView(performance: performance)
                }
                
                // Health Metrics
                if let metrics = health.metrics {
                    ServiceHealthMetricsView(metrics: metrics)
                }
                
                // Dependencies
                if !service.dependencies.isEmpty {
                    ServiceDependenciesView(
                        dependencies: service.dependencies,
                        serviceRegistry: serviceRegistry
                    )
                }
                
                // Monitoring
                if let monitoring = service.monitoring {
                    ServiceMonitoringView(monitoring: monitoring)
                }
                
                // Features
                if let features = service.features {
                    ServiceFeaturesView(features: features)
                }
            }
            .padding()
        }
        .navigationTitle(service.name)
    }
}

private struct ServiceDetailHeader: View {
    let service: ServiceDescriptor
    let health: ServiceHealth
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(service.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text(service.purpose)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    HStack {
                        Image(systemName: health.status.icon)
                            .foregroundColor(health.status.color)
                        Text(health.status.rawValue.capitalized)
                            .fontWeight(.semibold)
                            .foregroundColor(health.status.color)
                    }
                    
                    Text("v\(service.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Label(service.type.displayName, systemImage: "gear")
                    .foregroundColor(service.type.color)
                
                Spacer()
                
                Label(service.status.rawValue.capitalized, systemImage: "circle.fill")
                    .foregroundColor(service.status.color)
            }
            .font(.caption)
            
            if let message = health.message {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

private struct ServiceAPIsView: View {
    let apis: [ServiceAPI]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("APIs")
                .font(.headline)
            
            ForEach(apis, id: \.method) { api in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(api.method)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Text(api.returns)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(api.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !api.parameters.isEmpty {
                        Text("Parameters: \(api.parameters.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
        }
    }
}

private struct ServicePerformanceView: View {
    let performance: ServicePerformance
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Characteristics")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                PerformanceMetric(title: "Memory Usage", value: performance.memoryUsage)
                PerformanceMetric(title: "CPU Usage", value: performance.cpuUsage)
                PerformanceMetric(title: "I/O Operations", value: performance.ioOperations)
                
                if let customMetrics = performance.customMetrics {
                    ForEach(customMetrics.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        PerformanceMetric(title: key.replacingOccurrences(of: "_", with: " ").capitalized, value: value)
                    }
                }
            }
        }
    }
}

private struct PerformanceMetric: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}

private struct ServiceHealthMetricsView: View {
    let metrics: [String: Double]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Health Metrics")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(metrics.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    VStack(alignment: .leading) {
                        Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatMetricValue(value))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
            }
        }
    }
    
    private func formatMetricValue(_ value: Double) -> String {
        if value < 1 {
            return String(format: "%.3f", value)
        } else if value < 100 {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.0f", value)
        }
    }
}

private struct ServiceDependenciesView: View {
    let dependencies: [String]
    @ObservedObject var serviceRegistry: ServiceRegistry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dependencies")
                .font(.headline)
            
            ForEach(dependencies, id: \.self) { dependency in
                HStack {
                    let health = serviceRegistry.health(for: dependency)
                    Image(systemName: health.status.icon)
                        .foregroundColor(health.status.color)
                    
                    Text(dependency)
                        .font(.subheadline)
                    
                    Spacer()
                    
                    Text(health.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(health.status.color)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
        }
    }
}

private struct ServiceMonitoringView: View {
    let monitoring: ServiceMonitoring
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monitoring Configuration")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Metrics")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                ForEach(monitoring.metrics, id: \.self) { metric in
                    Text("• \(metric.replacingOccurrences(of: "_", with: " ").capitalized)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Alerts")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                ForEach(monitoring.alerts, id: \.self) { alert in
                    Text("• \(alert.replacingOccurrences(of: "_", with: " ").capitalized)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
        }
    }
}

private struct ServiceFeaturesView: View {
    let features: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Features")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(features, id: \.self) { feature in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text(feature.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption)
                    }
                    .padding(6)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
                }
            }
        }
    }
}

// MARK: - Preview

struct ServiceHealthDashboard_Previews: PreviewProvider {
    static var previews: some View {
        ServiceHealthDashboard()
            .frame(width: 1000, height: 700)
    }
}