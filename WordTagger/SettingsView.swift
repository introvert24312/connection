import SwiftUI
import CoreLocation
import MapKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: WordStore
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
            
            // 数据管理
            DataManagementView()
                .tabItem {
                    Label("数据", systemImage: "externaldrive")
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
    @AppStorage("defaultTagType") private var defaultTagType: String = "memory"
    @AppStorage("globalGraphInitialScale") private var globalGraphInitialScale: Double = 1.0
    @AppStorage("detailGraphInitialScale") private var detailGraphInitialScale: Double = 1.0
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 界面设置
                GroupBox("界面设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "默认显示音标",
                            description: "在单词列表中自动显示音标信息"
                        ) {
                            Toggle("", isOn: $showPhoneticByDefault)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("默认标签类型")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            
                            Picker("", selection: $defaultTagType) {
                                ForEach(Tag.TagType.predefinedCases, id: \.self) { type in
                                    Text(type.displayName).tag(type.rawValue)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            
                            Text("新建单词时默认使用的标签类型")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                            description: "单词详情图谱的默认缩放级别"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(String(format: "%.1f", detailGraphInitialScale))x")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                
                                Slider(value: $detailGraphInitialScale, in: 0.5...3.0, step: 0.1)
                                    .frame(width: 120)
                            }
                        }
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
                            description: "在单词含义中搜索匹配内容"
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

// MARK: - 数据管理

struct DataManagementView: View {
    @EnvironmentObject private var store: WordStore
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
                            Text("单词总数")
                                .foregroundColor(.secondary)
                            Text("\(store.words.count)")
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
                                Text("\(store.wordsCount(forTagType: type)) 个单词")
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
                        
                        Text("此操作将删除所有单词和标签数据，且无法撤销")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if dataManager.isDataPathSelected {
                            Text("⚠️ 同时会清除外部存储文件中的所有数据")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.top, 2)
                        }
                        
                        Button("清除所有数据") {
                            showingClearDataAlert = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.red)
                        .disabled(store.words.isEmpty && store.nodes.isEmpty)
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
            Text("此操作将删除所有单词和标签数据，且无法撤销。")
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
        
        // 如果有外部数据存储，也清除外部文件
        if dataManager.isDataPathSelected {
            Task {
                do {
                    try await dataService.saveAllData(store: store)
                    await MainActor.run {
                        resultMessage = "所有数据已清除（包括外部存储）"
                        isSuccess = true
                        showingResultAlert = true
                    }
                } catch {
                    await MainActor.run {
                        resultMessage = "数据已清除，但同步外部存储失败: \(error.localizedDescription)"
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
                
                Text("单词标签管理器")
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
                
                Text("© 2024 WordTagger. All rights reserved.")
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

// MARK: - 外部数据存储面板

struct ExternalDataStoragePanel: View {
    @StateObject private var dataManager = ExternalDataManager.shared
    @StateObject private var dataService = ExternalDataService.shared
    
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
                            .fill(dataService.isSaving ? .orange : .green)
                            .frame(width: 6, height: 6)
                        
                        Text(dataService.isSaving ? "同步中..." : "已同步")
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
                    Button(dataManager.isDataPathSelected ? "更改" : "设置") {
                        // 清除之前的错误
                        dataManager.lastError = nil
                        dataManager.selectDataFolder()
                    }
                    .buttonStyle(.bordered)
                    
                    if dataManager.isDataPathSelected {
                        Button("清除") {
                            dataManager.clearDataPath()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // 如果有错误，显示重试按钮
                    if dataManager.lastError != nil {
                        Button("重试") {
                            dataManager.lastError = nil
                            dataManager.selectDataFolder()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
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
                
                Text("选择一个文件夹来存储WordTagger的数据")
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

#Preview {
    SettingsView()
        .environmentObject(WordStore.shared)
}