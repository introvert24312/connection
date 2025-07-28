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
        .frame(width: 500, height: 400)
    }
}

// MARK: - 常规设置

struct GeneralSettingsView: View {
    @AppStorage("enableDebugMode") private var enableDebugMode: Bool = false
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 30.0
    @AppStorage("showPhoneticByDefault") private var showPhoneticByDefault: Bool = true
    @AppStorage("defaultTagType") private var defaultTagType: String = Tag.TagType.memory.rawValue
    
    var body: some View {
        Form {
            Section("界面") {
                Toggle("默认显示音标", isOn: $showPhoneticByDefault)
                
                Picker("默认标签类型", selection: $defaultTagType) {
                    ForEach(Tag.TagType.allCases, id: \.rawValue) { type in
                        Text(type.displayName).tag(type.rawValue)
                    }
                }
            }
            
            Section("性能") {
                HStack {
                    Text("自动保存间隔")
                    Spacer()
                    Stepper("\(Int(autoSaveInterval)) 秒", 
                           value: $autoSaveInterval, 
                           in: 10...300, 
                           step: 10)
                }
            }
            
            Section("开发") {
                Toggle("启用调试模式", isOn: $enableDebugMode)
                    .help("显示调试信息和性能指标")
            }
        }
        .padding()
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
        Form {
            Section("搜索范围") {
                Toggle("搜索音标", isOn: $searchInPhonetic)
                Toggle("搜索含义", isOn: $searchInMeaning)
                Toggle("搜索标签", isOn: $searchInTags)
            }
            
            Section("搜索算法") {
                Toggle("启用模糊搜索", isOn: $enableFuzzySearch)
                    .help("允许拼写错误和近似匹配")
                
                if enableFuzzySearch {
                    VStack(alignment: .leading) {
                        Text("匹配阈值: \(String(format: "%.1f", searchThreshold))")
                        Slider(value: $searchThreshold, in: 0.1...0.9, step: 0.1)
                        Text("较低的值需要更精确的匹配")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("结果限制") {
                HStack {
                    Text("最大搜索结果")
                    Spacer()
                    Stepper("\(maxSearchResults)", 
                           value: $maxSearchResults, 
                           in: 10...200, 
                           step: 10)
                }
            }
        }
        .padding()
    }
}

// MARK: - 数据管理

struct DataManagementView: View {
    @EnvironmentObject private var store: WordStore
    @State private var showingExportDialog = false
    @State private var showingImportDialog = false
    @State private var showingClearDataAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 数据统计
            GroupBox("数据统计") {
                VStack(alignment: .leading, spacing: 8) {
                    StatRow(title: "单词总数", value: "\(store.words.count)")
                    StatRow(title: "标签总数", value: "\(store.allTags.count)")
                    StatRow(title: "地点标签", value: "\(store.allTags.filter { $0.hasCoordinates }.count)")
                    
                    Divider()
                    
                    ForEach(Tag.TagType.allCases, id: \.self) { type in
                        StatRow(
                            title: "\(type.displayName)标签",
                            value: "\(store.wordsCount(forTagType: type)) 个单词"
                        )
                    }
                }
                .padding(8)
            }
            
            // 数据操作
            GroupBox("数据操作") {
                VStack(spacing: 12) {
                    HStack {
                        Button("导出数据") {
                            showingExportDialog = true
                        }
                        .buttonStyle(.bordered)
                        
                        Button("导入数据") {
                            showingImportDialog = true
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                    }
                    
                    Divider()
                    
                    HStack {
                        Button("清除所有数据") {
                            showingClearDataAlert = true
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundColor(Color.red)
                        
                        Spacer()
                    }
                }
                .padding(8)
            }
            
            Spacer()
        }
        .padding()
        .alert("确认清除数据", isPresented: $showingClearDataAlert) {
            Button("取消", role: .cancel) { }
            Button("清除", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("此操作将删除所有单词和标签数据，且无法撤销。")
        }
        .fileExporter(
            isPresented: $showingExportDialog,
            document: WordDataDocument(words: store.words),
            contentType: .json,
            defaultFilename: "words_export_\(Date().formatted(.iso8601.year().month().day()))"
        ) { result in
            switch result {
            case .success(let url):
                print("数据已导出到: \(url)")
            case .failure(let error):
                print("导出失败: \(error)")
            }
        }
        .fileImporter(
            isPresented: $showingImportDialog,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importData(from: url)
                }
            case .failure(let error):
                print("导入失败: \(error)")
            }
        }
    }
    
    private func clearAllData() {
        // 这里应该实现清除数据的逻辑
        print("清除所有数据")
    }
    
    private func importData(from url: URL) {
        // 这里应该实现导入数据的逻辑
        print("从 \(url) 导入数据")
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

// MARK: - 数据文档类型

struct WordDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    let words: [Word]
    
    init(words: [Word]) {
        self.words = words
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        self.words = try JSONDecoder().decode([Word].self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(words)
        return FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    SettingsView()
        .environmentObject(WordStore.shared)
}