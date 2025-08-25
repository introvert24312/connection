import SwiftUI
import Foundation

// MARK: - Architecture Visualization Service
// Optional runtime architecture diagram visualization for WordTagger

@MainActor
public class ArchitectureVisualizationService: ObservableObject {
    @Published public var services: [ServiceInfo] = []
    @Published public var dependencies: [ServiceDependency] = []
    @Published public var notifications: [NotificationFlow] = []
    
    public init() {
        loadArchitectureData()
    }
    
    private func loadArchitectureData() {
        // Core Services
        services = [
            ServiceInfo(
                id: "NodeStore",
                name: "NodeStore",
                type: .core,
                description: "Central State Management",
                responsibilities: [
                    "Manages @Published Node/Layer arrays",
                    "Handles CRUD operations",
                    "Coordinates search state",
                    "Manages tag filtering"
                ],
                status: .healthy
            ),
            ServiceInfo(
                id: "ExternalDataService", 
                name: "ExternalDataService",
                type: .core,
                description: "Persistence Engine",
                responsibilities: [
                    "Async save/load operations",
                    "Backup management", 
                    "Data corruption recovery",
                    "Sync coordination"
                ],
                status: .healthy
            ),
            ServiceInfo(
                id: "SearchService",
                name: "SearchService", 
                type: .specialized,
                description: "Advanced Search Engine",
                responsibilities: [
                    "Multi-field fuzzy search",
                    "Semantic matching",
                    "Location-based queries",
                    "Performance optimization"
                ],
                status: .healthy
            ),
            ServiceInfo(
                id: "GitService",
                name: "GitService",
                type: .specialized, 
                description: "Version Control",
                responsibilities: [
                    "Repository management",
                    "Auto-commit workflows",
                    "Credential handling",
                    "Sync operations"
                ],
                status: .healthy
            ),
            ServiceInfo(
                id: "TagMappingManager",
                name: "TagMappingManager",
                type: .infrastructure,
                description: "Tag System Manager", 
                responsibilities: [
                    "Type mappings",
                    "Display name resolution",
                    "Custom tag definitions",
                    "Built-in tag types"
                ],
                status: .healthy
            ),
            ServiceInfo(
                id: "KeyboardEventManager",
                name: "KeyboardEventManager",
                type: .infrastructure,
                description: "Input Event Handler",
                responsibilities: [
                    "Command throttling",
                    "Error recovery", 
                    "Focus state tracking",
                    "Conflict resolution"
                ],
                status: .healthy
            )
        ]
        
        // Service Dependencies
        dependencies = [
            ServiceDependency(from: "NodeStore", to: "ExternalDataService", type: .direct),
            ServiceDependency(from: "NodeStore", to: "TagMappingManager", type: .direct),
            ServiceDependency(from: "ExternalDataService", to: "ExternalDataManager", type: .direct),
            ServiceDependency(from: "GitService", to: "KeychainManager", type: .direct),
            ServiceDependency(from: "SearchService", to: "NodeStore", type: .direct),
            ServiceDependency(from: "GraphService", to: "NodeStore", type: .direct)
        ]
        
        // Notification Flows
        notifications = [
            NotificationFlow(
                name: "dataPathChanged",
                source: "ExternalDataManager", 
                targets: ["NodeStore"],
                description: "Triggers data reload when path changes"
            ),
            NotificationFlow(
                name: "nodeUpdated",
                source: "NodeStore",
                targets: ["GitService"],
                description: "Triggers auto-commit on node changes"
            ),
            NotificationFlow(
                name: "tagTypeNameChanged", 
                source: "TagMappingManager",
                targets: ["NodeStore"],
                description: "Updates tag display names"
            ),
            NotificationFlow(
                name: "clearTagFilter",
                source: "External",
                targets: ["NodeStore"], 
                description: "Resets tag filtering state"
            )
        ]
    }
    
    public func getServiceHealth() -> ArchitectureHealth {
        let healthyCount = services.filter { $0.status == .healthy }.count
        let totalCount = services.count
        let healthPercentage = Double(healthyCount) / Double(totalCount)
        
        return ArchitectureHealth(
            overallHealth: healthPercentage,
            serviceCount: totalCount,
            healthyServices: healthyCount,
            notificationFlows: notifications.count,
            dependencyCount: dependencies.count
        )
    }
    
    public func getDependencyGraph() -> String {
        // Generate Mermaid diagram dynamically
        var mermaid = "graph TD\n"
        
        // Add services
        for service in services {
            let emoji = service.type.emoji
            mermaid += "    \(service.id)[\"\(service.name)<br/>\(emoji) \(service.description)\"]\n"
        }
        
        mermaid += "\n"
        
        // Add dependencies
        for dependency in dependencies {
            let arrow = dependency.type == .notification ? "-->" : "-.->>"
            mermaid += "    \(dependency.from) \(arrow) \(dependency.to)\n"
        }
        
        return mermaid
    }
}

// MARK: - Architecture Data Models

public struct ServiceInfo: Identifiable {
    public let id: String
    public let name: String
    public let type: ServiceType
    public let description: String
    public let responsibilities: [String]
    public let status: ServiceStatus
}

public enum ServiceType {
    case core
    case specialized
    case infrastructure
    case communication
    case external
    
    var emoji: String {
        switch self {
        case .core: return "🏪"
        case .specialized: return "⚡" 
        case .infrastructure: return "🛠️"
        case .communication: return "📢"
        case .external: return "🌐"
        }
    }
    
    var color: Color {
        switch self {
        case .core: return .blue
        case .specialized: return .purple
        case .infrastructure: return .green
        case .communication: return .orange
        case .external: return .red
        }
    }
}

public enum ServiceStatus {
    case healthy
    case warning
    case error
    case unknown
    
    var color: Color {
        switch self {
        case .healthy: return .green
        case .warning: return .yellow
        case .error: return .red
        case .unknown: return .gray
        }
    }
}

public struct ServiceDependency {
    public let from: String
    public let to: String
    public let type: DependencyType
}

public enum DependencyType {
    case direct
    case notification
    case weak
}

public struct NotificationFlow {
    public let name: String
    public let source: String
    public let targets: [String]
    public let description: String
}

public struct ArchitectureHealth {
    public let overallHealth: Double
    public let serviceCount: Int
    public let healthyServices: Int
    public let notificationFlows: Int
    public let dependencyCount: Int
    
    public var healthDescription: String {
        switch overallHealth {
        case 0.9...1.0: return "Excellent"
        case 0.7..<0.9: return "Good"
        case 0.5..<0.7: return "Fair"
        default: return "Needs Attention"
        }
    }
}

// MARK: - SwiftUI Architecture Dashboard

public struct ArchitectureDashboardView: View {
    @StateObject private var visualizer = ArchitectureVisualizationService()
    @State private var selectedService: ServiceInfo?
    
    public var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                healthSection
                servicesSection
            }
            .padding()
        } detail: {
            if let service = selectedService {
                serviceDetailView(service)
            } else {
                Text("Select a service to view details")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Architecture Dashboard")
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WordTagger Architecture")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Real-time service monitoring and dependency visualization")
                .foregroundColor(.secondary)
        }
    }
    
    private var healthSection: some View {
        let health = visualizer.getServiceHealth()
        
        VStack(alignment: .leading, spacing: 12) {
            Text("System Health")
                .font(.headline)
            
            HStack {
                Circle()
                    .fill(health.overallHealth > 0.8 ? Color.green : Color.orange)
                    .frame(width: 12, height: 12)
                
                Text("\(health.healthDescription) (\(Int(health.overallHealth * 100))%)")
                    .fontWeight(.medium)
                
                Spacer()
            }
            
            HStack(spacing: 20) {
                MetricView(
                    title: "Services",
                    value: "\(health.serviceCount)",
                    subtitle: "\(health.healthyServices) healthy"
                )
                
                MetricView(
                    title: "Dependencies", 
                    value: "\(health.dependencyCount)",
                    subtitle: "connections"
                )
                
                MetricView(
                    title: "Notifications",
                    value: "\(health.notificationFlows)",
                    subtitle: "event flows"
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Services")
                .font(.headline)
            
            LazyVStack(spacing: 8) {
                ForEach(visualizer.services) { service in
                    ServiceRowView(
                        service: service,
                        isSelected: selectedService?.id == service.id
                    )
                    .onTapGesture {
                        selectedService = service
                    }
                }
            }
        }
    }
    
    private func serviceDetailView(_ service: ServiceInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(service.type.emoji)
                    .font(.title)
                
                VStack(alignment: .leading) {
                    Text(service.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(service.description)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Circle()
                    .fill(service.status.color)
                    .frame(width: 12, height: 12)
            }
            
            Text("Responsibilities")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(service.responsibilities, id: \.self) { responsibility in
                    HStack {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(responsibility)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

struct ServiceRowView: View {
    let service: ServiceInfo
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Text(service.type.emoji)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .fontWeight(.medium)
                
                Text(service.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Circle()
                .fill(service.status.color)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isSelected ? service.type.color.opacity(0.1) : Color.clear
        )
        .cornerRadius(8)
    }
}

struct MetricView: View {
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Usage Example
/*
 To integrate into your existing SwiftUI app:

 struct SettingsView: View {
     var body: some View {
         NavigationView {
             // ... existing settings
             
             NavigationLink("Architecture Dashboard", destination: ArchitectureDashboardView())
         }
     }
 }
 */