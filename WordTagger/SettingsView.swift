import SwiftUI
import CoreLocation
import MapKit
import UniformTypeIdentifiers

// MARK: - GitHub同步状态管理器

@MainActor
public class GitSyncStatusManager: ObservableObject {
    @Published public var isEnabled: Bool = false
    @Published public var isWorking: Bool = false
    @Published public var status: String = "未配置"
    @Published public var lastSyncTime: Date?
    @Published public var lastError: String?
    @Published public var totalSyncCount: Int = 0
    
    public static let shared = GitSyncStatusManager()
    
    private init() {
        loadStatus()
    }
    
    // MARK: - 状态更新
    
    public func updateStatus(
        isEnabled: Bool? = nil,
        isWorking: Bool? = nil,
        status: String? = nil,
        lastSyncTime: Date? = nil,
        lastError: String? = nil,
        totalSyncCount: Int? = nil
    ) {
        if let isEnabled = isEnabled { self.isEnabled = isEnabled }
        if let isWorking = isWorking { self.isWorking = isWorking }
        if let status = status { self.status = status }
        if let lastSyncTime = lastSyncTime { self.lastSyncTime = lastSyncTime }
        if let lastError = lastError { self.lastError = lastError }
        if let totalSyncCount = totalSyncCount { self.totalSyncCount = totalSyncCount }
        
        saveStatus()
        
        print("🔄 GitSyncStatusManager状态更新:")
        print("   - isEnabled: \(self.isEnabled)")
        print("   - isWorking: \(self.isWorking)")
        print("   - status: \(self.status)")
        print("   - totalSyncCount: \(self.totalSyncCount)")
    }
    
    public func startWorking(operation: String) {
        isWorking = true
        status = operation
        lastError = nil
        print("🟡 GitHub同步开始: \(operation)")
    }
    
    public func finishWorking(success: Bool, finalStatus: String, error: String? = nil) {
        isWorking = false
        status = finalStatus
        if success {
            lastSyncTime = Date()
            totalSyncCount += 1
            lastError = nil
            print("🟢 GitHub同步完成: \(finalStatus)")
        } else {
            lastError = error
            print("🔴 GitHub同步失败: \(error ?? "未知错误")")
        }
        saveStatus()
    }
    
    // MARK: - 状态计算
    
    public var statusColor: Color {
        if !isEnabled {
            return .secondary
        } else if isWorking {
            return .orange
        } else if lastError != nil {
            return .red
        } else {
            return .green
        }
    }
    
    public var statusIcon: String {
        if !isEnabled {
            return "externaldrive.badge.questionmark"
        } else if isWorking {
            return "externaldrive.badge.timemachine"
        } else if lastError != nil {
            return "externaldrive.badge.xmark"
        } else {
            return "externaldrive.badge.checkmark"
        }
    }
    
    public var displayStatus: String {
        if !isEnabled {
            return "GitHub同步未配置"
        } else if isWorking {
            return status
        } else if let error = lastError {
            return "同步错误: \(error)"
        } else {
            return "GitHub同步就绪"
        }
    }
    
    // MARK: - 持久化
    
    private func loadStatus() {
        let userDefaults = UserDefaults.standard
        isEnabled = userDefaults.bool(forKey: "GitSync_IsEnabled")
        status = userDefaults.string(forKey: "GitSync_Status") ?? "未配置"
        totalSyncCount = userDefaults.integer(forKey: "GitSync_TotalCount")
        
        if let lastSync = userDefaults.object(forKey: "GitSync_LastSyncTime") as? Date {
            lastSyncTime = lastSync
        }
        
        lastError = userDefaults.string(forKey: "GitSync_LastError")
    }
    
    private func saveStatus() {
        let userDefaults = UserDefaults.standard
        userDefaults.set(isEnabled, forKey: "GitSync_IsEnabled")
        userDefaults.set(status, forKey: "GitSync_Status")
        userDefaults.set(totalSyncCount, forKey: "GitSync_TotalCount")
        
        if let lastSync = lastSyncTime {
            userDefaults.set(lastSync, forKey: "GitSync_LastSyncTime")
        }
        
        userDefaults.set(lastError, forKey: "GitSync_LastError")
    }
}

// MARK: - GitHub同步状态指示器组件

struct GitSyncStatusIndicator: View {
    @StateObject private var statusManager = GitSyncStatusManager.shared
    @State private var showingTooltip = false
    
    var body: some View {
        HStack(spacing: 6) {
            // 状态圆点
            Circle()
                .fill(statusManager.statusColor)
                .frame(width: 8, height: 8)
                .scaleEffect(statusManager.isWorking ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), 
                          value: statusManager.isWorking)
            
            // 状态图标
            Image(systemName: statusManager.statusIcon)
                .font(.caption)
                .foregroundColor(statusManager.statusColor)
                .rotationEffect(.degrees(statusManager.isWorking ? 360 : 0))
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), 
                          value: statusManager.isWorking)
            
            // 状态文本（可选）
            if statusManager.isWorking {
                Text(statusManager.status)
                    .font(.caption2)
                    .foregroundColor(statusManager.statusColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusManager.statusColor.opacity(0.1))
        .cornerRadius(8)
        .onTapGesture {
            showingTooltip.toggle()
        }
        .help(statusManager.displayStatus)
        .popover(isPresented: $showingTooltip) {
            GitSyncStatusPopover()
        }
    }
}

// MARK: - 状态详情弹出框

struct GitSyncStatusPopover: View {
    @StateObject private var statusManager = GitSyncStatusManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack {
                Image(systemName: statusManager.statusIcon)
                    .foregroundColor(statusManager.statusColor)
                Text("GitHub同步状态")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("×") {
                    dismiss()
                }
                .font(.title2)
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // 当前状态
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle()
                        .fill(statusManager.statusColor)
                        .frame(width: 10, height: 10)
                    
                    Text(statusManager.displayStatus)
                        .font(.body)
                        .fontWeight(.medium)
                }
                
                if let lastSync = statusManager.lastSyncTime {
                    Text("上次同步: \(formatTime(lastSync))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if statusManager.totalSyncCount > 0 {
                    Text("总同步次数: \(statusManager.totalSyncCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // 快速操作
            if statusManager.isEnabled && !statusManager.isWorking {
                Divider()
                
                HStack {
                    Text("快速操作:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("打开设置") {
                        // 这里可以添加打开设置的逻辑
                        dismiss()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding()
        .frame(width: 250)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 紧凑状态指示器（用于工具栏）

struct CompactGitSyncIndicator: View {
    @StateObject private var statusManager = GitSyncStatusManager.shared
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusManager.statusColor)
                .frame(width: 6, height: 6)
                .scaleEffect(statusManager.isWorking ? 1.3 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), 
                          value: statusManager.isWorking)
            
            if statusManager.isEnabled {
                Text("\(statusManager.totalSyncCount)")
                    .font(.caption2)
                    .foregroundColor(statusManager.statusColor)
                    .fontWeight(.medium)
            }
        }
        .help(statusManager.displayStatus)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: NodeStore
    @AppStorage("searchThreshold") private var searchThreshold: Double = 0.3
    @AppStorage("enableDebugMode") private var enableDebugMode: Bool = false
    @AppStorage("maxSearchResults") private var maxSearchResults: Int = 50
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 30.0
    
    var body: some View {
        TabView {
            // 常规设置
            GeneralSettingsView()
                .tabItem {
                    Label("常规", systemImage: "gear")
                }
            
            // 搜索设置
            SearchSettingsView(
                searchThreshold: $searchThreshold,
                maxSearchResults: $maxSearchResults
            )
            .tabItem {
                Label("搜索", systemImage: "magnifyingglass")
            }
            
            // 层管理
            LayerManagementView()
                .tabItem {
                    Label("层管理", systemImage: "square.stack.3d.up")
                }
                .environmentObject(store)
            
            // 数据管理
            DataManagementView()
                .tabItem {
                    Label("数据", systemImage: "externaldrive")
                }
            
            // Git 同步
            GitSyncSettingsView()
                .tabItem {
                    Label("GitHub同步", systemImage: "externaldrive.connected.to.line.below")
                }
            
            // 关于
            AboutView()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - 常规设置

struct GeneralSettingsView: View {
    @AppStorage("enableDebugMode") private var enableDebugMode: Bool = false
    @AppStorage("enableGraphDebug") private var enableGraphDebug: Bool = false
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 30.0
    @AppStorage("showPhoneticByDefault") private var showPhoneticByDefault: Bool = true
    @AppStorage("globalGraphInitialScale") private var globalGraphInitialScale: Double = 1.0
    @AppStorage("detailGraphInitialScale") private var detailGraphInitialScale: Double = 1.0
    @AppStorage("fullscreenGraphInitialScale") private var fullscreenGraphInitialScale: Double = 1.0
    @AppStorage("layerStructureGraphInitialScale") private var layerStructureGraphInitialScale: Double = 0.9
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 界面设置
                GroupBox("界面设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "默认显示音标",
                            description: "在节点列表中自动显示音标信息"
                        ) {
                            Toggle("", isOn: $showPhoneticByDefault)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "全局图谱初始缩放",
                            description: "全局图谱窗口打开时的默认缩放级别"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(String(format: "%.1f", globalGraphInitialScale))x")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                
                                Slider(value: $globalGraphInitialScale, in: 0.5...3.0, step: 0.1)
                                    .frame(width: 120)
                            }
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "详情图谱初始缩放",
                            description: "节点详情图谱的默认缩放级别"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(String(format: "%.1f", detailGraphInitialScale))x")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                
                                Slider(value: $detailGraphInitialScale, in: 0.5...3.0, step: 0.1)
                                    .frame(width: 120)
                            }
                        }
                        
                        SettingRow(
                            title: "全屏图谱初始缩放",
                            description: "Command+D打开的全屏图谱默认缩放级别"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(String(format: "%.1f", fullscreenGraphInitialScale))x")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                
                                Slider(value: $fullscreenGraphInitialScale, in: 0.5...3.0, step: 0.1)
                                    .frame(width: 120)
                            }
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "层结构图谱初始缩放",
                            description: "命令面板中层结构图谱的默认缩放级别"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(String(format: "%.1f", layerStructureGraphInitialScale))x")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                
                                Slider(value: $layerStructureGraphInitialScale, in: 0.5...3.0, step: 0.1)
                                    .frame(width: 120)
                            }
                        }
                        
                        Divider()
                        
                        // 全局图谱选中状态管理
                        GlobalGraphSelectionSettingsView()
                    }
                    .padding(12)
                }
                
                // 性能设置
                GroupBox("性能设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "自动保存间隔",
                            description: "自动保存数据的时间间隔（秒）"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(Int(autoSaveInterval))秒")
                                    .foregroundColor(.secondary)
                                    .frame(width: 50, alignment: .trailing)
                                
                                Stepper("", 
                                       value: $autoSaveInterval, 
                                       in: 10...300, 
                                       step: 10)
                            }
                        }
                    }
                    .padding(12)
                }
                
                // 开发设置
                GroupBox("开发选项") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "调试模式",
                            description: "显示调试信息和性能指标"
                        ) {
                            Toggle("", isOn: $enableDebugMode)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "图谱调试信息",
                            description: "在WebView中显示图谱数据验证信息"
                        ) {
                            Toggle("", isOn: $enableGraphDebug)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        if enableGraphDebug {
                            Text("⚠️ 启用后会在图谱中显示详细的节点和边数据，用于调试数据传递问题")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.top, 4)
                        }
                    }
                    .padding(12)
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - 搜索设置

struct SearchSettingsView: View {
    @Binding var searchThreshold: Double
    @Binding var maxSearchResults: Int
    @AppStorage("enableFuzzySearch") private var enableFuzzySearch: Bool = true
    @AppStorage("searchInPhonetic") private var searchInPhonetic: Bool = true
    @AppStorage("searchInMeaning") private var searchInMeaning: Bool = true
    @AppStorage("searchInTags") private var searchInTags: Bool = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 搜索范围
                GroupBox("搜索范围") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "搜索音标",
                            description: "在音标字段中搜索匹配内容"
                        ) {
                            Toggle("", isOn: $searchInPhonetic)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "搜索含义",
                            description: "在节点含义中搜索匹配内容"
                        ) {
                            Toggle("", isOn: $searchInMeaning)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "搜索标签",
                            description: "在标签内容中搜索匹配内容"
                        ) {
                            Toggle("", isOn: $searchInTags)
                                .toggleStyle(SwitchToggleStyle())
                        }
                    }
                    .padding(12)
                }
                
                // 搜索算法
                GroupBox("搜索算法") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "模糊搜索",
                            description: "允许拼写错误和近似匹配"
                        ) {
                            Toggle("", isOn: $enableFuzzySearch)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        if enableFuzzySearch {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("匹配阈值")
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(String(format: "%.1f", searchThreshold))
                                        .foregroundColor(.secondary)
                                }
                                
                                Slider(value: $searchThreshold, in: 0.1...0.9, step: 0.1)
                                
                                Text("较低的值需要更精确的匹配")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(12)
                }
                
                // 结果限制
                GroupBox("结果设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "最大搜索结果",
                            description: "限制单次搜索返回的最大结果数量"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(maxSearchResults)")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                
                                Stepper("", 
                                       value: $maxSearchResults, 
                                       in: 10...200, 
                                       step: 10)
                            }
                        }
                    }
                    .padding(12)
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - 层管理

struct LayerManagementView: View {
    @EnvironmentObject private var store: NodeStore
    @State private var showingCreateLayerSheet = false
    @State private var showingDeleteAlert = false
    @State private var layerToDelete: Layer?
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部：当前活跃层状态条
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "target")
                        .foregroundColor(.blue)
                        .font(.body)
                    
                    Text("当前活跃层:")
                        .font(.body)
                        .fontWeight(.medium)
                    
                    if let currentLayer = store.currentLayer {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.from(currentLayer.color))
                                .frame(width: 12, height: 12)
                            
                            Text(currentLayer.displayName)
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("(\(currentLayer.name))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    } else {
                        Text("未选择")
                            .font(.body)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                
                Spacer()
                
                // 快速统计
                if store.currentLayer != nil {
                    HStack(spacing: 12) {
                        VStack(spacing: 2) {
                            Text("\(store.getNodesInCurrentLayer().count)")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                            Text("节点")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 2) {
                            Text("\(store.getNodesInCurrentLayer().count)")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            Text("节点")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 主内容区域
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 层管理区域
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("层管理")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Button(action: {
                                showingCreateLayerSheet = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("创建新层")
                                }
                                .font(.body)
                                .fontWeight(.medium)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                        
                        // 层列表
                        if store.layers.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "square.stack.3d.up")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray.opacity(0.6))
                                
                                VStack(spacing: 8) {
                                    Text("暂无层级")
                                        .font(.title3)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    
                                    Text("创建第一个层来开始组织您的节点和数据")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                
                                Button(action: {
                                    showingCreateLayerSheet = true
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                        Text("创建第一个层")
                                    }
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            )
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(store.sortedLayers, id: \.id) { layer in
                                    LayerRowView(
                                        layer: layer,
                                        wordCount: store.nodes.filter { $0.layerId == layer.id }.count,
                                        nodeCount: store.nodes.filter { $0.layerId == layer.id }.count,
                                        isActive: store.currentLayer?.id == layer.id,
                                        onActivate: {
                                            Task {
                                                await store.switchToLayer(layer)
                                            }
                                        },
                                        onDelete: {
                                            layerToDelete = layer
                                            showingDeleteAlert = true
                                        },
                                        onEdit: { newName in
                                            store.updateLayerDisplayName(layer: layer, newDisplayName: newName)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .sheet(isPresented: $showingCreateLayerSheet) {
            CreateLayerSheet()
                .environmentObject(store)
        }
        .alert("删除层", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {
                layerToDelete = nil
            }
            Button("删除", role: .destructive) {
                if let layer = layerToDelete {
                    store.deleteLayer(layer)
                    layerToDelete = nil
                }
            }
        } message: {
            if let layer = layerToDelete {
                let nodeCount = store.nodes.filter { $0.layerId == layer.id }.count
                Text("确定要删除层 \"\(layer.displayName)\" 吗？\n这将同时删除该层中的 \(nodeCount) 个节点，此操作无法撤销。")
            }
        }
    }
}

struct LayerRowView: View {
    let layer: Layer
    let wordCount: Int
    let nodeCount: Int
    let isActive: Bool
    let onActivate: () -> Void
    let onDelete: () -> Void
    let onEdit: (String) -> Void
    
    @State private var isEditing: Bool = false
    @State private var editingName: String = ""
    
    var body: some View {
        HStack(spacing: 16) {
            // 左侧：颜色指示器和状态
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.from(layer.color))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if isEditing {
                            TextField("层名称", text: $editingName)
                                .font(.headline)
                                .fontWeight(isActive ? .bold : .semibold)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    saveEdit()
                                }
                                .onAppear {
                                    editingName = layer.displayName
                                }
                        } else {
                            Text(layer.displayName)
                                .font(.headline)
                                .fontWeight(isActive ? .bold : .semibold)
                                .foregroundColor(.primary)
                        }
                        
                        if isActive {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                Text("活跃")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                    }
                    
                    Text(layer.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 中间：数据统计
            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    Text("\(wordCount)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("节点")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 2) {
                    Text("\(nodeCount)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("节点")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // 右侧：操作按钮
            HStack(spacing: 8) {
                if isEditing {
                    // 编辑模式下的按钮
                    Button(action: saveEdit) {
                        Image(systemName: "checkmark")
                            .font(.body)
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("保存")
                    
                    Button(action: cancelEdit) {
                        Image(systemName: "xmark")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("取消")
                } else {
                    // 正常模式下的按钮
                    if !isActive {
                        Button(action: onActivate) {
                            HStack(spacing: 4) {
                                Image(systemName: "target")
                                    .font(.caption)
                                Text("激活")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    
                    Button(action: startEdit) {
                        Image(systemName: "pencil")
                            .font(.body)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("编辑名称")
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.body)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("删除层")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.blue.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isActive ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1.5)
                )
        )
        .shadow(color: isActive ? Color.blue.opacity(0.1) : Color.clear, radius: 4, x: 0, y: 2)
    }
    
    private func startEdit() {
        isEditing = true
        editingName = layer.displayName
    }
    
    private func saveEdit() {
        let trimmedName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && trimmedName != layer.displayName {
            onEdit(trimmedName)
        }
        isEditing = false
    }
    
    private func cancelEdit() {
        isEditing = false
        editingName = layer.displayName
    }
}

struct CreateLayerSheet: View {
    @EnvironmentObject private var store: NodeStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var displayName: String = ""
    @State private var selectedColor: String = "blue"
    
    let availableColors = [
        ("blue", Color.blue),
        ("green", Color.green),
        ("orange", Color.orange),
        ("red", Color.red),
        ("purple", Color.purple),
        ("pink", Color.pink),
        ("yellow", Color.yellow),
        ("teal", Color.teal),
        ("indigo", Color.indigo),
        ("brown", Color.brown)
    ]
    
    var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏
            HStack {
                Text("创建新层")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button("取消") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("创建") {
                        let newLayer = store.createLayer(
                            name: name.isEmpty ? displayName.lowercased().replacingOccurrences(of: " ", with: "_") : name,
                            displayName: displayName.isEmpty ? name : displayName,
                            color: selectedColor
                        )
                        
                        // 如果这是第一个层，自动激活
                        if store.layers.count == 1 {
                            Task {
                                await store.switchToLayer(newLayer)
                            }
                        }
                        
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isFormValid)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 主内容区域
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 层信息区域
                    GroupBox("层信息") {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("层名称（英文）")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                TextField("例如: work, study, hobby", text: $name)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("显示名称（中文）")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                TextField("例如: 工作, 学习, 爱好", text: $displayName)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding()
                    }
                    
                    // 层颜色区域
                    GroupBox("层颜色") {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("选择用于标识此层的颜色")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                                ForEach(availableColors, id: \.0) { colorName, color in
                                    ColorButton(
                                        colorName: colorName,
                                        color: color,
                                        isSelected: selectedColor == colorName,
                                        onTap: { selectedColor = colorName }
                                    )
                                }
                            }
                        }
                        .padding()
                    }
                    
                    // 预览区域
                    if isFormValid {
                        GroupBox("预览") {
                            LayerPreviewRow(
                                selectedColor: selectedColor,
                                displayName: !displayName.isEmpty ? displayName : (!name.isEmpty ? name : "新层"),
                                name: !name.isEmpty ? name : (!displayName.isEmpty ? displayName.lowercased() : "new_layer")
                            )
                            .padding()
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 500, height: 550)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Helper Views for CreateLayerSheet

struct ColorButton: View {
    let colorName: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                )
                .scaleEffect(isSelected ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .help(colorName.capitalized)
    }
}

struct LayerPreviewRow: View {
    let selectedColor: String
    let displayName: String
    let name: String
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.from(selectedColor))
                .frame(width: 14, height: 14)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                    .fontWeight(.semibold)
                Text(name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 数据管理

struct DataManagementView: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var dataManager = ExternalDataManager.shared
    @StateObject private var dataService = ExternalDataService.shared
    @State private var showingClearDataAlert = false
    @State private var showingResultAlert = false
    @State private var resultMessage = ""
    @State private var isSuccess = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 外部数据存储设置
                ExternalDataStoragePanel()
                
                // 图片管理
                GroupBox("图片管理") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "photo.stack")
                                .foregroundColor(.blue)
                            Text("Markdown 图片存储")
                                .fontWeight(.medium)
                            Spacer()
                        }
                        
                        Text("所有通过编辑器上传的图片都保存在此文件夹中")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Button("打开图片文件夹") {
                                openImagesFolder()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            
                            Button("在 Finder 中显示") {
                                showInFinder()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                }
                
                // 数据统计
                GroupBox("数据统计") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("数据概览")
                                .fontWeight(.semibold)
                                .gridColumnAlignment(.leading)
                            Spacer()
                        }
                        
                        Divider()
                            .gridCellUnsizedAxes(.horizontal)
                        
                        GridRow {
                            Text("层数量")
                                .foregroundColor(.secondary)
                            Text("\(store.layers.count)")
                                .fontWeight(.medium)
                        }
                        
                        GridRow {
                            Text("节点总数")
                                .foregroundColor(.secondary)
                            Text("\(store.nodes.count)")
                                .fontWeight(.medium)
                        }
                        
                        GridRow {
                            Text("节点总数")
                                .foregroundColor(.secondary)
                            Text("\(store.nodes.count)")
                                .fontWeight(.medium)
                        }
                        
                        GridRow {
                            Text("标签总数")
                                .foregroundColor(.secondary)
                            Text("\(store.allTags.count)")
                                .fontWeight(.medium)
                        }
                        
                        GridRow {
                            Text("地点标签")
                                .foregroundColor(.secondary)
                            Text("\(store.allTags.filter { $0.hasCoordinates }.count)")
                                .fontWeight(.medium)
                        }
                        
                        Divider()
                            .gridCellUnsizedAxes(.horizontal)
                        
                        ForEach(Tag.TagType.predefinedCases, id: \.self) { type in
                            GridRow {
                                Text("\(type.displayName)标签")
                                    .foregroundColor(.secondary)
                                Text("\(store.nodesCount(forTagType: type)) 个节点")
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding(12)
                }
                
                
                // 危险操作区域
                GroupBox("危险操作") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("数据重置")
                                .fontWeight(.medium)
                            Spacer()
                        }
                        
                        Text("此操作将删除所有节点和标签数据，且无法撤销")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if dataManager.isDataPathSelected {
                            Text("⚠️ 同时会清除外部存储文件中的所有数据")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.top, 2)
                        }
                        
                        HStack(spacing: 8) {
                            Button("清除所有数据") {
                                showingClearDataAlert = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(.red)
                            .disabled(store.nodes.isEmpty && store.nodes.isEmpty)
                            
                            Button("强制刷新界面") {
                                store.forceRefreshUI()
                                resultMessage = "界面已强制刷新"
                                isSuccess = true
                                showingResultAlert = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                }
                
                Spacer()
            }
            .padding()
        }
        .alert("确认清除数据", isPresented: $showingClearDataAlert) {
            Button("取消", role: .cancel) { }
            Button("清除", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("此操作将删除所有节点和标签数据，且无法撤销。")
        }
        .alert(isSuccess ? "成功" : "错误", isPresented: $showingResultAlert) {
            Button("确定") { }
        } message: {
            Text(resultMessage)
        }
    }
    
    private func clearAllData() {
        // 清除内存数据
        store.clearAllData()
        
        // 如果有外部数据存储，清除所有外部文件（包括标签映射）
        if dataManager.isDataPathSelected {
            Task {
                do {
                    // 使用新的清理方法，彻底删除所有外部数据文件
                    try await dataService.clearAllExternalData()
                    await MainActor.run {
                        resultMessage = "所有数据已完全清除（包括外部存储和标签设置）"
                        isSuccess = true
                        showingResultAlert = true
                    }
                } catch {
                    await MainActor.run {
                        resultMessage = "数据已清除，但清理外部存储失败: \(error.localizedDescription)"
                        isSuccess = false
                        showingResultAlert = true
                    }
                }
            }
        } else {
            resultMessage = "所有数据已清除"
            isSuccess = true
            showingResultAlert = true
        }
    }
    
    private func openImagesFolder() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let imagesURL = documentsURL.appendingPathComponent("WordTagger/Images")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true, attributes: nil)
        
        // 打开文件夹
        NSWorkspace.shared.open(imagesURL)
    }
    
    private func showInFinder() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let imagesURL = documentsURL.appendingPathComponent("WordTagger/Images")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true, attributes: nil)
        
        // 在 Finder 中显示
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: imagesURL.path)
    }
}

struct SettingRow<Content: View>: View {
    let title: String
    let description: String
    let content: () -> Content
    
    init(title: String, description: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.description = description
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                content()
            }
        }
    }
}

struct StatRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - 关于页面

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Connection")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("版本 1.0.0")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("功能特点:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    FeatureRow(icon: "tag.fill", text: "智能标签系统")
                    FeatureRow(icon: "magnifyingglass", text: "模糊搜索功能")
                    FeatureRow(icon: "map", text: "地图可视化")
                    FeatureRow(icon: "command", text: "命令面板快捷操作")
                    FeatureRow(icon: "icloud", text: "数据导入导出")
                }
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Text("基于 SwiftUI 构建")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("© 2024 Connection. All rights reserved.")
                    .font(.caption2)
                    .foregroundColor(Color.secondary)
            }
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(text)
                .font(.body)
        }
    }
}

// MARK: - 全局图谱选中状态设置
struct GlobalGraphSelectionSettingsView: View {
    @StateObject private var selectionManager = GlobalGraphSelectionManager.shared
    
    var body: some View {
        SettingRow(
            title: "全局图谱选中状态",
            description: "管理全局图谱中的节点选中状态持久化"
        ) {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Text("\(selectionManager.selectedNodeIds.count)个选中")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Button("清除选中") {
                        selectionManager.clearAllSelections()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                if selectionManager.selectedNodeIds.count > 0 {
                    Text("选中的节点ID: \(selectionManager.selectedNodeIds.sorted().map(String.init).joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

// MARK: - 外部数据存储面板

struct ExternalDataStoragePanel: View {
    @StateObject private var dataManager = ExternalDataManager.shared
    @StateObject private var dataService = ExternalDataService.shared
    @EnvironmentObject private var store: NodeStore
    
    var body: some View {
        GroupBox(label: Text("外部数据存储").font(.headline)) {
            VStack(alignment: .leading, spacing: 12) {
                
                if dataManager.isDataPathSelected {
                    // 当前路径
                    VStack(alignment: .leading, spacing: 4) {
                        Text("存储位置:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(dataManager.currentDataPath?.path ?? "未设置")
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(4)
                    }
                    
                    // 同步状态
                    HStack {
                        Circle()
                            .fill(store.isLoading ? .blue : (dataService.isSaving ? .orange : .green))
                            .frame(width: 6, height: 6)
                        
                        Text(store.isLoading ? "加载数据..." : (dataService.isSaving ? "同步中..." : "已同步"))
                            .font(.caption)
                        
                        Spacer()
                        
                        if let lastSync = dataService.lastSyncTime {
                            Text(formatTime(lastSync))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("未设置外部数据存储位置")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("📁 选择文件夹来启用外部数据存储")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                
                // 错误提示
                if let error = dataManager.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
                }
                
                // 操作按钮
                HStack {
                    Button(dataManager.isDataPathSelected ? "更改位置" : "设置存储") {
                        Task {
                            // 清除之前的错误
                            dataManager.lastError = nil
                            dataManager.selectDataFolder()
                            
                            // 选择完成后自动保存并刷新
                            if dataManager.isDataPathSelected {
                                await store.forceSaveToExternalStorage()
                                // 触发数据重新加载
                                NotificationCenter.default.post(
                                    name: .dataPathChanged,
                                    object: dataManager,
                                    userInfo: ["newPath": dataManager.currentDataPath ?? URL(fileURLWithPath: "")]
                                )
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isLoading || dataService.isSaving)
                    
                    if dataManager.isDataPathSelected {
                        Button("清除") {
                            dataManager.clearDataPath()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // 如果有错误，显示重试按钮
                    if dataManager.lastError != nil {
                        Button("重试") {
                            Task {
                                dataManager.lastError = nil
                                dataManager.selectDataFolder()
                                
                                // 重试成功后也自动保存并刷新
                                if dataManager.isDataPathSelected {
                                    await store.forceSaveToExternalStorage()
                                    NotificationCenter.default.post(
                                        name: .dataPathChanged,
                                        object: dataManager,
                                        userInfo: ["newPath": dataManager.currentDataPath ?? URL(fileURLWithPath: "")]
                                    )
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - 数据文件夹设置弹窗

struct DataFolderSetupView: View {
    @StateObject private var dataManager = ExternalDataManager.shared
    @StateObject private var dataService = ExternalDataService.shared
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            // 标题
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                
                Text("设置数据存储位置")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("选择一个文件夹来存储Connection的数据")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // 当前路径显示
            if let currentPath = dataManager.currentDataPath {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前数据路径:")
                        .font(.headline)
                    
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)
                        
                        Text(currentPath.path)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            
            // 错误信息
            if let error = dataManager.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    
                    Text(error)
                        .font(.body)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            // 同步状态
            if dataManager.isDataPathSelected {
                HStack {
                    Circle()
                        .fill(dataService.isSaving ? .orange : .green)
                        .frame(width: 8, height: 8)
                    
                    Text(dataService.isSaving ? "同步中..." : "已同步")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let lastSync = dataService.lastSyncTime {
                        Text("• 上次同步: \(formatTime(lastSync))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // 操作按钮
            VStack(spacing: 12) {
                // 选择文件夹按钮
                Button(action: {
                    dataManager.selectDataFolder()
                }) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text(dataManager.isDataPathSelected ? "更改数据文件夹" : "选择数据文件夹")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                // 完成按钮
                if dataManager.isDataPathSelected {
                    Button(action: {
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "checkmark")
                            Text("完成设置")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                
                // 取消按钮
                Button(action: {
                    isPresented = false
                }) {
                    Text("取消")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
            }
        }
        .padding(32)
        .frame(width: 500, height: 600)
        .background(Color(.windowBackgroundColor))
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - GitHub同步设置

struct GitSyncSettingsView: View {
    @StateObject private var dataManager = ExternalDataManager.shared
    @StateObject private var statusManager = GitSyncStatusManager.shared
    @State private var remoteURLInput: String = ""
    @State private var branchInput: String = "master"
    @State private var githubUsername: String = ""
    @State private var githubToken: String = ""
    @State private var showingSetupAlert = false
    @State private var showingConfirmDialog = false
    @State private var isGitEnabled: Bool = false
    @State private var syncStatus: String = "未配置"
    @State private var isWorking: Bool = false
    @State private var lastSyncTime: Date?
    @State private var lastError: String?
    @State private var syncHistory: [SyncRecord] = []
    @State private var lastCommitHash: String?
    @State private var totalSyncCount: Int = 0
    @State private var showingSyncHistory = false
    @State private var showingTokenHelp = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // 状态概览
                GroupBox("GitHub同步状态") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Circle()
                                .fill(isGitEnabled ? (isWorking ? .orange : .green) : .secondary)
                                .frame(width: 8, height: 8)
                            
                            Text(syncStatus)
                                .font(.body)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            if isWorking {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else if isGitEnabled {
                                Button("查看历史") {
                                    showingSyncHistory = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        
                        // 详细统计信息
                        if isGitEnabled {
                            Divider()
                            
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                                GridRow {
                                    Text("总同步次数:")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                    Text("\(totalSyncCount) 次")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    
                                    if let lastSync = lastSyncTime {
                                        Text("上次同步:")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                        Text(formatDateTime(lastSync))
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                }
                                
                                if let commitHash = lastCommitHash {
                                    GridRow {
                                        Text("最新提交:")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                        Text(String(commitHash.prefix(8)))
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.blue)
                                        
                                        Spacer()
                                        Spacer()
                                    }
                                }
                            }
                        }
                        
                        if let error = lastError {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                                
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(4)
                        }
                        
                        // 成功提示
                        if let lastRecord = syncHistory.last, lastRecord.success, lastRecord.timestamp > Date().addingTimeInterval(-10) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                
                                Text("最近操作: \(lastRecord.operation.rawValue)成功")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                        }
                    }
                    .padding(12)
                }
                
                // 仓库配置
                GroupBox("GitHub仓库配置") {
                    VStack(alignment: .leading, spacing: 16) {
                        
                        if !dataManager.isDataPathSelected {
                            // 提示用户先设置数据路径
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("需要先设置数据存储路径")
                                        .font(.body)
                                        .fontWeight(.medium)
                                    
                                    Text("请在\"数据\"标签页中设置外部数据存储位置")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                // GitHub仓库URL
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("GitHub仓库URL")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    TextField("https://github.com/username/my-wordtagger-data.git", text: $remoteURLInput)
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isGitEnabled)
                                    
                                    Text("创建一个新的GitHub仓库来存储你的学习数据")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                // GitHub认证信息
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("GitHub认证")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        
                                        Button("帮助") {
                                            showingTokenHelp = true
                                        }
                                        .font(.caption)
                                        .buttonStyle(.borderless)
                                        .foregroundColor(.blue)
                                    }
                                    
                                    TextField("GitHub用户名", text: $githubUsername)
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isGitEnabled)
                                    
                                    SecureField("Personal Access Token", text: $githubToken)
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isGitEnabled)
                                    
                                    Text("需要GitHub Personal Access Token进行认证")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                // 分支名称
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("分支名称")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    TextField("master", text: $branchInput)
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isGitEnabled)
                                }
                                
                                // 当前配置显示
                                if isGitEnabled {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                            Text("已配置的仓库")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text("仓库:")
                                                    .foregroundColor(.secondary)
                                                Text(remoteURLInput)
                                                    .font(.system(.caption, design: .monospaced))
                                            }
                                            
                                            HStack {
                                                Text("用户:")
                                                    .foregroundColor(.secondary)
                                                Text(githubUsername.isEmpty ? "未设置" : githubUsername)
                                                    .font(.system(.caption, design: .monospaced))
                                            }
                                            
                                            HStack {
                                                Text("分支:")
                                                    .foregroundColor(.secondary)
                                                Text(branchInput)
                                                    .font(.system(.caption, design: .monospaced))
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(.controlBackgroundColor))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                
                // 操作按钮
                if dataManager.isDataPathSelected {
                    GroupBox("操作") {
                        VStack(alignment: .leading, spacing: 12) {
                            if isGitEnabled {
                                // 已配置时的操作
                                HStack(spacing: 12) {
                                    Button("同步到GitHub") {
                                        syncToGitHub()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isWorking)
                                    
                                    Button("从GitHub拉取") {
                                        pullFromGitHub()
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isWorking)
                                    
                                    Spacer()
                                    
                                    Button("重新配置") {
                                        showingConfirmDialog = true
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isWorking)
                                }
                            } else {
                                // 未配置时的设置按钮
                                Button("设置GitHub同步") {
                                    let repoURL = remoteURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let username = githubUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let token = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
                                    
                                    if repoURL.isEmpty || username.isEmpty || token.isEmpty {
                                        showingSetupAlert = true
                                    } else {
                                        setupGitRepository()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isWorking)
                            }
                        }
                        .padding(12)
                    }
                }
                
                // 使用说明
                GroupBox("使用说明") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("🎯 功能说明")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• 将你的学习数据（节点、标签、层等）自动同步到GitHub")
                                Text("• 支持多设备间的数据同步")
                                Text("• 数据变化时自动推送到GitHub")
                                Text("• 可以从其他设备拉取最新数据")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("⚠️ 系统要求")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• 需要安装Git命令行工具")
                                Text("• 如果出现权限错误，请在终端运行：")
                                Text("  xcode-select --install")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.blue)
                                Text("• 或下载完整版Xcode以获得命令行工具")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("📝 设置步骤")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("1. 在GitHub上创建一个新的私有仓库（推荐）")
                                Text("2. 复制仓库的HTTPS地址")
                                Text("3. 在上方填入仓库URL并点击\"设置GitHub同步\"")
                                Text("4. 系统会自动初始化Git并连接到你的仓库")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("🔄 未来使用")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• 在新设备上：clone你的GitHub仓库到本地文件夹")
                                Text("• 在WordTagger设置中选择该文件夹作为数据存储位置")
                                Text("• 系统会自动识别Git配置并启用同步功能")
                                Text("• 你的所有学习数据就能在多设备间同步了！")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                }
                
                Spacer()
            }
            .padding()
        }
        .onAppear {
            loadSettings()
        }
        .sheet(isPresented: $showingSyncHistory) {
            SyncHistoryView(history: syncHistory)
        }
        .alert("请完整填写GitHub信息", isPresented: $showingSetupAlert) {
            Button("确定") { }
        } message: {
            Text("请填写GitHub仓库URL、用户名和Personal Access Token")
        }
        .sheet(isPresented: $showingTokenHelp) {
            GitHubTokenHelpView()
        }
        .confirmationDialog("重新配置GitHub同步", isPresented: $showingConfirmDialog, titleVisibility: .visible) {
            Button("重新配置", role: .destructive) {
                disableGit()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("这将清除当前的GitHub配置，但不会删除已有的数据。")
        }
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // MARK: - Git操作函数
    
    private func loadSettings() {
        let userDefaults = UserDefaults.standard
        isGitEnabled = userDefaults.bool(forKey: "WordTagger_GitEnabled")
        remoteURLInput = userDefaults.string(forKey: "WordTagger_GitRemoteURL") ?? ""
        branchInput = userDefaults.string(forKey: "WordTagger_GitBranch") ?? "master"
        githubUsername = userDefaults.string(forKey: "WordTagger_GitUsername") ?? ""
        githubToken = userDefaults.string(forKey: "WordTagger_GitToken") ?? ""
        totalSyncCount = userDefaults.integer(forKey: "WordTagger_TotalSyncCount")
        lastCommitHash = userDefaults.string(forKey: "WordTagger_LastCommitHash")
        
        if let lastSync = userDefaults.object(forKey: "WordTagger_LastGitSync") as? Date {
            lastSyncTime = lastSync
        }
        
        // 加载同步历史
        if let historyData = userDefaults.data(forKey: "WordTagger_SyncHistory"),
           let decodedHistory = try? JSONDecoder().decode([SyncRecord].self, from: historyData) {
            syncHistory = decodedHistory
        }
        
        updateSyncStatus()
        
        // 同步到全局状态管理器
        statusManager.updateStatus(
            isEnabled: isGitEnabled,
            status: syncStatus,
            lastSyncTime: lastSyncTime,
            lastError: lastError,
            totalSyncCount: totalSyncCount
        )
    }
    
    private func saveSettings() {
        let userDefaults = UserDefaults.standard
        userDefaults.set(isGitEnabled, forKey: "WordTagger_GitEnabled")
        userDefaults.set(remoteURLInput, forKey: "WordTagger_GitRemoteURL")
        userDefaults.set(branchInput, forKey: "WordTagger_GitBranch")
        userDefaults.set(githubUsername, forKey: "WordTagger_GitUsername")
        userDefaults.set(githubToken, forKey: "WordTagger_GitToken")
        userDefaults.set(totalSyncCount, forKey: "WordTagger_TotalSyncCount")
        
        if let lastSync = lastSyncTime {
            userDefaults.set(lastSync, forKey: "WordTagger_LastGitSync")
        }
        
        if let commitHash = lastCommitHash {
            userDefaults.set(commitHash, forKey: "WordTagger_LastCommitHash")
        }
        
        // 保存同步历史（只保留最近50条记录）
        let recentHistory = Array(syncHistory.sorted { $0.timestamp > $1.timestamp }.prefix(50))
        if let historyData = try? JSONEncoder().encode(recentHistory) {
            userDefaults.set(historyData, forKey: "WordTagger_SyncHistory")
        }
    }
    
    private func updateSyncStatus() {
        if !isGitEnabled || remoteURLInput.isEmpty {
            syncStatus = "未配置"
        } else if isWorking {
            syncStatus = "同步中..."
        } else if lastError != nil {
            syncStatus = "错误"
        } else {
            syncStatus = "就绪"
        }
    }
    
    private func findGitPath() async -> String? {
        // 首先尝试静态路径
        let staticPaths = [
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
            "/usr/bin/git"
        ]
        
        for path in staticPaths {
            if FileManager.default.fileExists(atPath: path) {
                print("✅ 找到Git: \(path)")
                return path
            }
        }
        
        // 如果静态路径都失败，尝试使用which命令
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = ["git"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            var environment: [String: String] = [:]
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            process.environment = environment
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                        print("✅ 通过which找到Git: \(path)")
                        return path
                    }
                }
            }
        } catch {
            print("❌ which命令失败: \(error)")
        }
        
        print("❌ 所有方法都未能找到Git")
        return nil
    }
    
    private func recordSyncOperation(
        operation: SyncRecord.SyncOperation,
        success: Bool,
        commitHash: String? = nil,
        filesChanged: Int = 0,
        errorMessage: String? = nil
    ) {
        let record = SyncRecord(
            timestamp: Date(),
            operation: operation,
            success: success,
            commitHash: commitHash,
            filesChanged: filesChanged,
            errorMessage: errorMessage
        )
        
        syncHistory.append(record)
        
        if success {
            totalSyncCount += 1
            if let hash = commitHash {
                lastCommitHash = hash
            }
        }
        
        saveSettings()
        // 不立即更新状态，让调用者控制状态更新
    }
    
    private func getCommitHash(at workingDirectory: URL) async -> String? {
        do {
            guard let validGitPath = await findGitPath() else {
                print("❌ 获取commit hash失败: Git未找到")
                return nil
            }
            
            let pipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: validGitPath)
            process.arguments = ["rev-parse", "HEAD"]
            process.currentDirectoryURL = workingDirectory
            process.standardOutput = pipe
            
            // 设置环境变量
            var environment: [String: String] = [:]
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin"
            environment["GIT_TERMINAL_PROMPT"] = "0"
            environment["GIT_CONFIG_NOSYSTEM"] = "1"
            environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
            environment["HOME"] = NSHomeDirectory()
            environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            process.environment = environment
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let hash = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    print("✅ 获取到commit hash: \(String(hash.prefix(8)))")
                    return hash
                }
            } else {
                print("⚠️ 获取commit hash失败: 退出状态 \(process.terminationStatus)")
            }
        } catch {
            print("❌ 获取commit hash异常: \(error)")
        }
        return nil
    }
    
    private func setupGitRepository() {
        guard let dataPath = dataManager.currentDataPath else {
            lastError = "请先设置数据存储路径"
            updateSyncStatus()
            statusManager.updateStatus(lastError: lastError)
            return
        }
        
        isWorking = true
        syncStatus = "设置中..."
        lastError = nil
        statusManager.startWorking(operation: "初始化Git仓库")
        
        Task {
            do {
                // 首先配置Git用户信息（如果没有的话）
                try await configureGitUser(at: dataPath)
                
                // 运行Git命令初始化仓库
                try await runGitCommand(["init"], at: dataPath)
                
                // 构建带认证的URL
                let authenticatedURL = buildAuthenticatedURL()
                try await runGitCommand(["remote", "add", "origin", authenticatedURL], at: dataPath)
                
                await MainActor.run {
                    print("✅ Git设置成功，更新UI状态...")
                    isGitEnabled = true
                    isWorking = false
                    syncStatus = "设置完成"
                    recordSyncOperation(operation: .setup, success: true, filesChanged: 0)
                    saveSettings()
                    
                    statusManager.finishWorking(success: true, finalStatus: "GitHub同步已配置")
                    
                    print("🎯 当前状态: isGitEnabled=\(isGitEnabled), isWorking=\(isWorking), syncStatus=\(syncStatus)")
                    
                    // 3秒后重置状态为"就绪"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        print("🔄 3秒后重置状态为就绪")
                        self.updateSyncStatus()
                    }
                }
                
            } catch {
                await MainActor.run {
                    lastError = "Git设置失败: \(error.localizedDescription)"
                    recordSyncOperation(
                        operation: .setup,
                        success: false,
                        errorMessage: error.localizedDescription
                    )
                    statusManager.finishWorking(success: false, finalStatus: "GitHub同步配置失败", error: error.localizedDescription)
                    isWorking = false
                }
            }
        }
    }
    
    private func configureGitUser(at workingDirectory: URL) async throws {
        do {
            // 尝试获取当前用户信息
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["config", "--local", "user.name"]
            process.currentDirectoryURL = workingDirectory
            
            var environment: [String: String] = [:]
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin"
            environment["GIT_TERMINAL_PROMPT"] = "0"
            environment["GIT_CONFIG_NOSYSTEM"] = "1"
            environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
            environment["HOME"] = NSHomeDirectory()
            environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            process.environment = environment
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                // 用户信息不存在，设置默认值
                try await runGitCommand(["config", "--local", "user.name", "WordTagger User"], at: workingDirectory)
                try await runGitCommand(["config", "--local", "user.email", "wordtagger@local.app"], at: workingDirectory)
                print("✅ 已配置默认Git用户信息")
            } else {
                print("✅ Git用户信息已存在")
            }
        } catch {
            // 如果获取失败，直接设置默认值
            try await runGitCommand(["config", "--local", "user.name", "WordTagger User"], at: workingDirectory)
            try await runGitCommand(["config", "--local", "user.email", "wordtagger@local.app"], at: workingDirectory)
            print("✅ 已设置默认Git用户信息")
        }
    }
    
    private func syncToGitHub() {
        guard let dataPath = dataManager.currentDataPath else {
            lastError = "数据路径未设置"
            updateSyncStatus()
            statusManager.updateStatus(lastError: lastError)
            return
        }
        
        isWorking = true
        syncStatus = "推送中..."
        lastError = nil
        statusManager.startWorking(operation: "同步到GitHub")
        
        Task {
            do {
                // Git添加和提交
                try await runGitCommand(["add", "."], at: dataPath)
                let commitMessage = "Auto-sync WordTagger data - \(Date().formatted())"
                try await runGitCommand(["commit", "-m", commitMessage], at: dataPath)
                try await runGitCommand(["push", "origin", branchInput], at: dataPath)
                
                // 获取最新的commit hash
                let commitHash = await getCommitHash(at: dataPath)
                
                await MainActor.run {
                    lastSyncTime = Date()
                    syncStatus = "同步完成"
                    
                    // 记录成功的同步操作
                    recordSyncOperation(
                        operation: .push,
                        success: true,
                        commitHash: commitHash,
                        filesChanged: 1 // 简化计算，实际可以通过git status获取
                    )
                    
                    statusManager.finishWorking(success: true, finalStatus: "已同步到GitHub")
                    isWorking = false
                    
                    // 3秒后重置状态
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.updateSyncStatus()
                    }
                }
                
            } catch {
                await MainActor.run {
                    lastError = "同步失败: \(error.localizedDescription)"
                    
                    // 记录失败的同步操作
                    recordSyncOperation(
                        operation: .push,
                        success: false,
                        errorMessage: error.localizedDescription
                    )
                    
                    statusManager.finishWorking(success: false, finalStatus: "同步到GitHub失败", error: error.localizedDescription)
                    isWorking = false
                }
            }
        }
    }
    
    private func pullFromGitHub() {
        guard let dataPath = dataManager.currentDataPath else {
            lastError = "数据路径未设置"
            updateSyncStatus()
            statusManager.updateStatus(lastError: lastError)
            return
        }
        
        isWorking = true
        syncStatus = "拉取中..."
        lastError = nil
        statusManager.startWorking(operation: "从GitHub拉取")
        
        Task {
            do {
                try await runGitCommand(["pull", "origin", branchInput], at: dataPath)
                
                // 获取最新的commit hash
                let commitHash = await getCommitHash(at: dataPath)
                
                await MainActor.run {
                    lastSyncTime = Date()
                    syncStatus = "拉取完成"
                    
                    // 记录成功的拉取操作
                    recordSyncOperation(
                        operation: .pull,
                        success: true,
                        commitHash: commitHash,
                        filesChanged: 1 // 简化计算
                    )
                    
                    statusManager.finishWorking(success: true, finalStatus: "已从GitHub拉取")
                    isWorking = false
                    
                    // 3秒后重置状态
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.updateSyncStatus()
                    }
                    
                    // 通知数据已更新
                    NotificationCenter.default.post(
                        name: Notification.Name("ExternalDataPathChanged"),
                        object: nil,
                        userInfo: ["newPath": dataPath]
                    )
                }
                
            } catch {
                await MainActor.run {
                    lastError = "拉取失败: \(error.localizedDescription)"
                    
                    // 记录失败的拉取操作
                    recordSyncOperation(
                        operation: .pull,
                        success: false,
                        errorMessage: error.localizedDescription
                    )
                    
                    statusManager.finishWorking(success: false, finalStatus: "从GitHub拉取失败", error: error.localizedDescription)
                    isWorking = false
                }
            }
        }
    }
    
    private func disableGit() {
        isGitEnabled = false
        remoteURLInput = ""
        branchInput = "master"
        githubUsername = ""
        githubToken = ""
        lastError = nil
        saveSettings()
        updateSyncStatus()
        
        statusManager.updateStatus(
            isEnabled: false,
            status: "未配置"
        )
        statusManager.lastError = nil
    }
    
    private func runGitCommand(_ arguments: [String], at workingDirectory: URL) async throws {
        // 首先查找Git路径
        guard let gitPath = await findGitPath() else {
            throw GitError.commandFailed("git", "Git未找到，请确保已安装Git\n已检查路径: /opt/homebrew/bin/git, /usr/local/bin/git, /usr/bin/git")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            
            process.executableURL = URL(fileURLWithPath: gitPath)
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            
            // 设置环境变量以避免一些Sandbox问题
            var environment: [String: String] = [:]
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin"
            environment["GIT_TERMINAL_PROMPT"] = "0" // 禁用交互式提示
            environment["GIT_CONFIG_NOSYSTEM"] = "1" // 避免读取系统Git配置
            environment["GIT_CONFIG_GLOBAL"] = "/dev/null" // 避免读取全局Git配置
            environment["HOME"] = NSHomeDirectory() // 确保HOME路径正确
            // 特别针对Homebrew Git的设置
            environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            process.environment = environment
            
            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe
            
            do {
                print("🔧 执行Git命令: \(gitPath) \(arguments.joined(separator: " "))")
                print("🔧 工作目录: \(workingDirectory.path)")
                
                try process.run()
                process.waitUntilExit()
                
                let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                
                print("🔧 Git命令退出状态: \(process.terminationStatus)")
                if !output.isEmpty {
                    print("🔧 Git输出: \(output)")
                }
                if !errorOutput.isEmpty {
                    print("🔧 Git错误输出: \(errorOutput)")
                }
                
                if process.terminationStatus != 0 {
                    let fullError = errorOutput.isEmpty ? "命令执行失败" : errorOutput
                    throw GitError.commandFailed(arguments.joined(separator: " "), fullError)
                }
                
                continuation.resume(returning: ())
            } catch {
                print("❌ Git命令执行异常: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func buildAuthenticatedURL() -> String {
        let cleanURL = remoteURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = githubUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanToken = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 如果URL已经包含认证信息，直接返回
        if cleanURL.contains("@") {
            return cleanURL
        }
        
        // 构建认证URL: https://username:token@github.com/user/repo.git
        if let url = URL(string: cleanURL),
           let host = url.host,
           !cleanUsername.isEmpty,
           !cleanToken.isEmpty {
            let pathAndQuery = url.path + (url.query.map { "?\($0)" } ?? "")
            return "https://\(cleanUsername):\(cleanToken)@\(host)\(pathAndQuery)"
        }
        
        return cleanURL
    }
}

private enum GitError: LocalizedError {
    case commandFailed(String, String)
    
    var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let output):
            return "Git命令失败: \(command)\n输出: \(output)"
        }
    }
}

// MARK: - 同步记录数据结构
struct SyncRecord: Codable, Identifiable {
    var id = UUID()
    let timestamp: Date
    let operation: SyncOperation
    let success: Bool
    let commitHash: String?
    let filesChanged: Int
    let errorMessage: String?
    
    enum SyncOperation: String, Codable {
        case push = "推送"
        case pull = "拉取"
        case setup = "初始化"
    }
    
    var displayTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
}

// MARK: - 同步历史视图
struct SyncHistoryView: View {
    let history: [SyncRecord]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("同步历史")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 内容
            if history.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("暂无同步记录")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("开始使用GitHub同步功能后，这里会显示详细的同步历史")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(history.sorted { $0.timestamp > $1.timestamp }) { record in
                        SyncRecordRow(record: record)
                    }
                }
            }
        }
        .frame(width: 600, height: 400)
    }
}

struct SyncRecordRow: View {
    let record: SyncRecord
    
    var body: some View {
        HStack(spacing: 12) {
            // 状态图标
            Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(record.success ? .green : .red)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(record.operation.rawValue)
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(record.displayTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let commitHash = record.commitHash {
                    Text("提交: \(String(commitHash.prefix(8)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if record.filesChanged > 0 {
                    Text("文件变化: \(record.filesChanged) 个")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                if let error = record.errorMessage {
                    Text("错误: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - GitHub Token帮助视图

struct GitHubTokenHelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("如何获取GitHub Personal Access Token")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 内容
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("步骤说明")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                Text("1.")
                                    .fontWeight(.medium)
                                    .frame(width: 20, alignment: .leading)
                                Text("打开GitHub，点击右上角头像 → Settings")
                            }
                            
                            HStack(alignment: .top) {
                                Text("2.")
                                    .fontWeight(.medium)
                                    .frame(width: 20, alignment: .leading)
                                Text("在左侧菜单中找到 Developer settings → Personal access tokens → Tokens (classic)")
                            }
                            
                            HStack(alignment: .top) {
                                Text("3.")
                                    .fontWeight(.medium)
                                    .frame(width: 20, alignment: .leading)
                                Text("点击 \"Generate new token (classic)\"")
                            }
                            
                            HStack(alignment: .top) {
                                Text("4.")
                                    .fontWeight(.medium)
                                    .frame(width: 20, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("填写Token信息：")
                                    Text("• Note: 给Token起个名字，如 \"WordTagger Sync\"")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("• Expiration: 建议选择1年")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("• Scopes: 勾选 \"repo\" (完整仓库访问权限)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            HStack(alignment: .top) {
                                Text("5.")
                                    .fontWeight(.medium)
                                    .frame(width: 20, alignment: .leading)
                                Text("点击 \"Generate token\" 并立即复制生成的Token")
                            }
                            
                            HStack(alignment: .top) {
                                Text("6.")
                                    .fontWeight(.medium)
                                    .frame(width: 20, alignment: .leading)
                                Text("将复制的Token粘贴到WordTagger的 \"Personal Access Token\" 字段")
                            }
                        }
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("⚠️ 安全提醒")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("• Token生成后只显示一次，请立即复制保存")
                                .font(.body)
                            Text("• 不要将Token分享给其他人")
                                .font(.body)
                            Text("• Token具有完整的仓库访问权限，请妥善保管")
                                .font(.body)
                            Text("• 如果Token泄露，请立即到GitHub删除并重新生成")
                                .font(.body)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("📖 使用说明")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("配置完成后，WordTagger将能够：")
                                .font(.body)
                            Text("• 自动将你的学习数据推送到GitHub仓库")
                                .font(.body)
                            Text("• 从GitHub拉取最新的数据更新")
                                .font(.body)
                            Text("• 实现多设备间的数据同步")
                                .font(.body)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    // 快捷按钮
                    HStack {
                        Button("在浏览器中打开GitHub设置") {
                            if let url = URL(string: "https://github.com/settings/tokens") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Spacer()
                        
                        Button("关闭") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top)
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
    }
}

#Preview {
    SettingsView()
        .environmentObject(NodeStore.shared)
}