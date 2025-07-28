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
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 30.0
    @AppStorage("showPhoneticByDefault") private var showPhoneticByDefault: Bool = true
    @AppStorage("defaultTagType") private var defaultTagType: String = "memory"
    
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
    @State private var showingExportDialog = false
    @State private var showingImportDialog = false
    @State private var showingImportOptionsDialog = false
    @State private var showingClearDataAlert = false
    @State private var showingResultAlert = false
    @State private var resultMessage = ""
    @State private var isSuccess = false
    @State private var importValidationResult: ImportValidationResult?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                
                // 数据操作
                GroupBox("数据备份与恢复") {
                    VStack(alignment: .leading, spacing: 16) {
                        // 导出功能
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.blue)
                                Text("导出数据")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            
                            Text("将所有单词和标签数据导出为JSON文件")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if !store.words.isEmpty {
                                let summary = store.getExportSummary()
                                HStack(spacing: 12) {
                                    Label("\(summary.totalWords)", systemImage: "textformat")
                                    Label("\(summary.totalTags)", systemImage: "tag")
                                    Label("\(summary.wordsWithLocation)", systemImage: "location")
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            
                            Button(action: exportData) {
                                HStack {
                                    if store.isExporting {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "square.and.arrow.up")
                                    }
                                    Text("导出数据文件")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.isExporting || store.words.isEmpty)
                        }
                        
                        Divider()
                        
                        // 导入功能
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                    .foregroundColor(.green)
                                Text("导入数据")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            
                            Text("从JSON文件导入单词和标签数据")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(action: { showingImportOptionsDialog = true }) {
                                HStack {
                                    if store.isImporting {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "square.and.arrow.down")
                                    }
                                    Text("选择导入文件")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(store.isImporting)
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
                        
                        Button("清除所有数据") {
                            showingClearDataAlert = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.red)
                        .disabled(store.words.isEmpty)
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
        .alert("导入选项", isPresented: $showingImportOptionsDialog) {
            Button("合并数据", action: { importData(replaceExisting: false) })
            Button("替换数据", role: .destructive, action: { importData(replaceExisting: true) })
            Button("取消", role: .cancel) { }
        } message: {
            Text("选择导入方式：合并会添加新数据到现有数据中，替换会清除所有现有数据。")
        }
        .alert(isSuccess ? "成功" : "错误", isPresented: $showingResultAlert) {
            Button("确定") { }
            if let result = importValidationResult, result.hasWarnings {
                Button("查看详情") {
                    showImportDetails()
                }
            }
        } message: {
            Text(resultMessage)
        }
    }
    
    private func exportData() {
        store.exportData { success, message in
            isSuccess = success
            resultMessage = message ?? (success ? "导出成功" : "导出失败")
            showingResultAlert = true
        }
    }
    
    private func importData(replaceExisting: Bool) {
        store.importData(replaceExisting: replaceExisting) { success, message, validationResult in
            isSuccess = success
            resultMessage = message ?? (success ? "导入成功" : "导入失败")
            importValidationResult = validationResult
            showingResultAlert = true
        }
    }
    
    private func clearAllData() {
        store.clearAllData()
        resultMessage = "所有数据已清除"
        isSuccess = true
        showingResultAlert = true
    }
    
    private func showImportDetails() {
        guard let result = importValidationResult else { return }
        
        var details = "导入详情:\n"
        details += "原始数量: \(result.originalCount)\n"
        details += "有效数量: \(result.validCount)\n"
        
        if result.hasWarnings {
            details += "\n警告:\n"
            for warning in result.warnings {
                details += "• \(warning)\n"
            }
        }
        
        print(details) // 在控制台显示详情，也可以显示在单独的窗口中
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


#Preview {
    SettingsView()
        .environmentObject(WordStore.shared)
}